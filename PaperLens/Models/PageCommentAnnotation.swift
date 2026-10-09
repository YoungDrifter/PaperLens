import AppKit
import CoreText
import PDFKit

/// Shared proportions for native cards and their saved PDF appearance.
enum CommentCardMetrics {
    static let scale: CGFloat = 2.0 / 3.0
    static let defaultSize = CGSize(width: 160 * scale, height: 90 * scale)
    static let minimumSize = CGSize(width: 140 * scale, height: 80 * scale)
    static let bodyFontSize: CGFloat = 12
}

/// PDFKit's default FreeText appearance can omit fallback-font glyphs. Drawing
/// through CoreText records all glyphs (including CJK) in the exported appearance.
struct CommentGeometry: Equatable {
    var card: CGRect
    var marker: CGRect
    var attachment: CGPoint? = nil
    static let markerSize: CGFloat = 8

    static func initial(card: CGRect, page: CGRect) -> Self {
        let size = min(markerSize, min(page.width, page.height))
        let marker = CGRect(x: min(max(card.minX, page.minX), page.maxX - size),
                            y: min(max(card.maxY - size, page.minY), page.maxY - size), width: size, height: size)
        var placed = card
        if marker.maxX + 24 + card.width <= page.maxX { placed.origin.x = marker.maxX + 24 }
        else if marker.minX - 24 - card.width >= page.minX { placed.origin.x = marker.minX - 24 - card.width }
        else if marker.minY - 24 - card.height >= page.minY { placed.origin.y = marker.minY - 24 - card.height }
        else if marker.maxY + 24 + card.height <= page.maxY { placed.origin.y = marker.maxY + 24 }
        return Self(card: placed, marker: marker)
    }
}

/// Identical page-space geometry drives the on-screen and exported connectors.
struct CommentConnection {
    let path: CGPath?
    let endpoint: CGPoint

    static func borderPoint(_ point: CGPoint, card: CGRect, radius: CGFloat = 8) -> (point: CGPoint, normal: CGPoint) {
        let r = min(radius, min(card.width, card.height) / 2)
        let inner = card.insetBy(dx: r, dy: r)
        var q = CGPoint(x: min(max(point.x, inner.minX), inner.maxX), y: min(max(point.y, inner.minY), inner.maxY))
        if inner.contains(point) {
            let edges = [(point.x - inner.minX, CGPoint(x: inner.minX, y: point.y)),
                         (inner.maxX - point.x, CGPoint(x: inner.maxX, y: point.y)),
                         (point.y - inner.minY, CGPoint(x: point.x, y: inner.minY)),
                         (inner.maxY - point.y, CGPoint(x: point.x, y: inner.maxY))]
            q = edges.min(by: { $0.0 < $1.0 })!.1
        }
        let length = hypot(point.x - q.x, point.y - q.y)
        let normal: CGPoint
        if length > 0.001 {
            let sign: CGFloat = inner.contains(point) ? -1 : 1
            normal = CGPoint(x: sign * (point.x - q.x) / length, y: sign * (point.y - q.y) / length)
        }
        else if q.x <= inner.minX { normal = CGPoint(x: -1, y: 0) }
        else if q.x >= inner.maxX { normal = CGPoint(x: 1, y: 0) }
        else { normal = CGPoint(x: 0, y: q.y <= inner.minY ? -1 : 1) }
        return (CGPoint(x: q.x + normal.x * r, y: q.y + normal.y * r), normal)
    }

    init(marker: CGRect, card: CGRect, attachment: CGPoint? = nil, radius: CGFloat = 8) {
        let center = CGPoint(x: marker.midX, y: marker.midY)
        let desired = attachment.map { CGPoint(x: card.minX + $0.x * card.width, y: card.minY + $0.y * card.height) } ?? center
        let border = Self.borderPoint(desired, card: card, radius: radius)
        let normal = border.normal
        let end = border.point
        endpoint = end
        guard !marker.intersects(card) else { path = nil; return }
        let distance = max(0.001, hypot(end.x - center.x, end.y - center.y))
        let direction = CGPoint(x: (end.x - center.x) / distance, y: (end.y - center.y) / distance)
        let reach = marker.width / 2 / max(0.001, abs(direction.x) + abs(direction.y))
        let start = CGPoint(x: center.x + direction.x * reach, y: center.y + direction.y * reach)
        // A gentle perpendicular bend keeps even aligned endpoints curved.
        let gap = max(0, distance - marker.width / 2)
        let bend = min(90, gap * 0.35)
        let side = min(40, gap * 0.16)
        let p = CGMutablePath(); p.move(to: start)
        p.addCurve(to: end,
                   control1: CGPoint(x: start.x + direction.x * bend - direction.y * side,
                                     y: start.y + direction.y * bend + direction.x * side),
                   control2: CGPoint(x: end.x + normal.x * bend - normal.y * side,
                                     y: end.y + normal.y * bend + normal.x * side))
        // When a manually chosen edge faces away from the marker, route around
        // the card rather than drawing through its text.
        if attachment != nil, (center.x - end.x) * normal.x + (center.y - end.y) * normal.y < 0 {
            let clearance: CGFloat = 32
            let horizontal = abs(normal.x) >= abs(normal.y)
            let detour: [CGPoint]
            if horizontal {
                let y = abs(center.y - card.maxY) < abs(center.y - card.minY) ? card.maxY + clearance : card.minY - clearance
                detour = [CGPoint(x: center.x, y: y), CGPoint(x: end.x + normal.x * clearance, y: y), CGPoint(x: end.x + normal.x * clearance, y: end.y)]
            } else {
                let x = abs(center.x - card.maxX) < abs(center.x - card.minX) ? card.maxX + clearance : card.minX - clearance
                detour = [CGPoint(x: x, y: center.y), CGPoint(x: x, y: end.y + normal.y * clearance), CGPoint(x: end.x, y: end.y + normal.y * clearance)]
            }
            let d = max(0.001, hypot(detour[0].x - center.x, detour[0].y - center.y))
            let reach = marker.width / 2 * d / max(0.001, abs(detour[0].x - center.x) + abs(detour[0].y - center.y))
            let routeStart = CGPoint(x: center.x + (detour[0].x - center.x) * reach / d,
                                     y: center.y + (detour[0].y - center.y) * reach / d)
            let points = [routeStart] + detour + [end]
            let route = CGMutablePath(); route.move(to: routeStart)
            for i in 0..<(points.count - 1) {
                let before = points[max(0, i - 1)], after = points[min(points.count - 1, i + 2)]
                let a = points[i], b = points[i + 1]
                let c1 = CGPoint(x: a.x + (b.x - before.x) / 6, y: a.y + (b.y - before.y) / 6)
                let c2 = i == points.count - 2 ? CGPoint(x: end.x + normal.x * 12, y: end.y + normal.y * 12) : CGPoint(x: b.x - (after.x - a.x) / 6, y: b.y - (after.y - a.y) / 6)
                route.addCurve(to: b, control1: c1, control2: c2)
            }
            path = route
        } else { path = p }
    }
}

final class PageCommentAnnotation: PDFAnnotation {
    private static let cardKey = PDFAnnotationKey(rawValue: "PaperLensCommentCard")
    private static let attachmentKey = PDFAnnotationKey(rawValue: "PaperLensCommentAttachment")
    private static let markerKey = PDFAnnotationKey(rawValue: "PaperLensCommentMarker")
    var geometry: CommentGeometry {
        func rect(_ key: PDFAnnotationKey) -> CGRect? {
            guard let a = value(forAnnotationKey: key) as? [NSNumber], a.count == 4,
                  a.allSatisfy({ $0.doubleValue.isFinite }), a[2].doubleValue > 0, a[3].doubleValue > 0 else { return nil }
            return CGRect(x: a[0].doubleValue, y: a[1].doubleValue, width: a[2].doubleValue, height: a[3].doubleValue)
        }
        let saved = rect(Self.markerKey) ?? CGRect(x: bounds.minX, y: bounds.maxY - 8, width: 8, height: 8)
        let size = min(CommentGeometry.markerSize, min(saved.width, saved.height))
        let marker = CGRect(x: saved.midX - size / 2, y: saved.midY - size / 2, width: size, height: size)
        var attachment: CGPoint?
        if let a = value(forAnnotationKey: Self.attachmentKey) as? [NSNumber], a.count == 2,
           a.allSatisfy({ $0.doubleValue.isFinite && (0...1).contains($0.doubleValue) }) {
            attachment = CGPoint(x: a[0].doubleValue, y: a[1].doubleValue)
        }
        return CommentGeometry(card: rect(Self.cardKey) ?? bounds, marker: marker, attachment: attachment)
    }
    var hasGeometry: Bool { value(forAnnotationKey: Self.cardKey) != nil && value(forAnnotationKey: Self.markerKey) != nil }
    func setGeometry(_ geometry: CommentGeometry) {
        func store(_ rect: CGRect, _ key: PDFAnnotationKey) {
            setValue([rect.minX, rect.minY, rect.width, rect.height], forAnnotationKey: key)
        }
        store(geometry.card, Self.cardKey); store(geometry.marker, Self.markerKey)
        if let attachment = geometry.attachment {
            setValue([attachment.x, attachment.y], forAnnotationKey: Self.attachmentKey)
        } else { removeValue(forAnnotationKey: Self.attachmentKey) }
        var extent = geometry.card.union(geometry.marker)
        if let path = CommentConnection(marker: geometry.marker, card: geometry.card, attachment: geometry.attachment).path { extent = extent.union(path.boundingBoxOfPath) }
        bounds = extent
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let rgb = color.usingColorSpace(.deviceRGB) ?? .lightGray
        let fill = CommentManager.cardColor(for: rgb)
        let ink = CommentManager.connectionColor(for: rgb)
        let geometry = geometry
        let bounds = geometry.card
        if let connection = CommentConnection(marker: geometry.marker, card: bounds, attachment: geometry.attachment).path {
            context.addPath(connection); context.setStrokeColor(ink.withAlphaComponent(0.45).cgColor)
            context.setLineWidth(1.5); context.setLineCap(.round); context.strokePath()
        }
        Self.drawMarker(in: geometry.marker, color: rgb, context: context)
        let scale = CommentCardMetrics.scale
        let card = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 8 * scale, cornerHeight: 8 * scale, transform: nil)
        context.addPath(card)
        context.setFillColor(fill.cgColor)
        context.fillPath()
        context.addPath(card)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.20).cgColor)
        context.setLineWidth(0.7)
        context.strokePath()
        let foreground = CommentManager.textColor(on: rgb)
        context.textMatrix = .identity
        let heading = NSAttributedString(string: "Comment", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: foreground.withAlphaComponent(0.55)
        ])
        context.textPosition = CGPoint(x: bounds.minX + 12 * scale, y: bounds.maxY - 18 * scale)
        CTLineDraw(CTLineCreateWithAttributedString(heading), context)
        context.setStrokeColor(foreground.withAlphaComponent(0.1).cgColor)
        context.move(to: CGPoint(x: bounds.minX + 12 * scale, y: bounds.maxY - 27 * scale))
        context.addLine(to: CGPoint(x: bounds.maxX - 12 * scale, y: bounds.maxY - 27 * scale))
        context.strokePath()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let body = NSAttributedString(string: contents ?? "", attributes: [
            .font: font ?? NSFont.systemFont(ofSize: CommentCardMetrics.bodyFontSize),
            .foregroundColor: foreground,
            .paragraphStyle: paragraph
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(body)
        let bodyRect = CGRect(x: bounds.minX + 12 * scale, y: bounds.minY + 10 * scale,
                              width: max(1, bounds.width - 24 * scale), height: max(1, bounds.height - 44 * scale))
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: body.length),
                                             CGPath(rect: bodyRect, transform: nil), nil)
        CTFrameDraw(frame, context)
    }

    static func drawMarker(in rect: CGRect, color: NSColor, context: CGContext) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor((color.usingColorSpace(.deviceRGB) ?? color).withAlphaComponent(1).cgColor)
        context.setStrokeColor(NSColor(white: 0.55, alpha: 1).cgColor)
        context.setLineWidth(1)
        context.setLineJoin(.round)
        context.drawPath(using: .fillStroke)
    }

    func recordColor() {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return }
        setValue([rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent],
                 forAnnotationKey: PDFAnnotationKey(rawValue: "PaperLensCommentColor"))
    }

    static func restoring(_ original: PDFAnnotation) -> PageCommentAnnotation {
        let result = PageCommentAnnotation(bounds: original.bounds, forType: .freeText, withProperties: nil)
        if let source = original as? PageCommentAnnotation, source.hasGeometry { result.setGeometry(source.geometry) }
        else if let a = original.value(forAnnotationKey: cardKey) as? [NSNumber], a.count == 4,
                let b = original.value(forAnnotationKey: markerKey) as? [NSNumber], b.count == 4 {
            result.setValue(original.value(forAnnotationKey: attachmentKey), forAnnotationKey: attachmentKey)
            result.setValue(a, forAnnotationKey: cardKey); result.setValue(b, forAnnotationKey: markerKey)
            result.setGeometry(result.geometry)
        }
        result.contents = original.contents
        result.userName = original.userName
        result.font = original.font ?? NSFont.systemFont(ofSize: CommentCardMetrics.bodyFontSize)
        result.fontColor = original.fontColor ?? .black
        if let rgba = original.value(forAnnotationKey: PDFAnnotationKey(rawValue: "PaperLensCommentColor")) as? [NSNumber], rgba.count == 4 {
            result.color = NSColor(srgbRed: rgba[0].doubleValue, green: rgba[1].doubleValue,
                                   blue: rgba[2].doubleValue, alpha: rgba[3].doubleValue)
        } else {
            result.color = original.interiorColor ?? original.color
        }
        result.recordColor()
        result.border = original.border
        result.modificationDate = original.modificationDate
        result.setValue("pageflow-comment", forAnnotationKey: PDFAnnotationKey(rawValue: "PageFlowType"))
        result.shouldDisplay = false
        result.shouldPrint = true
        return result
    }
}
