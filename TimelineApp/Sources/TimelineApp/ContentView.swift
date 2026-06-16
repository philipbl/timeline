import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var document: TimelineDocument
    /// On-disk location, for live reload of external edits (e.g. Claude
    /// via MCP). nil for documents that haven't been saved yet.
    var fileURL: URL?

    @Environment(\.undoManager) private var undoManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var isFocusMode: Bool
    /// Per-window zoom, owned here so it persists across relaunch.
    @State private var zoom: CGFloat
    /// Snapshot taken when a canvas drag starts, so the whole drag
    /// becomes a single undo step on release.
    @State private var dragOriginalConfig: TimelineConfig?
    @State private var fileWatcher: FileWatcher?
    /// Event currently open in the editor popover (nil = closed).
    @State private var editingEventID: UUID?
    /// True while the open editor is for a freshly added event, so an
    /// empty cancel removes it.
    @State private var isNewEvent = false
    @State private var showSettings = false

    init(document: TimelineDocument, fileURL: URL?) {
        _document = ObservedObject(initialValue: document)
        self.fileURL = fileURL
        // Seed focus/zoom from saved state at init so the first render is
        // already correct — avoids the sidebar showing then sliding away.
        let saved = Self.savedWindowState(for: fileURL)
        _isFocusMode = State(initialValue: saved.focus)
        _zoom = State(initialValue: saved.zoom)
    }

    /// All edits route through the document so they register undo.
    private var configBinding: Binding<TimelineConfig> {
        Binding(
            get: { document.config },
            set: { document.update($0, undoManager: undoManager) })
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PreviewView(
                config: document.config,
                onEventMoved: moveEvent,
                editingEventID: $editingEventID,
                isNewEvent: $isNewEvent,
                eventBinding: eventBinding,
                onDeleteEvent: deleteEvent,
                onCloseEditor: closeEditor,
                // Relative phrases ("next Friday") resolve against today,
                // not the timeline's start date
                referenceDay: .today(),
                zoom: $zoom)

            // Bottom-right add button (Things/Fantastical style). The
            // new-event editor anchors here at the button; editing an
            // existing event anchors on the canvas (in PreviewView).
            if !isFocusMode {
                Button(action: startNewEvent) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.accentColor))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .padding(20)
                .help("Add an event")
                .popover(isPresented: newEventPresented, arrowEdge: .trailing) {
                    newEventEditor
                }
            }
        }
        // Focus-mode exit button at the true top-right corner
        .overlay(alignment: .topTrailing) {
            if isFocusMode {
                Button { isFocusMode = false } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(.borderless)
                .padding(8)
                .glassChrome(in: Circle())
                .padding(12)
                .help("Exit focus mode (⇧⌘F)")
            }
        }
        .ignoresSafeArea(.container, edges: isFocusMode ? .top : [])
        .toolbar(isFocusMode ? .hidden : .automatic, for: .windowToolbar)
        .focusedSceneValue(
            \.timelineActions,
            TimelineActions(
                exportPDF: exportPDF,
                exportPNG: exportPNG,
                printTimeline: printTimeline,
                toggleFocus: { isFocusMode.toggle() },
                resetZoom: { withAnimation(.snappy) { zoom = 1 } }))
        .onAppear { startWatching() }
        .onChange(of: fileURL) {
            startWatching()
            // A document saved for the first time gains a URL; pick up its
            // saved window state if any.
            let saved = Self.savedWindowState(for: fileURL)
            isFocusMode = saved.focus
            zoom = saved.zoom
        }
        .onChange(of: zoom) { saveWindowState() }
        .onChange(of: isFocusMode) { saveWindowState() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showSettings.toggle() } label: {
                    Label("Timeline Settings", systemImage: "slider.horizontal.3")
                }
                .help("Timeline settings")
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    TimelineSettings(config: configBinding)
                }

                Button { isFocusMode = true } label: {
                    Label(
                        "Focus", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Focus mode — hide the chrome (⇧⌘F)")

                Button(action: exportPDF) {
                    Label("Export PDF", systemImage: "doc.richtext")
                }
                .help("Export the timeline as a PDF")

                Button(action: exportPNG) {
                    Label("Export PNG", systemImage: "photo")
                }
                .help("Export the timeline as a PNG image")

                ShareLink(
                    item: shareableTimeline,
                    preview: SharePreview(
                        document.config.title.isEmpty
                            ? "Timeline" : document.config.title))
                    .help("Share the timeline image")
            }
        }
    }

    /// The current timeline as a shareable PNG (rendered lazily, in the
    /// current light/dark appearance).
    private var shareableTimeline: ShareableTimeline {
        ShareableTimeline(
            config: document.config,
            title: document.config.title,
            dark: colorScheme == .dark)
    }

    // MARK: - Event editor

    /// The new-event editor (anchored to the + button) is shown while a
    /// freshly added event is open.
    private var newEventPresented: Binding<Bool> {
        Binding(
            get: { isNewEvent && editingEventID != nil },
            set: { if !$0 { closeEditor() } })
    }

    @ViewBuilder private var newEventEditor: some View {
        if let id = editingEventID, let binding = eventBinding(id) {
            EventEditor(
                event: binding,
                onDelete: { deleteEvent(id) },
                onClose: { closeEditor() },
                // Escape on a new event discards it entirely
                onCancel: { deleteEvent(id) },
                referenceDay: .today(),
                showQuickAdd: true,
                // Until the event is named it has no palette slot, so predict
                // the color it will get from its start date instead of red.
                resolvedColorHex: TimelineRenderer.resolvedColorHex(
                    for: document.config)[id]
                    ?? TimelineRenderer.predictedColorHex(
                        for: document.config, start: binding.wrappedValue.start))
        }
    }

    /// A binding to the event with `id`, sort-safe (looks up by id, not
    /// index, and re-sorts on write).
    private func eventBinding(_ id: UUID) -> Binding<TimelineEvent>? {
        guard document.config.events.contains(where: { $0.id == id }) else {
            return nil
        }
        return Binding(
            get: {
                document.config.events.first { $0.id == id } ?? TimelineEvent()
            },
            set: { newValue in
                var config = document.config
                guard let index = config.events.firstIndex(where: { $0.id == id })
                else { return }
                config.events[index] = newValue
                config.events.sort { $0.start < $1.start }
                document.update(config, undoManager: undoManager)
            })
    }

    private func startNewEvent() {
        var start = Day.today()
        if let lower = document.config.timelineStart, start < lower { start = lower }
        if let upper = document.config.timelineEnd, upper < start { start = upper }
        var config = document.config
        let event = TimelineEvent(name: "", start: start)
        let index = config.events.firstIndex { event.start < $0.start }
            ?? config.events.endIndex
        config.events.insert(event, at: index)
        document.update(config, undoManager: undoManager)
        isNewEvent = true
        editingEventID = event.id
    }

    private func closeEditor() {
        // A new event left blank is treated as a cancel.
        if isNewEvent, let id = editingEventID,
           let event = document.config.events.first(where: { $0.id == id }),
           event.name.trimmingCharacters(in: .whitespaces).isEmpty {
            deleteEvent(id)
        }
        editingEventID = nil
        isNewEvent = false
    }

    private func deleteEvent(_ id: UUID) {
        document.update(
            document.config.removingEvent(id: id), undoManager: undoManager)
        editingEventID = nil
        isNewEvent = false
    }

    // Save-panel accessories use plain AppKit controls; SwiftUI hosting
    // views inside NSSavePanel don't reliably receive clicks.
    // Option choices persist in UserDefaults across exports and launches.

    private static let includeGeneratedKey = "exportIncludeGenerated"
    private static let pngScaleIndexKey = "exportPNGScaleIndex"
    private static let pngDarkKey = "exportPNGDark"

    private func exportPDF() {
        let defaults = UserDefaults.standard
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName(extension: "pdf")
        panel.canCreateDirectories = true

        let generatedCheckbox = NSButton(
            checkboxWithTitle: "Include generation date", target: nil, action: nil)
        generatedCheckbox.state =
            defaults.bool(forKey: Self.includeGeneratedKey) ? .on : .off
        panel.accessoryView = accessoryStack(views: [generatedCheckbox])

        guard panel.runModal() == .OK, let url = panel.url else { return }
        defaults.set(generatedCheckbox.state == .on, forKey: Self.includeGeneratedKey)
        do {
            try Exporter.pdfData(
                for: document.config,
                includeGenerated: generatedCheckbox.state == .on
            ).write(to: url)
        } catch {
            presentError(error)
        }
    }

    private func exportPNG() {
        let defaults = UserDefaults.standard
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedName(extension: "png")
        panel.canCreateDirectories = true

        let resolutionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        resolutionPopup.addItems(withTitles: [
            "Standard (72 dpi)", "High (144 dpi)", "Very High (288 dpi)",
        ])
        let savedIndex = defaults.object(forKey: Self.pngScaleIndexKey) as? Int ?? 1
        resolutionPopup.selectItem(at: max(0, min(savedIndex, 2)))
        let resolutionRow = NSStackView(views: [
            NSTextField(labelWithString: "Resolution:"), resolutionPopup,
        ])
        resolutionRow.orientation = .horizontal

        let appearancePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        appearancePopup.addItems(withTitles: ["Light", "Dark"])
        appearancePopup.selectItem(at: defaults.bool(forKey: Self.pngDarkKey) ? 1 : 0)
        let appearanceRow = NSStackView(views: [
            NSTextField(labelWithString: "Appearance:"), appearancePopup,
        ])
        appearanceRow.orientation = .horizontal

        let generatedCheckbox = NSButton(
            checkboxWithTitle: "Include generation date", target: nil, action: nil)
        generatedCheckbox.state =
            defaults.bool(forKey: Self.includeGeneratedKey) ? .on : .off

        panel.accessoryView = accessoryStack(
            views: [resolutionRow, appearanceRow, generatedCheckbox])

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let dark = appearancePopup.indexOfSelectedItem == 1
        defaults.set(generatedCheckbox.state == .on, forKey: Self.includeGeneratedKey)
        defaults.set(resolutionPopup.indexOfSelectedItem, forKey: Self.pngScaleIndexKey)
        defaults.set(dark, forKey: Self.pngDarkKey)
        let scales: [CGFloat] = [1, 2, 4]
        let scale = scales[max(0, min(resolutionPopup.indexOfSelectedItem, 2))]
        do {
            try Exporter.writePNG(
                for: document.config, to: url, scale: scale,
                includeGenerated: generatedCheckbox.state == .on, dark: dark)
        } catch {
            presentError(error)
        }
    }

    /// Move or resize an event by whole days during a canvas drag. Live
    /// changes bypass the undo manager; the release registers one undo
    /// step.
    private func moveEvent(
        id: UUID, part: TimelineRenderer.EventHitPart, dayDelta: Int, isFinal: Bool
    ) {
        if dragOriginalConfig == nil { dragOriginalConfig = document.config }
        guard let original = dragOriginalConfig else { return }

        let shifted = original.shiftingEvent(id: id, part: part, by: dayDelta)

        if isFinal {
            // Restore the original so the undo snapshot covers the drag
            document.config = original
            document.update(shifted, undoManager: undoManager)
            dragOriginalConfig = nil
        } else {
            document.config = shifted
        }
    }

    private func startWatching() {
        fileWatcher = nil
        guard let fileURL else { return }
        fileWatcher = FileWatcher(url: fileURL) {
            reloadFromDisk()
        }
    }

    // Per-document window UI state (zoom + focus mode), keyed by path.
    private static func windowStateKey(for url: URL?) -> String? {
        url.map { "windowState:\($0.path)" }
    }

    /// Saved focus/zoom for a document, with defaults when absent.
    static func savedWindowState(for url: URL?) -> (focus: Bool, zoom: CGFloat) {
        guard let key = windowStateKey(for: url),
              let dict = UserDefaults.standard.dictionary(forKey: key)
        else { return (false, 1) }
        return (dict["focus"] as? Bool ?? false,
                CGFloat(dict["zoom"] as? Double ?? 1))
    }

    private func saveWindowState() {
        guard let key = Self.windowStateKey(for: fileURL) else { return }
        UserDefaults.standard.set(
            ["zoom": Double(zoom), "focus": isFocusMode], forKey: key)
    }

    /// Apply external file changes (e.g. Claude editing via MCP) to the
    /// open document. Our own saves are recognized by comparing the disk
    /// contents against the current config's serialization.
    private func reloadFromDisk() {
        guard let fileURL,
              let text = try? String(contentsOf: fileURL, encoding: .utf8),
              let parsed = try? ConfigYAML.parse(text)
        else { return }
        // Tell the document system we're in sync with disk; otherwise the
        // next save sees a newer mtime and shows the "changed by another
        // application" conflict sheet for a change we already absorbed
        syncModificationDate(fileURL)
        if text == ConfigYAML.serialize(document.config) { return }
        document.update(parsed, undoManager: undoManager)
    }

    /// Update the backing NSDocument's recorded file modification date to
    /// match disk. DocumentGroup is NSDocument-backed on macOS, and that
    /// recorded date is what save-time conflict detection compares.
    private func syncModificationDate(_ url: URL) {
        guard let nsDocument = NSDocumentController.shared.documents.first(
            where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL })
        else { return }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let modified = attributes?[.modificationDate] as? Date {
            nsDocument.fileModificationDate = modified
        }
    }

    /// Print the paged (paper) layout through the system print dialog.
    private func printTimeline() {
        do {
            let includeGenerated = UserDefaults.standard.bool(
                forKey: Self.includeGeneratedKey)
            let data = try Exporter.pdfData(
                for: document.config, includeGenerated: includeGenerated)
            guard let pdf = PDFDocument(data: data) else { return }
            let printInfo = NSPrintInfo()
            printInfo.orientation = .landscape
            // Zero margins + 1:1 scale so the printed page matches the
            // exported PDF exactly (default printer margins shrink it)
            printInfo.topMargin = 0
            printInfo.bottomMargin = 0
            printInfo.leftMargin = 0
            printInfo.rightMargin = 0
            guard let operation = pdf.printOperation(
                for: printInfo, scalingMode: .pageScaleNone, autoRotate: true)
            else { return }
            operation.run()
        } catch {
            presentError(error)
        }
    }

    private func accessoryStack(views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        stack.frame.size = stack.fittingSize
        return stack
    }

    private func suggestedName(extension ext: String) -> String {
        let base = document.config.title.isEmpty ? "timeline" : document.config.title
        return base.lowercased().replacingOccurrences(of: " ", with: "-") + "." + ext
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
