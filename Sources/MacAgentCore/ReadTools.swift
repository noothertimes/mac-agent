import AppKit
import ApplicationServices

/// Read-only tools: they inspect the UI and never change anything.
enum ReadTools {
    static let defaultDepth = 30
    static let defaultNodes = 300
    static let hardNodeCap = 3000
    static let defaultFindLimit = 25

    static func tree(_ args: Args) throws -> ToolResult {
        let app = try args.app()
        let pid = app.processIdentifier
        let scope = args.string("scope") ?? "focused_window"
        var walker = TreeWalker(
            maxDepth: max(args.int("max_depth") ?? defaultDepth, 0),
            maxNodes: min(max(args.int("max_nodes") ?? defaultNodes, 1), hardNodeCap),
            compact: args.bool("compact") ?? true
        )
        let roots = try rootElements(pid: pid, scope: scope)
        for (index, element) in roots {
            walker.walk(element, id: ElementID(pid: pid, path: [index]))
        }
        var text = "\(Apps.describe(app)) scope=\(scope)\n" + walker.lines.joined(separator: "\n")
        if walker.truncated {
            text += "\n… truncated at \(walker.maxNodes) nodes. Raise max_nodes, narrow scope, or use find."
        }
        return ToolResult(text)
    }

    /// The app root's children that belong to the requested scope, with their child indices.
    static func rootElements(pid: Int32, scope: String) throws -> [(Int, AXUIElement)] {
        let root = AXUIElementCreateApplication(pid)
        let kids = Array(AX.children(root).enumerated())
        func role(_ element: AXUIElement) -> String { AX.string(element, kAXRoleAttribute) ?? "" }

        switch scope {
        case "all":
            return kids.map { ($0.offset, $0.element) }
        case "menubar":
            return kids.filter { role($0.element) == kAXMenuBarRole }.map { ($0.offset, $0.element) }
        case "windows":
            let windows = kids.filter { role($0.element) != kAXMenuBarRole }
            guard !windows.isEmpty else {
                throw ToolFailure("App has no open window here (it may be on another desktop or minimised). Try menubar, or window action=list.")
            }
            return windows.map { ($0.offset, $0.element) }
        case "focused_window":
            if let focused = AX.element(root, kAXFocusedWindowAttribute),
               let match = kids.first(where: { CFEqual($0.element, focused) }) {
                return [(match.offset, match.element)]
            }
            let windows = kids.filter { role($0.element) == kAXWindowRole }
            guard let first = windows.first else {
                throw ToolFailure("App has no open window. Try scope=all or menubar.")
            }
            return [(first.offset, first.element)]
        default:
            throw ToolFailure("Unknown scope \(scope). Use focused_window, windows, menubar or all.")
        }
    }

    static func find(_ args: Args) throws -> ToolResult {
        let app = try args.app()
        let text = try args.required("text")
        let limit = min(max(args.int("limit") ?? defaultFindLimit, 1), 200)
        let matches = ElementSearch.run(pid: app.processIdentifier, query: text, role: args.string("role"), limit: limit)
        guard !matches.isEmpty else {
            return ToolResult("No elements in \(Apps.describe(app)) match \"\(text)\".")
        }
        let lines = matches.map { NodeFormatter.line($0, depth: 0) }
        return ToolResult("\(matches.count) match(es) in \(Apps.describe(app)):\n" + lines.joined(separator: "\n"))
    }

    static let defaultTextChars = 15_000
    static let textVisitCap = 20_000
    static let defaultWait: Double = 10
    static let maxWait: Double = 60
    static let pollInterval: useconds_t = 400_000

    static func readText(_ args: Args) throws -> ToolResult {
        let app = try args.app()
        let scope = args.string("scope") ?? "focused_window"
        let roots = try rootElements(pid: app.processIdentifier, scope: scope).map(\.1)
        let maxChars = min(max(args.int("max_chars") ?? defaultTextChars, 200), 100_000)
        let texts = TextCollector.collect(from: roots, maxVisited: textVisitCap, maxChars: maxChars)
        guard !texts.isEmpty else { return ToolResult("No readable text in \(Apps.describe(app)) (\(scope)).") }
        return ToolResult("\(Apps.describe(app)):\n" + String(texts.joined(separator: "\n").prefix(maxChars)))
    }

    /// The focused window's readable text, one item per line, for before/after comparison.
    static func windowLines(_ app: NSRunningApplication) throws -> [String] {
        let roots = try rootElements(pid: app.processIdentifier, scope: "focused_window").map(\.1)
        return TextCollector.collect(from: roots, maxVisited: textVisitCap, maxChars: defaultTextChars)
    }

    static func waitFor(_ args: Args) throws -> ToolResult {
        let app = try args.app()
        let text = try args.required("text")
        let timeout = min(max(args.double("timeout") ?? defaultWait, 0), maxWait)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let found = ElementSearch.run(pid: app.processIdentifier, query: text, role: args.string("role"), limit: 5)
            if !found.isEmpty {
                return ToolResult("Appeared:\n" + found.map { NodeFormatter.line($0, depth: 0) }.joined(separator: "\n"))
            }
            usleep(pollInterval)
        } while Date() < deadline
        throw ToolFailure("\"\(text)\" did not appear in \(Apps.describe(app)) within \(Int(timeout))s.")
    }

    static func element(_ args: Args) throws -> ToolResult {
        let (id, element) = try args.element()
        let header = NodeFormatter.line(AX.info(element, id: id), depth: 0)
        let attributes = AX.allAttributes(element).map { "  \($0.0) = \($0.1)" }
        let children = AX.children(element).count
        return ToolResult(([header, "  children: \(children)"] + attributes).joined(separator: "\n"))
    }
}
