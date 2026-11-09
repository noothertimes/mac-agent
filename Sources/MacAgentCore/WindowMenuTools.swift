import AppKit
import ApplicationServices

/// Menu bar navigation and window management.
enum WindowMenuTools {
    // MARK: Menus

    static func menu(_ args: Args) throws -> ToolResult {
        let app = try args.app()
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let bar = AX.element(root, kAXMenuBarAttribute) else {
            throw ToolFailure("\(Apps.describe(app)) has no menu bar.")
        }
        let parts = (args.string("path") ?? "")
            .split(separator: ">")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let listOnly = args.bool("list") ?? parts.isEmpty
        var container = bar
        var trail: [String] = []

        for (index, part) in parts.enumerated() {
            let items = menuItems(of: container)
            guard let item = match(part, in: items) else {
                let level = trail.isEmpty ? "the menu bar" : trail.joined(separator: " > ")
                let options = items.compactMap { AX.string($0, kAXTitleAttribute) }.filter { !$0.isEmpty }
                throw ToolFailure("No \"\(part)\" in \(level). Available: \(options.joined(separator: ", "))")
            }
            trail.append(AX.string(item, kAXTitleAttribute) ?? part)
            let isLast = index == parts.count - 1
            if isLast && !listOnly { return try click(item, trail: trail) }
            container = item
        }
        let listing = menuItems(of: container).compactMap(describeItem)
        let heading = trail.isEmpty ? "Menu bar of \(Apps.describe(app))" : trail.joined(separator: " > ")
        return ToolResult(heading + ":\n" + listing.joined(separator: "\n"))
    }

    private static func click(_ item: AXUIElement, trail: [String]) throws -> ToolResult {
        guard AX.bool(item, kAXEnabledAttribute) != false else {
            throw ToolFailure("Menu item \(trail.joined(separator: " > ")) is disabled right now.")
        }
        let status = AXUIElementPerformAction(item, kAXPressAction as CFString)
        guard status == .success else { throw ToolFailure("Menu press failed (AX error \(status.rawValue)).") }
        return ToolResult("Clicked menu \(trail.joined(separator: " > "))")
    }

    static func menuItems(of element: AXUIElement) -> [AXUIElement] {
        let kids = AX.children(element)
        if AX.string(element, kAXRoleAttribute) == kAXMenuBarRole { return kids }
        if let submenu = kids.first(where: { AX.string($0, kAXRoleAttribute) == kAXMenuRole }) {
            return AX.children(submenu)
        }
        return kids
    }

    static func normalize(_ title: String) -> String {
        title.lowercased().replacingOccurrences(of: "…", with: "...").trimmingCharacters(in: .whitespaces)
    }

    static func match(_ wanted: String, in items: [AXUIElement]) -> AXUIElement? {
        let target = normalize(wanted)
        let titled = items.map { ($0, normalize(AX.string($0, kAXTitleAttribute) ?? "")) }.filter { !$0.1.isEmpty }
        return titled.first { $0.1 == target }?.0
            ?? titled.first { $0.1.replacingOccurrences(of: "...", with: "") == target }?.0
            ?? titled.first { $0.1.hasPrefix(target) }?.0
    }

    static func describeItem(_ item: AXUIElement) -> String? {
        guard let title = AX.string(item, kAXTitleAttribute), !title.isEmpty else { return nil }
        var line = "- " + title
        if let shortcut = shortcut(item) { line += "  (\(shortcut))" }
        if AX.bool(item, kAXEnabledAttribute) == false { line += "  [disabled]" }
        if AX.children(item).contains(where: { AX.string($0, kAXRoleAttribute) == kAXMenuRole }) { line += "  ▸" }
        return line
    }

    static func shortcut(_ item: AXUIElement) -> String? {
        guard let key = AX.string(item, kAXMenuItemCmdCharAttribute), !key.isEmpty else { return nil }
        let mods = (AX.attribute(item, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? 0
        return MenuShortcut.format(key: key, modifiers: mods)
    }

    // MARK: Windows

    static func window(_ args: Args) throws -> ToolResult {
        let app = try args.app()
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let windows = AX.attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let action = args.string("action") ?? "list"
        if action == "list" {
            guard !windows.isEmpty else { return ToolResult("\(Apps.describe(app)) has no windows.") }
            let lines = windows.enumerated().map { index, window in "\(index): " + describeWindow(window) }
            return ToolResult("Windows of \(Apps.describe(app)):\n" + lines.joined(separator: "\n"))
        }
        let index = args.int("index") ?? 0
        guard windows.indices.contains(index) else {
            throw ToolFailure("No window \(index); \(Apps.describe(app)) has \(windows.count).")
        }
        let window = windows[index]
        try apply(action, to: window, args: args, app: app)
        return ToolResult("\(action) done: " + describeWindow(window))
    }

    private static func apply(_ action: String, to window: AXUIElement, args: Args, app: NSRunningApplication) throws {
        switch action {
        case "move":
            guard let x = args.double("x"), let y = args.double("y") else { throw ToolFailure("move needs x and y.") }
            var point = CGPoint(x: x, y: y)
            try set(window, kAXPositionAttribute, AXValueCreate(.cgPoint, &point))
        case "resize":
            guard let width = args.double("width"), let height = args.double("height") else {
                throw ToolFailure("resize needs width and height.")
            }
            var size = CGSize(width: width, height: height)
            try set(window, kAXSizeAttribute, AXValueCreate(.cgSize, &size))
        case "minimize": try set(window, kAXMinimizedAttribute, kCFBooleanTrue)
        case "restore": try set(window, kAXMinimizedAttribute, kCFBooleanFalse)
        case "fullscreen": try set(window, "AXFullScreen", kCFBooleanTrue)
        case "exit_fullscreen": try set(window, "AXFullScreen", kCFBooleanFalse)
        case "raise":
            _ = app.activate()
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        case "close":
            guard let button = AX.element(window, kAXCloseButtonAttribute),
                  AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
            else { throw ToolFailure("Window has no working close button.") }
        default:
            throw ToolFailure("Unknown action \(action). Use list, move, resize, minimize, restore, fullscreen, exit_fullscreen, raise, close.")
        }
    }

    private static func set(_ window: AXUIElement, _ attribute: String, _ value: CFTypeRef?) throws {
        guard let value else { throw ToolFailure("Could not build value for \(attribute).") }
        let status = AXUIElementSetAttributeValue(window, attribute as CFString, value)
        guard status == .success else { throw ToolFailure("Setting \(attribute) failed (AX error \(status.rawValue)).") }
    }

    static func describeWindow(_ window: AXUIElement) -> String {
        var parts = ["\"\(AX.string(window, kAXTitleAttribute) ?? "")\""]
        if let frame = AX.frame(window) { parts.append(NodeFormatter.format(frame)) }
        if AX.bool(window, kAXMinimizedAttribute) == true { parts.append("minimized") }
        if AX.bool(window, kAXMainAttribute) == true { parts.append("main") }
        if AX.bool(window, "AXFullScreen") == true { parts.append("fullscreen") }
        return parts.joined(separator: " ")
    }
}

/// Formats AX menu shortcut modifiers (bit 0 shift, 1 option, 2 control, 3 = no command key).
public enum MenuShortcut {
    public static func format(key: String, modifiers: Int) -> String {
        var symbols = ""
        if modifiers & 4 != 0 { symbols += "⌃" }
        if modifiers & 2 != 0 { symbols += "⌥" }
        if modifiers & 1 != 0 { symbols += "⇧" }
        if modifiers & 8 == 0 { symbols += "⌘" }
        return symbols + key
    }
}
