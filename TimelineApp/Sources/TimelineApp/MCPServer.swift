import Foundation

/// Minimal MCP (Model Context Protocol) server over stdio, so Claude can
/// create timelines, manage events, and render previews. Run with
/// `Timeline --mcp`; register via:
///   claude mcp add timeline -- /path/to/Timeline.app/Contents/MacOS/Timeline --mcp
///
/// The protocol is newline-delimited JSON-RPC 2.0. Implemented by hand to
/// stay dependency-free; only the tools capability is offered.
enum MCPServer {

    struct ToolError: Error {
        let message: String
    }

    static func run() -> Never {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data)
                      as? [String: Any]
            else { continue }
            if let response = handle(message) {
                send(response)
            }
        }
        exit(0)
    }

    private static func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object)
        else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    // MARK: - JSON-RPC dispatch

    static func handle(_ message: [String: Any]) -> [String: Any]? {
        let method = message["method"] as? String ?? ""
        let id = message["id"]

        func result(_ value: Any) -> [String: Any]? {
            guard let id else { return nil }
            return ["jsonrpc": "2.0", "id": id, "result": value]
        }
        func rpcError(_ code: Int, _ text: String) -> [String: Any]? {
            guard let id else { return nil }
            return [
                "jsonrpc": "2.0", "id": id,
                "error": ["code": code, "message": text],
            ]
        }

        switch method {
        case "initialize":
            let params = message["params"] as? [String: Any]
            let version = params?["protocolVersion"] as? String ?? "2024-11-05"
            return result([
                "protocolVersion": version,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "timeline", "version": "1.0.0"],
            ])

        case "ping":
            return result([String: Any]())

        case "tools/list":
            return result(["tools": toolDefinitions])

        case "tools/call":
            guard let params = message["params"] as? [String: Any],
                  let name = params["name"] as? String
            else { return rpcError(-32602, "Missing tool name") }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                return result(try callTool(name, arguments))
            } catch let toolError as ToolError {
                return result([
                    "content": [["type": "text", "text": toolError.message]],
                    "isError": true,
                ])
            } catch {
                return result([
                    "content": [["type": "text", "text": "\(error)"]],
                    "isError": true,
                ])
            }

        default:
            // Notifications (no id) are silently ignored
            return id != nil ? rpcError(-32601, "Unknown method: \(method)") : nil
        }
    }

    // MARK: - Tool definitions

    private static let dateNote = "Date in YYYY-MM-DD format."

    static let toolDefinitions: [[String: Any]] = [
        [
            "name": "create_timeline",
            "description": """
                Create a new .timeline document (plain YAML). Fails if the \
                file already exists.
                """,
            "inputSchema": objectSchema(
                properties: [
                    "path": ["type": "string", "description": "File path for the new .timeline document."],
                    "title": ["type": "string"],
                    "timeline_start": ["type": "string", "description": dateNote + " Optional; enables past-day cross-off."],
                    "timeline_end": ["type": "string", "description": dateNote],
                ],
                required: ["path"]),
        ],
        [
            "name": "read_timeline",
            "description": "Read a .timeline document and return its YAML.",
            "inputSchema": objectSchema(
                properties: [
                    "path": ["type": "string"]
                ],
                required: ["path"]),
        ],
        [
            "name": "add_events",
            "description": """
                Add one or more events to a timeline. Events without an end \
                date render as dots; with an end date as bars.
                """,
            "inputSchema": objectSchema(
                properties: [
                    "path": ["type": "string"],
                    "events": [
                        "type": "array",
                        "items": objectSchema(
                            properties: [
                                "name": ["type": "string"],
                                "start": ["type": "string", "description": dateNote],
                                "end": ["type": "string", "description": dateNote + " Optional."],
                                "done": ["type": "boolean"],
                                "important": ["type": "boolean"],
                                "color": ["type": "string", "description": "Optional #RRGGBB override."],
                            ],
                            required: ["name", "start"]),
                    ],
                ],
                required: ["path", "events"]),
        ],
        [
            "name": "update_event",
            "description": """
                Update an event matched by its exact name. Pass end="none" \
                to turn a range back into a single-day event.
                """,
            "inputSchema": objectSchema(
                properties: [
                    "path": ["type": "string"],
                    "name": ["type": "string", "description": "Exact name of the event to update."],
                    "new_name": ["type": "string"],
                    "start": ["type": "string", "description": dateNote],
                    "end": ["type": "string", "description": dateNote + " Or \"none\" to clear."],
                    "done": ["type": "boolean"],
                    "important": ["type": "boolean"],
                    "color": ["type": "string"],
                ],
                required: ["path", "name"]),
        ],
        [
            "name": "remove_event",
            "description": "Remove an event matched by its exact name.",
            "inputSchema": objectSchema(
                properties: [
                    "path": ["type": "string"],
                    "name": ["type": "string"],
                ],
                required: ["path", "name"]),
        ],
        [
            "name": "add_holiday",
            "description": """
                Add a custom holiday (shaded band; optional name printed \
                under the dates). US federal holidays are automatic.
                """,
            "inputSchema": objectSchema(
                properties: [
                    "path": ["type": "string"],
                    "start": ["type": "string", "description": dateNote],
                    "end": ["type": "string", "description": dateNote + " Optional."],
                    "name": ["type": "string"],
                ],
                required: ["path", "start"]),
        ],
        [
            "name": "set_timeline_options",
            "description": "Update document-level options on a timeline.",
            "inputSchema": objectSchema(
                properties: [
                    "path": ["type": "string"],
                    "title": ["type": "string"],
                    "timeline_start": ["type": "string", "description": dateNote + " Or \"none\" to clear."],
                    "timeline_end": ["type": "string", "description": dateNote + " Or \"none\" to clear."],
                    "days_per_row": ["type": "integer", "minimum": 5, "maximum": 60],
                    "shade_weekends": ["type": "boolean"],
                    "shade_holidays": ["type": "boolean"],
                    "palette": [
                        "type": "string",
                        "description": "bright, muted, jewel, ocean, sunset, or forest.",
                    ],
                ],
                required: ["path"]),
        ],
        [
            "name": "render_timeline",
            "description": """
                Render a timeline to PNG or PDF (by output extension). PNG \
                renders are also returned inline so you can see the result.
                """,
            "inputSchema": objectSchema(
                properties: [
                    "path": ["type": "string"],
                    "output_path": ["type": "string", "description": "Destination .png or .pdf path."],
                    "dark": ["type": "boolean", "description": "Dark appearance (PNG only)."],
                ],
                required: ["path", "output_path"]),
        ],
    ]

    private static func objectSchema(
        properties: [String: Any], required: [String]
    ) -> [String: Any] {
        [
            "type": "object",
            "properties": properties,
            "required": required,
        ]
    }

    // MARK: - Tool implementations

    static func callTool(
        _ name: String, _ args: [String: Any]
    ) throws -> [String: Any] {
        switch name {
        case "create_timeline": return try createTimeline(args)
        case "read_timeline": return try readTimeline(args)
        case "add_events": return try addEvents(args)
        case "update_event": return try updateEvent(args)
        case "remove_event": return try removeEvent(args)
        case "add_holiday": return try addHoliday(args)
        case "set_timeline_options": return try setOptions(args)
        case "render_timeline": return try renderTimeline(args)
        default: throw ToolError(message: "Unknown tool: \(name)")
        }
    }

    private static func text(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]]]
    }

    private static func path(_ args: [String: Any]) throws -> URL {
        guard let raw = args["path"] as? String else {
            throw ToolError(message: "Missing path")
        }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
    }

    private static func day(_ value: Any?, _ field: String) throws -> Day? {
        guard let string = value as? String else { return nil }
        guard let day = Day(string: string) else {
            throw ToolError(message: "Invalid \(field) '\(string)': use YYYY-MM-DD")
        }
        return day
    }

    private static func load(_ url: URL) throws -> TimelineConfig {
        guard let textContent = try? String(contentsOf: url, encoding: .utf8) else {
            throw ToolError(message: "Could not read \(url.path)")
        }
        do {
            return try ConfigYAML.parse(textContent)
        } catch {
            throw ToolError(message: "Could not parse \(url.path): \(error.localizedDescription)")
        }
    }

    private static func save(_ config: TimelineConfig, to url: URL) throws {
        do {
            try ConfigYAML.serialize(config).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ToolError(message: "Could not write \(url.path): \(error.localizedDescription)")
        }
    }

    private static func createTimeline(_ args: [String: Any]) throws -> [String: Any] {
        let url = try path(args)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError(message: "\(url.path) already exists")
        }
        var config = TimelineConfig()
        config.title = args["title"] as? String ?? ""
        config.timelineStart = try day(args["timeline_start"], "timeline_start")
        config.timelineEnd = try day(args["timeline_end"], "timeline_end")
        try save(config, to: url)
        return text("Created \(url.path)")
    }

    private static func readTimeline(_ args: [String: Any]) throws -> [String: Any] {
        let url = try path(args)
        let config = try load(url)
        return text(ConfigYAML.serialize(config))
    }

    private static func addEvents(_ args: [String: Any]) throws -> [String: Any] {
        let url = try path(args)
        guard let events = args["events"] as? [[String: Any]], !events.isEmpty else {
            throw ToolError(message: "No events given")
        }
        var config = try load(url)
        var added: [String] = []
        for item in events {
            guard let name = item["name"] as? String,
                  let start = try day(item["start"], "start")
            else { throw ToolError(message: "Each event needs a name and a start date") }
            var event = TimelineEvent(name: name, start: start)
            event.end = try day(item["end"], "end")
            if let end = event.end, end < start {
                throw ToolError(message: "Event '\(name)': end is before start")
            }
            event.done = item["done"] as? Bool ?? false
            event.important = item["important"] as? Bool ?? false
            event.colorHex = item["color"] as? String
            config.events.append(event)
            added.append("\(name) (\(start)\(event.end.map { " – \($0)" } ?? ""))")
        }
        config.events.sort { $0.start < $1.start }
        try save(config, to: url)
        return text("Added \(added.count) event(s):\n" + added.joined(separator: "\n"))
    }

    private static func findEventIndex(
        _ config: TimelineConfig, named name: String
    ) throws -> Int {
        let matches = config.events.indices.filter { config.events[$0].name == name }
        guard !matches.isEmpty else {
            let names = config.events.map(\.name).joined(separator: ", ")
            throw ToolError(message: "No event named '\(name)'. Events: \(names)")
        }
        guard matches.count == 1 else {
            throw ToolError(message: "\(matches.count) events named '\(name)'; names must be unique to update")
        }
        return matches[0]
    }

    private static func updateEvent(_ args: [String: Any]) throws -> [String: Any] {
        let url = try path(args)
        guard let name = args["name"] as? String else {
            throw ToolError(message: "Missing event name")
        }
        var config = try load(url)
        let index = try findEventIndex(config, named: name)
        var event = config.events[index]

        if let newName = args["new_name"] as? String { event.name = newName }
        if let start = try day(args["start"], "start") { event.start = start }
        if let endString = args["end"] as? String {
            event.end = endString == "none" ? nil : try day(endString, "end")
        }
        if let end = event.end, end < event.start {
            throw ToolError(message: "End is before start")
        }
        if let done = args["done"] as? Bool { event.done = done }
        if let important = args["important"] as? Bool { event.important = important }
        if let color = args["color"] as? String { event.colorHex = color }

        config.events[index] = event
        config.events.sort { $0.start < $1.start }
        try save(config, to: url)
        return text("Updated '\(name)'")
    }

    private static func removeEvent(_ args: [String: Any]) throws -> [String: Any] {
        let url = try path(args)
        guard let name = args["name"] as? String else {
            throw ToolError(message: "Missing event name")
        }
        var config = try load(url)
        let index = try findEventIndex(config, named: name)
        config.events.remove(at: index)
        try save(config, to: url)
        return text("Removed '\(name)'")
    }

    private static func addHoliday(_ args: [String: Any]) throws -> [String: Any] {
        let url = try path(args)
        guard let start = try day(args["start"], "start") else {
            throw ToolError(message: "Missing start date")
        }
        var config = try load(url)
        var holiday = CustomHoliday(start: start)
        holiday.end = try day(args["end"], "end")
        holiday.name = args["name"] as? String ?? ""
        config.customHolidays.append(holiday)
        try save(config, to: url)
        return text("Added holiday\(holiday.name.isEmpty ? "" : " '\(holiday.name)'")")
    }

    private static func setOptions(_ args: [String: Any]) throws -> [String: Any] {
        let url = try path(args)
        var config = try load(url)
        var changed: [String] = []

        if let title = args["title"] as? String {
            config.title = title
            changed.append("title")
        }
        if let startString = args["timeline_start"] as? String {
            config.timelineStart =
                startString == "none" ? nil : try day(startString, "timeline_start")
            changed.append("timeline_start")
        }
        if let endString = args["timeline_end"] as? String {
            config.timelineEnd =
                endString == "none" ? nil : try day(endString, "timeline_end")
            changed.append("timeline_end")
        }
        if let daysPerRow = args["days_per_row"] as? Int {
            config.daysPerRow = daysPerRow
            changed.append("days_per_row")
        }
        if let shadeWeekends = args["shade_weekends"] as? Bool {
            config.shadeWeekends = shadeWeekends
            changed.append("shade_weekends")
        }
        if let shadeHolidays = args["shade_holidays"] as? Bool {
            config.shadeHolidays = shadeHolidays
            changed.append("shade_holidays")
        }
        if let palette = args["palette"] as? String {
            guard TimelineRenderer.palettes.contains(where: { $0.name == palette }) else {
                let names = TimelineRenderer.palettes.map(\.name).joined(separator: ", ")
                throw ToolError(message: "Unknown palette '\(palette)'. Available: \(names)")
            }
            config.paletteName = palette
            config.customPalette = nil
            changed.append("palette")
        }

        guard !changed.isEmpty else {
            throw ToolError(message: "No options given")
        }
        try save(config, to: url)
        return text("Updated \(changed.joined(separator: ", "))")
    }

    private static func renderTimeline(_ args: [String: Any]) throws -> [String: Any] {
        let url = try path(args)
        guard let outputRaw = args["output_path"] as? String else {
            throw ToolError(message: "Missing output_path")
        }
        let output = URL(fileURLWithPath: (outputRaw as NSString).expandingTildeInPath)
        let config = try load(url)
        let dark = args["dark"] as? Bool ?? false

        do {
            if output.pathExtension.lowercased() == "png" {
                try Exporter.writePNG(for: config, to: output, dark: dark)
            } else {
                try Exporter.pdfData(for: config).write(to: output)
            }
        } catch {
            throw ToolError(message: "Render failed: \(error.localizedDescription)")
        }

        var content: [[String: Any]] = [
            ["type": "text", "text": "Rendered \(url.path) -> \(output.path)"]
        ]
        // Inline PNGs (when reasonably small) so the model can see them
        if output.pathExtension.lowercased() == "png",
           let data = try? Data(contentsOf: output), data.count < 2_000_000 {
            content.append([
                "type": "image",
                "data": data.base64EncodedString(),
                "mimeType": "image/png",
            ])
        }
        return ["content": content]
    }
}
