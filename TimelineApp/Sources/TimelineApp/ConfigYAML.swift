import Foundation
import Yams

/// Reads and writes the same YAML schema as the Python CLI, so documents
/// stay interchangeable between the app and `timeline.py`.
enum ConfigYAML {
    enum ParseError: LocalizedError {
        case notADictionary
        case badDate(String)

        var errorDescription: String? {
            switch self {
            case .notADictionary:
                return "The file is not a timeline configuration."
            case .badDate(let s):
                return "Could not parse date \"\(s)\"."
            }
        }
    }

    // MARK: - Loading

    static func parse(_ text: String) throws -> TimelineConfig {
        let loaded = try Yams.load(yaml: text)
        guard let root = loaded as? [String: Any] else {
            if loaded == nil { return TimelineConfig() }
            throw ParseError.notADictionary
        }

        var config = TimelineConfig()
        config.title = root["title"] as? String ?? ""
        config.timelineStart = try (root["timeline_start"]).map(parseDay)
        config.timelineEnd = try (root["timeline_end"]).map(parseDay)
        config.daysPerRow = root["days_per_row"] as? Int
        config.shadeWeekends = root["shade_weekends"] as? Bool ?? true
        config.paletteName = root["palette"] as? String

        for item in root["custom_holidays"] as? [Any] ?? [] {
            if let dict = item as? [String: Any] {
                guard let startValue = dict["start"] else { continue }
                var holiday = CustomHoliday()
                holiday.start = try parseDay(startValue)
                holiday.end = try dict["end"].map(parseDay)
                holiday.name = dict["name"] as? String ?? ""
                config.customHolidays.append(holiday)
            } else {
                var holiday = CustomHoliday()
                holiday.start = try parseDay(item)
                config.customHolidays.append(holiday)
            }
        }

        for item in root["events"] as? [Any] ?? [] {
            guard let dict = item as? [String: Any],
                  let name = dict["name"] as? String,
                  let startValue = dict["start"]
            else { continue }
            var event = TimelineEvent()
            event.name = name
            event.start = try parseDay(startValue)
            event.end = try dict["end"].map(parseDay)
            event.done = dict["done"] as? Bool ?? false
            event.colorHex = dict["color"] as? String
            config.events.append(event)
        }

        return config
    }

    /// YAML date scalars arrive as Date (UTC midnight); quoted ones as String.
    private static func parseDay(_ value: Any) throws -> Day {
        if let date = value as? Date {
            return Day(date: date, calendar: Day.utcCalendar)
        }
        if let string = value as? String {
            if let day = Day(string: string) { return day }
            throw ParseError.badDate(string)
        }
        throw ParseError.badDate(String(describing: value))
    }

    // MARK: - Saving

    static func serialize(_ config: TimelineConfig) -> String {
        var lines: [String] = []

        if !config.title.isEmpty {
            lines.append("title: \(quote(config.title))")
            lines.append("")
        }
        if let start = config.timelineStart {
            lines.append("timeline_start: \"\(start)\"")
        }
        if let end = config.timelineEnd {
            lines.append("timeline_end: \"\(end)\"")
        }
        if let daysPerRow = config.daysPerRow {
            lines.append("days_per_row: \(daysPerRow)")
        }
        if !config.shadeWeekends {
            lines.append("shade_weekends: false")
        }
        if let palette = config.paletteName {
            lines.append("palette: \"\(palette)\"")
        }
        if config.timelineStart != nil || config.timelineEnd != nil
            || config.daysPerRow != nil || !config.shadeWeekends
            || config.paletteName != nil {
            lines.append("")
        }

        if !config.customHolidays.isEmpty {
            lines.append("custom_holidays:")
            for holiday in config.customHolidays {
                lines.append("  - start: \"\(holiday.start)\"")
                if let end = holiday.end {
                    lines.append("    end: \"\(end)\"")
                }
                if !holiday.name.isEmpty {
                    lines.append("    name: \(quote(holiday.name))")
                }
            }
            lines.append("")
        }

        lines.append("events:")
        for event in config.events {
            lines.append("  - name: \(quote(event.name))")
            lines.append("    start: \"\(event.start)\"")
            if let end = event.end {
                lines.append("    end: \"\(end)\"")
            }
            if event.done {
                lines.append("    done: true")
            }
            if let color = event.colorHex {
                lines.append("    color: \"\(color)\"")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
