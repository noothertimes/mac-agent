import AppKit

/// watch / unwatch / get_events tool handlers over EventHub.
enum EventTools {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func watch(_ args: Args) throws -> ToolResult {
        let target = try args.required("app")
        let isNotifications = target.lowercased() == "notifications"
        let app: NSRunningApplication
        if isNotifications {
            guard let center = NSRunningApplication.runningApplications(
                withBundleIdentifier: EventHub.notificationCenterBundle
            ).first else { throw ToolFailure("Notification Center process not found.") }
            app = center
        } else {
            app = try args.app()
        }
        if isNotifications {
            EventHub.shared.watchNotifications(pid: app.processIdentifier)
            return ToolResult("Watching notification banners (checked every second). Read with get_events.")
        }
        let requested = (args.raw["kinds"] as? [String]) ?? EventHub.defaultKinds
        let unknown = requested.filter { EventHub.notificationNames[$0] == nil }
        guard unknown.isEmpty else {
            throw ToolFailure("Unknown kinds: \(unknown.joined(separator: ", ")). Valid: \(EventHub.notificationNames.keys.sorted().joined(separator: ", "))")
        }
        let name = isNotifications ? "Notifications" : (app.localizedName ?? "pid \(app.processIdentifier)")
        let added = try EventHub.shared.watch(
            pid: app.processIdentifier, appName: name, kinds: requested, isNotificationCenter: isNotifications
        )
        guard !added.isEmpty else { throw ToolFailure("\(name) accepted none of the requested event kinds.") }
        return ToolResult("Watching \(name) for: \(added.joined(separator: ", ")). Now watching: \(EventHub.shared.watchedApps().joined(separator: ", ")). Read with get_events.")
    }

    static func unwatch(_ args: Args) throws -> ToolResult {
        let target = try args.required("app")
        let pid: Int32
        if target.lowercased() == "notifications" {
            guard let center = NSRunningApplication.runningApplications(
                withBundleIdentifier: EventHub.notificationCenterBundle
            ).first else { throw ToolFailure("Notification Center process not found.") }
            pid = center.processIdentifier
        } else {
            pid = try args.app().processIdentifier
        }
        let removed = EventHub.shared.unwatch(pid: pid)
        return ToolResult(removed ? "Stopped watching \(target)." : "\(target) was not being watched.")
    }

    static func getEvents(_ args: Args) -> ToolResult {
        let (events, latest) = EventHub.shared.fetch(after: args.int("after") ?? 0, wait: args.double("wait") ?? 0)
        guard !events.isEmpty else { return ToolResult("No new events. latest=\(latest)") }
        let lines = events.map { event in
            "#\(event.seq) \(timeFormatter.string(from: event.time)) \(event.kind) \(event.app): \(event.detail)"
        }
        return ToolResult(lines.joined(separator: "\n") + "\nlatest=\(latest)")
    }
}
