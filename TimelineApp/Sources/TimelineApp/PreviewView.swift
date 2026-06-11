import PDFKit
import SwiftUI

/// Live-rendered timeline canvas. Vector all the way down: the renderer
/// produces a single-page PDF and PDFKit displays it, so zooming stays
/// sharp at any magnification. Pinch to zoom, two-finger pan.
struct PreviewView: View {
    let config: TimelineConfig

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var proxy = PDFViewProxy()

    var body: some View {
        let dark = colorScheme == .dark
        let theme: TimelineRenderer.Theme = dark ? .dark : .light
        // Page fill and view backdrop share one color so the canvas looks
        // uniform with no visible page edges
        let canvasHex = dark ? "#1B1B20" : "#FAFAFC"
        let data =
            (try? Exporter.continuousPDFData(
                for: config, theme: theme,
                background: TimelineRenderer.cg(canvasHex))) ?? Data()

        PDFCanvasView(data: data, background: nsColor(canvasHex), proxy: proxy)
            .overlay(alignment: .bottomTrailing) { zoomControls }
    }

    private func nsColor(_ hex: String) -> NSColor {
        NSColor(cgColor: TimelineRenderer.cg(hex)) ?? .windowBackgroundColor
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button {
                proxy.view?.zoomOut(nil)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")

            Button {
                if let view = proxy.view {
                    view.scaleFactor = view.scaleFactorForSizeToFit
                }
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left.rectangle")
            }
            .help("Zoom to fit")

            Button {
                proxy.view?.zoomIn(nil)
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
}

final class PDFViewProxy: ObservableObject {
    weak var view: PDFView?
}

struct PDFCanvasView: NSViewRepresentable {
    let data: Data
    let background: NSColor
    let proxy: PDFViewProxy

    final class Coordinator {
        var lastData: Data?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = false
        view.pageShadowsEnabled = false
        view.autoScales = true
        view.minScaleFactor = 0.1
        view.maxScaleFactor = 12
        view.backgroundColor = background
        proxy.view = view
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        proxy.view = view
        view.backgroundColor = background
        guard context.coordinator.lastData != data else { return }
        let isFirstDocument = context.coordinator.lastData == nil
        context.coordinator.lastData = data

        // Preserve zoom and scroll position across live re-renders
        let wasAutoScaling = view.autoScales
        let oldScale = view.scaleFactor
        let destination = view.currentDestination

        view.document = PDFDocument(data: data)

        if isFirstDocument || wasAutoScaling {
            // Let PDFKit fit the page once the view has its real size
            view.autoScales = true
        } else {
            view.scaleFactor = oldScale
            if let destination, let page = view.document?.page(at: 0) {
                let point = destination.point
                if point.x.isFinite && point.y.isFinite {
                    view.go(to: PDFDestination(page: page, at: point))
                }
            }
        }
    }
}
