import SwiftUI

/// App-level preferences (⌘,). Document-level settings (title, dates,
/// palette, holidays…) live in the per-document toolbar popover; this is for
/// app behavior and the defaults applied to new documents.
struct SettingsView: View {
    @AppStorage("showTodayMarker") private var showTodayMarker = true
    @AppStorage("useAppleIntelligence") private var useAppleIntelligence = false
    @AppStorage("defaultPalette") private var defaultPalette =
        TimelineRenderer.palettes[0].name

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show today marker", isOn: $showTodayMarker)

                VStack(alignment: .leading, spacing: 3) {
                    Toggle(
                        "Use Apple Intelligence for event text",
                        isOn: $useAppleIntelligence)
                    Text(
                        "Parses natural-language event entry on-device when "
                        + "available. When off, the built-in parser is used "
                        + "(deterministic — same text always gives the same event).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("New Documents") {
                Picker("Default color palette", selection: $defaultPalette) {
                    ForEach(TimelineRenderer.palettes, id: \.name) { palette in
                        Text(palette.name.capitalized).tag(palette.name)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 260)
    }
}
