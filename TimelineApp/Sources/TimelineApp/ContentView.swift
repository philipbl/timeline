import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var document: TimelineDocument
    @Environment(\.undoManager) private var undoManager
    @State private var isFocusMode = false
    @AppStorage("editorWidth") private var editorWidth: Double = 380

    /// All edits route through the document so they register undo.
    private var configBinding: Binding<TimelineConfig> {
        Binding(
            get: { document.config },
            set: { document.update($0, undoManager: undoManager) })
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HSplitView {
                if !isFocusMode {
                    EditorView(config: configBinding)
                        .frame(minWidth: 330, idealWidth: editorWidth, maxWidth: 520)
                        .background(
                            // Remember the divider position across launches
                            GeometryReader { geo in
                                Color.clear.onChange(of: geo.size.width) {
                                    _, width in
                                    editorWidth = width
                                }
                            })
                }
                PreviewView(config: document.config)
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            }

            // Exit button pinned to the true top-right corner of the
            // window (the ZStack ignores the hidden title bar's safe area)
            if isFocusMode {
                Button {
                    isFocusMode = false
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(.borderless)
                .padding(8)
                .background(.regularMaterial, in: Circle())
                .padding(12)
                .help("Show the sidebar and toolbar (⇧⌘F)")
            }
        }
        .ignoresSafeArea(.container, edges: isFocusMode ? .top : [])
        .toolbar(isFocusMode ? .hidden : .automatic, for: .windowToolbar)
        // Menu bar (File/View) drives these via FocusedValues; the menu
        // owns the keyboard shortcuts so they survive toolbar hiding
        .focusedSceneValue(
            \.timelineActions,
            TimelineActions(
                exportPDF: exportPDF,
                exportPNG: exportPNG,
                printTimeline: printTimeline,
                toggleFocus: { isFocusMode.toggle() }))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isFocusMode = true
                } label: {
                    Label(
                        "Focus",
                        systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Hide the sidebar and toolbar (⇧⌘F)")

                Button(action: exportPDF) {
                    Label("Export PDF", systemImage: "doc.richtext")
                }
                .help("Export the timeline as a PDF")

                Button(action: exportPNG) {
                    Label("Export PNG", systemImage: "photo")
                }
                .help("Export the timeline as a PNG image")
            }
        }
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
