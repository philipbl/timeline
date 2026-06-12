import AppKit
import SwiftUI

/// Live-rendered timeline canvas. Renders a bitmap whose resolution
/// tracks the current zoom (so it stays sharp without PDFKit's document
/// reload flash), on a single uniform background color. Pinch to zoom,
/// two-finger pan, double-click to reset.
struct PreviewView: View {
    let config: TimelineConfig
    /// Called while an event is dragged on the canvas: (event id, part
    /// being dragged, day delta from drag start, final). nil disables
    /// dragging.
    var onEventMoved: ((UUID, TimelineRenderer.EventHitPart, Int, Bool) -> Void)?
    /// Called when an event is double-clicked.
    var onEventSelected: ((UUID) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("showTodayMarker") private var showTodayMarker = true
    @State private var zoom: CGFloat = 1
    @State private var gestureBaseZoom: CGFloat?
    @State private var dragTarget:
        (id: UUID, part: TimelineRenderer.EventHitPart, anchorDay: Day)?
    @State private var dragMissed = false

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
                        scale: renderScale, showToday: showTodayMarker)
                    {
                        Image(decorative: image, scale: renderScale)
                            .resizable()
                            .aspectRatio(canvas.width / canvas.height, contentMode: .fit)
                            .frame(width: displayWidth)
                            .gesture(dragEventGesture(
                                displayWidth: displayWidth, canvas: canvas))
                            // Double-click an event to reveal it in the
                            // editor; empty canvas resets the zoom
                            .onTapGesture(count: 2) { location in
                                let scale = displayWidth / canvas.width
                                let point = CGPoint(
                                    x: location.x / scale,
                                    y: canvas.height - location.y / scale)
                                let renderer = TimelineRenderer(
                                    config: config, layout: .continuous)
                                if let hit = renderer.eventHit(at: point) {
                                    onEventSelected?(hit.id)
                                } else {
                                    withAnimation(.snappy) { zoom = 1 }
                                }
                            }
                            .onContinuousHover { phase in
                                updateCursor(
                                    phase, displayWidth: displayWidth,
                                    canvas: canvas)
                            }
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
        .contextMenu {
            Button {
                copyImage(theme: theme, backgroundHex: canvasHex)
            } label: {
                Label("Copy Image", systemImage: "doc.on.doc")
            }

            Divider()

            Button {
                withAnimation(.snappy) { zoom = 1 }
            } label: {
                Label("Reset Zoom", systemImage: "1.magnifyingglass")
            }
            Button {
                withAnimation(.snappy) { zoom = clampZoom(zoom * 1.25) }
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            Button {
                withAnimation(.snappy) { zoom = clampZoom(zoom / 1.25) }
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
        }
        .overlay(alignment: .bottomTrailing) { zoomControls }
    }

    /// Copy the canvas to the clipboard as it currently looks (theme
    /// included), at 2x resolution.
    private func copyImage(theme: TimelineRenderer.Theme, backgroundHex: String) {
        guard let image = Exporter.continuousImage(
            for: config, theme: theme,
            background: TimelineRenderer.cg(backgroundHex), scale: 2)
        else { return }
        let size = TimelineRenderer(config: config, layout: .continuous).canvasSize
        let nsImage = NSImage(cgImage: image, size: size)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }

    /// Click-drag an event marker, bar, or label to move it day by day;
    /// drag a bar's end to change its duration.
    private func dragEventGesture(
        displayWidth: CGFloat, canvas: CGSize
    ) -> some Gesture {
        let scale = displayWidth / canvas.width

        // Image coordinates are top-left; the canvas is bottom-left
        func canvasPoint(_ location: CGPoint) -> CGPoint {
            CGPoint(
                x: location.x / scale,
                y: canvas.height - location.y / scale)
        }

        // The event follows the pointer: delta = days between the day
        // grabbed and the day under the pointer, so dragging to another
        // row works the same as dragging sideways
        func dayDelta(_ value: DragGesture.Value, anchor: Day) -> Int {
            let renderer = TimelineRenderer(config: config, layout: .continuous)
            return anchor.days(until: renderer.day(at: canvasPoint(value.location)))
        }

        return DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard onEventMoved != nil else { return }
                if dragTarget == nil && !dragMissed {
                    let start = canvasPoint(value.startLocation)
                    let renderer = TimelineRenderer(config: config, layout: .continuous)
                    if let hit = renderer.eventHit(at: start) {
                        dragTarget = (hit.id, hit.part, renderer.day(at: start))
                    } else {
                        dragMissed = true
                    }
                }
                guard let target = dragTarget else { return }
                onEventMoved?(
                    target.id, target.part,
                    dayDelta(value, anchor: target.anchorDay), false)
            }
            .onEnded { value in
                defer {
                    dragTarget = nil
                    dragMissed = false
                }
                guard let target = dragTarget else { return }
                onEventMoved?(
                    target.id, target.part,
                    dayDelta(value, anchor: target.anchorDay), true)
            }
    }

    /// Cursor feedback: resize arrows over bar ends, open hand over
    /// draggable events.
    private func updateCursor(
        _ phase: HoverPhase, displayWidth: CGFloat, canvas: CGSize
    ) {
        guard onEventMoved != nil else { return }
        switch phase {
        case .active(let location):
            let scale = displayWidth / canvas.width
            let canvasPoint = CGPoint(
                x: location.x / scale,
                y: canvas.height - location.y / scale)
            let renderer = TimelineRenderer(config: config, layout: .continuous)
            switch renderer.eventHit(at: canvasPoint)?.part {
            case .start, .end:
                NSCursor.resizeLeftRight.set()
            case .whole:
                NSCursor.openHand.set()
            case nil:
                NSCursor.arrow.set()
            }
        case .ended:
            NSCursor.arrow.set()
        }
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
        .glassChrome(in: RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }
}
