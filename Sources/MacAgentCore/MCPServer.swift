import Foundation

public typealias JSONObject = [String: Any]

/// Text returned to the model from one tool call.
public struct ToolResult {
    public let text: String
    public let isError: Bool

    public init(_ text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }
}

public protocol ToolProvider {
    var definitions: [JSONObject] { get }
    func call(name: String, arguments: JSONObject) -> ToolResult
}

/// Minimal MCP server over newline-delimited JSON-RPC 2.0 (stdio transport).
public final class MCPServer {
    public static let supportedVersions = ["2024-11-05", "2025-03-26", "2025-06-18"]
    public static let latestVersion = "2025-06-18"

    private let tools: ToolProvider
    private let name: String
    private let version: String
    private let instructions: String

    public init(tools: ToolProvider, name: String, version: String, instructions: String) {
        self.tools = tools
        self.name = name
        self.version = version
        self.instructions = instructions
    }

    /// Handles one raw input line. Returns the response line, or nil for notifications.
    public func handle(line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let message = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject
        else {
            return Self.encode(Self.error(id: NSNull(), code: -32700, message: "Parse error"))
        }
        return handle(message: message).flatMap(Self.encode)
    }

    public func handle(message: JSONObject) -> JSONObject? {
        let id = message["id"]
        guard let method = message["method"] as? String else {
            guard let id else { return nil }
            return Self.error(id: id, code: -32600, message: "Invalid request")
        }
        // Requests without an id are notifications and never get a response.
        guard let id else { return nil }
        let params = message["params"] as? JSONObject ?? [:]

        switch method {
        case "initialize":
            return Self.result(id: id, initializeResult(params: params))
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": tools.definitions])
        case "tools/call":
            return callTool(id: id, params: params)
        default:
            return Self.error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func initializeResult(params: JSONObject) -> JSONObject {
        let requested = params["protocolVersion"] as? String ?? Self.latestVersion
        let agreed = Self.supportedVersions.contains(requested) ? requested : Self.latestVersion
        return [
            "protocolVersion": agreed,
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": name, "version": version],
            "instructions": instructions,
        ]
    }

    private func callTool(id: Any, params: JSONObject) -> JSONObject {
        guard let toolName = params["name"] as? String else {
            return Self.error(id: id, code: -32602, message: "Missing tool name")
        }
        let arguments = params["arguments"] as? JSONObject ?? [:]
        let outcome = tools.call(name: toolName, arguments: arguments)
        return Self.result(id: id, [
            "content": [["type": "text", "text": outcome.text]],
            "isError": outcome.isError,
        ])
    }

    static func result(id: Any, _ result: JSONObject) -> JSONObject {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: Any, code: Int, message: String) -> JSONObject {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    static func encode(_ object: JSONObject) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
