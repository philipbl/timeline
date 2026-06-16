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

    var fileName: String {
        let base = title.isEmpty ? "timeline" : title
        return base.lowercased().replacingOccurrences(of: " ", with: "-") + ".png"
    }

    /// An NSItemProvider that produces the PNG on demand, for `.onDrag`.
    func dragProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = fileName
        let config = config
        let dark = dark
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier, visibility: .all
        ) { completion in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    completion(try Exporter.pngData(for: config, scale: 2, dark: dark), nil)
                } catch {
                    completion(nil, error)
                }
            }
            return nil
        }
        return provider
    }
}
