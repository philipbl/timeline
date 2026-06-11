import AppKit
import Foundation
import SwiftUI

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments

        // MCP server over stdio, so Claude can manage timeline documents
        if args.contains("--mcp") {
            MCPServer.run()
        }

        if args.contains("--self-test") {
            #if DEBUG
            exit(SelfTests.run())
            #else
            FileHandle.standardError.write(
                Data("Self tests are only available in debug builds\n".utf8))
            exit(1)
            #endif
        }
        // Headless render: Timeline --render in.timeline out.pdf|out.png [--dark]
        if args.count >= 4, args[1] == "--render" {
            do {
                let text = try String(contentsOfFile: args[2], encoding: .utf8)
                let config = try ConfigYAML.parse(text)
                let outputURL = URL(fileURLWithPath: args[3])
                // No generation stamp: keeps renders reproducible for the
                // golden-image check in CI
                if outputURL.pathExtension.lowercased() == "png" {
                    try Exporter.writePNG(
                        for: config, to: outputURL,
                        dark: args.contains("--dark"))
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

        // Golden-image check: Timeline --compare a.png b.png maxPercent
        if args.count >= 5, args[1] == "--compare" {
            guard let threshold = Double(args[4]),
                  let difference = Exporter.imageDifferencePercent(
                      URL(fileURLWithPath: args[2]), URL(fileURLWithPath: args[3]))
            else {
                FileHandle.standardError.write(
                    Data("Error: could not compare images\n".utf8))
                exit(2)
            }
            print(String(format: "Image difference: %.3f%% (max %.1f%%)", difference, threshold))
            exit(difference <= threshold ? 0 : 1)
        }

        TimelineAppMain.main()
    }
}

struct TimelineAppMain: App {
    var body: some Scene {
        DocumentGroup(newDocument: { TimelineDocument() }) { file in
            ContentView(document: file.document)
        }
        .defaultSize(width: 1280, height: 760)
        .commands {
            TimelineCommands()
        }
    }
}
