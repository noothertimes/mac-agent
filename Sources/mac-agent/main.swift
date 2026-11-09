import Foundation
import MacAgentCore

// stdout carries only JSON-RPC; diagnostics go to stderr.
setvbuf(stdout, nil, _IOLBF, 0)
AX.configure()

let readOnly = ProcessInfo.processInfo.environment["MAC_AGENT_READONLY"] == "1"
let server = MCPServer(
    tools: MacTools(readOnlyMode: readOnly, log: ActionLog(url: ActionLog.defaultURL)),
    name: "mac-agent",
    version: "0.1.0",
    instructions: """
        Controls this Mac through the Accessibility tree instead of screenshots. \
        Typical flow: list_apps or frontmost -> get_tree / find to get element ids -> \
        press / set_value / focus + type_text / key. Ids are child-index paths and go stale \
        when the UI changes; re-run find after navigation. Ask the user before anything that \
        sends messages, posts, pays or deletes.
        """
)

// Read stdin off the main thread; handle each request on the main queue so AppKit state stays fresh.
DispatchQueue.global(qos: .userInitiated).async {
    while let line = readLine(strippingNewline: true) {
        DispatchQueue.main.async {
            if let response = server.handle(line: line) {
                print(response)
                fflush(stdout)
            }
        }
    }
    DispatchQueue.main.async { exit(0) }
}

dispatchMain()
