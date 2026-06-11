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
    static func pdfData(
        for config: TimelineConfig, includeGenerated: Bool = false
    ) throws -> Data {
        let renderer = TimelineRenderer(
            config: config, layout: .paged, theme: .light,
            includeGenerated: includeGenerated)
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

    /// Single-page vector PDF of the continuous (title-once) layout.
    /// Used by the live preview so zooming stays sharp.
    static func continuousPDFData(
        for config: TimelineConfig, theme: TimelineRenderer.Theme,
        background: CGColor? = nil, includeGenerated: Bool = false
    ) throws -> Data {
        let renderer = TimelineRenderer(
            config: config, layout: .continuous, theme: theme,
            includeGenerated: includeGenerated)
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: renderer.canvasSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { throw ExportError.contextCreationFailed }

        ctx.beginPDFPage(nil)
        if let background {
            ctx.setFillColor(background)
            ctx.fill(mediaBox)
        }
        renderer.drawPage(0, in: ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    /// PNG export: one continuous image, white background, title once.
    /// Scale 1 = 72 dpi, 2 = 144 dpi, 4 = 288 dpi.
    static func writePNG(
        for config: TimelineConfig, to url: URL, scale: CGFloat = 2,
        includeGenerated: Bool = false
    ) throws {
        let renderer = TimelineRenderer(
            config: config, layout: .continuous, theme: .light,
            includeGenerated: includeGenerated)
        let size = renderer.canvasSize
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard width > 0, height > 0,
              let ctx = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ExportError.contextCreationFailed }

        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(.white)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setShouldAntialias(true)
        ctx.setShouldSmoothFonts(true)
        renderer.drawPage(0, in: ctx)

        guard let image = ctx.makeImage() else {
            throw ExportError.contextCreationFailed
        }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = size  // points, so the PNG reports its dpi correctly
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.contextCreationFailed
        }
        try data.write(to: url)
    }
}
