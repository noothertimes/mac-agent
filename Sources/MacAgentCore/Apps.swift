import AppKit

/// Finding and launching applications.
enum Apps {
    static func regular() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier > 0 }
    }

    static func frontmost() -> NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    /// Matches by pid, bundle id, exact name, then name prefix/substring. Nil query = frontmost app.
    static func find(_ query: String?) -> NSRunningApplication? {
        guard let query = query?.trimmingCharacters(in: .whitespaces), !query.isEmpty else { return frontmost() }
        if let pid = Int32(query) { return NSRunningApplication(processIdentifier: pid) }
        let all = NSWorkspace.shared.runningApplications.filter { $0.processIdentifier > 0 }
        let lower = query.lowercased()
        if let match = all.first(where: { $0.bundleIdentifier?.lowercased() == lower }) { return match }
        let named = all.filter { $0.localizedName != nil }
        if let match = named.first(where: { $0.localizedName!.lowercased() == lower }) { return match }
        let regularFirst = named.sorted { ($0.activationPolicy == .regular ? 0 : 1) < ($1.activationPolicy == .regular ? 0 : 1) }
        if let match = regularFirst.first(where: { $0.localizedName!.lowercased().hasPrefix(lower) }) { return match }
        return regularFirst.first(where: { $0.localizedName!.lowercased().contains(lower) })
    }

    /// Launches (or brings forward) an app with `open`, which avoids async NSWorkspace callbacks.
    static func open(_ nameOrBundle: String, url: String? = nil) -> (ok: Bool, message: String) {
        let looksLikeBundle = nameOrBundle.contains(".") && !nameOrBundle.contains(" ")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = (looksLikeBundle ? ["-b", nameOrBundle] : ["-a", nameOrBundle]) + (url.map { ["--", $0] } ?? [])
        let errors = Pipe()
        process.standardError = errors
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, "Could not run open: \(error.localizedDescription)")
        }
        guard process.terminationStatus == 0 else {
            let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (false, "open failed: \(detail.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return (true, "Opened \(nameOrBundle)" + (url.map { " with \($0)" } ?? ""))
    }

    static func describe(_ app: NSRunningApplication) -> String {
        let name = app.localizedName ?? "?"
        let bundle = app.bundleIdentifier ?? "-"
        return "\(name) (pid \(app.processIdentifier), \(bundle))"
    }
}
