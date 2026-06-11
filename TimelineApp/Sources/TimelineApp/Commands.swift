import SwiftUI

/// Actions the focused document window exposes to the menu bar.
struct TimelineActions {
    var exportPDF: () -> Void
    var exportPNG: () -> Void
    var printTimeline: () -> Void
    var toggleFocus: () -> Void
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
            Button("Toggle Focus Mode") { actions?.toggleFocus() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Divider()
        }
    }
}
