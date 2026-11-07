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
        provider(type: .png) { config, dark in
            try Exporter.pngData(for: config, scale: 2, dark: dark)
        }
    }

    /// An NSItemProvider that produces the PDF on demand, for `.onDrag`.
    func pdfDragProvider() -> NSItemProvider {
        provider(type: .pdf) { config, _ in
            try Exporter.pdfData(for: config)
        }
    }

    private func provider(
        type: UTType, render: @escaping (TimelineConfig, Bool) throws -> Data
    ) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = baseName
        let config = config
        let dark = dark
        provider.registerDataRepresentation(
            forTypeIdentifier: type.identifier, visibility: .all
        ) { completion in
            DispatchQueue.global(qos: .userInitiated).async {
                do { completion(try render(config, dark), nil) }
                catch { completion(nil, error) }
            }
            return nil
        }
        // Chromium-based apps (Slack, Chrome, VS Code, Discord…) only take
        // dropped files, not image data, so also offer a file, rendered when
        // a drop target asks for it.
        // ponytail: left in the temp folder; macOS clears it after a few days.
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(baseName)
            .appendingPathExtension(type.preferredFilenameExtension ?? "")
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier, visibility: .all
        ) { completion in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try FileManager.default.createDirectory(
                        at: file.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    try render(config, dark).write(to: file)
                    completion(file.dataRepresentation, nil)
                } catch { completion(nil, error) }
            }
            return nil
        }
        return provider
    }
}
