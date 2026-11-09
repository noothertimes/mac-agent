import ApplicationServices
import Foundation

/// Depth-first dump of an AX subtree as compact text lines, with node and depth caps.
struct TreeWalker {
    let maxDepth: Int
    let maxNodes: Int
    let compact: Bool
    /// Hidden layout containers don't count toward maxNodes, but total work is still bounded.
    static let visitMultiplier = 20
    static let visitCeiling = 20_000

    private(set) var lines: [String] = []
    private(set) var visited = 0
    private(set) var truncated = false

    init(maxDepth: Int, maxNodes: Int, compact: Bool) {
        self.maxDepth = maxDepth
        self.maxNodes = maxNodes
        self.compact = compact
    }

    private var visitLimit: Int { min(maxNodes * Self.visitMultiplier, Self.visitCeiling) }

    mutating func walk(_ element: AXUIElement, id: ElementID, depth: Int = 0, shownDepth: Int = 0) {
        guard lines.count < maxNodes, visited < visitLimit else {
            truncated = true
            return
        }
        visited += 1
        let node = AX.info(element, id: id)
        let show = !compact || NodeFormatter.isInformative(node)
        if show { lines.append(NodeFormatter.line(node, depth: shownDepth)) }
        guard depth < maxDepth else { return }
        for (index, child) in AX.children(element).enumerated() {
            walk(child, id: id.child(index), depth: depth + 1, shownDepth: show ? shownDepth + 1 : shownDepth)
        }
    }
}

/// Breadth-first text search across an app's UI, nearest-to-root matches first.
struct ElementSearch {
    static let maxVisited = 6000

    static func run(pid: Int32, query: String, role: String?, limit: Int) -> [AXNodeInfo] {
        let needle = query.lowercased()
        let wantedRole = role.map { $0.hasPrefix("AX") ? $0 : "AX" + $0 }
        var queue: [(AXUIElement, ElementID)] = [(AXUIElementCreateApplication(pid), ElementID(pid: pid, path: []))]
        var head = 0
        var matches: [AXNodeInfo] = []

        while head < queue.count, head < maxVisited, matches.count < limit {
            let (element, id) = queue[head]
            head += 1
            let node = AX.info(element, id: id)
            let roleOK = wantedRole.map { $0.caseInsensitiveCompare(node.role) == .orderedSame } ?? true
            let textOK = needle.isEmpty || node.texts.contains { $0.lowercased().contains(needle) }
            if roleOK && textOK && !id.path.isEmpty { matches.append(node) }
            for (index, child) in AX.children(element).enumerated() {
                queue.append((child, id.child(index)))
            }
        }
        return matches
    }
}
