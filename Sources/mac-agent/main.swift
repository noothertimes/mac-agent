import Foundation
import MacAgentCore

// stdout carries only JSON-RPC; diagnostics go to stderr.
setvbuf(stdout, nil, _IOLBF, 0)
AX.configure()

let readOnly = ProcessInfo.processInfo.environment["MAC_AGENT_READONLY"] == "1"
let server = MCPServer(
    tools: MacTools(readOnlyMode: readOnly, log: ActionLog(url: ActionLog.defaultURL)),
    name: "mac-agent",
    version: "0.3.0",
    instructions: """
        Controls this Mac through the Accessibility tree instead of screenshots. \
        Read: read_text (cheapest), get_tree / find (ids), menu list=true, window list, browser_tabs, \
        ocr only for apps with no tree. Act: find_and_press (cheapest single click) / press / set_value / \
        focus + type_text / key / menu / window / browser_js / run_script. For several steps use batch \
        with watch_app, which returns only what changed. Ids are child-index paths and go stale when the UI changes; \
        re-run find after navigation, or use wait_for. Events: watch an app (or "notifications"), \
        then get_events with wait. Ask the user before anything that sends messages, posts, pays or deletes.
        """
)

// Requests run on a serial worker queue; the main thread runs the run loop that delivers
// AX observer and NSWorkspace events, so a long get_events wait never blocks them.
let worker = DispatchQueue(label: "mac-agent.requests", qos: .userInitiated)
DispatchQueue.global(qos: .userInitiated).async {
    while let line = readLine(strippingNewline: true) {
        worker.async {
            if let response = server.handle(line: line) {
                print(response)
                fflush(stdout)
            }
        }
    }
    worker.async { exit(0) }
}

DispatchQueue.main.async { EventHub.shared.startWorkspaceEvents() }
RunLoop.main.run()
