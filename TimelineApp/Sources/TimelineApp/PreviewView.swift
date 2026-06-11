import SwiftUI

/// Live-rendered timeline canvas. Renders a bitmap whose resolution
/// tracks the current zoom (so it stays sharp without PDFKit's document
/// reload flash), on a single uniform background color. Pinch to zoom,
/// two-finger pan, double-click to reset.
struct PreviewView: View {
    let config: TimelineConfig

    @Environment(\.colorScheme) private var colorScheme
    @State private var zoom: CGFloat = 1
    @State private var gestureBaseZoom: CGFloat?

    private static let zoomRange: ClosedRange<CGFloat> = 0.25...3
    private static let maxRenderScale: CGFloat = 6  // ~432 dpi

    var body: some View {
        let dark = colorScheme == .dark
        let theme: TimelineRenderer.Theme = dark ? .dark : .light
        let canvasHex = dark ? "#1B1B20" : "#FAFAFC"
        let canvas = TimelineRenderer(config: config, layout: .continuous).canvasSize

        GeometryReader { geo in
            let fitWidth = max(geo.size.width - 48, 200)
            let displayWidth = fitWidth * zoom
            // Render at the resolution the current zoom needs (x2 for
            // Retina), bucketed to whole numbers to limit re-renders
            let renderScale = min(
                max(ceil(displayWidth * 2 / canvas.width), 1), Self.maxRenderScale)

            ScrollView([.vertical, .horizontal]) {
                Group {
                    if let image = Exporter.continuousImage(
                        for: config, theme: theme,
                        background: TimelineRenderer.cg(canvasHex),
                        scale: renderScale)
                    {
                        Image(decorative: image, scale: renderScale)
                            .resizable()
                            .aspectRatio(canvas.width / canvas.height, contentMode: .fit)
                            .frame(width: displayWidth)
                            .padding(24)
                    }
                }
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
        }
        .background(Color(hex: dark ? "#1B1B20" : "#FAFAFC"))
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
