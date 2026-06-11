import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Our own document type (.timeline) so the app doesn't claim every
    /// YAML file on the system. The contents are still plain YAML.
    static var timelineDocument: UTType {
        UTType(exportedAs: "com.philipbl.timeline", conformingTo: .yaml)
    }
}

/// Reference document so edits can register undo: every change goes
/// through update(_:undoManager:), giving ⌘Z/⇧⌘Z for free.
final class TimelineDocument: ReferenceFileDocument {
    typealias Snapshot = TimelineConfig

    @Published var config: TimelineConfig

    // .yaml stays openable (File > Open an existing events.yaml) but the
    // app only claims .timeline in Finder and always saves as .timeline
    static var readableContentTypes: [UTType] { [.timelineDocument, .yaml] }
    static var writableContentTypes: [UTType] { [.timelineDocument] }

    init() {
        config = TimelineConfig.starter()
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        config = try ConfigYAML.parse(text)
    }

    func snapshot(contentType: UTType) throws -> TimelineConfig {
        config
    }

    func fileWrapper(
        snapshot: TimelineConfig, configuration: WriteConfiguration
    ) throws -> FileWrapper {
        let text = ConfigYAML.serialize(snapshot)
        return FileWrapper(regularFileWithContents: Data(text.utf8))
    }

    /// Apply a change with undo support.
    func update(_ newConfig: TimelineConfig, undoManager: UndoManager?) {
        guard newConfig != config else { return }
        let old = config
        config = newConfig
        undoManager?.registerUndo(withTarget: self) { document in
            document.update(old, undoManager: undoManager)
        }
    }
}
