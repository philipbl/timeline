import SwiftUI

/// Shared form controls used by the settings and event/holiday editors.

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

/// One custom-holiday row: name with a disclosure for start / multi-day / end.
struct HolidayRow: View {
    @Binding var holiday: CustomHoliday
    let onDelete: () -> Void

    @State private var isExpanded: Bool

    init(holiday: Binding<CustomHoliday>, onDelete: @escaping () -> Void) {
        self._holiday = holiday
        self.onDelete = onDelete
        // A freshly added (unnamed) holiday opens expanded so its date is
        // editable right away; named ones start collapsed.
        self._isExpanded = State(initialValue: holiday.wrappedValue.name.isEmpty)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

/// A pure-SwiftUI switch that mirrors the macOS toggle. Used in the event
/// editor because the AppKit-backed Toggle(.switch) renders in its inactive
/// (gray) state on first appearance inside our .applicationDefined popover.
struct EditorSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 8)
            Capsule()
                .fill(configuration.isOn
                    ? Color.accentColor
                    : Color(nsColor: .tertiaryLabelColor))
                .frame(width: 26, height: 15)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
                        .padding(1)
                }
                .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
        }
        .contentShape(Rectangle())
    }
}
