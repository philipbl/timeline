import SwiftUI

/// Popover content for document-level settings: title, date range,
/// days-per-row, shading, and palette. Replaces the old sidebar's
/// "Timeline" section in the canvas-first redesign.
struct TimelineSettings: View {
    @Binding var config: TimelineConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline")
                .font(.headline)

            TextField("Title", text: $config.title, prompt: Text("Untitled"))
                .textFieldStyle(.roundedBorder)

            OptionalDayRow(
                label: "Starts", day: $config.timelineStart, defaultDay: .today())
            OptionalDayRow(
                label: "Ends", day: $config.timelineEnd,
                defaultDay: Day.today().shifted(days: 14))
            if config.timelineEnd == nil {
                Text("Without an end date, the timeline runs to the last event.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("Days per row")
                Spacer()
                Stepper(
                    value: Binding(
                        get: { config.daysPerRow ?? 22 },
                        set: { config.daysPerRow = $0 }),
                    in: 5...60
                ) {
                    Text("\(config.daysPerRow ?? 22)").monospacedDigit()
                }
            }

            Toggle("Shade weekends", isOn: $config.shadeWeekends)
            Toggle("Shade holidays", isOn: $config.shadeHolidays)

            Picker(
                "Colors",
                selection: Binding(
                    get: {
                        config.customPalette != nil
                            ? "custom" : (config.paletteName
                                ?? TimelineRenderer.palettes[0].name)
                    },
                    set: { name in
                        if name == "custom" {
                            config.customPalette =
                                TimelineRenderer.effectivePalette(for: config)
                        } else {
                            config.customPalette = nil
                            config.paletteName =
                                name == TimelineRenderer.palettes[0].name ? nil : name
                        }
                    })
            ) {
                ForEach(TimelineRenderer.palettes, id: \.name) { palette in
                    Text(palette.name.capitalized).tag(palette.name)
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
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(14)
        .frame(width: 300)
    }
}
