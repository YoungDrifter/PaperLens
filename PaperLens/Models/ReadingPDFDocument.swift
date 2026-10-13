import AppKit
import PDFKit

/// Keep ONYX's vector stamp strokes in the page's Retina/zoom-aware tiles.
/// PDFView's separate annotation appearance cache renders these small stamps
/// at page resolution and enlarges the bitmap, losing thin handwriting strokes.
final class ReadingPDFDocument: PDFDocument {
    override var pageClass: AnyClass { ReadingPDFPage.self }

    override func dataRepresentation() -> Data? {
        // PDFKit reads custom annotation keys lazily. Materialize every ONYX
        // stroke tag before serialization, including pages never displayed, so
        // removing the first stroke cannot lose identification after reopening.
        for index in 0..<pageCount {
            for annotation in page(at: index)?.annotations ?? [] where annotation.type == "Stamp" {
                _ = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "onyxtag"))
            }
        }
        return super.dataRepresentation()
    }
}

final class ReadingPDFPage: PDFPage {
    private var drawsVectorStrokes: Bool {
        annotations.contains { annotation in
            guard annotation.type == "Stamp" else { return false }
            let name = (annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "Name")) as? String)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            // PDFKit can omit an unknown Stamp /Name on serialization. ONYX's
            // stroke metadata also identifies the appearance after reopening.
            let tag = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "onyxtag")) as? String
            if name == "#ONYX-STROKE" { return true }
            let metadata = tag?.data(using: .utf8).flatMap {
                (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
            }
            return metadata?["type"] as? String == "BrushStrokeV2"
        }
    }

    // This is a rendering preference, not an annotation flag. Keep the original
    // annotation objects and their appearance streams for the existing save path.
    override var displaysAnnotations: Bool {
        get { super.displaysAnnotations && !drawsVectorStrokes }
        set { super.displaysAnnotations = newValue }
    }

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)
        guard super.displaysAnnotations, drawsVectorStrokes else { return }
        context.saveGState()
        defer { context.restoreGState() }
        // PDFAnnotation.draw applies the page box/rotation transform itself.
        // Use it only for tile culling; applying it to the context a second
        // time would offset cropped pages and rotate annotations twice.
        let pageTransform = transform(for: box)
        let visibleBounds = context.boundingBoxOfClipPath
        for annotation in annotations where annotation.shouldDisplay && annotation.bounds.applying(pageTransform).intersects(visibleBounds) {
            context.saveGState()
            annotation.draw(with: box, in: context)
            context.restoreGState()
        }
    }

    override func thumbnail(of size: NSSize, for box: PDFDisplayBox) -> NSImage {
        guard drawsVectorStrokes, super.displaysAnnotations else {
            return super.thumbnail(of: size, for: box)
        }
        // PDFKit's thumbnail implementation skips annotations when the native
        // annotation layer is disabled. Use the same vector page renderer here.
        let pageSize = bounds(for: box).size
        guard pageSize.width > 0, pageSize.height > 0, size.width > 0, size.height > 0 else {
            return super.thumbnail(of: size, for: box)
        }
        let scale = min(size.width / pageSize.width, size.height / pageSize.height)
        let imageSize = NSSize(width: pageSize.width * scale, height: pageSize.height * scale)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(ceil(imageSize.width * 2))),
            pixelsHigh: max(1, Int(ceil(imageSize.height * 2))),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return super.thumbnail(of: size, for: box)
        }
        let context = graphics.cgContext
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        context.scaleBy(x: CGFloat(bitmap.pixelsWide) / pageSize.width,
                        y: CGFloat(bitmap.pixelsHigh) / pageSize.height)
        draw(with: box, to: context)
        bitmap.size = imageSize
        let image = NSImage(size: imageSize)
        image.addRepresentation(bitmap)
        return image
    }
}
