import CoreGraphics
import CoreText
import Foundation

/// Port of the Python ReportLab renderer (timeline.py). Coordinates are
/// PDF-style: origin bottom-left, y grows upward — the same convention
/// ReportLab uses, so the layout math carries over unchanged.
struct TimelineRenderer {

    /// Named palettes, all dark enough to double as label text.
    static let palettes: [(name: String, colors: [String])] = [
        (
            "bright",
            ["#FF6B6B", "#3A86FF", "#FF9F1C", "#9B5DE5", "#00A878", "#E84A8A"]
        ),
        (
            "muted",
            ["#C0392B", "#1F618D", "#1E8449", "#B9770E", "#7D3C98", "#148F77"]
        ),
        (
            "jewel",
            ["#7B1FA2", "#C2185B", "#00838F", "#EF6C00", "#303F9F", "#558B2F"]
        ),
        (
            "ocean",
            ["#0277BD", "#00838F", "#3949AB", "#00695C", "#5E35B1", "#456990"]
        ),
        (
            "sunset",
            ["#E53935", "#FB8C00", "#C2185B", "#F4511E", "#8E24AA", "#D81B60"]
        ),
        (
            "forest",
            ["#2E7D32", "#827717", "#00695C", "#558B2F", "#37474F", "#6D4C41"]
        ),
    ]

    static func palette(named name: String?) -> [String] {
        palettes.first { $0.name == name }?.colors ?? palettes[0].colors
    }

    /// Custom palette from the document wins over a named one.
    static func effectivePalette(for config: TimelineConfig) -> [String] {
        if let custom = config.customPalette, !custom.isEmpty { return custom }
        return palette(named: config.paletteName)
    }

    /// Default palette, used as a fallback.
    static var eventColors: [String] { palettes[0].colors }

    /// UI chrome colors; event colors stay the same in both themes.
    struct Theme {
        var bar: CGColor
        var tick: CGColor
        var tickMuted: CGColor
        var date: CGColor
        var dateMuted: CGColor
        var weekendBand: CGColor
        var pastX: CGColor
        var done: CGColor
        var title: CGColor
        var subtitle: CGColor
        var footer: CGColor

        static let light = Theme(
            bar: cg("#33333B"),
            tick: cg("#4C4C55"),
            tickMuted: cg("#B3B6BC"),
            date: cg("#55555E"),
            dateMuted: cg("#A8ABB2"),
            weekendBand: cg("#F1F2F5"),
            pastX: cg("#6E6E76"),
            done: cg("#9A9AA2"),
            title: cg("#26262E"),
            subtitle: cg("#8A8A93"),
            footer: cg("#B8B8C0"))

        static let dark = Theme(
            bar: cg("#C8C8D0"),
            tick: cg("#9A9AA4"),
            tickMuted: cg("#55555E"),
            date: cg("#B8B8C2"),
            dateMuted: cg("#6A6A74"),
            weekendBand: cg("#2A2A31"),
            pastX: cg("#8A8A94"),
            done: cg("#6E6E78"),
            title: cg("#E8E8EE"),
            subtitle: cg("#8A8A93"),
            footer: cg("#5A5A64"))
    }

    /// Paged reproduces the CLI's letter-landscape pages (PDF export).
    /// Continuous lays every row on one tall canvas with the title once
    /// (app preview and PNG export).
    enum Layout {
        case paged
        case continuous
    }

    static func cg(_ hex: String) -> CGColor {
        var value: UInt64 = 0
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        Scanner(string: cleaned).scanHexInt64(&value)
        // sRGB, not generic RGB — must match SwiftUI's Color(.sRGB) exactly
        // or the preview background visibly differs from the canvas fill
        return CGColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1)
    }

    // Page geometry (US letter, landscape)
    static let pageSize = CGSize(width: 792, height: 612)
    let leftMargin: CGFloat = 54
    let rightMargin: CGFloat = 54
    let baseTopMargin: CGFloat = 54
    let bottomMargin: CGFloat = 54

    // Timeline visual constants — keep in sync with timeline.py
    let dayWidth: CGFloat  // 30 by default; set from days_per_row
    let tickHeight: CGFloat = 12
    let dotRadius: CGFloat = 4.5
    let rangeBaseOffset: CGFloat = 10
    let rangeStackSpacing: CGFloat = 9
    let eventVerticalSpacing: CGFloat = 16
    let eventBaseOffset: CGFloat = 25
    let maxEventHeight: CGFloat = 86.4  // 1.2 inch
    let rowDepthBelow: CGFloat = 52
    let labelFontSize: CGFloat = 9
    let labelTextHeight: CGFloat = 12

    let config: TimelineConfig
    let layout: Layout
    let theme: Theme
    let includeGenerated: Bool
    let startDay: Day
    let endDay: Day
    let totalDays: Int
    let maxDaysPerRow: Int
    let topMargin: CGFloat
    private let sortedEvents: [TimelineEvent]
    private let eventColorMap: [UUID: CGColor]
    private let usHolidays: [Day: String]

    struct Placement {
        var event: TimelineEvent
        var isRange: Bool
        var startX: CGFloat
        var endX: CGFloat
        var markerX: CGFloat
        var lineYOffset: CGFloat
        var continuesLeft: Bool
        var continuesRight: Bool
        var wedgeIndex: Int
        var wedgeCount: Int
        var labelX: CGFloat?
        var labelY: CGFloat?
        var textWidth: CGFloat
    }

    struct Row {
        var startDay: Day
        var numDays: Int
        var baselineY: CGFloat
        var pageIndex: Int
    }

    let rows: [Row]
    /// Page size for paged layout; full canvas size for continuous.
    let canvasSize: CGSize
    var pageCount: Int { (rows.map(\.pageIndex).max() ?? 0) + 1 }

    /// Default palette assignment, exposed so the editor can show each
    /// event's effective color.
    static func resolvedColorHex(for config: TimelineConfig) -> [UUID: String] {
        let palette = effectivePalette(for: config)
        let sorted = config.events.sorted { $0.start < $1.start }
        var result: [UUID: String] = [:]
        var paletteIndex = 0
        for event in sorted {
            if let hex = event.colorHex, !hex.isEmpty {
                result[event.id] = hex
            } else {
                result[event.id] = palette[paletteIndex % palette.count]
                paletteIndex += 1
            }
        }
        return result
    }

    init(
        config: TimelineConfig, layout: Layout = .paged, theme: Theme = .light,
        includeGenerated: Bool = false
    ) {
        self.config = config
        self.layout = layout
        self.theme = theme
        self.includeGenerated = includeGenerated

        let start = config.timelineStart ?? .today()
        var end = config.timelineEnd ?? start
        if config.timelineEnd == nil {
            for event in config.events {
                if event.effectiveEnd > end { end = event.effectiveEnd }
            }
        }
        if end < start { end = start }
        self.startDay = start
        self.endDay = end
        self.totalDays = start.days(until: end) + 1
        self.topMargin = baseTopMargin + (config.title.isEmpty ? 0 : 39.6)

        // days_per_row stretches/shrinks day spacing to fill the row;
        // without it, days get 30pt each
        let usableWidth = Self.pageSize.width - leftMargin - rightMargin
        if let daysPerRow = config.daysPerRow, daysPerRow >= 3 {
            self.maxDaysPerRow = min(daysPerRow, 60)
            self.dayWidth = usableWidth / CGFloat(min(daysPerRow, 60))
        } else {
            self.dayWidth = 30
            self.maxDaysPerRow = max(1, Int(usableWidth / 30))
        }

        let resolved = Self.resolvedColorHex(for: config)
        self.eventColorMap = resolved.mapValues { Self.cg($0) }
        self.sortedEvents = config.events.sorted { $0.start < $1.start }
        self.usHolidays = USHolidays.holidays(from: start, to: end)

        // Split into rows
        var rowSpans: [(Day, Int)] = []
        var current = start
        var remaining = totalDays
        while remaining > 0 {
            let days = min(maxDaysPerRow, remaining)
            rowSpans.append((current, days))
            current = current.shifted(days: days)
            remaining -= days
        }

        // Per-row space needed above the baseline (driven by label stacking)
        var gapsAbove: [CGFloat] = []
        for (rowDay, days) in rowSpans {
            var labelTop: CGFloat = 0
            _ = Self.layoutEvents(
                forRow: rowDay, numDays: days, events: sortedEvents,
                leftMargin: leftMargin, dayWidth: dayWidth,
                rangeBaseOffset: rangeBaseOffset, rangeStackSpacing: rangeStackSpacing,
                eventBaseOffset: eventBaseOffset, eventVerticalSpacing: eventVerticalSpacing,
                maxEventHeight: maxEventHeight, labelFontSize: labelFontSize,
                labelTextHeight: labelTextHeight, maxLabelTop: &labelTop)
            labelTop = max(labelTop, eventBaseOffset + 12)
            gapsAbove.append(labelTop + 8)
        }

        var built: [Row] = []
        switch layout {
        case .paged:
            let pageTop = Self.pageSize.height - topMargin
            var currentY: CGFloat?
            var pageIndex = 0
            for (index, (rowDay, days)) in rowSpans.enumerated() {
                let gapAbove = gapsAbove[index]
                var y: CGFloat
                if let existing = currentY {
                    y = existing - rowDepthBelow - gapAbove
                } else {
                    y = pageTop - gapAbove
                }
                if y < bottomMargin + rowDepthBelow {
                    pageIndex += 1
                    y = pageTop - gapAbove
                }
                built.append(
                    Row(startDay: rowDay, numDays: days, baselineY: y, pageIndex: pageIndex))
                currentY = y
            }
            self.canvasSize = Self.pageSize

        case .continuous:
            // Accumulate offsets from the top, then flip once the total
            // height is known
            var offsets: [CGFloat] = []
            var offsetFromTop: CGFloat = topMargin
            for gapAbove in gapsAbove {
                offsetFromTop += gapAbove
                offsets.append(offsetFromTop)
                offsetFromTop += rowDepthBelow
            }
            let totalHeight = offsetFromTop + bottomMargin
            for (index, (rowDay, days)) in rowSpans.enumerated() {
                built.append(
                    Row(
                        startDay: rowDay, numDays: days,
                        baselineY: totalHeight - offsets[index], pageIndex: 0))
            }
            self.canvasSize = CGSize(width: Self.pageSize.width, height: totalHeight)
        }
        self.rows = built
    }

    func color(for event: TimelineEvent) -> CGColor {
        if event.done { return theme.done }
        return eventColorMap[event.id] ?? Self.cg(Self.eventColors[0])
    }

    // MARK: - Calendar helpers

    func isHoliday(_ day: Day) -> Bool {
        if usHolidays[day] != nil { return true }
        for holiday in config.customHolidays {
            if holiday.start <= day && day <= holiday.effectiveEnd { return true }
        }
        return false
    }

    func isWeekendOrHoliday(_ day: Day) -> Bool {
        day.isWeekend || isHoliday(day)
    }

    /// Whether a day gets a gray band, per the shading options.
    func shouldShade(_ day: Day) -> Bool {
        (config.shadeWeekends && day.isWeekend)
            || (config.shadeHolidays && isHoliday(day))
    }

    func holidayName(_ day: Day) -> String? {
        if let us = usHolidays[day] { return us }
        for holiday in config.customHolidays {
            if !holiday.name.isEmpty, holiday.start <= day, day <= holiday.effectiveEnd {
                return holiday.name
            }
        }
        return nil
    }

    // MARK: - Text

    static func font(_ name: String, _ size: CGFloat) -> CTFont {
        CTFontCreateWithName(name as CFString, size, nil)
    }

    static func textWidth(_ text: String, font: CTFont) -> CGFloat {
        let attributed = NSAttributedString(
            string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    enum TextAlign { case left, center, right }

    static func drawText(
        _ text: String, at point: CGPoint, font: CTFont, color: CGColor,
        align: TextAlign = .left, in ctx: CGContext
    ) {
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color])
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        var x = point.x
        switch align {
        case .left: break
        case .center: x -= width / 2
        case .right: x -= width
        }
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: x, y: point.y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: - Layout (static so init can use it before self is ready)

    static func layoutEvents(
        forRow rowStart: Day, numDays: Int, events: [TimelineEvent],
        leftMargin: CGFloat, dayWidth: CGFloat,
        rangeBaseOffset: CGFloat, rangeStackSpacing: CGFloat,
        eventBaseOffset: CGFloat, eventVerticalSpacing: CGFloat,
        maxEventHeight: CGFloat, labelFontSize: CGFloat, labelTextHeight: CGFloat,
        maxLabelTop: inout CGFloat
    ) -> [Placement] {
        let rowEnd = rowStart.shifted(days: numDays - 1)
        let startX = leftMargin
        let barEndX = startX + CGFloat(numDays - 1) * dayWidth
        let labelFont = font("Helvetica-Bold", labelFontSize)

        var occupiedBoxes: [CGRect] = []
        var occupiedRanges: [(CGFloat, CGFloat, CGFloat)] = []
        var placements: [Placement] = []
        maxLabelTop = 0

        // Count point events sharing a day (wedge splitting)
        var pointCounts: [Day: Int] = [:]
        for event in events where !event.isRange {
            if rowStart <= event.start && event.start <= rowEnd {
                pointCounts[event.start, default: 0] += 1
            }
        }
        var pointSeen: [Day: Int] = [:]

        func overlapsExisting(_ rect: CGRect) -> Bool {
            let padding: CGFloat = 5
            for box in occupiedBoxes {
                if !(rect.maxX + padding < box.minX || rect.minX > box.maxX + padding
                    || rect.maxY + padding < box.minY || rect.minY > box.maxY + padding) {
                    return true
                }
            }
            return false
        }

        for event in events {
            let eventEnd = event.effectiveEnd
            if event.start > rowEnd || eventEnd < rowStart { continue }

            let visibleStart = max(event.start, rowStart)
            let visibleEnd = min(eventEnd, rowEnd)
            var startPosX = startX + CGFloat(rowStart.days(until: visibleStart)) * dayWidth
            var endPosX = startX + CGFloat(rowStart.days(until: visibleEnd)) * dayWidth

            let continuesLeft = event.start < rowStart
            let continuesRight = eventEnd > rowEnd

            let markerX = event.isRange ? (startPosX + endPosX) / 2 : startPosX
            if continuesLeft { startPosX = startX - 10 }
            if continuesRight { endPosX = barEndX + 10 }

            var lineYOffset: CGFloat = 0
            if event.isRange {
                lineYOffset = rangeBaseOffset
                for (occStart, occEnd, occOffset) in occupiedRanges {
                    if !(endPosX + 5 < occStart || startPosX > occEnd + 5) {
                        lineYOffset = max(lineYOffset, occOffset + rangeStackSpacing)
                    }
                }
                occupiedRanges.append((startPosX, endPosX, lineYOffset))
                occupiedBoxes.append(
                    CGRect(x: startPosX, y: lineYOffset - 4, width: endPosX - startPosX, height: 8))
            }

            var wedgeIndex = 0
            var wedgeCount = 1
            if !event.isRange {
                wedgeCount = pointCounts[event.start] ?? 1
                wedgeIndex = pointSeen[event.start] ?? 0
                pointSeen[event.start] = wedgeIndex + 1
            }

            placements.append(
                Placement(
                    event: event, isRange: event.isRange,
                    startX: startPosX, endX: endPosX, markerX: markerX,
                    lineYOffset: lineYOffset,
                    continuesLeft: continuesLeft, continuesRight: continuesRight,
                    wedgeIndex: wedgeIndex, wedgeCount: wedgeCount,
                    labelX: nil, labelY: nil, textWidth: 0))
        }

        // Second pass: labels avoid other labels and every range bar
        for index in placements.indices {
            let event = placements[index].event
            if event.start < rowStart { continue }

            let markerX = placements[index].markerX
            let stackExtra =
                placements[index].isRange
                ? placements[index].lineYOffset - rangeBaseOffset : 0
            let textWidth = Self.textWidth(event.name, font: labelFont)
            var yOffset = eventBaseOffset + stackExtra

            for _ in 0..<20 {
                if yOffset > maxEventHeight {
                    yOffset = maxEventHeight
                    break
                }
                let rect = CGRect(
                    x: markerX - textWidth / 2, y: yOffset,
                    width: textWidth, height: labelTextHeight)
                if !overlapsExisting(rect) { break }
                yOffset += eventVerticalSpacing
            }

            placements[index].labelX = markerX - textWidth / 2
            placements[index].labelY = yOffset
            placements[index].textWidth = textWidth
            occupiedBoxes.append(
                CGRect(
                    x: markerX - textWidth / 2, y: yOffset,
                    width: textWidth, height: labelTextHeight))
            maxLabelTop = max(maxLabelTop, yOffset + labelTextHeight)
        }

        return placements
    }

    func layoutEvents(forRow rowStart: Day, numDays: Int) -> [Placement] {
        var unused: CGFloat = 0
        return Self.layoutEvents(
            forRow: rowStart, numDays: numDays, events: sortedEvents,
            leftMargin: leftMargin, dayWidth: dayWidth,
            rangeBaseOffset: rangeBaseOffset, rangeStackSpacing: rangeStackSpacing,
            eventBaseOffset: eventBaseOffset, eventVerticalSpacing: eventVerticalSpacing,
            maxEventHeight: maxEventHeight, labelFontSize: labelFontSize,
            labelTextHeight: labelTextHeight, maxLabelTop: &unused)
    }

    // MARK: - Drawing

    /// Draw one page (paged) or the whole canvas (continuous, page 0)
    /// into a PDF-coordinate (bottom-left origin) context.
    func drawPage(_ pageIndex: Int, in ctx: CGContext) {
        drawHeader(in: ctx)
        for row in rows where row.pageIndex == pageIndex {
            drawTimelineRow(row, in: ctx)
            drawEvents(row, in: ctx)
            drawPastDayMarkers(row, in: ctx)
        }
    }

    private func drawHeader(in ctx: CGContext) {
        let width = canvasSize.width
        if !config.title.isEmpty {
            let titleY = canvasSize.height - baseTopMargin
            Self.drawText(
                config.title, at: CGPoint(x: width / 2, y: titleY),
                font: Self.font("Helvetica-Bold", 18), color: theme.title,
                align: .center, in: ctx)
            let subtitle = "\(monthDay(startDay)) – \(monthDay(endDay)), \(endDay.year)"
            Self.drawText(
                subtitle, at: CGPoint(x: width / 2, y: titleY - 16),
                font: Self.font("Helvetica", 9.5), color: theme.subtitle,
                align: .center, in: ctx)
        }

        if includeGenerated {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            Self.drawText(
                "Generated \(formatter.string(from: Date()))",
                at: CGPoint(x: width - rightMargin, y: 28.8),
                font: Self.font("Helvetica", 7), color: theme.footer,
                align: .right, in: ctx)
        }
    }

    private func monthDay(_ day: Day) -> String {
        let months = [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ]
        return "\(months[day.month - 1]) \(day.day)"
    }

    private func drawTimelineRow(_ row: Row, in ctx: CGContext) {
        let startX = leftMargin
        let y = row.baselineY
        let barEndX = startX + CGFloat(row.numDays - 1) * dayWidth
        let bandBottom = y - 40
        let bandHeight: CGFloat = 54

        // Merged bands for consecutive shaded days
        var i = 0
        while i < row.numDays {
            if shouldShade(row.startDay.shifted(days: i)) {
                var j = i
                while j + 1 < row.numDays,
                    shouldShade(row.startDay.shifted(days: j + 1)) {
                    j += 1
                }
                let bandX = startX + CGFloat(i) * dayWidth - dayWidth / 2
                let bandWidth = CGFloat(j - i + 1) * dayWidth
                ctx.setFillColor(theme.weekendBand)
                let path = CGPath(
                    roundedRect: CGRect(
                        x: bandX, y: bandBottom, width: bandWidth, height: bandHeight),
                    cornerWidth: 4, cornerHeight: 4, transform: nil)
                ctx.addPath(path)
                ctx.fillPath()
                i = j + 1
            } else {
                i += 1
            }
        }

        // Main timeline bar
        ctx.setStrokeColor(theme.bar)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: startX, y: y))
        ctx.addLine(to: CGPoint(x: barEndX, y: y))
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Ticks and dates; cramped rows label every other day
        let dateInterval = dayWidth < 20 ? 2 : 1
        ctx.setLineWidth(1)
        for i in 0..<row.numDays {
            let day = row.startDay.shifted(days: i)
            let x = startX + CGFloat(i) * dayWidth
            let special = isWeekendOrHoliday(day)

            ctx.setStrokeColor(special ? theme.tickMuted : theme.tick)
            ctx.move(to: CGPoint(x: x, y: y - tickHeight / 2))
            ctx.addLine(to: CGPoint(x: x, y: y + tickHeight / 2))
            ctx.strokePath()

            if i % dateInterval == 0 {
                Self.drawText(
                    day.shortLabel, at: CGPoint(x: x, y: y - tickHeight / 2 - 12),
                    font: Self.font("Helvetica", 8),
                    color: special ? theme.dateMuted : theme.date,
                    align: .center, in: ctx)
            }
        }

        // Holiday names: centered in the band when it holds one holiday.
        // No shading, no names.
        let holidayFont = Self.font("Helvetica-Oblique", 6.5)
        var lastLabelEnd = -CGFloat.infinity
        i = 0
        while config.shadeHolidays, i < row.numDays {
            if !isWeekendOrHoliday(row.startDay.shifted(days: i)) {
                i += 1
                continue
            }
            var j = i
            while j + 1 < row.numDays,
                isWeekendOrHoliday(row.startDay.shifted(days: j + 1)) {
                j += 1
            }

            var groups: [(String, Int, Int)] = []
            var k = i
            while k <= j {
                if let name = holidayName(row.startDay.shifted(days: k)) {
                    var g = k
                    while g + 1 <= j, holidayName(row.startDay.shifted(days: g + 1)) == name {
                        g += 1
                    }
                    groups.append((name, k, g))
                    k = g + 1
                } else {
                    k += 1
                }
            }

            for (name, groupStart, groupEnd) in groups {
                let centerDay =
                    groups.count == 1
                    ? CGFloat(i + j) / 2 : CGFloat(groupStart + groupEnd) / 2
                let centerX = startX + centerDay * dayWidth
                let nameWidth = Self.textWidth(name, font: holidayFont)
                if centerX - nameWidth / 2 > lastLabelEnd + 4 {
                    Self.drawText(
                        name, at: CGPoint(x: centerX, y: y - 36),
                        font: holidayFont, color: theme.subtitle,
                        align: .center, in: ctx)
                    lastLabelEnd = centerX + nameWidth / 2
                }
            }
            i = j + 1
        }
    }

    private func drawPastDayMarkers(_ row: Row, in ctx: CGContext) {
        let today = Day.today()
        ctx.setStrokeColor(theme.pastX)
        ctx.setLineWidth(1.3)
        for i in 0..<row.numDays {
            let day = row.startDay.shifted(days: i)
            if day < today {
                let x = leftMargin + CGFloat(i) * dayWidth
                let s: CGFloat = 3.5
                ctx.move(to: CGPoint(x: x - s, y: row.baselineY - s))
                ctx.addLine(to: CGPoint(x: x + s, y: row.baselineY + s))
                ctx.move(to: CGPoint(x: x - s, y: row.baselineY + s))
                ctx.addLine(to: CGPoint(x: x + s, y: row.baselineY - s))
                ctx.strokePath()
            }
        }
    }

    private func drawArrowhead(
        at point: CGPoint, direction: CGFloat, color: CGColor, in ctx: CGContext
    ) {
        let size: CGFloat = 5
        ctx.setFillColor(color)
        ctx.move(to: CGPoint(x: point.x, y: point.y - size * 0.8))
        ctx.addLine(to: CGPoint(x: point.x + direction * size, y: point.y))
        ctx.addLine(to: CGPoint(x: point.x, y: point.y + size * 0.8))
        ctx.closePath()
        ctx.fillPath()
    }

    private func drawEvents(_ row: Row, in ctx: CGContext) {
        let y = row.baselineY
        let labelFont = Self.font("Helvetica-Bold", labelFontSize)

        for p in layoutEvents(forRow: row.startDay, numDays: row.numDays) {
            let eventColor = color(for: p.event)
            var markerTop: CGFloat

            if p.isRange {
                let lineY = y + p.lineYOffset
                ctx.setStrokeColor(eventColor)
                ctx.setLineWidth(4.5)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: p.startX, y: lineY))
                ctx.addLine(to: CGPoint(x: p.endX, y: lineY))
                ctx.strokePath()
                ctx.setLineCap(.butt)

                if p.continuesLeft {
                    drawArrowhead(
                        at: CGPoint(x: p.startX, y: lineY), direction: -1,
                        color: eventColor, in: ctx)
                }
                if p.continuesRight {
                    drawArrowhead(
                        at: CGPoint(x: p.endX, y: lineY), direction: 1,
                        color: eventColor, in: ctx)
                }
                markerTop = p.lineYOffset + 4
            } else {
                ctx.setFillColor(eventColor)
                if p.wedgeCount > 1 {
                    let r = dotRadius + 1
                    let extent = 360.0 / CGFloat(p.wedgeCount)
                    let startAngle = (90 + CGFloat(p.wedgeIndex) * extent) * .pi / 180
                    let endAngle = startAngle + extent * .pi / 180
                    let center = CGPoint(x: p.markerX, y: y)
                    ctx.move(to: center)
                    ctx.addArc(
                        center: center, radius: r, startAngle: startAngle,
                        endAngle: endAngle, clockwise: false)
                    ctx.closePath()
                    ctx.fillPath()
                    markerTop = r + 2
                } else {
                    ctx.fillEllipse(
                        in: CGRect(
                            x: p.markerX - dotRadius, y: y - dotRadius,
                            width: dotRadius * 2, height: dotRadius * 2))
                    markerTop = dotRadius + 2
                }
            }

            guard let labelX = p.labelX, let labelY = p.labelY else { continue }
            let labelYAbs = y + labelY

            // Leader line connecting a raised label back to its marker
            if labelY - 3 - markerTop > 10 {
                ctx.setStrokeColor(eventColor.copy(alpha: 0.4)!)
                ctx.setLineWidth(0.8)
                ctx.move(to: CGPoint(x: p.markerX, y: y + markerTop))
                ctx.addLine(to: CGPoint(x: p.markerX, y: labelYAbs - 3))
                ctx.strokePath()
            }

            Self.drawText(
                p.event.name, at: CGPoint(x: labelX, y: labelYAbs),
                font: labelFont, color: eventColor, align: .left, in: ctx)

            // Important events get a box around the label
            if p.event.important {
                let box = CGRect(
                    x: labelX - 4, y: labelYAbs - 3.5,
                    width: p.textWidth + 8, height: labelTextHeight + 1.5)
                ctx.setStrokeColor(eventColor)
                ctx.setLineWidth(1.2)
                ctx.addPath(
                    CGPath(
                        roundedRect: box, cornerWidth: 3.5, cornerHeight: 3.5,
                        transform: nil))
                ctx.strokePath()
            }

            if p.event.done {
                ctx.setStrokeColor(theme.done)
                ctx.setLineWidth(1.2)
                let strikeY = labelYAbs + labelTextHeight / 2 - 3
                ctx.move(to: CGPoint(x: labelX, y: strikeY))
                ctx.addLine(to: CGPoint(x: labelX + p.textWidth, y: strikeY))
                ctx.strokePath()
            }
        }
    }
}
