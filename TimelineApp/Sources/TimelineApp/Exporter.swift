import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum Exporter {
    enum ExportError: LocalizedError {
        case contextCreationFailed

        var errorDescription: String? { "Could not create a graphics context." }
    }

    /// Paged, paper-style PDF — same as the Python CLI output, title
    /// repeated on every page.
    static func pdfData(for config: TimelineConfig) throws -> Data {
        let renderer = TimelineRenderer(config: config, layout: .paged, theme: .light)
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: TimelineRenderer.pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { throw ExportError.contextCreationFailed }

        for page in 0..<renderer.pageCount {
            ctx.beginPDFPage(nil)
            renderer.drawPage(page, in: ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    /// Render the continuous (single-canvas, title-once) layout to a
    /// CGImage. Scale 2 = 144 dpi. Transparent background unless a
    /// background color is given.
    static func continuousImage(
        for config: TimelineConfig, theme: TimelineRenderer.Theme,
        background: CGColor? = nil, scale: CGFloat = 2
    ) -> CGImage? {
        let renderer = TimelineRenderer(config: config, layout: .continuous, theme: theme)
        let size = renderer.canvasSize
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard width > 0, height > 0,
              let ctx = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        if let background {
            ctx.setFillColor(background)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        ctx.setShouldAntialias(true)
        ctx.setShouldSmoothFonts(true)
        renderer.drawPage(0, in: ctx)
        return ctx.makeImage()
    }

    /// PNG export: one continuous image, white background, title once.
    static func writePNG(for config: TimelineConfig, to url: URL) throws {
        guard let image = continuousImage(
            for: config, theme: .light, background: CGColor.white)
        else { throw ExportError.contextCreationFailed }
        let rep = NSBitmapImageRep(cgImage: image)
        let renderer = TimelineRenderer(config: config, layout: .continuous)
        rep.size = renderer.canvasSize  // points, so the PNG reports 144 dpi
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.contextCreationFailed
        }
        try data.write(to: url)
    }
}
