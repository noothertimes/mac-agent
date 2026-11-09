import AppKit
import ApplicationServices

/// Dispatches MCP tool calls to the accessibility, input and app helpers.
public final class MacTools: ToolProvider {
    private let readOnlyMode: Bool
    private let log: ActionLog

    public init(readOnlyMode: Bool, log: ActionLog) {
        self.readOnlyMode = readOnlyMode
        self.log = log
    }

    public var definitions: [JSONObject] { ToolDefinitions.all }

    public func call(name: String, arguments: JSONObject) -> ToolResult {
        let args = Args(arguments)
        let isAction = !ToolDefinitions.readOnlyNames.contains(name)
        if isAction && readOnlyMode {
            return ToolResult("Refused: mac-agent is in read-only mode (MAC_AGENT_READONLY=1).", isError: true)
        }
        if !Self.permissionFree.contains(name) && !AX.isTrusted(prompt: false) {
            return ToolResult(Self.permissionHelp, isError: true)
        }
        let result: ToolResult
        do {
            result = try dispatch(name, args)
        } catch let failure as ToolFailure {
            result = ToolResult(failure.message, isError: true)
        } catch {
            result = ToolResult("\(error)", isError: true)
        }
        if isAction { log.record(tool: name, arguments: arguments, result: result) }
        return result
    }

    private func dispatch(_ name: String, _ args: Args) throws -> ToolResult {
        switch name {
        case "check_permission": return checkPermission(args)
        case "list_apps": return listApps()
        case "frontmost": return try frontmost()
        case "get_tree": return try ReadTools.tree(args)
        case "find": return try ReadTools.find(args)
        case "get_element": return try ReadTools.element(args)
        case "press": return try ActionTools.press(args)
        case "set_value": return try ActionTools.setValue(args)
        case "focus": return try ActionTools.focus(args)
        case "perform_action": return try ActionTools.perform(args)
        case "type_text": return try ActionTools.typeText(args)
        case "key": return try ActionTools.key(args)
        case "click": return try ActionTools.click(args)
        case "scroll": return try ActionTools.scroll(args)
        case "open_app": return try ActionTools.openApp(args)
        case "activate": return try ActionTools.activate(args)
        case "watch": return try EventTools.watch(args)
        case "unwatch": return try EventTools.unwatch(args)
        case "get_events": return EventTools.getEvents(args)
        case "read_text": return try ReadTools.readText(args)
        case "wait_for": return try ReadTools.waitFor(args)
        case "menu": return try WindowMenuTools.menu(args)
        case "window": return try WindowMenuTools.window(args)
        case "clipboard_get": return SystemTools.clipboardGet()
        case "clipboard_set": return try SystemTools.clipboardSet(args)
        case "run_script": return try SystemTools.runScript(args)
        case "browser_tabs": return try SystemTools.browserTabs(args)
        case "browser_js": return try SystemTools.browserJS(args)
        case "ocr": return try SystemTools.ocr(args)
        default: throw ToolFailure("Unknown tool: \(name)")
        }
    }

    /// Tools that don't touch the Accessibility API.
    static let permissionFree: Set<String> = [
        "check_permission", "list_apps", "get_events", "clipboard_get", "clipboard_set",
        "run_script", "browser_tabs", "browser_js",
    ]

    static let permissionHelp = """
        No Accessibility permission. Open System Settings > Privacy & Security > Accessibility and \
        switch on the app that launched this helper (the terminal or editor running Claude Code), \
        then restart that app. Call check_permission with prompt=true to open the dialog.
        """

    private func checkPermission(_ args: Args) -> ToolResult {
        let trusted = AX.isTrusted(prompt: args.bool("prompt") ?? false)
        return ToolResult(trusted ? "Accessibility permission: granted." : Self.permissionHelp, isError: !trusted)
    }

    private func listApps() -> ToolResult {
        let front = Apps.frontmost()?.processIdentifier
        let lines = Apps.regular()
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            .map { Apps.describe($0) + ($0.processIdentifier == front ? "  <- frontmost" : "") }
        return ToolResult(lines.joined(separator: "\n"))
    }

    private func frontmost() throws -> ToolResult {
        guard let app = Apps.frontmost() else { throw ToolFailure("No frontmost app.") }
        let pid = app.processIdentifier
        let root = AXUIElementCreateApplication(pid)
        var lines = ["App: " + Apps.describe(app)]
        if let window = AX.element(root, kAXFocusedWindowAttribute) {
            let index = AX.rootIndex(of: window, pid: pid)
            let id = index.map { ElementID(pid: pid, path: [$0]) }
            lines.append("Window: \(AX.string(window, kAXTitleAttribute) ?? "(untitled)")" + (id.map { " [\($0)]" } ?? ""))
        }
        if let focused = AX.element(root, kAXFocusedUIElementAttribute) {
            let node = AX.info(focused, id: ElementID(pid: pid, path: []))
            lines.append("Focused element (find it with `find` for an id): " + NodeFormatter.line(node, depth: 0))
        }
        return ToolResult(lines.joined(separator: "\n"))
    }
}

struct ToolFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Typed access to tool arguments.
struct Args {
    let raw: JSONObject
    init(_ raw: JSONObject) { self.raw = raw }

    func string(_ key: String) -> String? { raw[key] as? String }
    func bool(_ key: String) -> Bool? { raw[key] as? Bool }
    func int(_ key: String) -> Int? { (raw[key] as? NSNumber)?.intValue }
    func double(_ key: String) -> Double? { (raw[key] as? NSNumber)?.doubleValue }

    func required(_ key: String) throws -> String {
        guard let value = string(key) else { throw ToolFailure("Missing required argument: \(key)") }
        return value
    }

    func elementID() throws -> ElementID {
        let text = try required("id")
        guard let id = ElementID(string: text) else { throw ToolFailure("Bad element id: \(text)") }
        return id
    }

    func element() throws -> (ElementID, AXUIElement) {
        let id = try elementID()
        guard let element = AX.resolve(id) else {
            throw ToolFailure("Element \(id) no longer exists (the UI changed). Call get_tree or find again.")
        }
        return (id, element)
    }

    func app() throws -> NSRunningApplication {
        let query = string("app")
        guard let app = Apps.find(query), app.processIdentifier > 0 else {
            throw ToolFailure("No running app matches \"\(query ?? "")\".")
        }
        AX.enableFullTree(pid: app.processIdentifier)
        return app
    }
}
