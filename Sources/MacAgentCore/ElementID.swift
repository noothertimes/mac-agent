import Foundation

/// Stable-as-long-as-the-UI-is-unchanged address of a UI element:
/// the app's pid plus the child-index path from the app root, e.g. "812:1.0.4".
public struct ElementID: Equatable, CustomStringConvertible {
    public let pid: Int32
    public let path: [Int]

    public init(pid: Int32, path: [Int]) {
        self.pid = pid
        self.path = path
    }

    public init?(string: String) {
        let parts = string.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let pid = Int32(parts[0]), pid > 0 else { return nil }
        if parts[1].isEmpty {
            self.init(pid: pid, path: [])
            return
        }
        var indices: [Int] = []
        for piece in parts[1].split(separator: ".", omittingEmptySubsequences: false) {
            guard let index = Int(piece), index >= 0 else { return nil }
            indices.append(index)
        }
        self.init(pid: pid, path: indices)
    }

    public func child(_ index: Int) -> ElementID {
        ElementID(pid: pid, path: path + [index])
    }

    public var description: String {
        "\(pid):" + path.map(String.init).joined(separator: ".")
    }
}
