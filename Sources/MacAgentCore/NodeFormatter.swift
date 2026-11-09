import CoreGraphics
import Foundation

/// Plain snapshot of one accessibility element, independent of the AX API so it can be tested.
public struct AXNodeInfo {
    public var id: ElementID
    public var role: String
    public var subrole: String?
    public var title: String?
    public var value: String?
    public var desc: String?
    public var identifier: String?
    public var enabled: Bool?
    public var focused: Bool?
    public var frame: CGRect?
    public var actions: [String]

    public init(
        id: ElementID, role: String, subrole: String? = nil, title: String? = nil,
        value: String? = nil, desc: String? = nil, identifier: String? = nil,
        enabled: Bool? = nil, focused: Bool? = nil, frame: CGRect? = nil, actions: [String] = []
    ) {
        self.id = id
        self.role = role
        self.subrole = subrole
        self.title = title
        self.value = value
        self.desc = desc
        self.identifier = identifier
        self.enabled = enabled
        self.focused = focused
        self.frame = frame
        self.actions = actions
    }

    var texts: [String] {
        [title, value, desc, identifier].compactMap { $0 }.filter { !$0.isEmpty }
    }
}

/// Turns accessibility nodes into compact one-line text, which costs far fewer tokens than JSON.
public enum NodeFormatter {
    public static let maxTextLength = 120

    /// Container roles that carry no meaning on their own; compact mode hides them (children still show).
    static let noiseRoles: Set<String> = [
        "AXGroup", "AXUnknown", "AXSplitGroup", "AXScrollArea", "AXLayoutArea",
        "AXLayoutItem", "AXSplitter", "AXGenericElement",
    ]

    /// Roles that only mean something when they carry text (an empty label or icon is noise).
    static let textOnlyRoles: Set<String> = ["AXStaticText", "AXImage"]

    /// Actions nearly every web element has; listing them on every line wastes tokens.
    /// They still work through perform_action.
    static let hiddenActions: Set<String> = [
        "AXScrollToVisible", "AXShowDefaultUI", "AXShowAlternateUI", "AXShowMenu",
    ]

    public static func isInformative(_ node: AXNodeInfo) -> Bool {
        if !node.texts.isEmpty { return true }
        return !noiseRoles.contains(node.role) && !textOnlyRoles.contains(node.role)
    }

    public static func line(_ node: AXNodeInfo, depth: Int) -> String {
        var parts = ["[\(node.id)]", shortRole(node)]
        if let title = clean(node.title) { parts.append("\"\(title)\"") }
        if let value = clean(node.value), value != clean(node.title) { parts.append("value=\"\(value)\"") }
        if let desc = clean(node.desc), desc != clean(node.title) { parts.append("desc=\"\(desc)\"") }
        if let identifier = clean(node.identifier) { parts.append("#\(identifier)") }
        if node.enabled == false { parts.append("disabled") }
        if node.focused == true { parts.append("focused") }
        if let frame = node.frame { parts.append(format(frame)) }
        let actions = node.actions.filter { !hiddenActions.contains($0) }.map(actionName)
        if !actions.isEmpty { parts.append("actions=" + actions.joined(separator: ",")) }
        return String(repeating: "  ", count: max(depth, 0)) + parts.joined(separator: " ")
    }

    static func shortRole(_ node: AXNodeInfo) -> String {
        guard let subrole = node.subrole, !subrole.isEmpty else { return strip(node.role) }
        return strip(node.role) + "/" + strip(subrole)
    }

    /// Custom actions arrive as "Name:Move previous\nTarget:0x0\nSelector:(null)"; keep just the name.
    static func actionName(_ raw: String) -> String {
        guard raw.hasPrefix("Name:") else { return strip(raw) }
        let name = raw.dropFirst("Name:".count).split(separator: "\n", maxSplits: 1).first ?? ""
        return "\"\(name)\""
    }

    static func strip(_ name: String) -> String {
        name.hasPrefix("AX") ? String(name.dropFirst(2)) : name
    }

    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let flat = text
            .replacingOccurrences(of: "\r\n", with: " / ")
            .replacingOccurrences(of: "\n", with: " / ")
            .trimmingCharacters(in: .whitespaces)
        guard !flat.isEmpty else { return nil }
        guard flat.count > maxTextLength else { return flat }
        return String(flat.prefix(maxTextLength)) + "…"
    }

    static func format(_ frame: CGRect) -> String {
        "@\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
    }
}
