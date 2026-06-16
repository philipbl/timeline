import SwiftUI

/// Popover content for creating or editing one event. A natural-language
/// quick-add field sits on top (parser fills the fields); structured
/// fields below for precise edits.
struct EventEditor: View {
    @Binding var event: TimelineEvent
    /// nil when creating a brand-new event (no Delete button).
    var onDelete: (() -> Void)?
    var onClose: () -> Void
    /// Escape: discards a new event (vs. onClose which keeps it).
    var onCancel: () -> Void
    /// Reference date for relative phrases ("next Friday").
    var referenceDay: Day
    /// The natural-language quick-add field only makes sense when creating.
    var showQuickAdd: Bool = true
    /// The event's effective palette color (#RRGGBB), shown in the color
    /// well when the event has no explicit override.
    var resolvedColorHex: String = "#9A9AA2"

    @State private var quickText = ""
    @State private var isParsing = false
    @FocusState private var quickFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Natural-language quick add (new events only)
            if showQuickAdd {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.secondary)
                        TextField("e.g. Trip to Boston Jul 1–7", text: $quickText)
                            .textFieldStyle(.roundedBorder)
                            .focused($quickFocused)
                            .onSubmit(applyQuickText)
                        if isParsing {
                            ProgressView().controlSize(.small)
                        } else {
                            Button(action: applyQuickText) {
                                Image(systemName: "return")
                            }
                            .buttonStyle(.borderless)
                            .disabled(
                                quickText.trimmingCharacters(in: .whitespaces)
                                    .isEmpty)
                            .help("Fill the fields from this text")
                        }
                    }
                    Text("Type a date or range; press Return to fill the fields below.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()
            }

            TextField("Name", text: $event.name, prompt: Text("Event name"))
                .textFieldStyle(.roundedBorder)

            DayPicker(label: "Start", day: $event.start)

            Toggle(
                "Multi-day",
                isOn: Binding(
                    get: { event.end != nil },
                    set: { event.end = $0 ? event.start.shifted(days: 1) : nil }))
            if event.end != nil {
                DayPicker(
                    label: "End",
                    day: Binding(
                        get: { event.end ?? event.start },
                        set: { event.end = $0 }))
            }

            Toggle("Done", isOn: $event.done)
            Toggle("Important", isOn: $event.important)

            colorRow

            // Plain style (not .roundedBorder) so the vertical-axis field
            // actually grows with the text instead of scrolling one line.
            TextField(
                "Notes", text: $event.notes,
                prompt: Text("Notes"), axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary))

            Divider()

            HStack {
                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                        onClose()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete event")
                }
                Spacer()
                // ⌘Return closes; plain Return is reserved for the
                // quick-add field's parse action.
                Button("Done") { onClose() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .toggleStyle(EditorSwitchStyle())
        .controlSize(.small)
        .padding(14)
        .frame(width: 300)
        .onAppear { quickFocused = true }
        .onExitCommand { onCancel() }  // Escape
    }

    private var colorRow: some View {
        HStack {
            Text("Color")
            Spacer()
            ColorPicker(
                "",
                selection: Binding(
                    get: { Color(hex: event.colorHex ?? resolvedColorHex) },
                    set: { event.colorHex = $0.hexString }),
                supportsOpacity: false)
                .labelsHidden()
            if event.colorHex != nil {
                Button("Auto") { event.colorHex = nil }
                    .help("Use the automatic palette color")
            }
        }
    }

    private func applyQuickText() {
        let trimmed = quickText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isParsing else { return }
        isParsing = true
        Task {
            // Apple Intelligence when available, else the built-in parser
            let parsed = await EventIntelligence.parse(
                trimmed, relativeTo: referenceDay)
            await MainActor.run {
                if let parsed {
                    event.name = parsed.name
                    event.start = parsed.start
                    event.end = parsed.end
                    quickText = ""
                }
                isParsing = false
            }
        }
    }
}
