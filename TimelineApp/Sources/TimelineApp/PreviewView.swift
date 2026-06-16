import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

    // Editing an existing event anchors its popover over the event's
    // label on the canvas. (New events anchor to the + button instead,
    // handled in ContentView.)
    /// The event being edited.
    @Binding var editingEventID: UUID?
    /// True while the open editor is for a new event (its popover lives on
    /// the + button, so this view doesn't show one).
    @Binding var isNewEvent: Bool
    /// Resolves a binding to an event for the editor; nil disables editing.
    var eventBinding: ((UUID) -> Binding<TimelineEvent>?)?
    var onDeleteEvent: ((UUID) -> Void)?
    var onCloseEditor: (() -> Void)?
    /// Text dropped on the canvas, with the day under the drop point, so a
    /// new event can be parsed/created from it.
    var onDropText: ((String, Day) -> Void)?
    var referenceDay: Day = .today()

    /// Owned by ContentView so it can be persisted per window.
    @Binding var zoom: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("showTodayMarker") private var showTodayMarker = true
    @State private var gestureBaseZoom: CGFloat?
    @State private var dragTarget:
        (id: UUID, part: TimelineRenderer.EventHitPart, anchorDay: Day)?
    @State private var dragMissed = false
    @State private var dropTargeted = false

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
                    let scale = displayWidth / canvas.width
                    // Equatable so changing editingEventID/selection doesn't
                    // re-render the (expensive) bitmap — only config/zoom do.
                    TimelineCanvasImage(
                        config: config, dark: dark, renderScale: renderScale,
                        showToday: showTodayMarker, displayWidth: displayWidth,
                        aspect: canvas.width / canvas.height
                    )
                    .equatable()
                    .gesture(dragEventGesture(
                                displayWidth: displayWidth, canvas: canvas))
                            // Single-click an event opens its editor.
                            // (No double-click handler here: pairing it
                            // with single-click delays the click ~0.3s
                            // while SwiftUI disambiguates. Zoom reset lives
                            // on the % button, ⌘0, and the context menu.)
                            .onTapGesture(count: 1) { location in
                                let point = CGPoint(
                                    x: location.x / scale,
                                    y: canvas.height - location.y / scale)
                                let renderer = TimelineRenderer(
                                    config: config, layout: .continuous)
                                if let hit = renderer.eventHit(at: point) {
                                    isNewEvent = false
                                    editingEventID = hit.id
                                } else if editingEventID != nil {
                                    // Our popover (applicationDefined) won't
                                    // auto-close, so an empty-canvas tap does.
                                    onCloseEditor?()
                                }
                            }
                            .onContinuousHover { phase in
                                updateCursor(
                                    phase, displayWidth: displayWidth,
                                    canvas: canvas)
                            }
                            // Drop text (e.g. "Lunch with Sam Friday") onto the
                            // canvas to create an event at the day under it.
                            // Accept broadly (.data covers text/RTF/private
                            // app types like Fantastical events) and extract
                            // text with several strategies in the handler.
                            .onDrop(
                                of: [.data, .url],
                                isTargeted: $dropTargeted
                            ) { providers, location in
                                handleTextDrop(
                                    providers, at: location,
                                    displayWidth: displayWidth, canvas: canvas)
                            }
                            .overlay {
                                if dropTargeted {
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(
                                            Color.accentColor, lineWidth: 2)
                                }
                            }
                            // Editor popover anchored at the event's marker.
                            // A hand-rolled NSPopover (not SwiftUI's .popover)
                            // so it survives app switches and re-anchors in
                            // place when switching events instead of flashing.
                            .overlay {
                                EditorPopover(
                                    isPresented: editingEventID != nil && !isNewEvent,
                                    anchorRect: anchorRect(scale: scale, canvas: canvas),
                                    editKey: editingEventID,
                                    onClose: { onCloseEditor?() }
                                ) {
                                    editorContent
                                }
                            }
                            .padding(24)
                }
                // Top-align so the canvas starts at the top of the
                // window instead of floating centered; leftover vertical
                // space (from preserving the canvas aspect ratio) collects
                // at the bottom rather than splitting top and bottom
                .frame(
                    minWidth: geo.size.width, minHeight: geo.size.height,
                    alignment: .top)
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
        // Bottom-left so the bottom-right add button has room
        .overlay(alignment: .bottomLeading) { zoomControls }
    }

    /// The editor popover's content for the event being edited (existing
    /// events only — new events use the + button's popover).
    @ViewBuilder
    private var editorContent: some View {
        if let id = editingEventID, let binding = eventBinding?(id) {
            EventEditor(
                event: binding,
                onDelete: { onDeleteEvent?(id) },
                onClose: { onCloseEditor?() },
                // Escape on an existing event just closes (keeps edits)
                onCancel: { onCloseEditor?() },
                referenceDay: referenceDay,
                showQuickAdd: false,
                resolvedColorHex: TimelineRenderer.resolvedColorHex(
                    for: config)[id] ?? TimelineRenderer.eventColors[0])
        }
    }

    /// Rect spanning the edited event from its marker up to its label top,
    /// centered on the marker, in bottom-left (canvas) coordinates — the
    /// same origin as the popover's host view, so no fragile height-flip is
    /// needed. The popover attaches above this rect or below it, clearing the
    /// event's text either way (it flips downward on the top row).
    private func anchorRect(scale: CGFloat, canvas: CGSize) -> CGRect {
        guard let id = editingEventID else { return .zero }
        let renderer = TimelineRenderer(config: config, layout: .continuous)
        for row in renderer.rows {
            let placements = renderer.layoutEvents(
                forRow: row.startDay, numDays: row.numDays)
            guard let p = placements.first(where: { $0.event.id == id })
            else { continue }
            // labelY is the text baseline; the glyphs' visual top is only
            // about the cap height above it (~0.8 * font size), not the full
            // line box. Plus a few points of breathing room above the label.
            let labelTopCanvas =
                row.baselineY + (p.labelY ?? 0) + renderer.labelFontSize * 0.8 + 6
            let yBottom = row.baselineY * scale
            let yTop = labelTopCanvas * scale
            return CGRect(
                x: p.markerX * scale, y: yBottom,
                width: 1, height: max(yTop - yBottom, 1))
        }
        return .zero
    }

    /// Load dropped text and hand it to `onDropText` with the day under the
    /// drop point. Returns true if any provider supplied text.
    private func handleTextDrop(
        _ providers: [NSItemProvider], at location: CGPoint,
        displayWidth: CGFloat, canvas: CGSize
    ) -> Bool {
        guard let onDropText else { return false }
        let scale = displayWidth / canvas.width
        let point = CGPoint(
            x: location.x / scale, y: canvas.height - location.y / scale)
        let day = TimelineRenderer(config: config, layout: .continuous).day(at: point)

        guard let provider = providers.first else { return false }
        loadText(from: provider) { text in
            guard let text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            DispatchQueue.main.async { onDropText(text, day) }
        }
        return true
    }

    /// Pull text out of a dropped item via several strategies: plain string,
    /// then attributed (RTF), then a URL's string.
    private func loadText(
        from provider: NSItemProvider, completion: @escaping (String?) -> Void
    ) {
        if provider.hasItemConformingToTypeIdentifier("com.apple.ical.ics") {
            // Calendar apps (Fantastical, Calendar) drop an .ics event with
            // no plain-text flavor; hand the raw iCalendar to the parser.
            provider.loadDataRepresentation(
                forTypeIdentifier: "com.apple.ical.ics"
            ) { data, _ in
                completion(data.flatMap { String(data: $0, encoding: .utf8) })
            }
        } else if provider.canLoadObject(ofClass: NSString.self) {
            _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
                completion(obj as? String)
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.rtf.identifier) {
            // RTF (e.g. some calendar apps): decode to plain text.
            provider.loadDataRepresentation(
                forTypeIdentifier: UTType.rtf.identifier
            ) { data, _ in
                let string = data.flatMap {
                    try? NSAttributedString(
                        data: $0,
                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                        documentAttributes: nil)
                }?.string
                completion(string)
            }
        } else if provider.canLoadObject(ofClass: NSURL.self) {
            _ = provider.loadObject(ofClass: NSURL.self) { obj, _ in
                completion((obj as? URL)?.absoluteString)
            }
        } else {
            completion(nil)
        }
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

/// Hosts the event editor in an `NSPopover` we drive ourselves. SwiftUI's
/// `.popover` is transient — it closes when the app deactivates, and it
/// tears down/rebuilds (a visible flash) whenever the anchor changes. This
/// uses `behavior = .applicationDefined` so it stays open across app
/// switches, and moves `positioningRect` in place when the edited event
/// changes so switching events doesn't flash.
private struct EditorPopover<Content: View>: NSViewRepresentable {
    let isPresented: Bool
    /// Anchor in the overlaid view's coordinate space (top-left origin).
    let anchorRect: CGRect
    /// Changes when the edited event changes (drives in-place reposition).
    let editKey: UUID?
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        context.coordinator.host = view
        return view
    }

    /// Transparent to clicks so the canvas's tap gesture underneath still
    /// fires; it only serves as the popover's positioning view.
    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onClose = onClose
        context.coordinator.update(
            isPresented: isPresented, anchorRect: anchorRect,
            editKey: editKey, content: content())
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSPopoverDelegate {
        weak var host: NSView?
        var popover: NSPopover?
        var hosting: NSHostingController<Content>?
        var currentKey: UUID?
        var onClose: (() -> Void)?

        func update(
            isPresented: Bool, anchorRect: CGRect,
            editKey: UUID?, content: Content
        ) {
            guard let host else { return }
            guard isPresented else {
                if popover?.isShown == true { popover?.performClose(nil) }
                return
            }

            if let hc = hosting {
                hc.rootView = content
            } else {
                let hc = NSHostingController(rootView: content)
                // Drive the popover's size from the SwiftUI content's ideal
                // size. Without this NSPopover keeps its default 320x320, so
                // shorter editors leave empty space below the content and the
                // arrow detaches from the event by that slack.
                hc.sizingOptions = [.preferredContentSize]
                hosting = hc
            }

            let pop: NSPopover
            if let existing = popover {
                pop = existing
            } else {
                pop = NSPopover()
                pop.behavior = .applicationDefined
                pop.delegate = self
                pop.contentViewController = hosting
                popover = pop
            }

            // anchorRect is already in the host's bottom-left coordinate
            // space, so attach to the top (maxY) edge directly — the popover
            // sits above the event (AppKit flips it below when there's no
            // room, e.g. the top row).
            if !pop.isShown {
                pop.show(relativeTo: anchorRect, of: host, preferredEdge: .maxY)
                currentKey = editKey
            } else if editKey != currentKey {
                pop.positioningRect = anchorRect
                currentKey = editKey
            }
        }

        // No onClose here: with .applicationDefined the popover only closes
        // because we drove isPresented false (Done/Escape/empty-click already
        // cleared the editing state). Calling onClose again would clobber a
        // brand-new event opened in the same gesture (clicking + while the
        // editor is open).
    }
}

/// The rendered timeline bitmap, isolated as an Equatable view so it only
/// re-renders when the document, zoom, or appearance changes — not when
/// the selection/editor state changes.
private struct TimelineCanvasImage: View, Equatable {
    let config: TimelineConfig
    let dark: Bool
    let renderScale: CGFloat
    let showToday: Bool
    let displayWidth: CGFloat
    let aspect: CGFloat

    static func == (lhs: TimelineCanvasImage, rhs: TimelineCanvasImage) -> Bool {
        lhs.config == rhs.config && lhs.dark == rhs.dark
            && lhs.renderScale == rhs.renderScale && lhs.showToday == rhs.showToday
            && lhs.displayWidth == rhs.displayWidth
    }

    var body: some View {
        let bg = TimelineRenderer.cg(dark ? "#1B1B20" : "#FAFAFC")
        if let image = Exporter.continuousImage(
            for: config, theme: dark ? .dark : .light,
            background: bg, scale: renderScale, showToday: showToday)
        {
            Image(decorative: image, scale: renderScale)
                .resizable()
                .aspectRatio(aspect, contentMode: .fit)
                .frame(width: displayWidth)
        }
    }
}
