import AppKit
import SwiftUI

/// Actions the focused document window exposes to the menu bar.
struct TimelineActions {
    var exportPDF: () -> Void
    var exportPNG: () -> Void
    var printTimeline: () -> Void
    var toggleFocus: () -> Void
    var resetZoom: () -> Void
}

struct TimelineActionsKey: FocusedValueKey {
    typealias Value = TimelineActions
}

extension FocusedValues {
    var timelineActions: TimelineActions? {
        get { self[TimelineActionsKey.self] }
        set { self[TimelineActionsKey.self] = newValue }
    }
}

struct TimelineCommands: Commands {
    @FocusedValue(\.timelineActions) private var actions
    @AppStorage("showTodayMarker") private var showTodayMarker = true

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Timeline") {
                NSApplication.shared.orderFrontStandardAboutPanel(
                    options: [.credits: Self.aboutCredits])
            }
        }

        CommandGroup(after: .saveItem) {
            Divider()
            Button("Export as PDF…") { actions?.exportPDF() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button("Export as PNG…") { actions?.exportPNG() }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
                .disabled(actions == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") { actions?.printTimeline() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(actions == nil)
        }

        CommandGroup(after: .sidebar) {
            Toggle("Show Today Marker", isOn: $showTodayMarker)
            Button("Actual Size") { actions?.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(actions == nil)
            Button("Toggle Focus Mode") { actions?.toggleFocus() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Divider()
        }
    }

    /// Credits shown in the standard About panel: a one-liner and a
    /// link to the repository. Version/copyright come from Info.plist.
    private static var aboutCredits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let credits = NSMutableAttributedString(
            string: "Visual timelines for planning and tracking.\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ])
        credits.append(
            NSAttributedString(
                string: "github.com/philipbl/timeline",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .link: URL(string: "https://github.com/philipbl/timeline")!,
                    .paragraphStyle: paragraph,
                ]))
        return credits
    }
}
