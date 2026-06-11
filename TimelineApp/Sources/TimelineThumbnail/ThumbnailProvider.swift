import QuickLookThumbnailing

/// Finder thumbnail for .timeline documents: the rendered timeline,
/// scaled to fit the requested icon size on a white card.
class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        do {
            let text = try String(contentsOf: request.fileURL, encoding: .utf8)
            let config = try ConfigYAML.parse(text)
            let renderer = TimelineRenderer(
                config: config, layout: .continuous, theme: .light)
            let canvas = renderer.canvasSize

            let maximum = request.maximumSize
            let scale = min(
                maximum.width / canvas.width, maximum.height / canvas.height)
            let contextSize = CGSize(
                width: canvas.width * scale, height: canvas.height * scale)

            handler(
                QLThumbnailReply(contextSize: contextSize) { context -> Bool in
                    // Size off the real context: Quick Look hands a
                    // pixel-scaled context, not a point-scaled one
                    let pixelWidth = CGFloat(context.width)
                    let pixelHeight = CGFloat(context.height)
                    let pixelScale = min(
                        pixelWidth / canvas.width, pixelHeight / canvas.height)
                    context.setFillColor(TimelineRenderer.cg("#FFFFFF"))
                    context.fill(
                        CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
                    context.scaleBy(x: pixelScale, y: pixelScale)
                    renderer.drawPage(0, in: context)
                    return true
                }, nil)
        } catch {
            handler(nil, error)
        }
    }
}
