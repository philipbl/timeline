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

            Section("Image Import") {
                GemmaModelRow()
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
        .frame(width: 460, height: 360)
    }
}

/// Download/delete the Gemma 4 model used to find events in images.
private struct GemmaModelRow: View {
    @ObservedObject private var model = GemmaModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Gemma 4 model")
                Spacer()
                if GemmaModel.isSupported { controls }
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var controls: some View {
        switch model.state {
        case .missing, .failed:
            Button("Download (\(ByteCountFormatter.string(fromByteCount: GemmaModel.downloadSize, countStyle: .file)))") {
                Task { await model.download() }
            }
        case .downloading(let fraction):
            ProgressView(value: fraction).frame(width: 100)
            Button("Cancel") { model.cancelDownload() }
        case .verifying:
            ProgressView().controlSize(.small)
            Text("Verifying…").foregroundStyle(.secondary)
        case .ready:
            Text("Installed").foregroundStyle(.secondary)
            Button("Delete") { model.delete() }
        }
    }

    private var caption: String {
        guard GemmaModel.isSupported else {
            return "Needs a Mac with Apple silicon. Images are read with basic text "
                + "recognition instead."
        }
        if case .failed(let message) = model.state { return message }
        return "Finds events in images and PDFs dropped or pasted (⇧⌘V) on a "
            + "timeline. Runs entirely on this Mac. Without it, basic text "
            + "recognition is used."
    }
}
