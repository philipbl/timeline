import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var yamlTimeline: UTType {
        UTType(importedAs: "public.yaml", conformingTo: .plainText)
    }
}

struct TimelineDocument: FileDocument {
    var config: TimelineConfig

    static var readableContentTypes: [UTType] { [.yamlTimeline, .plainText] }
    static var writableContentTypes: [UTType] { [.yamlTimeline] }

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
