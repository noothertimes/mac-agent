import AppKit
import ApplicationServices

struct HubEvent {
    let seq: Int
    let time: Date
    let kind: String
    let app: String
    let detail: String
}

/// Collects UI events (AXObserver) and app lifecycle events (NSWorkspace) into a bounded queue
/// that get_events reads with long-polling. Observers fire on the main run loop; requests run
/// on a worker queue, so waiting for events never blocks their delivery.
public final class EventHub {
    public static let shared = EventHub()

    static let capacity = 500
    static let maxWait: Double = 60
    static let coalesceWindow: TimeInterval = 1
    static let textDelay: Double = 0.35
    static let detailLimit = 400
    static let notificationCenterBundle = "com.apple.notificationcenterui"

    static let notificationNames: [String: String] = [
        "window": kAXWindowCreatedNotification,
        "focus_window": kAXFocusedWindowChangedNotification,
        "focus": kAXFocusedUIElementChangedNotification,
        "title": kAXTitleChangedNotification,
        "value": kAXValueChangedNotification,
        "menu": kAXMenuOpenedNotification,
        "sheet": kAXSheetCreatedNotification,
        "created": kAXCreatedNotification,
        "destroyed": kAXUIElementDestroyedNotification,
        "moved": kAXWindowMovedNotification,
        "resized": kAXWindowResizedNotification,
        "minimized": kAXWindowMiniaturizedNotification,
    ]
    static let defaultKinds = ["window", "focus_window", "title", "sheet", "menu"]
    static let kindForNotification = Dictionary(uniqueKeysWithValues: notificationNames.map { ($1, $0) })

    private let condition = NSCondition()
    private var events: [HubEvent] = []
    private var nextSeq = 1
    private var observers: [Int32: (observer: AXObserver, name: String)] = [:]
    private var notificationCenterPid: Int32?
    private var workspaceStarted = false
    private var lastKey = ""

    /// App launch/quit/switch events. Call once on the main thread.
    public func startWorkspaceEvents() {
        guard !workspaceStarted else { return }
        workspaceStarted = true
        let center = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, String)] = [
            (NSWorkspace.didLaunchApplicationNotification, "app_launched"),
            (NSWorkspace.didTerminateApplicationNotification, "app_quit"),
            (NSWorkspace.didActivateApplicationNotification, "app_activated"),
        ]
        for (name, kind) in pairs {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.push(kind: kind, app: app?.localizedName ?? "?", detail: app?.bundleIdentifier ?? "")
            }
        }
    }

    func push(kind: String, app: String, detail: String) {
        condition.lock()
        defer { condition.unlock() }
        let key = kind + "|" + app + "|" + detail
        if key == lastKey, let last = events.last, Date().timeIntervalSince(last.time) < Self.coalesceWindow {
            return
        }
        lastKey = key
        events.append(HubEvent(seq: nextSeq, time: Date(), kind: kind, app: app, detail: detail))
        nextSeq += 1
        if events.count > Self.capacity { events.removeFirst(events.count - Self.capacity) }
        condition.broadcast()
    }

    /// Events newer than `after`, waiting up to `wait` seconds for the first one.
    func fetch(after: Int, wait: Double) -> (events: [HubEvent], latest: Int) {
        let deadline = Date().addingTimeInterval(min(max(wait, 0), Self.maxWait))
        condition.lock()
        defer { condition.unlock() }
        while !events.contains(where: { $0.seq > after }), condition.wait(until: deadline) {}
        return (events.filter { $0.seq > after }, nextSeq - 1)
    }

    private var notificationPoller: NotificationPoller?

    /// Banner text arrives as "App, Title, Body" from Notification Center.
    func watchNotifications(pid: Int32) {
        unwatch(pid: pid)
        let poller = NotificationPoller(pid: pid) { [weak self] text in
            self?.push(kind: "notification", app: "Notifications", detail: text)
        }
        condition.lock()
        notificationPoller?.stop()
        notificationPoller = poller
        notificationCenterPid = pid
        condition.unlock()
        poller.start()
    }

    func watch(pid: Int32, appName: String, kinds: [String], isNotificationCenter: Bool) throws -> [String] {
        unwatch(pid: pid)
        var created: AXObserver?
        let status = AXObserverCreate(pid, axEventCallback, &created)
        guard status == .success, let observer = created else {
            throw ToolFailure("Could not observe \(appName) (AX error \(status.rawValue)).")
        }
        let root = AXUIElementCreateApplication(pid)
        let refcon = UnsafeMutableRawPointer(bitPattern: Int(pid))
        let added = kinds.filter { kind in
            guard let name = Self.notificationNames[kind] else { return false }
            return AXObserverAddNotification(observer, root, name as CFString, refcon) == .success
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        condition.lock()
        observers[pid] = (observer, appName)
        if isNotificationCenter { notificationCenterPid = pid }
        condition.unlock()
        return added
    }

    @discardableResult
    func unwatch(pid: Int32) -> Bool {
        condition.lock()
        let entry = observers.removeValue(forKey: pid)
        var stoppedPoller = false
        if notificationCenterPid == pid {
            notificationCenterPid = nil
            notificationPoller?.stop()
            stoppedPoller = notificationPoller != nil
            notificationPoller = nil
        }
        condition.unlock()
        guard let entry else { return stoppedPoller }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(entry.observer), .defaultMode)
        return true
    }

    func watchedApps() -> [String] {
        condition.lock()
        defer { condition.unlock() }
        let apps = observers.map { "\($0.value.name) (pid \($0.key))" }
        return (apps + (notificationPoller == nil ? [] : ["Notifications"])).sorted()
    }

    /// Called on the main thread by the AX observer callback.
    fileprivate func received(pid: Int32, element: AXUIElement, notification: String) {
        condition.lock()
        let appName = observers[pid]?.name ?? "pid \(pid)"
        let fromNotificationCenter = notificationCenterPid == pid
        condition.unlock()

        let kind = fromNotificationCenter ? "notification" : (Self.kindForNotification[notification] ?? notification)
        let needsContent = fromNotificationCenter || kind == "window" || kind == "sheet"
        guard needsContent else {
            push(kind: kind, app: appName, detail: Self.describe(element, deep: false))
            return
        }
        // New windows and banners fill in their text a moment after they appear.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.textDelay) { [weak self] in
            let detail = Self.describe(element, deep: true)
            if fromNotificationCenter && detail.isEmpty { return }
            self?.push(kind: kind, app: appName, detail: detail)
        }
    }

    static func describe(_ element: AXUIElement, deep: Bool) -> String {
        let role = NodeFormatter.strip(AX.string(element, kAXRoleAttribute) ?? "")
        var texts = [AX.string(element, kAXTitleAttribute), AX.valueText(element), AX.string(element, kAXDescriptionAttribute)]
            .compactMap { $0 }.filter { !$0.isEmpty }
        if deep { texts += TextCollector.collect(from: [element], maxVisited: 60, maxChars: detailLimit) }
        var seen = Set<String>()
        let unique = texts.filter { seen.insert($0).inserted }
        let body = NodeFormatter.clean(unique.joined(separator: " | ")) ?? ""
        return deep ? String(body.prefix(detailLimit)) : "\(role) \(body)".trimmingCharacters(in: .whitespaces)
    }
}

private func axEventCallback(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?
) {
    let pid = Int32(truncatingIfNeeded: Int(bitPattern: refcon))
    EventHub.shared.received(pid: pid, element: element, notification: notification as String)
}
