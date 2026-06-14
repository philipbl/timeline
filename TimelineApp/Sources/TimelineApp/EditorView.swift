import SwiftUI

struct EditorView: View {
    @Binding var config: TimelineConfig
    /// Set externally (canvas double-click) to expand an event's row and
    /// scroll it into view; resets to nil once handled.
    @Binding var revealEventID: UUID?
    @State private var expandedEvents: Set<UUID> = []
    @FocusState private var focusedEventName: UUID?

    var body: some View {
        let resolvedColors = TimelineRenderer.resolvedColorHex(for: config)

        // List (not Form) so .swipeActions works on the rows; grouped-form
        // look recreated with row backgrounds
        ScrollViewReader { scrollProxy in
            List {
            Section("Timeline") {
                TextField("Title", text: $config.title, prompt: Text("Untitled"))
                    .groupedRow(index: 0, count: 6)

                OptionalDayRow(label: "Starts", day: $config.timelineStart, defaultDay: .today())
                    .groupedRow(index: 1, count: 6)
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
                .groupedRow(index: 2, count: 4)
                DisclosureGroup("Advanced") {
                    HStack {
                        Text("Days per row")
                        Spacer()
                        Stepper(
                            value: Binding(
                                get: { config.daysPerRow ?? 22 },
                                set: { config.daysPerRow = $0 }),
                            in: 5...60
                        ) {
                            Text("\(config.daysPerRow ?? 22)")
                                .monospacedDigit()
                        }
                    }
                    .padding(.top, 4)

                    Toggle("Shade weekends", isOn: $config.shadeWeekends)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    Toggle("Shade holidays", isOn: $config.shadeHolidays)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    Picker(
                        "Colors",
                        selection: Binding(
                            get: {
                                config.customPalette != nil
                                    ? "custom"
                                    : config.paletteName
                                        ?? TimelineRenderer.palettes[0].name
                            },
                            set: { name in
                                if name == "custom" {
                                    // Seed with the currently active palette
                                    config.customPalette =
                                        TimelineRenderer.effectivePalette(for: config)
                                } else {
                                    config.customPalette = nil
                                    config.paletteName =
                                        name == TimelineRenderer.palettes[0].name
                                        ? nil : name
                                }
                            })
                    ) {
                        ForEach(TimelineRenderer.palettes, id: \.name) { palette in
                            Text(palette.name.capitalized)
                                .tag(palette.name)
                        }
                        Divider()
                        Text("Custom").tag("custom")
                    }
                    .pickerStyle(.menu)

                    if config.customPalette != nil {
                        CustomPaletteEditor(
                            colors: Binding(
                                get: { config.customPalette ?? [] },
                                set: { config.customPalette = $0 }))
                    }
                }
                .groupedRow(index: 3, count: 4)
            }

            Section {
                // Binding-based ForEach (idiomatic and delete-safe); the
                // row's scroll identity is its element id, so no explicit
                // .id() — that was what broke delete diffing before
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
                        Button {
                            duplicateEvent(event.id)
                        } label: {
                            Label("Duplicate Event", systemImage: "doc.on.doc")
                        }

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
                    if !config.events.isEmpty {
                        Button(action: toggleCollapseAll) {
                            Label(
                                allCollapsed ? "Expand All" : "Collapse All",
                                systemImage: allCollapsed
                                    ? "chevron.down" : "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                        .help(allCollapsed ? "Expand all events" : "Collapse all events")
                    }
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
                        deleteHoliday(holiday.id)
                    }
                    .groupedRow(
                        index: config.customHolidays.firstIndex { $0.id == holiday.id }
                            ?? 0,
                        count: config.customHolidays.count)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteHoliday(holiday.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button {
                            duplicateHoliday(holiday.id)
                        } label: {
                            Label("Duplicate Holiday", systemImage: "doc.on.doc")
                        }

                        Button(role: .destructive) {
                            deleteHoliday(holiday.id)
                        } label: {
                            Label("Delete Holiday", systemImage: "trash")
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
                Text("US federal holidays and weekends are shaded automatically, if the option is selected.")
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
            .onChange(of: revealEventID) {
                guard let id = revealEventID else { return }
                // Double-click toggles: open and scroll into view, or
                // close if the row is already expanded
                if expandedEvents.contains(id) {
                    expandedEvents.remove(id)
                } else {
                    expandedEvents.insert(id)
                    withAnimation {
                        scrollProxy.scrollTo(id, anchor: .center)
                    }
                }
                revealEventID = nil
            }
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

    private func duplicateEvent(_ id: UUID) {
        guard let original = config.events.first(where: { $0.id == id }) else { return }

        var copy = original
        copy.id = UUID()

        // Keep the list chronological when inserting duplicates.
        let index = config.events.firstIndex { copy.start < $0.start }
            ?? config.events.endIndex
        config.events.insert(copy, at: index)
        expandedEvents.insert(copy.id)

        // Focus the duplicated row's name field once inserted.
        DispatchQueue.main.async {
            focusedEventName = copy.id
        }
    }

    private func deleteHoliday(_ id: UUID) {
        config.customHolidays.removeAll { $0.id == id }
    }

    private func duplicateHoliday(_ id: UUID) {
        guard let original = config.customHolidays.first(where: { $0.id == id })
        else { return }
        var copy = original
        copy.id = UUID()
        let index = config.customHolidays.firstIndex { copy.start < $0.start }
            ?? config.customHolidays.endIndex
        config.customHolidays.insert(copy, at: index)
    }

    /// True when no event rows are expanded.
    private var allCollapsed: Bool {
        config.events.allSatisfy { !expandedEvents.contains($0.id) }
    }

    private func toggleCollapseAll() {
        if allCollapsed {
            expandedEvents = Set(config.events.map(\.id))
        } else {
            expandedEvents.removeAll()
        }
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

/// Row of color wells for a user-defined palette, with add/remove.
struct CustomPaletteEditor: View {
    @Binding var colors: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(colors.indices, id: \.self) { index in
                ColorPicker(
                    "Color \(index + 1)",
                    selection: Binding(
                        get: { Color(hex: colors[index]) },
                        set: { colors[index] = $0.hexString }),
                    supportsOpacity: false)
                .labelsHidden()
            }

            Spacer()

            Button {
                colors.append(colors.last ?? "#FF6B6B")
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(colors.count >= 10)
            .help("Add a color")

            Button {
                if colors.count > 2 { colors.removeLast() }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(colors.count <= 2)
            .help("Remove the last color")
        }
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

            Toggle("Done", isOn: $event.done)
                .toggleStyle(.switch)
                .controlSize(.small)

            Toggle("Important", isOn: $event.important)
                .toggleStyle(.switch)
                .controlSize(.small)

            TextField(
                "Notes", text: $event.notes,
                prompt: Text("Notes (shown in gray on the timeline)"),
                axis: .vertical)
                .lineLimit(1...3)
        } label: {
            HStack {
                colorDot
                TextField("Name", text: $event.name, prompt: Text("Event name"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .strikethrough(event.done)
                    .fontWeight(event.important ? .semibold : .regular)
                    .focused(nameFocus, equals: event.id)
                Spacer()
                if isExpanded {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete event")
                } else {
                    Text(dateSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
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

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            DayPicker(label: "Start", day: $holiday.start)

            Toggle(
                "Multi-day",
                isOn: Binding(
                    get: { holiday.end != nil },
                    set: { holiday.end = $0 ? holiday.start.shifted(days: 1) : nil }))
            .toggleStyle(.switch)
            .controlSize(.small)
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
                if isExpanded {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete holiday")
                } else {
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
