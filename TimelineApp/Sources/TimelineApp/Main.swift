import AppKit
import Foundation
import SwiftUI

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        // Headless mode for testing: Timeline --render in.yaml out.pdf|out.png
        if args.count >= 4, args[1] == "--render" {
            do {
                let text = try String(contentsOfFile: args[2], encoding: .utf8)
                let config = try ConfigYAML.parse(text)
                let outputURL = URL(fileURLWithPath: args[3])
                if outputURL.pathExtension.lowercased() == "png" {
                    try Exporter.writePNG(for: config, to: outputURL)
                } else {
                    try Exporter.pdfData(for: config).write(to: outputURL)
                }
                print("Rendered \(args[2]) -> \(args[3])")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
                exit(1)
            }
        }

        TimelineAppMain.main()
    }
}

struct TimelineAppMain: App {
    var body: some Scene {
        DocumentGroup(newDocument: TimelineDocument()) { file in
            ContentView(document: file.$document)
        }
        .defaultSize(width: 1280, height: 760)
    }
}
