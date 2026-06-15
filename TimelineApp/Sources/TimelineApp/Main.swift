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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let restoreKey = "restoreOpenDocuments"

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            DeepLink.handle(url)
        }
    }

    /// Reopen the documents (and window frames) that were open at last
    /// quit. macOS's built-in restoration doesn't fire reliably for this
    /// ad-hoc-signed bundle, so we persist it ourselves.
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { self.restoreOpenDocuments() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveOpenDocuments()
    }

    private func saveOpenDocuments() {
        let entries: [[String: String]] =
            NSDocumentController.shared.documents.compactMap { doc in
                guard let path = doc.fileURL?.path,
                      let window = doc.windowControllers.first?.window
                else { return nil }
                return ["path": path, "frame": window.frameDescriptor]
            }
        UserDefaults.standard.set(entries, forKey: Self.restoreKey)
    }

    private func restoreOpenDocuments() {
        // Don't override a document opened by a file double-click, a
        // deep link, or the system at launch.
        let alreadyOpen = NSDocumentController.shared.documents.contains {
            $0.fileURL != nil
        }
        guard !alreadyOpen,
              let entries = UserDefaults.standard.array(forKey: Self.restoreKey)
                  as? [[String: String]],
              !entries.isEmpty
        else { return }

        let controller = NSDocumentController.shared
        for entry in entries {
            guard let path = entry["path"] else { continue }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            controller.openDocument(withContentsOf: url, display: true) {
                document, _, _ in
                if let frame = entry["frame"],
                   let window = document?.windowControllers.first?.window {
                    window.setFrame(from: frame)
                }
            }
        }

        // Dismiss the launch "Open" panel if it appeared
        for window in NSApp.windows where window is NSOpenPanel {
            window.close()
        }
    }
}

struct TimelineAppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: { TimelineDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1280, height: 760)
        .commands {
            TimelineCommands()
        }
    }
}
