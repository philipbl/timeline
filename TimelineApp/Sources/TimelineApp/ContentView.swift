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
        let options = ExportOptionsModel()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName(extension: "pdf")
        panel.canCreateDirectories = true
        attachAccessory(PDFExportOptionsView(options: options), to: panel)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Exporter.pdfData(
                for: document.config, includeGenerated: options.includeGenerated
            ).write(to: url)
        } catch {
            presentError(error)
        }
    }

    private func exportPNG() {
        let options = ExportOptionsModel()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedName(extension: "png")
        panel.canCreateDirectories = true
        attachAccessory(PNGExportOptionsView(options: options), to: panel)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Exporter.writePNG(
                for: document.config, to: url, scale: options.scale,
                includeGenerated: options.includeGenerated)
        } catch {
            presentError(error)
        }
    }

    private func attachAccessory(_ view: some View, to panel: NSSavePanel) {
        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)
        panel.accessoryView = hosting
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

final class ExportOptionsModel: ObservableObject {
    @Published var includeGenerated = false
    @Published var scale: CGFloat = 2
}

struct PDFExportOptionsView: View {
    @ObservedObject var options: ExportOptionsModel

    var body: some View {
        Toggle("Include generation date", isOn: $options.includeGenerated)
            .padding(12)
    }
}

struct PNGExportOptionsView: View {
    @ObservedObject var options: ExportOptionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Resolution:", selection: $options.scale) {
                Text("Standard (72 dpi)").tag(CGFloat(1))
                Text("High (144 dpi)").tag(CGFloat(2))
                Text("Very High (288 dpi)").tag(CGFloat(4))
            }
            .pickerStyle(.menu)
            .fixedSize()

            Toggle("Include generation date", isOn: $options.includeGenerated)
        }
        .padding(12)
    }
}
