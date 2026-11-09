import Foundation

/// Chooses which search match to press. It would rather refuse than guess.
enum ElementPicker {
    enum Outcome {
        case picked(AXNodeInfo)
        case ambiguous([AXNodeInfo])
        case none
    }

    static func pick(_ matches: [AXNodeInfo], text: String, index: Int?) -> Outcome {
        let candidates = narrowToExact(matches, text: text)
        if let index {
            return candidates.indices.contains(index) ? .picked(candidates[index]) : .none
        }
        guard let first = candidates.first else { return .none }
        if candidates.count == 1 { return .picked(first) }
        let pressable = candidates.filter(isPressable)
        return pressable.count == 1 ? .picked(pressable[0]) : .ambiguous(candidates)
    }

    private static func narrowToExact(_ matches: [AXNodeInfo], text: String) -> [AXNodeInfo] {
        let needle = text.lowercased()
        let exact = matches.filter { node in node.texts.contains { $0.lowercased() == needle } }
        return exact.isEmpty ? matches : exact
    }

    private static func isPressable(_ node: AXNodeInfo) -> Bool {
        node.enabled != false && node.actions.contains("AXPress")
    }
}

/// What changed between two text snapshots, as "+ added" and "- removed" lines.
enum TextDiff {
    static let defaultLimit = 40

    static func changes(before: [String], after: [String], limit: Int = defaultLimit) -> [String] {
        let added = subtract(before, from: after).map { "+ " + $0 }
        let removed = subtract(after, from: before).map { "- " + $0 }
        let all = added + removed
        guard all.count > limit else { return all }
        return Array(all.prefix(limit)) + ["… \(all.count - limit) more changes"]
    }

    /// Items of `base` left after removing one occurrence per item in `other`, in order.
    private static func subtract(_ other: [String], from base: [String]) -> [String] {
        var remaining = Dictionary(other.map { ($0, 1) }, uniquingKeysWith: +)
        return base.filter { item in
            guard let count = remaining[item], count > 0 else { return true }
            remaining[item] = count - 1
            return false
        }
    }
}

/// Runs several tool calls in order, stopping at the first failure.
enum BatchRunner {
    static let maxSteps = 25

    struct Outcome {
        let lines: [String]
        let failed: Bool
    }

    static func run(steps: [JSONObject], call: (String, JSONObject) -> ToolResult) throws -> Outcome {
        try validate(steps)
        var lines: [String] = []
        for (offset, step) in steps.enumerated() {
            let name = step["tool"] as? String ?? ""
            let result = call(name, step["args"] as? JSONObject ?? [:])
            lines.append("\(offset + 1) \(result.isError ? "FAILED" : "ok") \(name): \(result.text)")
            if result.isError {
                lines.append("Stopped at step \(offset + 1) of \(steps.count).")
                return Outcome(lines: lines, failed: true)
            }
        }
        return Outcome(lines: lines, failed: false)
    }

    private static func validate(_ steps: [JSONObject]) throws {
        guard !steps.isEmpty else { throw ToolFailure("Give at least one step.") }
        guard steps.count <= maxSteps else { throw ToolFailure("Too many steps (max \(maxSteps)).") }
        for (offset, step) in steps.enumerated() {
            guard let name = step["tool"] as? String, !name.isEmpty else {
                throw ToolFailure("Step \(offset + 1) has no tool name.")
            }
            guard name != "batch" else { throw ToolFailure("A batch cannot contain another batch.") }
        }
    }
}
