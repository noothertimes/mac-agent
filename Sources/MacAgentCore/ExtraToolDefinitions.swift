import Foundation

/// Schemas for events, text reading, menus, windows, clipboard, scripts, browsers and OCR.
enum ExtraToolDefinitions {
    typealias Def = ToolDefinitions
    static let appArg = Def.appArg
    static let browserArg: JSONObject = [
        "type": "string",
        "description": "Brave Browser, Google Chrome, Microsoft Edge, Chromium or Safari. Default: frontmost or first running.",
    ]

    static let all: [JSONObject] = events + reading + control + system

    static let events: [JSONObject] = [
        Def.tool("watch",
                 "Start receiving events from an app (or app=\"notifications\" for notification banners with their text). Kinds: window, focus_window, focus, title, value, menu, sheet, created, destroyed, moved, resized, minimized. App launch/quit/switch events are always on.",
                 ["app": ["type": "string"], "kinds": ["type": "array", "items": ["type": "string"]]],
                 required: ["app"], readOnly: true),
        Def.tool("unwatch", "Stop receiving events from an app.", ["app": ["type": "string"]],
                 required: ["app"], readOnly: true),
        Def.tool("get_events",
                 "Get events newer than `after` (a seq number). Waits up to `wait` seconds (max 60) for the first one. Returns the latest seq to pass next time.",
                 ["after": ["type": "integer"], "wait": ["type": "number"]], readOnly: true),
    ]

    static let reading: [JSONObject] = [
        Def.tool("read_text", "All readable text of an app's window in reading order, without ids. Cheapest way to read a page or chat.",
                 ["app": appArg, "scope": ["type": "string", "enum": ["focused_window", "windows", "all"]],
                  "max_chars": ["type": "integer", "description": "Default 15000."]], readOnly: true),
        Def.tool("wait_for", "Wait until an element containing `text` (optional role) appears, up to `timeout` seconds (default 10, max 60).",
                 ["app": appArg, "text": ["type": "string"], "role": ["type": "string"], "timeout": ["type": "number"]],
                 required: ["text"], readOnly: true),
        Def.tool("clipboard_get", "Read the text on the clipboard.", readOnly: true),
        Def.tool("browser_tabs", "List every tab (window.tab, title, URL) of the user's real browser.",
                 ["browser": browserArg], readOnly: true),
        Def.tool("ocr", "Fallback for apps with no accessibility tree (games, canvas, iPhone Mirroring): recognise text in a window or screen region, with click coordinates. Needs Screen Recording permission.",
                 ["app": appArg, "x": ["type": "number"], "y": ["type": "number"],
                  "width": ["type": "number"], "height": ["type": "number"]], readOnly: true),
    ]

    static let control: [JSONObject] = [
        Def.tool("menu", "Click a menu bar item by path, e.g. \"File > Export…\". With list=true or no path, list items at that level (with shortcuts).",
                 ["app": appArg, "path": ["type": "string"], "list": ["type": "boolean"]], readOnly: false),
        Def.tool("window", "List an app's windows, or move/resize/minimize/restore/fullscreen/exit_fullscreen/raise/close window `index` (default 0).",
                 ["app": appArg,
                  "action": ["type": "string", "enum": ["list", "move", "resize", "minimize", "restore", "fullscreen", "exit_fullscreen", "raise", "close"]],
                  "index": ["type": "integer"], "x": ["type": "number"], "y": ["type": "number"],
                  "width": ["type": "number"], "height": ["type": "number"]], readOnly: false),
    ]

    static let system: [JSONObject] = [
        Def.tool("clipboard_set", "Put text on the clipboard.", ["text": ["type": "string"]], required: ["text"], readOnly: false),
        Def.tool("run_script", "Run AppleScript or JavaScript for Automation (Mail, Messages, Calendar, Finder, Music, System Events…). Returns the script's result.",
                 ["source": ["type": "string"],
                  "language": ["type": "string", "enum": ["applescript", "javascript"]],
                  "timeout": ["type": "number", "description": "Seconds, default 30, max 120."]],
                 required: ["source"], readOnly: false),
        Def.tool("browser_js", "Run JavaScript in a tab of the user's real signed-in browser and return the result (wrap objects in JSON.stringify). Default: active tab of front window. Needs 'Allow JavaScript from Apple Events' in the browser's Developer menu.",
                 ["code": ["type": "string"], "browser": browserArg, "window": ["type": "integer"], "tab": ["type": "integer"]],
                 required: ["code"], readOnly: false),
    ]
}
