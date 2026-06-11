import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Binding var document: TimelineDocument

    var body: some View {
        HSplitView {
            EditorView(config: $document.config)
                .frame(minWidth: 330, idealWidth: 380, maxWidth: 520)
            PreviewView(config: document.config)
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName(extension: "pdf")
        panel.canCreateDirectories = true

        let generatedCheckbox = NSButton(
            checkboxWithTitle: "Include generation date", target: nil, action: nil)
        generatedCheckbox.state = .off
        panel.accessoryView = accessoryStack(views: [generatedCheckbox])

        guard panel.runModal() == .OK, let url = panel.url else { return }
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
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedName(extension: "png")
        panel.canCreateDirectories = true

        let resolutionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        resolutionPopup.addItems(withTitles: [
            "Standard (72 dpi)", "High (144 dpi)", "Very High (288 dpi)",
        ])
        resolutionPopup.selectItem(at: 1)
        let resolutionRow = NSStackView(views: [
            NSTextField(labelWithString: "Resolution:"), resolutionPopup,
        ])
        resolutionRow.orientation = .horizontal

        let generatedCheckbox = NSButton(
            checkboxWithTitle: "Include generation date", target: nil, action: nil)
        generatedCheckbox.state = .off

        panel.accessoryView = accessoryStack(views: [resolutionRow, generatedCheckbox])

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scales: [CGFloat] = [1, 2, 4]
        let scale = scales[max(0, min(resolutionPopup.indexOfSelectedItem, 2))]
        do {
            try Exporter.writePNG(
                for: document.config, to: url, scale: scale,
                includeGenerated: generatedCheckbox.state == .on)
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
