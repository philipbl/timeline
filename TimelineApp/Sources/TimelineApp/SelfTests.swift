// In-binary test suite, run with `TimelineApp --self-test` (debug builds
// only). The command line tools don't ship XCTest or swift-testing, so
// tests live in the executable where they also get internal access.

#if DEBUG

import Foundation

private var currentTest = ""
private var failureCount = 0
private var testCount = 0

private func expect(
    _ condition: Bool, _ message: String = "", line: UInt = #line
) {
    if !condition {
        failureCount += 1
        print("  FAIL line \(line) in \(currentTest) \(message)")
    }
}

private func test(_ name: String, _ body: () throws -> Void) {
    currentTest = name
    testCount += 1
    do {
        try body()
    } catch {
        failureCount += 1
        print("  FAIL \(name): \(error)")
    }
}

// MARK: - Helpers

private func day(_ string: String) -> Day {
    Day(string: string)!
}

private func point(_ name: String, _ start: String) -> TimelineEvent {
    TimelineEvent(name: name, start: day(start))
}

private func span(_ name: String, _ start: String, _ end: String) -> TimelineEvent {
    TimelineEvent(name: name, start: day(start), end: day(end))
}

private func makeConfig(
    start: String = "2026-06-08", end: String? = nil,
    events: [TimelineEvent] = []
) -> TimelineConfig {
    var config = TimelineConfig()
    config.timelineStart = day(start)
    config.timelineEnd = end.map { day($0) }
    config.events = events
    return config
}

private func placement(
    _ placements: [TimelineRenderer.Placement], _ name: String
) -> TimelineRenderer.Placement {
    placements.first { $0.event.name == name }!
}

// MARK: - Suite

enum SelfTests {
    static func run() -> Int32 {
        // Day
        test("dayArithmetic") {
            let d = day("2026-06-08")
            expect(d.shifted(days: 1) == day("2026-06-09"))
            expect(d.shifted(days: 30) == day("2026-07-08"))
            expect(d.days(until: day("2026-06-18")) == 10)
        }
        test("dayWeekend") {
            expect(day("2026-06-13").isWeekend)  // Saturday
            expect(day("2026-06-14").isWeekend)  // Sunday
            expect(!day("2026-06-10").isWeekend)  // Wednesday
        }
        test("dayParsing") {
            expect(Day(string: "2026-06-08") == Day(year: 2026, month: 6, day: 8))
            expect(Day(string: "2026-7-1") == Day(year: 2026, month: 7, day: 1))
            expect(Day(string: "not a date") == nil)
        }

        // US holidays
        test("usHolidayNames") {
            let holidays = USHolidays.holidays(forYear: 2026)
            expect(holidays[day("2026-11-26")] == "Thanksgiving Day")
            expect(holidays[day("2026-12-25")] == "Christmas Day")
            expect(holidays[day("2026-06-19")] == "Juneteenth National Independence Day")
        }
        test("observedHolidayGetsSameName") {
            // July 4, 2026 is a Saturday; July 3 is the observed day
            let holidays = USHolidays.holidays(forYear: 2026)
            expect(holidays[day("2026-07-03")] == "Independence Day")
            expect(holidays[day("2026-07-04")] == "Independence Day")
        }

        // YAML round trip
        test("yamlRoundTrip") {
            var config = makeConfig(
                start: "2026-06-08", end: "2026-07-20",
                events: [
                    point("Dot", "2026-06-18"),
                    span("Range", "2026-07-01", "2026-07-07"),
                ])
            config.title = "Round \"Trip\""
            config.daysPerRow = 14
            config.shadeWeekends = false
            config.shadeHolidays = false
            config.events[0].done = true
            config.events[0].important = true
            config.events[1].colorHex = "#123456"
            config.customHolidays = [
                CustomHoliday(
                    name: "Retreat", start: day("2026-06-15"), end: day("2026-06-16"))
            ]
            config.customPalette = ["#D62828", "#003049"]

            let parsed = try ConfigYAML.parse(ConfigYAML.serialize(config))

            expect(parsed.title == config.title)
            expect(parsed.timelineStart == config.timelineStart)
            expect(parsed.timelineEnd == config.timelineEnd)
            expect(parsed.daysPerRow == 14)
            expect(parsed.shadeWeekends == false)
            expect(parsed.shadeHolidays == false)
            expect(parsed.customPalette == ["#D62828", "#003049"])
            expect(parsed.events.map(\.name) == ["Dot", "Range"])
            expect(parsed.events[0].done && parsed.events[0].important)
            expect(parsed.events[1].colorHex == "#123456")
            expect(parsed.customHolidays.first?.name == "Retreat")
            expect(parsed.customHolidays.first?.end == day("2026-06-16"))
        }
        test("yamlNamedPaletteRoundTrip") {
            var config = makeConfig(events: [point("A", "2026-06-10")])
            config.paletteName = "jewel"
            let parsed = try ConfigYAML.parse(ConfigYAML.serialize(config))
            expect(parsed.paletteName == "jewel")
            expect(parsed.customPalette == nil)
        }

        // Renderer geometry
        test("defaultRowLength") {
            let renderer = TimelineRenderer(
                config: makeConfig(events: [point("A", "2026-06-10")]))
            expect(renderer.dayWidth == 30)
            expect(renderer.maxDaysPerRow == 22)
        }
        test("daysPerRowOverride") {
            var config = makeConfig(events: [point("A", "2026-06-10")])
            config.daysPerRow = 10
            let renderer = TimelineRenderer(config: config)
            expect(renderer.maxDaysPerRow == 10)
            expect(renderer.dayWidth == (792 - 108) / 10)
        }
        test("longTimelinePaginates") {
            let config = makeConfig(end: "2026-12-31", events: [point("A", "2026-06-10")])
            expect(TimelineRenderer(config: config, layout: .paged).pageCount > 1)
            let continuous = TimelineRenderer(config: config, layout: .continuous)
            expect(continuous.pageCount == 1)
            expect(continuous.canvasSize.height > TimelineRenderer.pageSize.height)
        }
        test("startDateInferredFromEarliestEvent") {
            var config = makeConfig(
                events: [point("B", "2025-12-01"), point("A", "2025-11-20")])
            config.timelineStart = nil
            let renderer = TimelineRenderer(config: config)
            expect(renderer.startDay == day("2025-11-20"))
            expect(renderer.endDay == day("2025-12-01"))
        }
        test("endDateInferredFromLatestEvent") {
            let config = makeConfig(
                events: [point("A", "2026-06-10"), span("B", "2026-06-12", "2026-07-02")])
            expect(TimelineRenderer(config: config).endDay == day("2026-07-02"))
        }

        // Row layout
        test("eventsOutsideRowExcluded") {
            let config = makeConfig(
                end: "2026-08-15",
                events: [point("In", "2026-06-10"), point("Out", "2026-08-10")])
            let renderer = TimelineRenderer(config: config)
            let placements = renderer.layoutEvents(forRow: day("2026-06-08"), numDays: 10)
            expect(placements.map(\.event.name) == ["In"])
        }
        test("wrappedEventLabelOnlyOnStartingRow") {
            let config = makeConfig(
                end: "2026-06-30", events: [span("Wrap", "2026-06-12", "2026-06-25")])
            let renderer = TimelineRenderer(config: config)
            let row1 = renderer.layoutEvents(forRow: day("2026-06-08"), numDays: 10)
            let row2 = renderer.layoutEvents(forRow: day("2026-06-18"), numDays: 10)
            expect(placement(row1, "Wrap").labelY != nil)
            expect(placement(row2, "Wrap").labelY == nil)
        }
        test("wrappedEventContinuationFlags") {
            let config = makeConfig(
                end: "2026-06-30", events: [span("Wrap", "2026-06-12", "2026-06-25")])
            let renderer = TimelineRenderer(config: config)
            let p1 = placement(
                renderer.layoutEvents(forRow: day("2026-06-08"), numDays: 10), "Wrap")
            let p2 = placement(
                renderer.layoutEvents(forRow: day("2026-06-18"), numDays: 10), "Wrap")
            expect(!p1.continuesLeft && p1.continuesRight)
            expect(p2.continuesLeft && !p2.continuesRight)
        }
        test("overlappingRangesStack") {
            let config = makeConfig(events: [
                span("A", "2026-06-09", "2026-06-12"),
                span("B", "2026-06-11", "2026-06-14"),
            ])
            let renderer = TimelineRenderer(config: config)
            let placements = renderer.layoutEvents(forRow: day("2026-06-08"), numDays: 10)
            expect(
                placement(placements, "B").lineYOffset
                    > placement(placements, "A").lineYOffset)
        }
        test("labelsAvoidRangeBars") {
            let config = makeConfig(events: [
                span("Low", "2026-06-09", "2026-06-16"),
                span("High", "2026-06-10", "2026-06-15"),
            ])
            let renderer = TimelineRenderer(config: config)
            let placements = renderer.layoutEvents(forRow: day("2026-06-08"), numDays: 10)
            let topBar = placements.map(\.lineYOffset).max()!
            for p in placements {
                expect(p.labelY! > topBar)
            }
        }
        test("labelsDoNotOverlapEachOther") {
            let config = makeConfig(events: [
                point("Event Alpha", "2026-06-10"),
                point("Event Bravo", "2026-06-11"),
                point("Event Charlie", "2026-06-12"),
            ])
            let renderer = TimelineRenderer(config: config)
            let placements = renderer.layoutEvents(forRow: day("2026-06-08"), numDays: 10)
            let boxes = placements.map {
                (x: $0.labelX!, y: $0.labelY!, w: $0.textWidth, h: renderer.labelTextHeight)
            }
            for (i, a) in boxes.enumerated() {
                for b in boxes[(i + 1)...] {
                    let overlaps = !(a.x + a.w < b.x || a.x > b.x + b.w
                        || a.y + a.h < b.y || a.y > b.y + b.h)
                    expect(!overlaps)
                }
            }
        }

        // Same-day wedges
        test("sameDayPointsSplitIntoHalfCircles") {
            let config = makeConfig(
                events: [point("A", "2026-06-10"), point("B", "2026-06-10")])
            let renderer = TimelineRenderer(config: config)
            let placements = renderer.layoutEvents(forRow: day("2026-06-08"), numDays: 10)
            expect(placements.allSatisfy { $0.wedgeCount == 2 })
            expect(Set(placements.map(\.wedgeIndex)) == [0, 1])
        }
        test("lonePointKeepsFullCircle") {
            let config = makeConfig(events: [point("A", "2026-06-10")])
            let renderer = TimelineRenderer(config: config)
            expect(
                renderer.layoutEvents(forRow: day("2026-06-08"), numDays: 10)[0]
                    .wedgeCount == 1)
        }
        test("sameDayPointAndRangeDoNotSplit") {
            let config = makeConfig(events: [
                point("Dot", "2026-06-10"), span("Bar", "2026-06-10", "2026-06-12"),
            ])
            let renderer = TimelineRenderer(config: config)
            let placements = renderer.layoutEvents(forRow: day("2026-06-08"), numDays: 10)
            expect(placement(placements, "Dot").wedgeCount == 1)
        }

        // Colors
        test("colorsAssignedInDateOrder") {
            let late = point("Late", "2026-06-20")
            let early = point("Early", "2026-06-09")
            let config = makeConfig(events: [late, early])
            let resolved = TimelineRenderer.resolvedColorHex(for: config)
            expect(resolved[early.id] == TimelineRenderer.palettes[0].colors[0])
            expect(resolved[late.id] == TimelineRenderer.palettes[0].colors[1])
        }
        test("adjacentEventsNeverShareColor") {
            let events = (0..<10).map { point("E\($0)", "2026-06-\(9 + $0)") }
            let config = makeConfig(events: events)
            let resolved = TimelineRenderer.resolvedColorHex(for: config)
            let sorted = config.events.sorted { $0.start < $1.start }
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                expect(resolved[a.id] != resolved[b.id])
            }
        }
        test("explicitColorRespectedAndSkipped") {
            var custom = point("Custom", "2026-06-10")
            custom.colorHex = "#123456"
            let other = point("Other", "2026-06-11")
            let config = makeConfig(events: [custom, other])
            let resolved = TimelineRenderer.resolvedColorHex(for: config)
            expect(resolved[custom.id] == "#123456")
            expect(resolved[other.id] == TimelineRenderer.palettes[0].colors[0])
        }
        test("customPaletteOverridesNamed") {
            var config = makeConfig(events: [point("A", "2026-06-10")])
            config.paletteName = "jewel"
            config.customPalette = ["#111111", "#222222"]
            expect(
                TimelineRenderer.effectivePalette(for: config) == ["#111111", "#222222"])
            config.customPalette = nil
            expect(
                TimelineRenderer.effectivePalette(for: config)
                    == TimelineRenderer.palette(named: "jewel"))
        }

        // Shading
        test("shadingChecksRespectOptions") {
            var config = makeConfig(events: [point("A", "2026-06-10")])
            config.shadeWeekends = false
            config.shadeHolidays = true
            let renderer = TimelineRenderer(config: config)
            expect(!renderer.shouldShade(day("2026-06-13")))  // Saturday
            expect(renderer.shouldShade(day("2026-06-19")))  // Juneteenth

            config.shadeWeekends = true
            config.shadeHolidays = false
            let renderer2 = TimelineRenderer(config: config)
            expect(renderer2.shouldShade(day("2026-06-13")))
            expect(!renderer2.shouldShade(day("2026-06-19")))
        }
        test("customHolidayDetected") {
            var config = makeConfig(events: [point("A", "2026-06-10")])
            config.customHolidays = [
                CustomHoliday(
                    name: "Retreat", start: day("2026-06-15"), end: day("2026-06-17"))
            ]
            let renderer = TimelineRenderer(config: config)
            expect(renderer.isHoliday(day("2026-06-16")))
            expect(renderer.holidayName(day("2026-06-16")) == "Retreat")
            expect(!renderer.isHoliday(day("2026-06-18")))
        }

        // Exports
        test("pdfExportProducesValidData") {
            let config = makeConfig(
                end: "2026-07-20",
                events: [point("A", "2026-06-18"), span("B", "2026-07-01", "2026-07-07")])
            let data = try Exporter.pdfData(for: config)
            expect(data.count > 0)
            expect(data.prefix(4) == Data("%PDF".utf8))
        }

        if failureCount == 0 {
            print("All \(testCount) tests passed")
            return 0
        }
        print("\(failureCount) failure(s) across \(testCount) tests")
        return 1
    }
}

#endif
