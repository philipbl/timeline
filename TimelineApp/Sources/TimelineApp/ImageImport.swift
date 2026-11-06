import AppKit
import PDFKit
import UniformTypeIdentifiers
import Vision

/// An image or PDF dropped or pasted for event import.
enum ImportItem {
    case file(URL)   // image or PDF on disk (Finder)
    case data(Data)  // image (or PDF) bytes from another app or the clipboard
}

/// An event found in an image, before the user reviews it.
struct ImportCandidate: Equatable {
    var name: String
    var start: Day
    var end: Day?
    var notes: String = ""
    /// The weekday printed with the date in the image ("Tuesday"), if any.
    var printedWeekday: String?

    /// The printed weekday when `start` doesn't fall on it ("Tuesday, June
    /// 9th" resolved to a Wednesday): a hint the year is wrong.
    var mismatchedWeekday: String? {
        guard let printedWeekday,
              let index = ImageImport.weekdayNames.firstIndex(of: printedWeekday),
              index != start.weekday
        else { return nil }
        return printedWeekday
    }
}

/// Finds dated events in images: Vision OCR, then Gemma 4 (image + OCR
/// text) or, without the model, the built-in EventParser line by line.
enum ImageImport {

    // MARK: - Inputs

    static func isImportable(_ url: URL) -> Bool {
        guard url.isFileURL,
              let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    /// Whether a dropped item might be an image or PDF (file URLs are only
    /// known once loaded).
    static func mayHoldImage(_ provider: NSItemProvider) -> Bool {
        [UTType.fileURL, .image, .pdf].contains {
            provider.hasItemConformingToTypeIdentifier($0.identifier)
        }
    }

    /// Load dropped images/PDFs, in drop order. Calls back on the main queue
    /// with whatever loaded (empty if none were images, e.g. a text file).
    static func loadItems(
        from providers: [NSItemProvider], completion: @escaping ([ImportItem]) -> Void
    ) {
        let group = DispatchGroup()
        let lock = NSLock()
        var found = [ImportItem?](repeating: nil, count: providers.count)
        for (index, provider) in providers.enumerated() {
            group.enter()
            let finish: (ImportItem?) -> Void = { item in
                lock.withLock { found[index] = item }
                group.leave()
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: NSURL.self) { url, _ in
                    finish((url as? URL).flatMap { isImportable($0) ? .file($0) : nil })
                }
            } else if let type = [UTType.image, .pdf].first(where: {
                provider.hasItemConformingToTypeIdentifier($0.identifier)
            }) {
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) {
                    data, _ in finish(data.map(ImportItem.data))
                }
            } else {
                finish(nil)
            }
        }
        group.notify(queue: .main) { completion(found.compactMap { $0 }) }
    }

    /// Images/PDFs on the clipboard: copied files, or image data when there's
    /// no text (text keeps going to the text parser).
    static func items(from pasteboard: NSPasteboard) -> [ImportItem] {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        let files = (urls ?? []).filter(isImportable).map(ImportItem.file)
        if !files.isEmpty { return files }
        guard pasteboard.string(forType: .string) == nil,
              let data = [NSPasteboard.PasteboardType.png, .tiff, .pdf]
                .lazy.compactMap({ pasteboard.data(forType: $0) }).first
        else { return [] }
        return [.data(data)]
    }

    /// Each image, or each PDF page, loaded on demand (a long PDF would be
    /// a lot of memory up front).
    static func pages(from items: [ImportItem]) -> [() -> CGImage?] {
        items.flatMap { item -> [() -> CGImage?] in
            let pdf: PDFDocument?
            switch item {
            case .file(let url):
                let isPDF = (try? url.resourceValues(forKeys: [.contentTypeKey]))?
                    .contentType?.conforms(to: .pdf) == true
                if !isPDF, let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                    return [{ image(from: source) }]
                }
                pdf = isPDF ? PDFDocument(url: url) : nil
            case .data(let data):
                if data.starts(with: Data("%PDF".utf8)) {
                    pdf = PDFDocument(data: data)
                } else if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                    return [{ image(from: source) }]
                } else {
                    pdf = nil
                }
            }
            guard let pdf else { return [] }
            return (0..<pdf.pageCount).map { index in
                {
                    pdf.page(at: index)?
                        .thumbnail(of: CGSize(width: 2048, height: 2048), for: .mediaBox)
                        .cgImage(forProposedRect: nil, context: nil, hints: nil)
                }
            }
        }
    }

    /// Upright (EXIF orientation applied) and at most 3072 px: plenty for
    /// OCR, and Gemma resizes again internally.
    private static func image(from source: CGImageSource) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3072,
        ] as CFDictionary)
    }

    // MARK: - Reading

    /// OCR + Gemma (or the basic parser) on one page. Throws if Gemma fails,
    /// so the caller can fall back.
    static func read(
        _ page: () -> CGImage?, today: Day, useGemma: Bool
    ) async throws -> [ImportCandidate] {
        guard let image = page() else { return [] }
        let ocr = recognizeText(in: image)
        guard useGemma else { return basicCandidates(ocr: ocr, today: today) }
        let reply = try await GemmaRunner.shared.reply(
            image: image, prompt: prompt(ocr: ocr, today: today))
        return parseReply(reply, today: today)
    }

    static func recognizeText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// Gemma's prompt (after the image). The OCR text comes first: in the
    /// bake-off it took handwritten notes from 0/4 to 4/4. Years are left to
    /// Swift (`parseReply`); the model's weekday arithmetic was unreliable.
    static func prompt(ocr: String, today: Day) -> String {
        """
        Text recognized in the image (may contain OCR errors):
        \(ocr)

        Today is \(today). The user dropped this image onto their timeline app. \
        It may be a flyer, schedule, syllabus, calendar, email, or photo. List \
        every event in it that has a date.

        Rules:
        - One event per line, exactly: NAME | START | END | WEEKDAY | NOTES
        - START and END: YYYY-MM-DD if the year is printed in the image, \
        otherwise MM-DD. Write relative dates (tomorrow, next Friday) as \
        YYYY-MM-DD using today's date. END is the last day of a multi-day \
        event, otherwise NONE.
        - WEEKDAY: the day of the week printed with the start date (for \
        example Tuesday), otherwise NONE.
        - NOTES: the time and place if printed (for example 7 PM, Smith's \
        backyard), otherwise NONE.
        - NAME is short (under 60 characters) and does not include the date.
        - Skip anything without a specific date.
        - Output only the lines, nothing else. If there are no dated events, \
        output NONE.
        """
    }

    /// Parse "NAME | START | END | WEEKDAY | NOTES" lines. Yearless dates
    /// (MM-DD) resolve to the next occurrence on or after today; an end
    /// date takes the start's year, rolling over for Dec → Jan spans.
    static func parseReply(_ reply: String, today: Day) -> [ImportCandidate] {
        reply.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            func field(_ i: Int) -> String? {
                guard i < fields.count, !fields[i].isEmpty,
                      fields[i].uppercased() != "NONE" else { return nil }
                return fields[i]
            }
            guard let rawName = field(0), let startText = field(1),
                  let start = date(startText, onOrAfter: today)
            else { return nil }
            let end = field(2).flatMap { date($0, onOrAfter: start) }.flatMap {
                $0 > start ? $0 : nil
            }
            // Drop list markers the model sometimes keeps ("1. ", "- ")
            let name = rawName.replacingOccurrences(
                of: #"^(?:[-*•]|\d+[.)])\s+"#, with: "", options: .regularExpression)
            return ImportCandidate(
                name: name, start: start, end: end, notes: field(4) ?? "",
                printedWeekday: weekdayName(field(3)))
        }
    }

    /// "2026-06-09" as is; "06-09" → next June 9 on or after `reference`.
    private static func date(_ text: String, onOrAfter reference: Day) -> Day? {
        if let day = Day(string: text), text.split(separator: "-").first?.count == 4 {
            return day
        }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[0]), (1...31).contains(parts[1])
        else { return nil }
        return upcoming(month: parts[0], day: parts[1], onOrAfter: reference)
    }

    static func upcoming(month: Int, day: Int, onOrAfter reference: Day) -> Day {
        let candidate = Day(year: reference.year, month: month, day: day)
        return candidate < reference
            ? Day(year: reference.year + 1, month: month, day: day) : candidate
    }

    /// Monday first, matching `Day.weekday`.
    static let weekdayNames = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
    ]

    /// "tues", "TUESDAY," → "Tuesday"; nil if it isn't a weekday.
    private static func weekdayName(_ text: String?) -> String? {
        guard let prefix = text?.lowercased().filter(\.isLetter).prefix(3),
              prefix.count == 3
        else { return nil }
        return weekdayNames.first { $0.lowercased().hasPrefix(prefix) }
    }

    /// Without Gemma: each OCR line that has a number and a date the
    /// EventParser understands. A leading weekday ("Tuesday, June 9th") is
    /// taken off first (the parser would read it as "next Tuesday") and
    /// checked against the date instead. Yearless past dates roll forward.
    static func basicCandidates(ocr: String, today: Day) -> [ImportCandidate] {
        ocr.split(whereSeparator: \.isNewline).compactMap { rawLine in
            var line = String(rawLine)
            guard line.contains(where: \.isNumber) else { return nil }
            let weekdayPattern =
                #"(?i)\b(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)(day|nesday|sday|urday)?\b\.?,?"#
            var printed: String?
            if let range = line.range(of: weekdayPattern, options: .regularExpression) {
                printed = String(line[range])
                line.removeSubrange(range)
            }
            guard var parsed = EventParser.parseDated(line, relativeTo: today) else {
                return nil
            }
            let hasYear = line.range(
                of: #"\b\d{4}\b|\d{1,2}/\d{1,2}/\d{2}"#, options: .regularExpression) != nil
            if !hasYear, parsed.start < today {
                parsed.start.year += 1
                parsed.end?.year += 1
            }
            return ImportCandidate(
                name: parsed.name, start: parsed.start, end: parsed.end,
                printedWeekday: weekdayName(printed))
        }
    }

    // MARK: - Review

    static func isDuplicate(_ candidate: ImportCandidate, in events: [TimelineEvent]) -> Bool {
        let name = candidate.name.trimmingCharacters(in: .whitespaces).lowercased()
        return events.contains {
            $0.name.trimmingCharacters(in: .whitespaces).lowercased() == name
                && $0.start == candidate.start && $0.end == candidate.end
        }
    }

    /// Outside the timeline's explicit start/end (no explicit bounds = never).
    static func isOutOfRange(_ candidate: ImportCandidate, in config: TimelineConfig) -> Bool {
        if let lower = config.timelineStart, candidate.start < lower { return true }
        if let upper = config.timelineEnd, upper < (candidate.end ?? candidate.start) {
            return true
        }
        return false
    }

    /// `config` with the candidates added (unnamed ones skipped), explicit
    /// bounds stretched to show them, and events kept in date order.
    static func adding(_ candidates: [ImportCandidate], to config: TimelineConfig) -> TimelineConfig {
        var config = config
        for candidate in candidates
        where !candidate.name.trimmingCharacters(in: .whitespaces).isEmpty {
            config.events.append(TimelineEvent(
                name: candidate.name, start: candidate.start, end: candidate.end,
                notes: candidate.notes))
            if let lower = config.timelineStart, candidate.start < lower {
                config.timelineStart = candidate.start
            }
            if let upper = config.timelineEnd, upper < (candidate.end ?? candidate.start) {
                config.timelineEnd = candidate.end ?? candidate.start
            }
        }
        config.events.sort { $0.start < $1.start }
        return config
    }
}
