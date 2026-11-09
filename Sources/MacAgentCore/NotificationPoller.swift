import AppKit
import ApplicationServices

/// Notification banners appear inside Notification Center's existing window, so no AX
/// "created" event fires for them. This polls that window once a second and reports each
/// new banner (keyed by its identifier) exactly once.
final class NotificationPoller {
    static let interval: TimeInterval = 1
    static let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]
    static let maxVisited = 400
    static let seenLimit = 300

    private let pid: Int32
    private let onBanner: (String) -> Void
    private var timer: Timer?
    private var seen: [String] = []

    init(pid: Int32, onBanner: @escaping (String) -> Void) {
        self.pid = pid
        self.onBanner = onBanner
    }

    /// Schedules on the main run loop. Existing banners are marked seen so only new ones report.
    func start() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.seen = self.banners().map(\.key)
            let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
        }
    }

    private func tick() {
        for banner in banners() where !seen.contains(banner.key) {
            seen.append(banner.key)
            onBanner(banner.text)
        }
        if seen.count > Self.seenLimit { seen.removeFirst(seen.count - Self.seenLimit) }
    }

    private func banners() -> [(key: String, text: String)] {
        var found: [(String, String)] = []
        var stack = AX.children(AXUIElementCreateApplication(pid)).filter {
            AX.string($0, kAXRoleAttribute) == kAXWindowRole
        }
        var visited = 0
        while let element = stack.popLast(), visited < Self.maxVisited {
            visited += 1
            if let subrole = AX.string(element, kAXSubroleAttribute), Self.bannerSubroles.contains(subrole) {
                let desc = AX.string(element, kAXDescriptionAttribute) ?? ""
                let text = desc.isEmpty
                    ? TextCollector.collect(from: [element], maxVisited: 30, maxChars: 400).joined(separator: " | ")
                    : desc
                let key = (AX.string(element, kAXIdentifierAttribute) ?? "") + "|" + text
                if !text.isEmpty { found.append((key, text)) }
                continue
            }
            stack.append(contentsOf: AX.children(element))
        }
        return found
    }
}
