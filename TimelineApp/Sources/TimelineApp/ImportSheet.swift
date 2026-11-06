import SwiftUI

/// One image import: runs the pages through OCR + Gemma (or the basic
/// parser) and collects rows for review as each page finishes.
@MainActor
final class ImportSession: ObservableObject, Identifiable {
    struct Row: Identifiable {
        let id = UUID()
        var include: Bool
        var event: ImportCandidate
    }

    @Published var rows: [Row] = []
    /// What's running ("Reading 2 of 5…"); nil once finished or stopped.
    @Published private(set) var progress: String? = "Reading image…"
    @Published private(set) var isDownloading = false
    /// Why the basic importer was used, if it was.
    @Published private(set) var note: String?
    private var task: Task<Void, Never>?

    /// `download`: fetch Gemma first (the user just agreed to it, or a
    /// download is already under way).
    init(items: [ImportItem], download: Bool, existing: [TimelineEvent]) {
        task = Task { await run(items, download: download, existing: existing) }
    }

    func stop() { task?.cancel() }

    private func run(_ items: [ImportItem], download: Bool, existing: [TimelineEvent]) async {
        let model = GemmaModel.shared
        if download {
            isDownloading = true
            await model.download()
            isDownloading = false
            if case .failed(let message) = model.state {
                note = "Gemma couldn't be downloaded (\(message)). Used basic text recognition."
            }
        }
        var useGemma = GemmaModel.isSupported && model.state == .ready
        if !useGemma, note == nil {
            note = GemmaModel.isSupported
                ? "Used basic text recognition. Download Gemma 4 in Settings for better results."
                : "Used basic text recognition (Gemma 4 needs a Mac with Apple silicon)."
        }

        let pages = ImageImport.pages(from: items)
        let today = Day.today()
        for (index, page) in pages.enumerated() {
            if Task.isCancelled { break }
            progress = pages.count > 1 ? "Reading \(index + 1) of \(pages.count)…" : "Reading image…"
            var found: [ImportCandidate] = []
            do {
                found = try await ImageImport.read(page, today: today, useGemma: useGemma)
            } catch is CancellationError {
                break
            } catch {
                // Gemma failed (e.g. not enough memory): basic for the rest
                useGemma = false
                note = "Gemma couldn't run (\(error.localizedDescription)). Used basic text recognition."
                found = (try? await ImageImport.read(page, today: today, useGemma: false)) ?? []
            }
            rows += found.map {
                Row(include: !ImageImport.isDuplicate($0, in: existing), event: $0)
            }
        }
        await GemmaRunner.shared.unload()
        progress = nil
    }
}

/// Review sheet for events found in dropped/pasted images: check, edit,
/// import. Opens immediately; rows stream in as pages finish.
struct ImportSheet: View {
    @ObservedObject var session: ImportSession
    @ObservedObject private var model = GemmaModel.shared
    let config: TimelineConfig
    let onImport: ([ImportCandidate]) -> Void
    let onCancel: () -> Void

    private var selected: [ImportCandidate] {
        session.rows.filter(\.include).map(\.event)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(16)
            Divider()
            if session.rows.isEmpty {
                Text(session.progress == nil ? "No dated events found." : "Looking for events…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List($session.rows) { $row in
                    ImportRowView(row: $row, config: config)
                }
            }
            Divider()
            footer.padding(16)
        }
        .frame(minWidth: 720, minHeight: 380)
        .frame(idealHeight: 480)
        .onDisappear { session.stop() }
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import Events").font(.headline)
            if session.isDownloading {
                downloadStatus
            } else if let progress = session.progress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progress).foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop") { session.stop() }
                        .help("Stop reading; keep the events found so far")
                }
            }
            if let note = session.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var downloadStatus: some View {
        switch model.state {
        case .downloading(let fraction):
            ProgressView(value: fraction) {
                Text("Downloading Gemma 4 — \(Int(fraction * 100))%")
                    .foregroundStyle(.secondary)
            }
        default:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Verifying download…").foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            let allOn = !session.rows.isEmpty && session.rows.allSatisfy(\.include)
            Button(allOn ? "Select None" : "Select All") {
                for i in session.rows.indices { session.rows[i].include = !allOn }
            }
            .disabled(session.rows.isEmpty)
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(selected.count == 1 ? "Import 1 Event" : "Import \(selected.count) Events") {
                onImport(selected)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selected.isEmpty)
        }
    }
}

private struct ImportRowView: View {
    @Binding var row: ImportSession.Row
    let config: TimelineConfig

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: $row.include).labelsHidden()
            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: $row.event.name)
                TextField("Notes", text: $row.event.notes)
                    .font(.caption)
                    .controlSize(.small)
            }
            DayPicker(label: "", day: $row.event.start)
                .labelsHidden()
                .fixedSize()
            OptionalDayRow(label: "End", day: $row.event.end, defaultDay: row.event.start)
                .fixedSize()
            warnings.frame(width: 90, alignment: .leading)
        }
        .padding(.vertical, 4)
        .opacity(row.include ? 1 : 0.55)
    }

    @ViewBuilder private var warnings: some View {
        let event = row.event
        HStack(spacing: 6) {
            if ImageImport.isDuplicate(event, in: config.events) {
                Text("Already added").font(.caption).foregroundStyle(.secondary)
            }
            if ImageImport.isOutOfRange(event, in: config) {
                Image(systemName: "arrow.left.and.right.square")
                    .foregroundStyle(.orange)
                    .help("Outside this timeline's dates — importing extends them")
            }
            if let printed = event.mismatchedWeekday {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("The image says \(printed), but \(event.start.localDate.formatted(.dateTime.month(.wide).day().year())) is a \(event.start.localDate.formatted(.dateTime.weekday(.wide))). Check the year.")
            }
        }
    }
}
