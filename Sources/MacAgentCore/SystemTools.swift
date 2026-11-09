import AppKit
import ImageIO
import Vision

/// Clipboard, AppleScript/JXA, browser tabs/JavaScript, and OCR fallback.
enum SystemTools {
    static let scriptTimeout: Double = 30
    static let outputLimit = 30_000

    // MARK: Clipboard

    static func clipboardGet() -> ToolResult {
        let text = NSPasteboard.general.string(forType: .string)
        return ToolResult(text.map { String($0.prefix(outputLimit)) } ?? "(clipboard has no text)")
    }

    static func clipboardSet(_ args: Args) throws -> ToolResult {
        let text = try args.required("text")
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else { throw ToolFailure("Clipboard write failed.") }
        return ToolResult("Clipboard set (\(text.count) characters).")
    }

    // MARK: Scripts

    static func runScript(_ args: Args) throws -> ToolResult {
        let source = try args.required("source")
        let language = (args.string("language") ?? "applescript").lowercased()
        guard ["applescript", "javascript"].contains(language) else {
            throw ToolFailure("language must be applescript or javascript.")
        }
        let timeout = min(max(args.double("timeout") ?? scriptTimeout, 1), 120)
        return try Script.run(source, javaScript: language == "javascript", timeout: timeout)
    }

    // MARK: Browsers (the user's real, signed-in browser via Apple Events)

    static let chromiumBrowsers = ["Brave Browser", "Google Chrome", "Microsoft Edge", "Chromium"]
    static let allBrowsers = chromiumBrowsers + ["Safari"]

    static func browserName(_ args: Args) throws -> String {
        if let requested = args.string("browser") {
            guard let name = allBrowsers.first(where: { $0.lowercased().hasPrefix(requested.lowercased()) }) else {
                throw ToolFailure("Supported browsers: \(allBrowsers.joined(separator: ", ")).")
            }
            return name
        }
        let running = Set(Apps.regular().compactMap(\.localizedName))
        if let front = Apps.frontmost()?.localizedName, allBrowsers.contains(front) { return front }
        guard let name = allBrowsers.first(where: running.contains) else { throw ToolFailure("No supported browser is running.") }
        return name
    }

    static func browserTabs(_ args: Args) throws -> ToolResult {
        let browser = try browserName(args)
        let titleProperty = browser == "Safari" ? "name" : "title"
        let source = """
            tell application \(Script.quote(browser))
              set out to ""
              set wi to 0
              repeat with w in windows
                set wi to wi + 1
                set ti to 0
                repeat with t in tabs of w
                  set ti to ti + 1
                  set out to out & wi & "." & ti & " | " & (\(titleProperty) of t) & " | " & (URL of t) & (character id 10)
                end repeat
              end repeat
              return out
            end tell
            """
        let result = try Script.run(source, javaScript: false, timeout: scriptTimeout)
        return ToolResult("\(browser) tabs (window.tab, title, url):\n" + result.text)
    }

    static func browserJS(_ args: Args) throws -> ToolResult {
        let browser = try browserName(args)
        let code = Script.quote(try args.required("code"))
        let target: String
        if let window = args.int("window"), let tabIndex = args.int("tab") {
            target = "tab \(tabIndex) of window \(window)"
        } else {
            target = browser == "Safari" ? "current tab of front window" : "active tab of front window"
        }
        let source = browser == "Safari"
            ? "tell application \"Safari\" to do JavaScript \(code) in \(target)"
            : "tell application \(Script.quote(browser)) to execute \(target) javascript \(code)"
        do {
            return try Script.run(source, javaScript: false, timeout: scriptTimeout)
        } catch let failure as ToolFailure {
            throw ToolFailure(failure.message + """
                \nIf this says JavaScript is turned off: in \(browser) enable \
                View > Developer > Allow JavaScript from Apple Events (Safari: Develop menu).
                """)
        }
    }

    // MARK: OCR fallback for apps without an accessibility tree

    static func ocr(_ args: Args) throws -> ToolResult {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw ToolFailure("""
                OCR needs Screen Recording permission for the app running Claude Code (VS Code): \
                System Settings > Privacy & Security > Screen & System Audio Recording, then restart it.
                """)
        }
        let rect = try captureRect(args)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("mac-agent-ocr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let region = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-R", region, file.path]
        try capture.run()
        capture.waitUntilExit()
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ToolFailure("Screen capture failed.") }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> (CGRect, String)? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            let frame = CGRect(
                x: rect.minX + box.minX * rect.width, y: rect.minY + (1 - box.maxY) * rect.height,
                width: box.width * rect.width, height: box.height * rect.height
            )
            return (frame, text)
        }
        .sorted { abs($0.0.minY - $1.0.minY) > 6 ? $0.0.minY < $1.0.minY : $0.0.minX < $1.0.minX }
        .map { "\($0.1)  \(NodeFormatter.format($0.0))" }
        return ToolResult("OCR of \(region) (click coordinates are screen points):\n" + lines.joined(separator: "\n"))
    }

    private static func captureRect(_ args: Args) throws -> CGRect {
        if let x = args.double("x"), let y = args.double("y"), let w = args.double("width"), let h = args.double("height") {
            return CGRect(x: x, y: y, width: w, height: h)
        }
        if args.string("app") != nil {
            let app = try args.app()
            let root = AXUIElementCreateApplication(app.processIdentifier)
            guard let window = AX.element(root, kAXFocusedWindowAttribute) ?? AX.element(root, kAXMainWindowAttribute),
                  let frame = AX.frame(window) else { throw ToolFailure("\(Apps.describe(app)) has no window to read.") }
            return frame
        }
        guard let screen = NSScreen.main else { throw ToolFailure("No screen.") }
        return CGRect(origin: .zero, size: screen.frame.size)
    }
}

/// Runs AppleScript / JavaScript for Automation through osascript with a timeout.
enum Script {
    static func quote(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"" + escaped + "\""
    }

    static func run(_ source: String, javaScript: Bool, timeout: Double) throws -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", javaScript ? "JavaScript" : "AppleScript", "-"]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        input.fileHandleForWriting.write(Data(source.utf8))
        try? input.fileHandleForWriting.close()

        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()

        let text = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let errorText = String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationReason == .uncaughtSignal { throw ToolFailure("Script timed out after \(Int(timeout))s.") }
        guard process.terminationStatus == 0 else { throw ToolFailure("Script error: \(errorText)") }
        return ToolResult(text.isEmpty ? "(no output)" : String(text.prefix(SystemTools.outputLimit)))
    }
}
