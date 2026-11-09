import AppKit
import ApplicationServices

/// Thin, failure-tolerant wrappers over the macOS Accessibility (AX) C API.
public enum AX {
    /// Seconds to wait on an unresponsive app before giving up on an AX call.
    static let messagingTimeout: Float = 1.5

    public static func configure() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
    }

    /// Pids we've already asked to expose their full tree.
    private static var webEnabled: Set<Int32> = []
    static let webWarmup: useconds_t = 400_000

    /// Chromium/Electron apps (Chrome, VS Code, Slack…) only build their AX tree when an
    /// assistive client sets AXManualAccessibility. Harmless no-op for native apps.
    static func enableFullTree(pid: Int32) {
        guard !webEnabled.contains(pid) else { return }
        webEnabled.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        let status = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if status == .success { usleep(webWarmup) }
    }

    public static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        (attribute(element, name) as? NSNumber)?.boolValue
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    static func valueText(_ element: AXUIElement) -> String? {
        let value = attribute(element, kAXValueAttribute)
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        return CGRect(origin: point, size: extent)
    }

    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    static func info(_ element: AXUIElement, id: ElementID) -> AXNodeInfo {
        AXNodeInfo(
            id: id,
            role: string(element, kAXRoleAttribute) ?? "AXUnknown",
            subrole: string(element, kAXSubroleAttribute),
            title: string(element, kAXTitleAttribute),
            value: valueText(element),
            desc: string(element, kAXDescriptionAttribute) ?? string(element, kAXHelpAttribute),
            identifier: string(element, kAXIdentifierAttribute),
            enabled: bool(element, kAXEnabledAttribute),
            focused: bool(element, kAXFocusedAttribute),
            frame: frame(element),
            actions: actions(element)
        )
    }

    /// Walks the child-index path from the app root. Nil if the UI changed and the path is gone.
    public static func resolve(_ id: ElementID) -> AXUIElement? {
        var current = AXUIElementCreateApplication(id.pid)
        for index in id.path {
            let kids = children(current)
            guard index < kids.count else { return nil }
            current = kids[index]
        }
        return current
    }

    /// Finds the path of a known element (e.g. the focused window) among the app root's children.
    static func rootIndex(of target: AXUIElement, pid: Int32) -> Int? {
        children(AXUIElementCreateApplication(pid)).firstIndex { CFEqual($0, target) }
    }

    /// Every attribute an element exposes, with short readable values. Used by get_element.
    static func allAttributes(_ element: AXUIElement) -> [(String, String)] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let list = names as? [String] else { return [] }
        return list.sorted().map { name in
            (name, describe(attribute(element, name)))
        }
    }

    static func describe(_ value: CFTypeRef?) -> String {
        guard let value else { return "-" }
        if let text = value as? String { return NodeFormatter.clean(text) ?? "\"\"" }
        if let number = value as? NSNumber { return number.stringValue }
        if let list = value as? [Any] { return "[\(list.count) items]" }
        if CFGetTypeID(value) == AXUIElementGetTypeID() { return "<element>" }
        if CFGetTypeID(value) == AXValueGetTypeID() { return String(describing: value) }
        return String(describing: type(of: value))
    }
}
