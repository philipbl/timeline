import Foundation

/// US federal holidays, matching the names of the Python `holidays` package
/// (with "(observed)" handling folded in: the observed day gets the same
/// name so adjacent labels merge, as in the CLI).
enum USHolidays {
    static func holidays(forYear year: Int) -> [Day: String] {
        var result: [Day: String] = [:]

        func add(_ day: Day, _ name: String) {
            result[day] = name
            // Observed shifts: Saturday -> Friday before, Sunday -> Monday after
            if day.weekday == 5 {
                result[day.shifted(days: -1)] = name
            } else if day.weekday == 6 {
                result[day.shifted(days: 1)] = name
            }
        }

        func nthWeekday(_ n: Int, weekday: Int, month: Int) -> Day {
            // weekday: Monday = 0 ... Sunday = 6
            var day = Day(year: year, month: month, day: 1)
            while day.weekday != weekday { day = day.shifted(days: 1) }
            return day.shifted(days: (n - 1) * 7)
        }

        func lastWeekday(_ weekday: Int, month: Int) -> Day {
            var day = Day(year: year, month: month, day: 1).shifted(days: -1)
            let lastOfMonth: Day = {
                var d = Day(year: year, month: month, day: 28)
                while d.shifted(days: 1).month == month { d = d.shifted(days: 1) }
                return d
            }()
            day = lastOfMonth
            while day.weekday != weekday { day = day.shifted(days: -1) }
            return day
        }

        add(Day(year: year, month: 1, day: 1), "New Year's Day")
        add(nthWeekday(3, weekday: 0, month: 1), "Martin Luther King Jr. Day")
        add(nthWeekday(3, weekday: 0, month: 2), "Washington's Birthday")
        add(lastWeekday(0, month: 5), "Memorial Day")
        if year >= 2021 {
            add(Day(year: year, month: 6, day: 19), "Juneteenth National Independence Day")
        }
        add(Day(year: year, month: 7, day: 4), "Independence Day")
        add(nthWeekday(1, weekday: 0, month: 9), "Labor Day")
        add(nthWeekday(2, weekday: 0, month: 10), "Columbus Day")
        add(Day(year: year, month: 11, day: 11), "Veterans Day")
        add(nthWeekday(4, weekday: 3, month: 11), "Thanksgiving Day")
        add(Day(year: year, month: 12, day: 25), "Christmas Day")

        return result
    }

    /// Holidays for every year touched by [start, end].
    static func holidays(from start: Day, to end: Day) -> [Day: String] {
        var result: [Day: String] = [:]
        for year in (start.year - 1)...(end.year + 1) {
            result.merge(holidays(forYear: year)) { a, _ in a }
        }
        return result
    }
}
