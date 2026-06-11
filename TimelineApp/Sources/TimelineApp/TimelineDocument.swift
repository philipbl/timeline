import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Our own document type (.timeline) so the app doesn't claim every
    /// YAML file on the system. The contents are still plain YAML and
    /// stay compatible with the Python CLI.
    static var timelineDocument: UTType {
        UTType(exportedAs: "com.philipbl.timeline", conformingTo: .yaml)
    }
}

struct TimelineDocument: FileDocument {
    var config: TimelineConfig

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

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let text = ConfigYAML.serialize(config)
        return FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
