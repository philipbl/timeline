import SwiftUI

struct EditorView: View {
    @Binding var config: TimelineConfig
    @State private var expandedEvents: Set<UUID> = []
    @FocusState private var focusedEventName: UUID?

    var body: some View {
        let resolvedColors = TimelineRenderer.resolvedColorHex(for: config)

        // List (not Form) so .swipeActions works on the rows; grouped-form
        // look recreated with row backgrounds
        List {
            Section("Timeline") {
                TextField("Title", text: $config.title, prompt: Text("Untitled"))
                    .groupedRow(index: 0, count: 3)

                OptionalDayRow(label: "Starts", day: $config.timelineStart, defaultDay: .today())
                    .groupedRow(index: 1, count: 3)
                VStack(alignment: .leading, spacing: 6) {
                    OptionalDayRow(
                        label: "Ends", day: $config.timelineEnd,
                        defaultDay: Day.today().shifted(days: 14))
                    if config.timelineEnd == nil {
                        Text("Without an end date, the timeline runs to the last event.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .groupedRow(index: 2, count: 3)
            }

            Section {
                ForEach($config.events) { $event in
                    EventRow(
                        event: $event,
                        resolvedColorHex: resolvedColors[event.id]
                            ?? TimelineRenderer.eventColors[0],
                        isExpanded: expansionBinding(for: event.id),
                        nameFocus: $focusedEventName,
                        onDelete: { deleteEvent(event.id) }
                    )
                    .groupedRow(
                        index: config.events.firstIndex { $0.id == event.id } ?? 0,
                        count: config.events.count)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteEvent(event.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteEvent(event.id)
                        } label: {
                            Label("Delete Event", systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Events")
                    Spacer()
                    Button(action: addEvent) {
                        Label("Add Event", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.titleAndIcon)
                }
            }

            Section {
                ForEach($config.customHolidays) { $holiday in
                    HolidayRow(holiday: $holiday) {
                        config.customHolidays.removeAll { $0.id == holiday.id }
                    }
                    .groupedRow(
                        index: config.customHolidays.firstIndex { $0.id == holiday.id }
                            ?? 0,
                        count: config.customHolidays.count)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            config.customHolidays.removeAll { $0.id == holiday.id }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Custom Holidays")
                    Spacer()
                    Button {
                        config.customHolidays.append(CustomHoliday(start: .today()))
                    } label: {
                        Label("Add Holiday", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.titleAndIcon)
                }
            } footer: {
                Text("US federal holidays and weekends are shaded automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
        .listRowSeparator(.hidden)
        .environment(\.defaultMinListRowHeight, 40)
        .onAppear(perform: sortEvents)
        .onChange(of: config.events.map(\.start)) {
            sortEvents()
        }
    }

    /// Keep events chronological at all times — including after edits to
    /// a start date and when new events are inserted.
    private func sortEvents() {
        let sorted = config.events.sorted { $0.start < $1.start }
        if sorted.map(\.id) != config.events.map(\.id) {
            config.events = sorted
        }
    }

    private func addEvent() {
        var start = Day.today()
        if let timelineStart = config.timelineStart, start < timelineStart {
            start = timelineStart
        }
        if let timelineEnd = config.timelineEnd, timelineEnd < start {
            start = timelineEnd
        }
        let event = TimelineEvent(name: "", start: start)
        // Insert at the chronological position rather than appending
        let index = config.events.firstIndex { event.start < $0.start }
            ?? config.events.endIndex
        config.events.insert(event, at: index)
        expandedEvents.insert(event.id)
        // Focus the new row's name field once it exists in the hierarchy
        DispatchQueue.main.async {
            focusedEventName = event.id
        }
    }

    private func deleteEvent(_ id: UUID) {
        config.events.removeAll { $0.id == id }
        expandedEvents.remove(id)
    }

    private func expansionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedEvents.contains(id) },
            set: { expanded in
                if expanded {
                    expandedEvents.insert(id)
                } else {
                    expandedEvents.remove(id)
                }
            })
    }
}

/// Grouped-form row styling for List rows: shared rounded box per
/// section (rounded top on the first row, bottom on the last), with the
/// roomier insets of .formStyle(.grouped).
struct GroupedRow: ViewModifier {
    let index: Int
    let count: Int

    func body(content: Content) -> some View {
        let top: CGFloat = index == 0 ? 8 : 0
        let bottom: CGFloat = index == max(count - 1, 0) ? 8 : 0
        content
            .padding(.vertical, 2)
            .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            .listRowSeparator(.hidden)
            .listRowBackground(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: top, bottomLeading: bottom,
                        bottomTrailing: bottom, topTrailing: top))
                    .fill(Color.primary.opacity(0.055))
                    .padding(.horizontal, 4))
    }
}

extension View {
    func groupedRow(index: Int, count: Int) -> some View {
        modifier(GroupedRow(index: index, count: count))
    }
}

/// DatePicker bound to a Day.
struct DayPicker: View {
    let label: String
    @Binding var day: Day

    var body: some View {
        DatePicker(
            label,
            selection: Binding(
                get: { day.localDate },
                set: { day = Day(date: $0) }),
            displayedComponents: .date)
    }
}

/// Toggleable optional date (timeline start/end overrides).
struct OptionalDayRow: View {
    let label: String
    @Binding var day: Day?
    let defaultDay: Day

    var body: some View {
        HStack {
            Toggle(
                label,
                isOn: Binding(
                    get: { day != nil },
                    set: { day = $0 ? defaultDay : nil }))
            .toggleStyle(.switch)
            .controlSize(.small)
            if day != nil {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { (day ?? defaultDay).localDate },
                        set: { day = Day(date: $0) }),
                    displayedComponents: .date)
                .labelsHidden()
            }
        }
    }
}

struct EventRow: View {
    @Binding var event: TimelineEvent
    let resolvedColorHex: String
    @Binding var isExpanded: Bool
    var nameFocus: FocusState<UUID?>.Binding
    let onDelete: () -> Void

    @State private var showColorPicker = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            DayPicker(label: "Start", day: $event.start)

            Toggle(
                "Multi-day",
                isOn: Binding(
                    get: { event.end != nil },
                    set: { event.end = $0 ? event.start.shifted(days: 1) : nil }))
            .toggleStyle(.switch)
            .controlSize(.small)
            if event.end != nil {
                DayPicker(
                    label: "End",
                    day: Binding(
                        get: { event.end ?? event.start },
                        set: { event.end = $0 }))
            }

            HStack {
                Toggle("Done", isOn: $event.done)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete event")
            }
        } label: {
            HStack {
                colorDot
                TextField("Name", text: $event.name, prompt: Text("Event name"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .strikethrough(event.done)
                    .focused(nameFocus, equals: event.id)
                Spacer()
                Text(dateSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// The event's effective color; click to customize it.
    private var colorDot: some View {
        Button {
            showColorPicker = true
        } label: {
            Circle()
                .fill(Color(hex: resolvedColorHex))
                .frame(width: 11, height: 11)
                .overlay(
                    Circle().strokeBorder(.quaternary, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Change event color")
        .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
            VStack(spacing: 10) {
                ColorPicker(
                    "Event Color",
                    selection: Binding(
                        get: { Color(hex: event.colorHex ?? resolvedColorHex) },
                        set: { event.colorHex = $0.hexString }),
                    supportsOpacity: false)

                if event.colorHex != nil {
                    Button("Use Automatic Color") {
                        event.colorHex = nil
                        showColorPicker = false
                    }
                }
            }
            .padding(12)
            .frame(minWidth: 180)
        }
    }

    private var dateSummary: String {
        if let end = event.end {
            return "\(event.start.shortLabel) – \(end.shortLabel)"
        }
        return event.start.shortLabel
    }
}

struct HolidayRow: View {
    @Binding var holiday: CustomHoliday
    let onDelete: () -> Void

    var body: some View {
        DisclosureGroup {
            DayPicker(label: "Start", day: $holiday.start)

            HStack {
                Toggle(
                    "Multi-day",
                    isOn: Binding(
                        get: { holiday.end != nil },
                        set: { holiday.end = $0 ? holiday.start.shifted(days: 1) : nil }))
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete holiday")
            }
            if holiday.end != nil {
                DayPicker(
                    label: "End",
                    day: Binding(
                        get: { holiday.end ?? holiday.start },
                        set: { holiday.end = $0 }))
            }
        } label: {
            HStack {
                TextField("Name", text: $holiday.name, prompt: Text("Holiday name (optional)"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                Spacer()
                Text(
                    holiday.end != nil
                        ? "\(holiday.start.shortLabel) – \(holiday.effectiveEnd.shortLabel)"
                        : holiday.start.shortLabel
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(
            format: "#%02X%02X%02X",
            Int(round(ns.redComponent * 255)),
            Int(round(ns.greenComponent * 255)),
            Int(round(ns.blueComponent * 255)))
    }
}
