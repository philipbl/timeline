import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum Exporter {
    enum ExportError: LocalizedError {
        case contextCreationFailed

        var errorDescription: String? { "Could not create a graphics context." }
    }

    static func pdfData(for config: TimelineConfig) throws -> Data {
        let renderer = TimelineRenderer(config: config)
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

    /// Render one page to a CGImage. Scale 2 = 144 dpi.
    static func pageImage(
        for config: TimelineConfig, page: Int, scale: CGFloat = 2
    ) -> CGImage? {
        let renderer = TimelineRenderer(config: config)
        let size = TimelineRenderer.pageSize
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Bitmap contexts share the bottom-left origin, so only scale
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(.white)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setShouldAntialias(true)
        ctx.setShouldSmoothFonts(true)
        renderer.drawPage(page, in: ctx)
        return ctx.makeImage()
    }

    static func pngData(for config: TimelineConfig, page: Int, scale: CGFloat = 2) -> Data? {
        guard let image = pageImage(for: config, page: page, scale: scale) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = TimelineRenderer.pageSize  // points, so the PNG reports 144 dpi
        return rep.representation(using: .png, properties: [:])
    }

    /// Write PNG(s) for every page. Multi-page documents get -1, -2 ... suffixes.
    static func writePNGs(for config: TimelineConfig, to url: URL) throws {
        let renderer = TimelineRenderer(config: config)
        let pageCount = renderer.pageCount

        if pageCount == 1 {
            guard let data = pngData(for: config, page: 0) else {
                throw ExportError.contextCreationFailed
            }
            try data.write(to: url)
            return
        }

        let base = url.deletingPathExtension()
        for page in 0..<pageCount {
            guard let data = pngData(for: config, page: page) else {
                throw ExportError.contextCreationFailed
            }
            let pageURL = URL(fileURLWithPath: base.path + "-\(page + 1).png")
            try data.write(to: pageURL)
        }
    }
}
