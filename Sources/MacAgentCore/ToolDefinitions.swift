import Foundation

/// JSON Schemas for every tool the server exposes.
enum ToolDefinitions {
    static let appArg: JSONObject = [
        "type": "string",
        "description": "App name, bundle id or pid. Omit for the frontmost app.",
    ]
    static let idArg: JSONObject = [
        "type": "string",
        "description": "Element id like \"812:0.3.1\" from get_tree or find. Ids change when the UI changes.",
    ]

    static func tool(_ name: String, _ description: String, _ properties: JSONObject = [:], required: [String] = [], readOnly: Bool) -> JSONObject {
        [
            "name": name,
            "description": description,
            "inputSchema": ["type": "object", "properties": properties, "required": required],
            "annotations": ["readOnlyHint": readOnly],
        ]
    }

    static let all: [JSONObject] = core + ExtraToolDefinitions.all

    static let core: [JSONObject] = [
        tool("check_permission",
             "Check whether this helper has macOS Accessibility permission. prompt=true opens the system dialog.",
             ["prompt": ["type": "boolean"]], readOnly: true),
        tool("list_apps", "List running apps with a UI (name, pid, bundle id, frontmost).", readOnly: true),
        tool("frontmost", "Show the frontmost app, its focused window and the focused element.", readOnly: true),
        tool("get_tree",
             "Read an app's UI as text: one line per element with id, role, title, value, frame and actions. Use instead of screenshots.",
             [
                 "app": appArg,
                 "scope": ["type": "string", "enum": ["focused_window", "windows", "menubar", "all"],
                           "description": "Default focused_window."],
                 "max_depth": ["type": "integer", "description": "Default 30."],
                 "max_nodes": ["type": "integer", "description": "Default 300."],
                 "compact": ["type": "boolean", "description": "Hide empty layout containers. Default true."],
             ], readOnly: true),
        tool("find",
             "Search an app's UI for elements whose title, value, description or identifier contains text. Optional role filter (e.g. Button, TextField).",
             ["app": appArg, "text": ["type": "string"], "role": ["type": "string"], "limit": ["type": "integer"]],
             required: ["text"], readOnly: true),
        tool("get_element", "List every accessibility attribute of one element.", ["id": idArg],
             required: ["id"], readOnly: true),
        tool("press", "Press a button, link, checkbox or menu item (AXPress; falls back to clicking its centre).",
             ["id": idArg], required: ["id"], readOnly: false),
        tool("set_value", "Set a text field's value directly. If the app ignores it, use focus + type_text.",
             ["id": idArg, "text": ["type": "string"]], required: ["id", "text"], readOnly: false),
        tool("focus", "Focus an element (e.g. a text field) so typing goes into it.", ["id": idArg],
             required: ["id"], readOnly: false),
        tool("perform_action", "Run a named AX action on an element, e.g. AXShowMenu, AXRaise, AXConfirm, AXIncrement.",
             ["id": idArg, "action": ["type": "string"]], required: ["id", "action"], readOnly: false),
        tool("type_text", "Type text as keystrokes into the focused element (or focus `id` first).",
             ["text": ["type": "string"], "id": idArg], required: ["text"], readOnly: false),
        tool("key", "Press a key combo, e.g. \"return\", \"cmd+a\", \"cmd+shift+t\", \"escape\".",
             ["combo": ["type": "string"]], required: ["combo"], readOnly: false),
        tool("click", "Click at screen coordinates, or at the centre of element `id`. Use only when press fails.",
             [
                 "x": ["type": "number"], "y": ["type": "number"], "id": idArg,
                 "right": ["type": "boolean"], "count": ["type": "integer", "description": "2 = double-click."],
             ], readOnly: false),
        tool("scroll", "Scroll by lines (dy>0 = up, dy<0 = down), optionally over element `id`.",
             ["dx": ["type": "integer"], "dy": ["type": "integer"], "id": idArg], readOnly: false),
        tool("open_app", "Launch or bring forward an app by name or bundle id; with `url`, open that URL or file in it.",
             ["app": ["type": "string"], "url": ["type": "string"]], required: ["app"], readOnly: false),
        tool("activate", "Bring a running app to the front.", ["app": appArg], required: ["app"], readOnly: false),
    ]

    static let readOnlyNames: Set<String> = Set(all.compactMap { definition in
        let hints = definition["annotations"] as? JSONObject
        return (hints?["readOnlyHint"] as? Bool) == true ? definition["name"] as? String : nil
    })
}
