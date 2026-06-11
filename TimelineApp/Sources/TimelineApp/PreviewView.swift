import SwiftUI

/// Live-rendered timeline canvas. Follows the app's light/dark appearance,
/// draws the title once, and supports pinch-zoom and two-finger panning.
struct PreviewView: View {
    let config: TimelineConfig

    @Environment(\.colorScheme) private var colorScheme
    @State private var zoom: CGFloat = 1
    @State private var gestureBaseZoom: CGFloat?

    private static let zoomRange: ClosedRange<CGFloat> = 0.25...6

    var body: some View {
        let theme: TimelineRenderer.Theme = colorScheme == .dark ? .dark : .light

        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                Group {
                    if let image = Exporter.continuousImage(for: config, theme: theme) {
                        let canvas = TimelineRenderer(config: config, layout: .continuous)
                            .canvasSize
                        let fitWidth = max(geo.size.width - 48, 200)
                        let displayWidth = fitWidth * zoom
                        Image(decorative: image, scale: 2)
                            .resizable()
                            .aspectRatio(canvas.width / canvas.height, contentMode: .fit)
                            .frame(width: displayWidth)
                            .padding(24)
                    }
                }
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    if gestureBaseZoom == nil { gestureBaseZoom = zoom }
                    zoom = clampZoom((gestureBaseZoom ?? 1) * value.magnification)
                }
                .onEnded { _ in gestureBaseZoom = nil }
        )
        .onTapGesture(count: 2) {
            withAnimation(.snappy) { zoom = 1 }
        }
        .overlay(alignment: .bottomTrailing) { zoomControls }
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button {
                withAnimation(.snappy) { zoom = clampZoom(zoom / 1.25) }
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")

            Button {
                withAnimation(.snappy) { zoom = 1 }
            } label: {
                Text("\(Int(round(zoom * 100)))%")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(minWidth: 38)
            }
            .help("Reset zoom")

            Button {
                withAnimation(.snappy) { zoom = clampZoom(zoom * 1.25) }
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in")
        }
        .buttonStyle(.borderless)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }
}
