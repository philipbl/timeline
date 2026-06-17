import AppKit
import SwiftUI

/// Drives keyboard navigation for the find panel. A local key monitor lets
/// ↑/↓ move the selection and Return open it even while the text field has
/// focus (the field would otherwise consume the arrow keys for the cursor).
/// Closures are read live so the monitor always sees the current matches.
final class SearchController: ObservableObject {
    @Published var selection = 0
    var currentMatchIDs: () -> [UUID] = { [] }
    var onSelectID: (UUID) -> Void = { _ in }
    var onScrollTo: (UUID) -> Void = { _ in }

    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let ids = self.currentMatchIDs()
            switch event.keyCode {
            case 126:  // up arrow
                guard !ids.isEmpty else { return nil }
                self.selection = max(self.selection - 1, 0)
                self.onScrollTo(ids[self.selection])
                return nil
            case 125:  // down arrow
                guard !ids.isEmpty else { return nil }
                self.selection = min(self.selection + 1, ids.count - 1)
                self.onScrollTo(ids[self.selection])
                return nil
            case 36, 76:  // return / enter
                if ids.indices.contains(self.selection) {
                    self.onSelectID(ids[self.selection])
                }
                return nil
            default:
                return event
            }
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Spotlight-style find panel (⌘F): type to filter events by name or note,
/// ↑/↓ to move, Return to open the highlighted one, click any result, Escape
/// to dismiss.
struct EventSearchPanel: View {
    @Binding var query: String
    let events: [TimelineEvent]
    let onSelect: (UUID) -> Void
    let onClose: () -> Void

    @StateObject private var controller = SearchController()
    @FocusState private var focused: Bool

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
            }
            .padding(10)

            if !matches.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) {
                                index, event in
                                row(event)
                                    .background(
                                        index == controller.selection
                                            ? Color.accentColor.opacity(0.15)
                                            : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onSelect(event.id) }
                                    .onHover { if $0 { controller.selection = index } }
                                    .id(event.id)
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                    .onAppear { controller.onScrollTo = { proxy.scrollTo($0) } }
                }
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
        .onAppear {
            focused = true
            controller.currentMatchIDs = { matches.map(\.id) }
            controller.onSelectID = onSelect
            controller.install()
        }
        .onDisappear { controller.uninstall() }
        .onChange(of: query) { controller.selection = 0 }
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
