import SwiftUI

/// Spotlight-style find panel (⌘F): type to filter events by name or note,
/// click a result (or press Return for the first match) to open it.
struct EventSearchPanel: View {
    @Binding var query: String
    let events: [TimelineEvent]
    let onSelect: (UUID) -> Void
    let onClose: () -> Void

    @FocusState private var focused: Bool
    @State private var hovered: UUID?

    private var matches: [TimelineEvent] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return events.filter {
            $0.name.lowercased().contains(q) || $0.notes.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find event", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { if let first = matches.first { onSelect(first.id) } }
            }
            .padding(10)

            if !matches.isEmpty {
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(matches) { event in
                            row(event)
                                .background(
                                    hovered == event.id
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(event.id) }
                                .onHover { hovered = $0 ? event.id : nil }
                        }
                    }
                }
                .frame(maxHeight: 240)
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Divider()
                Text("No matching events")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
        .frame(width: 320)
        .glassChrome(in: RoundedRectangle(cornerRadius: 10))
        .onAppear { focused = true }
        .onExitCommand { onClose() }
    }

    private func row(_ event: TimelineEvent) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.name.isEmpty ? "(untitled)" : event.name)
                Text(dateLabel(event))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func dateLabel(_ event: TimelineEvent) -> String {
        if let end = event.end {
            return "\(event.start.shortLabel) – \(end.shortLabel)"
        }
        return event.start.shortLabel
    }
}
