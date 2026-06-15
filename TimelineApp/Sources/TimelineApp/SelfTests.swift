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
            config.events[0].notes = "bring the slides"
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
            expect(parsed.events[0].notes == "bring the slides")
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
        test("pastDayMarksOnlyWithExplicitBounds") {
            var config = makeConfig(events: [point("A", "2025-11-20")])
            expect(TimelineRenderer(config: config).marksPastDays)  // has start
            config.timelineStart = nil
            expect(!TimelineRenderer(config: config).marksPastDays)
            config.timelineEnd = day("2025-12-31")
            expect(TimelineRenderer(config: config).marksPastDays)
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

        // Hit testing
        test("hitTestFindsDotBarAndLabel") {
            let dot = point("Dot", "2026-06-10")
            let bar = span("Bar", "2026-06-13", "2026-06-16")
            let config = makeConfig(end: "2026-06-22", events: [dot, bar])
            let renderer = TimelineRenderer(config: config, layout: .continuous)
            let row = renderer.rows[0]

            // Dot marker: 2 days from row start
            let dotX = renderer.leftMargin + 2 * renderer.dayWidth
            expect(renderer.eventID(at: CGPoint(x: dotX, y: row.baselineY)) == dot.id)

            // Bar: above the baseline at its stack offset, mid-span
            let barX = renderer.leftMargin + 6.5 * renderer.dayWidth
            expect(
                renderer.eventID(
                    at: CGPoint(x: barX, y: row.baselineY + renderer.rangeBaseOffset))
                    == bar.id)

            // Label of the dot
            let placements = renderer.layoutEvents(
                forRow: row.startDay, numDays: row.numDays)
            let dotPlacement = placements.first { $0.event.id == dot.id }!
            expect(
                renderer.eventID(
                    at: CGPoint(
                        x: dotPlacement.labelX! + 2,
                        y: row.baselineY + dotPlacement.labelY! + 2)) == dot.id)

            // Empty space misses
            expect(
                renderer.eventID(
                    at: CGPoint(x: renderer.leftMargin + 11 * renderer.dayWidth,
                                y: row.baselineY)) == nil)
        }

        // Event shifting (canvas drag)
        test("shiftEventMovesPreservingDuration") {
            let bar = span("Bar", "2026-06-10", "2026-06-12")
            let config = makeConfig(end: "2026-06-22", events: [bar])
            let moved = config.shiftingEvent(id: bar.id, part: .whole, by: 3)
            expect(moved.events[0].start == day("2026-06-13"))
            expect(moved.events[0].end == day("2026-06-15"))
        }
        test("shiftEventResizesEnds") {
            let bar = span("Bar", "2026-06-10", "2026-06-12")
            let config = makeConfig(end: "2026-06-22", events: [bar])

            let longer = config.shiftingEvent(id: bar.id, part: .end, by: 4)
            expect(longer.events[0].start == day("2026-06-10"))
            expect(longer.events[0].end == day("2026-06-16"))

            let trimmed = config.shiftingEvent(id: bar.id, part: .start, by: 1)
            expect(trimmed.events[0].start == day("2026-06-11"))
            expect(trimmed.events[0].end == day("2026-06-12"))

            // End can't cross start; start can't cross end
            let collapsed = config.shiftingEvent(id: bar.id, part: .end, by: -10)
            expect(collapsed.events[0].end == day("2026-06-10"))
            let pinched = config.shiftingEvent(id: bar.id, part: .start, by: 10)
            expect(pinched.events[0].start == day("2026-06-12"))
        }
        test("shiftEventClampsToBounds") {
            let dot = point("Dot", "2026-06-10")
            let config = makeConfig(end: "2026-06-22", events: [dot])
            let early = config.shiftingEvent(id: dot.id, part: .whole, by: -10)
            expect(early.events[0].start == day("2026-06-08"))
            let late = config.shiftingEvent(id: dot.id, part: .whole, by: 30)
            expect(late.events[0].start == day("2026-06-22"))
        }
        test("dayAtPointMapsAcrossRows") {
            // 30 days -> two rows of 22 and 8
            let config = makeConfig(end: "2026-07-07", events: [point("A", "2026-06-10")])
            let renderer = TimelineRenderer(config: config, layout: .continuous)
            expect(renderer.rows.count == 2)
            let row1 = renderer.rows[0]
            let row2 = renderer.rows[1]

            // Third tick of row 1
            expect(
                renderer.day(
                    at: CGPoint(
                        x: renderer.leftMargin + 2 * renderer.dayWidth,
                        y: row1.baselineY + 5)) == day("2026-06-10"))
            // Second tick of row 2 (vertically nearest to row 2)
            expect(
                renderer.day(
                    at: CGPoint(
                        x: renderer.leftMargin + renderer.dayWidth,
                        y: row2.baselineY - 5)) == day("2026-07-01"))
            // Clamps beyond the short row's end
            expect(
                renderer.day(
                    at: CGPoint(x: 5000, y: row2.baselineY)) == day("2026-07-07"))
        }
        test("hitTestFindsBarEnds") {
            let bar = span("Bar", "2026-06-13", "2026-06-16")
            let config = makeConfig(end: "2026-06-22", events: [bar])
            let renderer = TimelineRenderer(config: config, layout: .continuous)
            let row = renderer.rows[0]
            let y = row.baselineY + renderer.rangeBaseOffset
            let startX = renderer.leftMargin + 5 * renderer.dayWidth
            let endX = renderer.leftMargin + 8 * renderer.dayWidth
            expect(renderer.eventHit(at: CGPoint(x: startX, y: y))?.part == .start)
            expect(renderer.eventHit(at: CGPoint(x: endX, y: y))?.part == .end)
            expect(
                renderer.eventHit(at: CGPoint(x: (startX + endX) / 2, y: y))?.part
                    == .whole)
        }

        // Event delete / duplicate (the data path behind the editor rows;
        // the original delete bug was SwiftUI view diffing, not reachable
        // headlessly, but the mutation semantics are locked down here)
        test("removingEventByID") {
            let a = point("A", "2026-06-10")
            let b = point("B", "2026-06-12")
            let config = makeConfig(events: [a, b])
            expect(config.removingEvent(id: a.id).events.map(\.name) == ["B"])
            // removing a missing id is a no-op
            expect(config.removingEvent(id: UUID()).events.count == 2)
        }
        test("duplicatingEventInsertsChronologicallyWithNewID") {
            let a = span("Trip", "2026-06-15", "2026-06-18")
            let later = point("Later", "2026-06-20")
            let config = makeConfig(events: [a, later])
            let result = config.duplicatingEvent(id: a.id)
            expect(result != nil)
            let after = result!.config
            expect(after.events.count == 3)
            expect(result!.newID != a.id)
            // duplicate keeps content and lands next to the original (index 1)
            let dup = after.events.first { $0.id == result!.newID }!
            expect(dup.name == "Trip" && dup.start == a.start && dup.end == a.end)
            expect(after.events.map(\.name) == ["Trip", "Trip", "Later"])
            // duplicating a missing id returns nil
            expect(config.duplicatingEvent(id: UUID()) == nil)
        }

        // MCP server
        test("mcpInitializeAndToolsList") {
            let initResponse = MCPServer.handle([
                "jsonrpc": "2.0", "id": 1, "method": "initialize",
                "params": ["protocolVersion": "2024-11-05"],
            ])
            let initResult = initResponse?["result"] as? [String: Any]
            expect(initResult?["protocolVersion"] as? String == "2024-11-05")

            let listResponse = MCPServer.handle([
                "jsonrpc": "2.0", "id": 2, "method": "tools/list",
            ])
            let tools =
                (listResponse?["result"] as? [String: Any])?["tools"]
                as? [[String: Any]]
            expect((tools?.count ?? 0) == 8)

            // Notifications get no response
            expect(
                MCPServer.handle([
                    "jsonrpc": "2.0", "method": "notifications/initialized",
                ]) == nil)
        }
        test("mcpCreateAddUpdateRenderFlow") {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("mcp-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent("t.timeline").path

            _ = try MCPServer.callTool(
                "create_timeline",
                ["path": file, "title": "MCP", "timeline_start": "2026-06-08"])
            _ = try MCPServer.callTool(
                "add_events",
                [
                    "path": file,
                    "events": [
                        ["name": "Dot", "start": "2026-06-15"],
                        ["name": "Bar", "start": "2026-06-10", "end": "2026-06-12"],
                    ],
                ])
            _ = try MCPServer.callTool(
                "update_event",
                ["path": file, "name": "Dot", "important": true, "start": "2026-06-16"])

            let parsed = try ConfigYAML.parse(
                try String(contentsOfFile: file, encoding: .utf8))
            expect(parsed.title == "MCP")
            expect(parsed.events.map(\.name) == ["Bar", "Dot"])  // sorted
            expect(parsed.events[1].important)
            expect(parsed.events[1].start == day("2026-06-16"))

            _ = try MCPServer.callTool("remove_event", ["path": file, "name": "Bar"])
            let afterRemove = try ConfigYAML.parse(
                try String(contentsOfFile: file, encoding: .utf8))
            expect(afterRemove.events.count == 1)

            // Render returns inline image content
            let pngPath = dir.appendingPathComponent("out.png").path
            let render = try MCPServer.callTool(
                "render_timeline", ["path": file, "output_path": pngPath])
            let contents = render["content"] as? [[String: Any]]
            expect(contents?.contains { $0["type"] as? String == "image" } == true)
            expect(FileManager.default.fileExists(atPath: pngPath))

            // PDF render works too
            let pdfPath = dir.appendingPathComponent("out.pdf").path
            _ = try MCPServer.callTool(
                "render_timeline", ["path": file, "output_path": pdfPath])
            let pdfData = FileManager.default.contents(atPath: pdfPath)
            expect(pdfData?.prefix(4) == Data("%PDF".utf8))

            // Duplicate create fails
            do {
                _ = try MCPServer.callTool("create_timeline", ["path": file])
                expect(false, "expected duplicate create to throw")
            } catch {}
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
