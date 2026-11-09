import ApplicationServices

/// Pulls the readable text out of a subtree in reading order: labels, field values, headings, links.
enum TextCollector {
    /// Roles whose description is real content rather than a tooltip.
    static let describedRoles: Set<String> = ["AXButton", "AXLink", "AXImage", "AXCheckBox", "AXRadioButton", "AXTab"]

    static func text(of element: AXUIElement) -> String? {
        let role = AX.string(element, kAXRoleAttribute) ?? ""
        if let value = AX.valueText(element), !value.isEmpty, role != "AXScrollBar", role != "AXSlider" {
            return value
        }
        if let title = AX.string(element, kAXTitleAttribute), !title.isEmpty { return title }
        if describedRoles.contains(role), let desc = AX.string(element, kAXDescriptionAttribute), !desc.isEmpty {
            return desc
        }
        return nil
    }

    /// Drops icon-font glyphs (Private Use Area), zero-width characters and whitespace.
    /// Returns "" when nothing letter- or digit-like is left.
    static func readable(_ raw: String) -> String {
        let kept = raw.unicodeScalars.filter { scalar in
            !(0xE000...0xF8FF).contains(scalar.value)
                && !(0xF0000...0x10FFFF).contains(scalar.value)
                && scalar.properties.generalCategory != .format
        }
        let text = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) ? text : ""
    }

    static func collect(from roots: [AXUIElement], maxVisited: Int, maxChars: Int) -> [String] {
        var output: [String] = []
        var recent: [String] = []
        var visited = 0
        var chars = 0
        var stack = Array(roots.reversed())
        while let element = stack.popLast(), visited < maxVisited, chars < maxChars {
            visited += 1
            if let text = text(of: element).map(readable), !text.isEmpty, !recent.contains(text) {
                output.append(text)
                chars += text.count
                recent.append(text)
                if recent.count > 4 { recent.removeFirst() }
            }
            stack.append(contentsOf: AX.children(element).reversed())
        }
        return output
    }
}
