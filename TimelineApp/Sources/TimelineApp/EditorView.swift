import SwiftUI

struct EditorView: View {
    @Binding var config: TimelineConfig

    var body: some View {
        Form {
            Section("Timeline") {
                TextField("Title", text: $config.title, prompt: Text("Untitled"))

                OptionalDayRow(label: "Starts", day: $config.timelineStart, defaultDay: .today())
                OptionalDayRow(
                    label: "Ends", day: $config.timelineEnd,
                    defaultDay: Day.today().shifted(days: 14))
                if config.timelineEnd == nil {
                    Text("Without an end date, the timeline runs to the last event.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach($config.events) { $event in
                    EventRow(event: $event) {
                        config.events.removeAll { $0.id == event.id }
                    }
                }
            } header: {
                HStack {
                    Text("Events")
                    Spacer()
                    Button {
                        withAnimation {
                            config.events.append(newEvent())
                        }
                    } label: {
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
                }
            } header: {
                HStack {
                    Text("Custom Holidays")
                    Spacer()
                    Button {
                        withAnimation {
                            config.customHolidays.append(CustomHoliday(start: .today()))
                        }
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
        .formStyle(.grouped)
    }

    private func newEvent() -> TimelineEvent {
        let start = config.timelineStart ?? .today()
        let lastEvent = config.events.map(\.effectiveEnd).max()
        return TimelineEvent(name: "New Event", start: lastEvent?.shifted(days: 1) ?? start)
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
    let onDelete: () -> Void

    var body: some View {
        DisclosureGroup {
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

            Toggle(
                "Custom color",
                isOn: Binding(
                    get: { event.colorHex != nil },
                    set: { event.colorHex = $0 ? "#FF6B6B" : nil }))
            if event.colorHex != nil {
                ColorPicker(
                    "Color",
                    selection: Binding(
                        get: { Color(hex: event.colorHex ?? "#FF6B6B") },
                        set: { event.colorHex = $0.hexString }),
                    supportsOpacity: false)
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete Event", systemImage: "trash")
            }
        } label: {
            HStack {
                Circle()
                    .fill(Color(hex: event.colorHex ?? "#9A9AA2"))
                    .frame(width: 9, height: 9)
                    .opacity(event.colorHex == nil ? 0.4 : 1)
                TextField("Name", text: $event.name, prompt: Text("Event name"))
                    .textFieldStyle(.plain)
                    .strikethrough(event.done)
                Spacer()
                Text(dateSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
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

            Toggle(
                "Multi-day",
                isOn: Binding(
                    get: { holiday.end != nil },
                    set: { holiday.end = $0 ? holiday.start.shifted(days: 1) : nil }))
            if holiday.end != nil {
                DayPicker(
                    label: "End",
                    day: Binding(
                        get: { holiday.end ?? holiday.start },
                        set: { holiday.end = $0 }))
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete Holiday", systemImage: "trash")
            }
        } label: {
            HStack {
                TextField("Name", text: $holiday.name, prompt: Text("Holiday name (optional)"))
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
