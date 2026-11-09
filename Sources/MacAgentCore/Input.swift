import CoreGraphics
import Foundation

/// Synthetic keyboard and mouse events, for when an element has no usable AX action.
enum Input {
    static let typingChunk = 16
    static let chunkDelay: useconds_t = 8_000
    static let clickDelay: useconds_t = 30_000

    static func type(_ text: String) {
        let units = Array(text.utf16)
        var start = 0
        while start < units.count {
            let end = min(start + typingChunk, units.count)
            var chunk = Array(units[start..<end])
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: isDown) else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                event.post(tap: .cghidEventTap)
            }
            usleep(chunkDelay)
            start = end
        }
    }

    static func press(_ combo: KeyCombo) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: combo.keyCode, keyDown: isDown) else {
                continue
            }
            event.flags = combo.flags
            event.post(tap: .cghidEventTap)
        }
    }

    static func click(at point: CGPoint, right: Bool = false, count: Int = 1) {
        let (down, up, button): (CGEventType, CGEventType, CGMouseButton) = right
            ? (.rightMouseDown, .rightMouseUp, .right)
            : (.leftMouseDown, .leftMouseUp, .left)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: button)?
            .post(tap: .cghidEventTap)
        usleep(clickDelay)
        for clickNumber in 1...max(count, 1) {
            for type in [down, up] {
                guard let event = CGEvent(
                    mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button
                ) else { continue }
                event.setIntegerValueField(.mouseEventClickState, value: Int64(clickNumber))
                event.post(tap: .cghidEventTap)
            }
        }
    }

    static func scroll(dx: Int32, dy: Int32) {
        CGEvent(
            scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0
        )?.post(tap: .cghidEventTap)
    }
}
