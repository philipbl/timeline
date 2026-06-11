import Foundation

/// A calendar day, free of time zones — the class of bug we do not want.
struct Day: Hashable, Comparable, CustomStringConvertible {
    var year: Int
    var month: Int
    var day: Int

    static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Interpret a Date in the given calendar (defaults to the user's).
    init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Parse "2026-06-08" or "2026-6-8".
    init?(string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    static func today() -> Day {
        Day(date: Date())
    }

    var utcDate: Date {
        Day.utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Date at noon local time, for DatePicker bindings.
    var localDate: Date {
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func shifted(days: Int) -> Day {
        let d = Day.utcCalendar.date(byAdding: .day, value: days, to: utcDate)!
        let c = Day.utcCalendar.dateComponents([.year, .month, .day], from: d)
        return Day(year: c.year!, month: c.month!, day: c.day!)
    }

    func days(until other: Day) -> Int {
        Day.utcCalendar.dateComponents([.day], from: utcDate, to: other.utcDate).day!
    }

    /// Monday = 0 ... Sunday = 6 (matches Python's weekday()).
    var weekday: Int {
        // Calendar weekday: Sunday = 1 ... Saturday = 7
        let w = Day.utcCalendar.component(.weekday, from: utcDate)
        return (w + 5) % 7
    }

    var isWeekend: Bool { weekday == 5 || weekday == 6 }

    static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// "6/18" style label.
    var shortLabel: String { "\(month)/\(day)" }
}

struct TimelineEvent: Identifiable, Equatable {
    var id = UUID()
    var name: String = ""
    var start: Day = .today()
    var end: Day?
    var done: Bool = false
    /// Important events get a box around their label.
    var important: Bool = false
    /// Explicit color override ("#RRGGBB"); nil means palette-assigned.
    var colorHex: String?

    var isRange: Bool { end != nil }
    var effectiveEnd: Day { end ?? start }
}

struct CustomHoliday: Identifiable, Equatable {
    var id = UUID()
    var name: String = ""
    var start: Day = .today()
    var end: Day?

    var effectiveEnd: Day { end ?? start }
}

struct TimelineConfig: Equatable {
    var title: String = ""
    var timelineStart: Day?
    var timelineEnd: Day?
    /// Days per timeline row; nil sizes rows automatically (~30pt/day).
    var daysPerRow: Int?
    /// Gray bands behind weekends.
    var shadeWeekends: Bool = true
    /// Gray bands behind holidays (US federal and custom).
    var shadeHolidays: Bool = true
    /// Named color palette; nil uses the default ("bright").
    var paletteName: String?
    /// User-defined palette ("#RRGGBB" list); overrides paletteName.
    var customPalette: [String]?
    var events: [TimelineEvent] = []
    var customHolidays: [CustomHoliday] = []

    /// A copy with one event moved or resized by whole days, clamped to
    /// explicit timeline bounds. Used by canvas dragging.
    func shiftingEvent(
        id: UUID, part: TimelineRenderer.EventHitPart, by dayDelta: Int
    ) -> TimelineConfig {
        guard let index = events.firstIndex(where: { $0.id == id }) else {
            return self
        }
        var copy = self
        var event = copy.events[index]
        let duration = event.start.days(until: event.effectiveEnd)

        switch part {
        case .whole:
            var newStart = event.start.shifted(days: dayDelta)
            if let bound = timelineStart, newStart < bound { newStart = bound }
            if let bound = timelineEnd {
                let lastStart = bound.shifted(days: -duration)
                if newStart > lastStart { newStart = lastStart }
            }
            if event.end != nil {
                event.end = newStart.shifted(days: duration)
            }
            event.start = newStart

        case .start:
            var newStart = event.start.shifted(days: dayDelta)
            if let bound = timelineStart, newStart < bound { newStart = bound }
            if newStart > event.effectiveEnd { newStart = event.effectiveEnd }
            event.start = newStart

        case .end:
            guard event.end != nil else { return self }
            var newEnd = event.effectiveEnd.shifted(days: dayDelta)
            if let bound = timelineEnd, newEnd > bound { newEnd = bound }
            if newEnd < event.start { newEnd = event.start }
            event.end = newEnd
        }

        copy.events[index] = event
        copy.events.sort { $0.start < $1.start }
        return copy
    }

    static func starter() -> TimelineConfig {
        var config = TimelineConfig()
        config.title = "Timeline"
        config.timelineStart = .today()
        config.events = [
            TimelineEvent(name: "First Event", start: Day.today().shifted(days: 3)),
            TimelineEvent(
                name: "A Longer Task",
                start: Day.today().shifted(days: 5),
                end: Day.today().shifted(days: 9)),
        ]
        return config
    }
}
