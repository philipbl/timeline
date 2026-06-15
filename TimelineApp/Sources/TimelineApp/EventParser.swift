import Foundation

/// Result of parsing a free-text event line.
struct ParsedEvent: Equatable {
    var name: String
    var start: Day
    var end: Day?
}

/// Lightweight natural-language parser for event entry and paste-to-create.
/// Pulls a date or date range out of a line of text and treats the rest
/// as the title. Deliberately dependency-free and fully testable; the
/// Apple Intelligence path (when available) layers on top of this for
/// fuzzier input, falling back here.
enum EventParser {

    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
        "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12,
        "december": 12,
    ]

    // Monday = 0 ... Sunday = 6, matching Day.weekday
    private static let weekdays: [String: Int] = [
        "monday": 0, "mon": 0, "tuesday": 1, "tue": 1, "tues": 1,
        "wednesday": 2, "wed": 2, "thursday": 3, "thu": 3, "thurs": 3,
        "friday": 4, "fri": 4, "saturday": 5, "sat": 5, "sunday": 6, "sun": 6,
    ]

    private static let rangeSeparators = [
        "–", "—", "-", " to ", " through ", " until ", " thru ",
    ]

    /// Parse a single line into an event. Returns nil only if no usable
    /// title remains; a line with no date defaults to `today`.
    static func parse(
        _ rawText: String, relativeTo today: Day = .today(),
        defaultYear: Int? = nil
    ) -> ParsedEvent? {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip a leading markdown bullet or checkbox
        text = text.replacingOccurrences(
            of: #"^\s*(?:[-*+]|\d+\.)\s+(?:\[[ xX]?\]\s+)?"#,
            with: "", options: .regularExpression)
        guard !text.isEmpty else { return nil }

        let year = defaultYear ?? today.year

        if let (range, start, end) = findDateExpression(
            in: text, today: today, year: year)
        {
            let name = cleanTitle(byRemoving: range, from: text)
            // If stripping the date leaves nothing, keep the whole text
            return ParsedEvent(
                name: name.isEmpty ? text : name, start: start, end: end)
        }

        return ParsedEvent(name: text, start: today, end: nil)
    }

    /// Parse multiple lines (e.g. a pasted list) into events.
    static func parseList(
        _ text: String, relativeTo today: Day = .today(),
        defaultYear: Int? = nil
    ) -> [ParsedEvent] {
        text.split(whereSeparator: \.isNewline).compactMap {
            parse(String($0), relativeTo: today, defaultYear: defaultYear)
        }
    }

    // MARK: - Date expression search

    /// Finds the first date or range in the text. Returns the matched
    /// character range plus the resolved start/end.
    private static func findDateExpression(
        in text: String, today: Day, year: Int
    ) -> (Range<String.Index>, Day, Day?)? {
        // Try ranges first (they contain single dates), then singles
        if let result = findRange(in: text, today: today, year: year) {
            return result
        }
        if let (range, day) = findSingleDate(in: text, today: today, year: year) {
            return (range, day, nil)
        }
        return nil
    }

    private static func findRange(
        in text: String, today: Day, year: Int
    ) -> (Range<String.Index>, Day, Day?)? {
        let lower = text.lowercased()
        for separator in rangeSeparators {
            guard let sepRange = lower.range(of: separator) else { continue }
            let leftText = String(text[text.startIndex..<sepRange.lowerBound])
            let rightText = String(text[sepRange.upperBound...])

            guard let (leftRange, startDay) = findSingleDate(
                in: leftText, today: today, year: year, anchorAtEnd: true)
            else { continue }
            guard let (rightRel, endDayRaw) = findSingleDate(
                in: rightText, today: today, year: year,
                contextMonth: startDay.month)
            else { continue }

            // The end might land before the start when only a day was
            // given on the right ("Jul 31 - 2" never happens, but guard)
            var endDay = endDayRaw
            if endDay < startDay { endDay = startDay }

            // Map the right match back into the original string
            let rightStart = text.index(
                sepRange.upperBound,
                offsetBy: text.distance(
                    from: rightText.startIndex, to: rightRel.lowerBound))
            let fullRange = leftRange.lowerBound..<rightStart
            // Extend to include the right match end
            let rightEnd = text.index(
                sepRange.upperBound,
                offsetBy: text.distance(
                    from: rightText.startIndex, to: rightRel.upperBound))
            _ = fullRange
            return (leftRange.lowerBound..<rightEnd, startDay, endDay)
        }
        return nil
    }

    /// Finds a single date in `text`. With `anchorAtEnd`, prefers the
    /// last match (so "Trip Jul 1" picks the date, not stray numbers).
    /// `contextMonth` lets the right side of a range omit the month
    /// ("Jul 1-7" → 7 means Jul 7).
    private static func findSingleDate(
        in text: String, today: Day, year: Int,
        anchorAtEnd: Bool = false, contextMonth: Int? = nil
    ) -> (Range<String.Index>, Day)? {
        var matches: [(Range<String.Index>, Day)] = []

        // 1. Month name + day [+ year]: "Jul 1", "July 1, 2026"
        matches += scan(
            text,
            pattern:
                #"(?i)\b([a-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s*(\d{4}))?"#
        ) { groups in
            guard let month = months[groups[1].lowercased()] else { return nil }
            guard let day = Int(groups[2]) else { return nil }
            let y = groups.count > 3 && !groups[3].isEmpty ? Int(groups[3])! : year
            return Day(year: y, month: month, day: day)
        }

        // 2. Numeric m/d[/y]: "7/1", "7/1/2026", "07/01/26"
        matches += scan(
            text, pattern: #"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#
        ) { groups in
            guard let month = Int(groups[1]), let day = Int(groups[2]),
                (1...12).contains(month), (1...31).contains(day)
            else { return nil }
            var y = year
            if groups.count > 3, !groups[3].isEmpty, let parsed = Int(groups[3]) {
                y = parsed < 100 ? 2000 + parsed : parsed
            }
            return Day(year: y, month: month, day: day)
        }

        // 3. Bare day number, only when a context month is supplied
        //    (right side of a same-month range, "Jul 1-7")
        if let contextMonth {
            matches += scan(text, pattern: #"\b(\d{1,2})\b"#) { groups in
                guard let day = Int(groups[1]), (1...31).contains(day)
                else { return nil }
                return Day(year: year, month: contextMonth, day: day)
            }
        }

        // 4. Relative terms
        matches += relativeMatches(in: text, today: today)

        guard !matches.isEmpty else { return nil }
        matches.sort { $0.0.lowerBound < $1.0.lowerBound }
        return anchorAtEnd ? matches.last : matches.first
    }

    private static func relativeMatches(
        in text: String, today: Day
    ) -> [(Range<String.Index>, Day)] {
        var result: [(Range<String.Index>, Day)] = []

        for (range, _) in scanRanges(text, pattern: #"(?i)\btoday\b"#) {
            result.append((range, today))
        }
        for (range, _) in scanRanges(text, pattern: #"(?i)\btomorrow\b"#) {
            result.append((range, today.shifted(days: 1)))
        }
        for (range, _) in scanRanges(text, pattern: #"(?i)\byesterday\b"#) {
            result.append((range, today.shifted(days: -1)))
        }
        // "next <weekday>" / "this <weekday>" / bare "<weekday>".
        // Weekday names go in the alternation (longest first) so "next"
        // can only match the prefix, never be mistaken for the weekday.
        let names = weekdays.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        for (range, groups) in scanGroups(
            text, pattern: #"(?i)\b(?:(next|this)\s+)?(\#(names))\b"#)
        {
            guard let weekday = weekdays[groups[2].lowercased()] else { continue }
            let forceNext = groups[1].lowercased() == "next"
            result.append((range, nextWeekday(weekday, from: today, forceNext: forceNext)))
        }
        return result
    }

    /// The next date on `weekday`. Bare/"this" picks today if it matches,
    /// else the upcoming one; "next" always skips to the following week.
    private static func nextWeekday(
        _ weekday: Int, from today: Day, forceNext: Bool
    ) -> Day {
        var delta = (weekday - today.weekday + 7) % 7
        if forceNext { delta = delta == 0 ? 7 : delta + 7 }
        return today.shifted(days: delta)
    }

    // MARK: - Title cleanup

    private static func cleanTitle(
        byRemoving range: Range<String.Index>, from text: String
    ) -> String {
        var title = text
        title.removeSubrange(range)
        // Drop connector words left dangling where the date was
        title = title.replacingOccurrences(
            of: #"(?i)\s*\b(on|from|due|by|the|at)\b\s*$"#,
            with: "", options: .regularExpression)
        title = title.replacingOccurrences(
            of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return title.trimmingCharacters(
            in: CharacterSet(charactersIn: " \t-–—,:"))
    }

    // MARK: - Regex helpers

    private static func scan(
        _ text: String, pattern: String,
        transform: ([String]) -> Day?
    ) -> [(Range<String.Index>, Day)] {
        scanGroups(text, pattern: pattern).compactMap { range, groups in
            transform(groups).map { (range, $0) }
        }
    }

    private static func scanRanges(
        _ text: String, pattern: String
    ) -> [(Range<String.Index>, [String])] {
        scanGroups(text, pattern: pattern)
    }

    /// Returns each match's range and its capture groups (group 0 = whole).
    private static func scanGroups(
        _ text: String, pattern: String
    ) -> [(Range<String.Index>, [String])] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var results: [(Range<String.Index>, [String])] = []
        for match in regex.matches(in: text, range: fullRange) {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                let r = match.range(at: i)
                groups.append(r.location == NSNotFound ? "" : nsText.substring(with: r))
            }
            results.append((swiftRange, groups))
        }
        return results
    }
}
