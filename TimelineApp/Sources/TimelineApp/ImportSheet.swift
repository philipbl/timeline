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
    /// The page being read and where Vision found text on it (normalized,
    /// bottom-left), for the scanning preview.
    @Published private(set) var page: CGImage?
    @Published private(set) var textBoxes: [CGRect] = []
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
            let count = pages.count > 1 ? " (\(index + 1) of \(pages.count))" : ""
            progress = "Reading image\(count)…"
            let onStep: @Sendable (ImageImport.Step) async -> Void = { step in
                await self.show(step, count: count)
            }
            var found: [ImportCandidate] = []
            do {
                found = try await ImageImport.read(
                    page, today: today, useGemma: useGemma, onStep: onStep)
            } catch is CancellationError {
                break
            } catch {
                // Gemma failed (e.g. not enough memory): basic for the rest
                useGemma = false
                note = "Gemma couldn't run (\(error.localizedDescription)). Used basic text recognition."
                found = (try? await ImageImport.read(
                    page, today: today, useGemma: false, onStep: onStep)) ?? []
            }
            withAnimation {
                rows += found.map {
                    Row(include: !ImageImport.isDuplicate($0, in: existing), event: $0)
                }
            }
        }
        await GemmaRunner.shared.unload()
        progress = nil
        page = nil
    }

    private func show(_ step: ImageImport.Step, count: String) {
        switch step {
        case .image(let image):
            page = image
            textBoxes = []
            progress = "Reading text\(count)…"
        case .text(let boxes):
            textBoxes = boxes
            progress = "Finding events\(count)…"
        }
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
            if !session.rows.isEmpty {
                List($session.rows) { $row in
                    ImportRowView(row: $row, config: config)
                }
            }
            if let page = session.page {
                // Big while nothing's found yet; a strip under the rows after
                ScanPreview(image: page, boxes: session.textBoxes)
                    .frame(maxWidth: .infinity, maxHeight: session.rows.isEmpty ? .infinity : 140)
                    .padding(16)
            } else if session.rows.isEmpty {
                Text(session.progress == nil ? "No dated events found." : "Looking for events…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// The page being read: the text Vision found is boxed, and a scan line
/// sweeps up and down, lighting the boxes it passes, while the model works.
private struct ScanPreview: View {
    let image: CGImage
    let boxes: [CGRect]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var boxesShownAt = Date()

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    Canvas { gc, size in
                        draw(in: gc, size: size, at: context.date)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            .onChange(of: boxes.count) { boxesShownAt = .now }
    }

    private func draw(in gc: GraphicsContext, size: CGSize, at date: Date) {
        // Top → bottom → top at a steady pace, every 3.2 s; none with
        // reduce motion
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.2) / 1.6
        let sweep = reduceMotion ? nil : 1 - abs(phase - 1)
        let fadeIn = reduceMotion ? 1 : min(1, date.timeIntervalSince(boxesShownAt) / 0.6)
        for box in boxes {
            let rect = CGRect(
                x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                width: box.width * size.width, height: box.height * size.height
            ).insetBy(dx: -2, dy: -1)
            // Brightest while the line crosses the box, fading off its edges
            let lit = sweep.map { sweep -> Double in
                let y = sweep * size.height
                return max(0, 1 - max(rect.minY - y, y - rect.maxY, 0) / 40)
            } ?? 0
            let path = Path(roundedRect: rect, cornerRadius: 2)
            gc.fill(path, with: .color(.accentColor.opacity((0.12 + 0.3 * lit) * fadeIn)))
            gc.stroke(path, with: .color(.accentColor.opacity((0.45 + 0.5 * lit) * fadeIn)),
                      lineWidth: 1)
        }
        guard let sweep else { return }
        let y = sweep * size.height
        let band = CGRect(x: 0, y: y - 36, width: size.width, height: 72)
        gc.fill(Path(band), with: .linearGradient(
            Gradient(colors: [.clear, .accentColor.opacity(0.3), .clear]),
            startPoint: CGPoint(x: 0, y: band.minY), endPoint: CGPoint(x: 0, y: band.maxY)))
        gc.fill(Path(CGRect(x: 0, y: y - 1, width: size.width, height: 2)),
                with: .color(.accentColor.opacity(0.9)))
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
