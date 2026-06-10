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

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName(extension: "pdf")
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Exporter.pdfData(for: document.config).write(to: url)
        } catch {
            presentError(error)
        }
    }

    private func exportPNG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedName(extension: "png")
        panel.canCreateDirectories = true
        let pages = TimelineRenderer(config: document.config).pageCount
        if pages > 1 {
            panel.message = "The timeline has \(pages) pages; they will be saved as separate numbered images."
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Exporter.writePNGs(for: document.config, to: url)
        } catch {
            presentError(error)
        }
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
