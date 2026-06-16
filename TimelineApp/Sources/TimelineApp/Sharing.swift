import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A lazily-rendered PNG of a timeline, for ShareLink and drag-and-drop.
/// The bytes are produced only when a share destination or drop target
/// actually asks for them, so constructing one is cheap.
struct ShareableTimeline: Transferable {
    let config: TimelineConfig
    let title: String
    let dark: Bool

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            try Exporter.pngData(for: item.config, scale: 2, dark: item.dark)
        }
        .suggestedFileName { $0.fileName }
    }

    /// Extension-less base name; the system appends the type's extension.
    var baseName: String {
        let base = title.isEmpty ? "timeline" : title
        return base.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    /// Full file name with extension, for ShareLink's suggestedFileName.
    var fileName: String { baseName + ".png" }

    /// An NSItemProvider that produces the PNG on demand, for `.onDrag`.
    func dragProvider() -> NSItemProvider {
        // suggestedName must be extension-less: the system adds ".png" from
        // the type, so "name.png" here would become "name.png.png".
        provider(typeIdentifier: UTType.png.identifier) { config, dark in
            try Exporter.pngData(for: config, scale: 2, dark: dark)
        }
    }

    /// An NSItemProvider that produces the PDF on demand, for `.onDrag`.
    func pdfDragProvider() -> NSItemProvider {
        provider(typeIdentifier: UTType.pdf.identifier) { config, _ in
            try Exporter.pdfData(for: config)
        }
    }

    private func provider(
        typeIdentifier: String, render: @escaping (TimelineConfig, Bool) throws -> Data
    ) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = baseName
        let config = config
        let dark = dark
        provider.registerDataRepresentation(
            forTypeIdentifier: typeIdentifier, visibility: .all
        ) { completion in
            DispatchQueue.global(qos: .userInitiated).async {
                do { completion(try render(config, dark), nil) }
                catch { completion(nil, error) }
            }
            return nil
        }
        return provider
    }
}
