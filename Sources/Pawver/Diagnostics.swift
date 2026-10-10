import AppKit
import os

enum LogCategory: String, CaseIterable {
    case app, drag, shake, shelf, dropin, dragout, hotkey, permissions
}

/// Diagnostics: os.Logger (subsystem com.weijiaren.Pawver) plus an
/// optional plain-text mirror file, enabled only when the environment variable
/// PAWVER_LOG_DIR is set (scripts/run.sh points it at <project>/logs).
@MainActor
enum Diag {
    static let subsystem = "com.weijiaren.Pawver"
    static var verbose = false

    private static var loggers: [LogCategory: Logger] = {
        var d: [LogCategory: Logger] = [:]
        for c in LogCategory.allCases { d[c] = Logger(subsystem: subsystem, category: c.rawValue) }
        return d
    }()
    private static var fileHandle: FileHandle?
    private(set) static var logFileURL: URL?
    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func configureFileMirror() {
        guard let dir = ProcessInfo.processInfo.environment["PAWVER_LOG_DIR"], !dir.isEmpty else { return }
        let dirURL = URL(fileURLWithPath: dir, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let url = dirURL.appendingPathComponent("pawver-\(f.string(from: Date())).log")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            fileHandle = try FileHandle(forWritingTo: url)
            logFileURL = url
        } catch {
            loggers[.app]?.error("log file mirror failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func info(_ c: LogCategory, _ message: String) {
        loggers[c]?.info("\(message, privacy: .public)")
        mirror("INFO ", c, message)
    }

    static func notice(_ c: LogCategory, _ message: String) {
        loggers[c]?.notice("\(message, privacy: .public)")
        mirror("NOTE ", c, message)
    }

    /// Per-event detail, only when verbose diagnostics are enabled.
    static func debug(_ c: LogCategory, _ message: @autoclosure () -> String) {
        guard verbose else { return }
        let m = message()
        loggers[c]?.debug("\(m, privacy: .public)")
        mirror("DEBUG", c, m)
    }

    static func error(_ c: LogCategory, _ message: String) {
        loggers[c]?.error("\(message, privacy: .public)")
        mirror("ERROR", c, message)
    }

    private static func mirror(_ level: String, _ c: LogCategory, _ message: String) {
        guard let fh = fileHandle else { return }
        let line = "\(stampFormatter.string(from: Date())) \(level) [\(c.rawValue)] \(message)\n"
        if let data = line.data(using: .utf8) { fh.write(data) }
    }
}

extension NSDragOperation {
    /// Human-readable names for logs, e.g. "copy|move".
    var names: String {
        if isEmpty { return "none" }
        var parts: [String] = []
        if contains(.copy) { parts.append("copy") }
        if contains(.link) { parts.append("link") }
        if contains(.generic) { parts.append("generic") }
        if contains(.`private`) { parts.append("private") }
        if contains(.move) { parts.append("move") }
        if contains(.delete) { parts.append("delete") }
        let known: NSDragOperation = [.copy, .link, .generic, .`private`, .move, .delete]
        let rest = rawValue & ~known.rawValue
        if rest != 0 { parts.append(String(format: "0x%lx", rest)) }
        return parts.joined(separator: "|")
    }
}

extension NSEvent.ModifierFlags {
    var names: String {
        var parts: [String] = []
        if contains(.control) { parts.append("ctrl") }
        if contains(.option) { parts.append("option") }
        if contains(.shift) { parts.append("shift") }
        if contains(.command) { parts.append("cmd") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }
}

func fmt(_ p: CGPoint) -> String { String(format: "(%.1f, %.1f)", p.x, p.y) }
func fmt(_ r: CGRect) -> String { String(format: "(%.1f, %.1f, %.1f×%.1f)", r.minX, r.minY, r.width, r.height) }
func ms(_ seconds: Double?) -> String {
    guard let s = seconds else { return "n/a" }
    return String(format: "%.1fms", s * 1000)
}
