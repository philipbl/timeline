import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns free text into an event. Uses Apple Intelligence (on-device
/// Foundation Models, macOS 26 on capable Macs) for fuzzy phrasing and
/// falls back to the built-in EventParser everywhere else.
///
/// Plain string generation is used rather than @Generable guided output:
/// the FoundationModels macros need a plugin the SwiftPM command-line
/// build can't load, so we ask for a strict line format and parse it.
enum EventIntelligence {
    /// Apple Intelligence is opt-in (UserDefaults "useAppleIntelligence",
    /// default off): the on-device model gives nondeterministic and often
    /// wrong results for this task, so the deterministic EventParser is the
    /// default. Flip the flag to experiment with the AI path.
    static var useAppleIntelligence: Bool {
        UserDefaults.standard.bool(forKey: "useAppleIntelligence")
    }

    static func parse(
        _ text: String, relativeTo today: Day
    ) async -> ParsedEvent? {
        #if canImport(FoundationModels)
        if useAppleIntelligence, #available(macOS 26.0, *),
           let ai = await appleIntelligence(text, today) {
            return ai
        }
        #endif
        return EventParser.parse(text, relativeTo: today)
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func appleIntelligence(
        _ text: String, _ today: Day
    ) async -> ParsedEvent? {
        guard case .available = SystemLanguageModel.default.availability else {
            return nil
        }
        let prompt = """
            Today is \(today.description) (format YYYY-MM-DD). Extract one \
            calendar event from this text: "\(text)".
            Resolve relative phrases ("today", "tomorrow", "next Friday") \
            against today. For a bare date with no year, use the current or \
            next upcoming occurrence.
            Respond with exactly three lines and nothing else:
            TITLE: <the event title with date words removed>
            START: <YYYY-MM-DD>
            END: <YYYY-MM-DD, or NONE for a single-day event>
            """
        do {
            let session = LanguageModelSession()
            let reply = try await session.respond(to: prompt).content
            return parseReply(reply, original: text)
        } catch {
            return nil  // fall back to the parser
        }
    }
    #endif

    /// Parse the model's "TITLE/START/END" reply. Internal for testing.
    static func parseReply(_ reply: String, original: String) -> ParsedEvent? {
        var title = ""
        var startStr = ""
        var endStr = ""
        for rawLine in reply.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let v = value(of: "TITLE", in: line) { title = v }
            else if let v = value(of: "START", in: line) { startStr = v }
            else if let v = value(of: "END", in: line) { endStr = v }
        }
        guard let start = Day(string: startStr) else { return nil }
        var end = Day(string: endStr)
        if let e = end, e < start { end = nil }
        let name = title.trimmingCharacters(in: .whitespaces)
        return ParsedEvent(
            name: name.isEmpty ? original : name, start: start, end: end)
    }

    private static func value(of key: String, in line: String) -> String? {
        let prefix = "\(key):"
        guard line.uppercased().hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(
            in: .whitespaces)
    }
}
