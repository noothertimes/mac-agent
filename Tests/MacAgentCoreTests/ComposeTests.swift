import XCTest
@testable import MacAgentCore

private func node(_ path: Int, title: String, pressable: Bool = true, enabled: Bool? = nil) -> AXNodeInfo {
    AXNodeInfo(
        id: ElementID(pid: 1, path: [path]), role: "AXButton", title: title,
        enabled: enabled, actions: pressable ? ["AXPress"] : []
    )
}

final class ElementPickerTests: XCTestCase {
    func testPicksTheOnlyMatch() {
        guard case .picked(let found) = ElementPicker.pick([node(0, title: "Save as")], text: "save", index: nil) else {
            return XCTFail("expected a pick")
        }
        XCTAssertEqual(found.title, "Save as")
    }

    func testPrefersTheOnlyExactMatchOverPartialOnes() {
        let matches = [node(0, title: "Save as"), node(1, title: "Save"), node(2, title: "Autosave")]
        guard case .picked(let found) = ElementPicker.pick(matches, text: "save", index: nil) else {
            return XCTFail("expected a pick")
        }
        XCTAssertEqual(found.title, "Save")
    }

    func testPrefersTheOnlyPressableCandidate() {
        let matches = [node(0, title: "Send", pressable: false), node(1, title: "Send")]
        guard case .picked(let found) = ElementPicker.pick(matches, text: "send", index: nil) else {
            return XCTFail("expected a pick")
        }
        XCTAssertEqual(found.id.path, [1])
    }

    func testDisabledElementsDoNotCountAsPressable() {
        let matches = [node(0, title: "Send", enabled: false), node(1, title: "Send")]
        guard case .picked(let found) = ElementPicker.pick(matches, text: "send", index: nil) else {
            return XCTFail("expected a pick")
        }
        XCTAssertEqual(found.id.path, [1])
    }

    func testRefusesToGuessBetweenEqualCandidates() {
        let matches = [node(0, title: "OK"), node(1, title: "OK")]
        guard case .ambiguous(let options) = ElementPicker.pick(matches, text: "ok", index: nil) else {
            return XCTFail("expected ambiguity")
        }
        XCTAssertEqual(options.count, 2)
    }

    func testIndexChoosesAmongCandidates() {
        let matches = [node(0, title: "OK"), node(1, title: "OK")]
        guard case .picked(let found) = ElementPicker.pick(matches, text: "ok", index: 1) else {
            return XCTFail("expected a pick")
        }
        XCTAssertEqual(found.id.path, [1])
    }

    func testOutOfRangeIndexAndNoMatchesFindNothing() {
        guard case .none = ElementPicker.pick([node(0, title: "OK")], text: "ok", index: 5) else {
            return XCTFail("expected none")
        }
        guard case .none = ElementPicker.pick([], text: "ok", index: nil) else {
            return XCTFail("expected none")
        }
    }
}

final class TextDiffTests: XCTestCase {
    func testReportsOnlyAddedAndRemovedLines() {
        XCTAssertEqual(TextDiff.changes(before: ["a", "b"], after: ["b", "c"]), ["+ c", "- a"])
    }

    func testRepeatedLinesAreCounted() {
        XCTAssertEqual(TextDiff.changes(before: ["a"], after: ["a", "a"]), ["+ a"])
    }

    func testNoChangeGivesNothing() {
        XCTAssertEqual(TextDiff.changes(before: ["a"], after: ["a"]), [])
    }

    func testLongDiffsAreCapped() {
        let after = (0..<10).map(String.init)
        let result = TextDiff.changes(before: [], after: after, limit: 3)
        XCTAssertEqual(result, ["+ 0", "+ 1", "+ 2", "… 7 more changes"])
    }
}

final class BatchRunnerTests: XCTestCase {
    func testRunsStepsInOrderAndReportsEachOnOneLine() throws {
        var called: [String] = []
        let outcome = try BatchRunner.run(steps: [["tool": "a"], ["tool": "b", "args": ["x": 1]]]) { name, _ in
            called.append(name)
            return ToolResult("done \(name)")
        }
        XCTAssertEqual(called, ["a", "b"])
        XCTAssertEqual(outcome.lines, ["1 ok a: done a", "2 ok b: done b"])
        XCTAssertFalse(outcome.failed)
    }

    func testPassesArgumentsToTheTool() throws {
        var seen: JSONObject = [:]
        _ = try BatchRunner.run(steps: [["tool": "a", "args": ["text": "hi"]]]) { _, args in
            seen = args
            return ToolResult("")
        }
        XCTAssertEqual(seen["text"] as? String, "hi")
    }

    func testStopsAtTheFirstFailure() throws {
        var called: [String] = []
        let outcome = try BatchRunner.run(steps: [["tool": "a"], ["tool": "b"], ["tool": "c"]]) { name, _ in
            called.append(name)
            return ToolResult("boom", isError: name == "b")
        }
        XCTAssertEqual(called, ["a", "b"])
        XCTAssertTrue(outcome.failed)
        XCTAssertEqual(outcome.lines.last, "Stopped at step 2 of 3.")
    }

    func testRejectsNestedBatchBeforeRunningAnything() {
        var ran = false
        XCTAssertThrowsError(try BatchRunner.run(steps: [["tool": "a"], ["tool": "batch"]]) { _, _ in
            ran = true
            return ToolResult("")
        })
        XCTAssertFalse(ran)
    }

    func testRejectsEmptyMalformedAndOversizedBatches() {
        let run = { (steps: [JSONObject]) in try BatchRunner.run(steps: steps) { _, _ in ToolResult("") } }
        XCTAssertThrowsError(try run([]))
        XCTAssertThrowsError(try run([["args": [:] as JSONObject]]))
        XCTAssertThrowsError(try run(Array(repeating: ["tool": "a"], count: BatchRunner.maxSteps + 1)))
    }
}
