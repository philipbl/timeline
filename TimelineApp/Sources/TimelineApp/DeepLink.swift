import AppKit
import Foundation

/// timeline:// URL scheme, for Shortcuts, scripts, and other apps.
///
///   timeline://add-event?file=~/plan.timeline&name=Dentist&start=2026-06-15
///       Optional: end, done, important, color (#RRGGBB), and
///       start/end accept "today". Opens the document unless it is
///       already open (open windows live-update via the file watcher).
///   timeline://open?file=~/plan.timeline
enum DeepLink {

    struct Failure: Error {
        let message: String
    }

    static func handle(_ url: URL) {
        do {
            try process(url)
        } catch let failure as Failure {
            alert(failure.message)
        } catch {
            alert(error.localizedDescription)
        }
    }

    static func process(_ url: URL) throws {
        guard url.scheme == "timeline",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw Failure(message: "Not a timeline:// URL: \(url)")
        }

        var params: [String: String] = [:]
        for item in components.queryItems ?? [] {
            params[item.name] = item.value
        }

        guard let fileParam = params["file"], !fileParam.isEmpty else {
            throw Failure(message: "The URL needs a file parameter")
        }
        let fileURL = URL(
            fileURLWithPath: (fileParam as NSString).expandingTildeInPath)

        // Only act on our own document type. The scheme is reachable from
        // web pages and other apps, and add-event rewrites the file, so
        // refusing non-.timeline paths keeps it from clobbering arbitrary
        // YAML/JSON (or opening unrelated files).
        guard fileURL.pathExtension.lowercased() == "timeline" else {
            throw Failure(message: "The file must be a .timeline document")
        }

        switch components.host {
        case "open":
            NSWorkspace.shared.open(fileURL)

        case "add-event":
            try addEvent(params, to: fileURL)

        default:
            throw Failure(
                message: "Unknown action '\(components.host ?? "")'. "
                    + "Supported: add-event, open")
        }
    }

    private static func addEvent(
        _ params: [String: String], to fileURL: URL
    ) throws {
        guard let name = params["name"], !name.isEmpty else {
            throw Failure(message: "add-event needs a name parameter")
        }
        guard let start = try day(params["start"], "start") else {
            throw Failure(message: "add-event needs a start date (YYYY-MM-DD or today)")
        }
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw Failure(message: "Could not read \(fileURL.path)")
        }
        var config: TimelineConfig
        do {
            config = try ConfigYAML.parse(text)
        } catch {
            throw Failure(message: "Could not parse \(fileURL.path): \(error.localizedDescription)")
        }

        var event = TimelineEvent(name: name, start: start)
        event.end = try day(params["end"], "end")
        if let end = event.end, end < start {
            throw Failure(message: "End is before start")
        }
        event.done = params["done"] == "true"
        event.important = params["important"] == "true"
        event.colorHex = params["color"]

        config.events.append(event)
        config.events.sort { $0.start < $1.start }
        do {
            try ConfigYAML.serialize(config).write(
                to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw Failure(message: "Could not write \(fileURL.path): \(error.localizedDescription)")
        }

        // Open windows pick the change up via the file watcher; if the
        // document isn't open anywhere, open it so the add is visible
        let isOpen = NSApp.windows.contains {
            $0.representedURL?.standardizedFileURL == fileURL.standardizedFileURL
        }
        if !isOpen {
            NSWorkspace.shared.open(fileURL)
        }
    }

    private static func day(_ value: String?, _ field: String) throws -> Day? {
        guard let value, !value.isEmpty else { return nil }
        if value == "today" { return Day.today() }
        guard let parsed = Day(string: value) else {
            throw Failure(message: "Invalid \(field) '\(value)': use YYYY-MM-DD or today")
        }
        return parsed
    }

    private static func alert(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Timeline URL failed"
            alert.informativeText = message
            alert.runModal()
        }
    }
}
