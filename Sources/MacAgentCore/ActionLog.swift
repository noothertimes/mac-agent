import Foundation

/// Append-only JSON-lines record of every action tool call, so anything done can be reviewed later.
public final class ActionLog {
    private let url: URL?
    private let formatter = ISO8601DateFormatter()

    /// Pass nil to disable logging (tests).
    public init(url: URL?) {
        self.url = url
        if let url {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        }
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/mac-agent/actions.jsonl")
    }

    func record(tool: String, arguments: JSONObject, result: ToolResult) {
        guard let url else { return }
        let entry: JSONObject = [
            "time": formatter.string(from: Date()),
            "tool": tool,
            "arguments": arguments,
            "ok": !result.isError,
            "result": String(result.text.prefix(300)),
        ]
        guard JSONSerialization.isValidJSONObject(entry),
              var data = try? JSONSerialization.data(withJSONObject: entry) else { return }
        data.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            do {
                try data.write(to: url)
            } catch {
                FileHandle.standardError.write(Data("mac-agent: could not write action log: \(error)\n".utf8))
            }
        }
    }
}
