import CoreGraphics
import XCTest
@testable import MacAgentCore

private final class StubTools: ToolProvider {
    var definitions: [JSONObject] { [["name": "echo"]] }
    func call(name: String, arguments: JSONObject) -> ToolResult {
        name == "echo" ? ToolResult(arguments["text"] as? String ?? "") : ToolResult("nope", isError: true)
    }
}

private func makeServer() -> MCPServer {
    MCPServer(tools: StubTools(), name: "test", version: "0.0.1", instructions: "hi")
}

private func decode(_ line: String?) throws -> JSONObject {
    let data = try XCTUnwrap(line?.data(using: .utf8))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? JSONObject)
}

final class MCPServerTests: XCTestCase {
    func testInitializeAgreesOnSupportedVersion() throws {
        let response = try decode(makeServer().handle(
            line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#
        ))
        let result = try XCTUnwrap(response["result"] as? JSONObject)
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertEqual((result["serverInfo"] as? JSONObject)?["name"] as? String, "test")
        XCTAssertNotNil((result["capabilities"] as? JSONObject)?["tools"])
    }

    func testInitializeFallsBackToLatestForUnknownVersion() throws {
        let response = try decode(makeServer().handle(
            line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#
        ))
        XCTAssertEqual((response["result"] as? JSONObject)?["protocolVersion"] as? String, MCPServer.latestVersion)
    }

    func testNotificationGetsNoResponse() {
        XCTAssertNil(makeServer().handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
    }

    func testBlankLineIsIgnored() {
        XCTAssertNil(makeServer().handle(line: "   "))
    }

    func testParseErrorReturnsJSONRPCError() throws {
        let response = try decode(makeServer().handle(line: "{not json"))
        XCTAssertEqual((response["error"] as? JSONObject)?["code"] as? Int, -32700)
    }

    func testUnknownMethodReturnsMethodNotFound() throws {
        let response = try decode(makeServer().handle(line: #"{"jsonrpc":"2.0","id":"a","method":"nope"}"#))
        XCTAssertEqual(response["id"] as? String, "a")
        XCTAssertEqual((response["error"] as? JSONObject)?["code"] as? Int, -32601)
    }

    func testToolsListReturnsDefinitions() throws {
        let response = try decode(makeServer().handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let tools = try XCTUnwrap((response["result"] as? JSONObject)?["tools"] as? [JSONObject])
        XCTAssertEqual(tools.first?["name"] as? String, "echo")
    }

    func testToolsCallWrapsResultAsTextContent() throws {
        let response = try decode(makeServer().handle(
            line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hello"}}}"#
        ))
        let result = try XCTUnwrap(response["result"] as? JSONObject)
        let content = try XCTUnwrap(result["content"] as? [JSONObject])
        XCTAssertEqual(content.first?["text"] as? String, "hello")
        XCTAssertEqual(result["isError"] as? Bool, false)
    }

    func testToolsCallWithoutNameIsInvalidParams() throws {
        let response = try decode(makeServer().handle(line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{}}"#))
        XCTAssertEqual((response["error"] as? JSONObject)?["code"] as? Int, -32602)
    }

    func testResponsesAreSingleLine() {
        let line = makeServer().handle(line: #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"echo","arguments":{"text":"a\nb"}}}"#)
        XCTAssertFalse(line?.contains("\n") ?? true)
    }
}

final class ElementIDTests: XCTestCase {
    func testRoundTrip() {
        let id = ElementID(pid: 812, path: [1, 0, 4])
        XCTAssertEqual(id.description, "812:1.0.4")
        XCTAssertEqual(ElementID(string: "812:1.0.4"), id)
    }

    func testRootHasEmptyPath() {
        XCTAssertEqual(ElementID(string: "5:"), ElementID(pid: 5, path: []))
    }

    func testRejectsMalformedIds() {
        for bad in ["", "abc", "12", "0:1", "-3:1", "12:1..2", "12:a", "12:-1"] {
            XCTAssertNil(ElementID(string: bad), bad)
        }
    }

    func testChildAppendsIndex() {
        XCTAssertEqual(ElementID(pid: 9, path: [2]).child(7).description, "9:2.7")
    }
}

final class KeyComboTests: XCTestCase {
    func testPlainKey() throws {
        XCTAssertEqual(try KeyCombo.parse("return"), KeyCombo(keyCode: 36, flags: []))
    }

    func testModifiersAndCaseAndSpaces() throws {
        let combo = try KeyCombo.parse(" Cmd + Shift + T ")
        XCTAssertEqual(combo.keyCode, 17)
        XCTAssertEqual(combo.flags, [.maskCommand, .maskShift])
    }

    func testAliases() throws {
        XCTAssertEqual(try KeyCombo.parse("option+esc").flags, .maskAlternate)
        XCTAssertEqual(try KeyCombo.parse("control+a").flags, .maskControl)
    }

    func testErrors() {
        XCTAssertThrowsError(try KeyCombo.parse("")) { XCTAssertEqual($0 as? KeyComboError, .empty) }
        XCTAssertThrowsError(try KeyCombo.parse("cmd+banana")) {
            XCTAssertEqual($0 as? KeyComboError, .unknownKey("banana"))
        }
        XCTAssertThrowsError(try KeyCombo.parse("hyper+a")) {
            XCTAssertEqual($0 as? KeyComboError, .unknownModifier("hyper"))
        }
    }
}

final class NodeFormatterTests: XCTestCase {
    private let id = ElementID(pid: 1, path: [0, 2])

    func testFullLine() {
        let node = AXNodeInfo(
            id: id, role: "AXButton", title: "Send", desc: "Send message", enabled: true, focused: true,
            frame: CGRect(x: 10.6, y: 20, width: 30, height: 40), actions: ["AXPress", "AXScrollToVisible"]
        )
        XCTAssertEqual(
            NodeFormatter.line(node, depth: 1),
            #"  [1:0.2] Button "Send" desc="Send message" focused @10,20 30x40 actions=Press"#
        )
    }

    func testDisabledSubroleIdentifierAndDuplicateValueHidden() {
        let node = AXNodeInfo(id: id, role: "AXTextField", subrole: "AXSearchField", title: "Q", value: "Q",
                              identifier: "search", enabled: false)
        XCTAssertEqual(NodeFormatter.line(node, depth: 0), "[1:0.2] TextField/SearchField \"Q\" #search disabled")
    }

    func testLongAndMultilineTextIsFlattenedAndTruncated() {
        let long = String(repeating: "x", count: 200)
        let node = AXNodeInfo(id: id, role: "AXStaticText", value: "a\nb " + long)
        let line = NodeFormatter.line(node, depth: 0)
        XCTAssertTrue(line.contains("value=\"a / b "))
        XCTAssertTrue(line.hasSuffix("…\""))
    }

    func testInformative() {
        XCTAssertFalse(NodeFormatter.isInformative(AXNodeInfo(id: id, role: "AXGroup")))
        XCTAssertTrue(NodeFormatter.isInformative(AXNodeInfo(id: id, role: "AXGroup", desc: "Chat list")))
        XCTAssertTrue(NodeFormatter.isInformative(AXNodeInfo(id: id, role: "AXButton")))
        XCTAssertFalse(NodeFormatter.isInformative(AXNodeInfo(id: id, role: "AXStaticText", value: "")))
        XCTAssertTrue(NodeFormatter.isInformative(AXNodeInfo(id: id, role: "AXStaticText", value: "Hi")))
    }

    func testCustomActionNamesAreShortened() {
        let node = AXNodeInfo(id: id, role: "AXButton", actions: ["AXPress", "Name:Move previous\nTarget:0x0\nSelector:(null)"])
        XCTAssertEqual(NodeFormatter.line(node, depth: 0), "[1:0.2] Button actions=Press,\"Move previous\"")
    }

    func testShowMenuHiddenFromActionList() {
        let node = AXNodeInfo(id: id, role: "AXLink", title: "Home", actions: ["AXPress", "AXShowMenu"])
        XCTAssertEqual(NodeFormatter.line(node, depth: 0), "[1:0.2] Link \"Home\" actions=Press")
    }
}

final class ToolDefinitionTests: XCTestCase {
    func testEveryToolHasSchemaAndReadOnlyHint() {
        for definition in ToolDefinitions.all {
            XCTAssertNotNil(definition["name"] as? String)
            XCTAssertNotNil(definition["inputSchema"] as? JSONObject)
            XCTAssertNotNil((definition["annotations"] as? JSONObject)?["readOnlyHint"] as? Bool)
        }
    }

    func testReadOnlySetMatchesIntent() {
        XCTAssertTrue(ToolDefinitions.readOnlyNames.isSuperset(of: ["get_tree", "find", "list_apps", "frontmost"]))
        XCTAssertTrue(ToolDefinitions.readOnlyNames.isDisjoint(with: ["press", "type_text", "key", "click", "open_app"]))
    }

    func testReadOnlyModeRefusesActions() {
        let tools = MacTools(readOnlyMode: true, log: ActionLog(url: nil))
        let result = tools.call(name: "key", arguments: ["combo": "return"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("read-only"))
    }
}
