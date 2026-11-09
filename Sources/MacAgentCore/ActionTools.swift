import AppKit
import ApplicationServices

/// Tools that change things: press, type, click, open apps. Every call is written to the action log.
enum ActionTools {
    static func press(_ args: Args) throws -> ToolResult {
        let (id, element) = try args.element()
        let label = NodeFormatter.line(AX.info(element, id: id), depth: 0)
        if AX.actions(element).contains(kAXPressAction),
           AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            return ToolResult("Pressed \(label)")
        }
        guard let frame = AX.frame(element) else {
            throw ToolFailure("Element has no Press action and no frame to click: \(label)")
        }
        Input.click(at: CGPoint(x: frame.midX, y: frame.midY))
        return ToolResult("No AXPress, clicked centre instead: \(label)")
    }

    static func setValue(_ args: Args) throws -> ToolResult {
        let (id, element) = try args.element()
        let text = try args.required("text")
        let status = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString)
        guard status == .success else {
            throw ToolFailure("Could not set value (AX error \(status.rawValue)). Try focus + type_text.")
        }
        return ToolResult("Set value of \(id). Now: \"\(AX.valueText(element) ?? "")\"")
    }

    static func focus(_ args: Args) throws -> ToolResult {
        let (id, element) = try args.element()
        let status = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard status == .success else {
            throw ToolFailure("Could not focus \(id) (AX error \(status.rawValue)). Try click with id.")
        }
        return ToolResult("Focused \(id)")
    }

    static func perform(_ args: Args) throws -> ToolResult {
        let (id, element) = try args.element()
        let requested = try args.required("action")
        let action = requested.hasPrefix("AX") ? requested : "AX" + requested
        let available = AX.actions(element)
        guard available.contains(action) else {
            throw ToolFailure("\(id) has no \(action). Available: \(available.joined(separator: ", "))")
        }
        let status = AXUIElementPerformAction(element, action as CFString)
        guard status == .success else { throw ToolFailure("\(action) failed (AX error \(status.rawValue)).") }
        return ToolResult("Performed \(action) on \(id)")
    }

    static func typeText(_ args: Args) throws -> ToolResult {
        let text = try args.required("text")
        if args.string("id") != nil {
            _ = try focus(args)
        }
        Input.type(text)
        return ToolResult("Typed \(text.count) characters.")
    }

    static func key(_ args: Args) throws -> ToolResult {
        let comboText = try args.required("combo")
        do {
            Input.press(try KeyCombo.parse(comboText))
        } catch let error as KeyComboError {
            throw ToolFailure(error.description)
        }
        return ToolResult("Pressed \(comboText)")
    }

    static func click(_ args: Args) throws -> ToolResult {
        let point: CGPoint
        if args.string("id") != nil {
            let (id, element) = try args.element()
            guard let frame = AX.frame(element) else { throw ToolFailure("\(id) has no frame.") }
            point = CGPoint(x: frame.midX, y: frame.midY)
        } else if let x = args.double("x"), let y = args.double("y") {
            point = CGPoint(x: x, y: y)
        } else {
            throw ToolFailure("Give either id, or x and y.")
        }
        Input.click(at: point, right: args.bool("right") ?? false, count: args.int("count") ?? 1)
        return ToolResult("Clicked at \(Int(point.x)),\(Int(point.y))")
    }

    static func scroll(_ args: Args) throws -> ToolResult {
        if args.string("id") != nil {
            let (id, element) = try args.element()
            guard let frame = AX.frame(element) else { throw ToolFailure("\(id) has no frame.") }
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                    mouseCursorPosition: CGPoint(x: frame.midX, y: frame.midY), mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        let dx = Int32(clamping: args.int("dx") ?? 0)
        let dy = Int32(clamping: args.int("dy") ?? 0)
        guard dx != 0 || dy != 0 else { throw ToolFailure("Give dx and/or dy.") }
        Input.scroll(dx: dx, dy: dy)
        return ToolResult("Scrolled dx=\(dx) dy=\(dy)")
    }

    static func openApp(_ args: Args) throws -> ToolResult {
        let outcome = Apps.open(try args.required("app"), url: args.string("url"))
        guard outcome.ok else { throw ToolFailure(outcome.message) }
        return ToolResult(outcome.message)
    }

    static func activate(_ args: Args) throws -> ToolResult {
        let app = try args.app()
        guard app.activate() else { throw ToolFailure("Could not activate \(Apps.describe(app)).") }
        return ToolResult("Activated \(Apps.describe(app))")
    }
}
