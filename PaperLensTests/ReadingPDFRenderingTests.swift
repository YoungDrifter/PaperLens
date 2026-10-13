import AppKit
import PDFKit
import Testing
@testable import PaperLens

@MainActor
struct ReadingPDFRenderingTests {
    // A vector stamp with the same ONYX appearance/metadata structure. No user
    // document is bundled with the tests or rewritten by this fixture.
    private func fixture(name: String = "#ONYX-STROKE", twoStrokes: Bool = false) -> Data {
        let appearance = "0.827451 0.168627 0.168627 RG 0.22 w 11 21 m 15 37 l 19 23 l 25 39 l S"
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 120 160] /Resources << >> /Contents 4 0 R /Annots [5 0 R] >>",
            "<< /Length 0 >>\nstream\n\nendstream",
            "<< /Type /Annot /Subtype /Stamp /Name /\(name.replacingOccurrences(of: "#", with: "#23")) /Rect [10 20 30 40] /F 4 /AP << /N 6 0 R >> /onyxtag ({\"type\":\"BrushStrokeV2\",\"id\":\"preserve-me\"}) >>",
            "<< /Type /XObject /Subtype /Form /BBox [10 20 30 40] /Resources << >> /Length \(appearance.utf8.count) >>\nstream\n\(appearance)\nendstream"
        ]
        if twoStrokes {
            objects[2] = objects[2].replacingOccurrences(of: "[5 0 R]", with: "[5 0 R 7 0 R]")
            objects.append(objects[4].replacingOccurrences(of: "[10 20 30 40]", with: "[50 20 70 40]"))
        }
        var pdf = "%PDF-1.7\n"
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let start = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(start)\n%%EOF\n"
        if name != "#ONYX-STROKE" { pdf = pdf.replacingOccurrences(of: "BrushStrokeV2", with: "BrushStrokeXX") }
        return Data(pdf.utf8)
    }

    private func pixels(_ page: PDFPage, scale: CGFloat = 3) -> Data {
        let size = page.bounds(for: .cropBox).size
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    @Test func onyxStrokesUsePageTilesAndMatchVectorReferenceAcrossZoomAndRotation() throws {
        let data = fixture()
        let document = try #require(ReadingPDFDocument(data: data))
        let reference = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))
        let original = try #require(reference.page(at: 0))
        #expect(page is ReadingPDFPage)
        #expect(!page.displaysAnnotations) // Suppresses PDFView's low-resolution overlay.
        #expect(page.annotation(at: CGPoint(x: 15, y: 30)) === page.annotations.first)
        for rotation in [0, 90, 180, 270] {
            page.rotation = rotation
            original.rotation = rotation
            page.setBounds(CGRect(x: 5, y: 7, width: 100, height: 140), for: .cropBox)
            original.setBounds(CGRect(x: 5, y: 7, width: 100, height: 140), for: .cropBox)
            for scale: CGFloat in [1, 2, 3, 5] {
                #expect(pixels(page, scale: scale) == pixels(original, scale: scale))
            }
        }
    }

    @Test func thumbnailsContainStrokesAndHiddenAnnotationsStayHidden() throws {
        let document = try #require(ReadingPDFDocument(data: fixture()))
        let page = try #require(document.page(at: 0))
        let thumbnail = page.thumbnail(of: NSSize(width: 120, height: 160), for: .cropBox)
        let bitmap = try #require(thumbnail.representations.first as? NSBitmapImageRep)
        let hasInk = (0..<bitmap.pixelsWide).contains { x in
            (0..<bitmap.pixelsHigh).contains { y in
                let color = bitmap.colorAt(x: x, y: y)!
                return color.redComponent > color.greenComponent + 0.1
            }
        }
        #expect(hasInk)
        let visible = pixels(page)
        let annotation = try #require(page.annotations.first)
        annotation.shouldDisplay = false
        #expect(pixels(page) != visible)
        annotation.shouldDisplay = true
        #expect(pixels(page) == visible)
        page.displaysAnnotations = false
        #expect(pixels(page) != visible)
    }

    @Test func savePreservesEditableStampAppearanceFlagsAndMetadata() throws {
        let document = try #require(ReadingPDFDocument(data: fixture()))
        let page = try #require(document.page(at: 0))
        let annotation = try #require(page.annotations.first)
        let before = pixels(page)
        let saved = try #require(document.dataRepresentation())
        let reopened = try #require(PDFDocument(data: saved))
        let restoredPage = try #require(reopened.page(at: 0))
        let restored = try #require(restoredPage.annotations.first)
        #expect(restored.type == "Stamp")
        #expect(restored.shouldDisplay == annotation.shouldDisplay)
        #expect(restored.shouldPrint == annotation.shouldPrint)
        #expect(restored.bounds == annotation.bounds)
        #expect(restored.value(forAnnotationKey: PDFAnnotationKey(rawValue: "onyxtag")) as? String == "{\"type\":\"BrushStrokeV2\",\"id\":\"preserve-me\"}")
        // PDFKit re-encodes the appearance color space when serializing a
        // drawn stamp. Verify geometry/ink survives, then require the reopened
        // reader's pixels to match PDFKit's vector renderer exactly.
        func inkBounds(_ data: Data) -> CGRect {
            var bounds = CGRect.null
            for index in stride(from: 0, to: data.count, by: 4)
                where Int(data[index]) - Int(data[index + 1]) > 20 {
                bounds = bounds.union(CGRect(x: (index / 4) % 360, y: (index / 4) / 360, width: 1, height: 1))
            }
            return bounds
        }
        #expect(!inkBounds(before).isNull)
        #expect(inkBounds(pixels(restoredPage)) == inkBounds(before))
        let readingReopened = try #require(ReadingPDFDocument(data: saved))
        let readingPage = try #require(readingReopened.page(at: 0))
        #expect(!readingPage.displaysAnnotations)
        #expect(pixels(readingPage) == pixels(restoredPage))
        page.removeAnnotation(annotation)
        #expect(page.displaysAnnotations) // Ordinary page rendering resumes after removal.
        page.addAnnotation(annotation)
        #expect(!page.displaysAnnotations)
        #expect(pixels(page) == before)
    }

    @Test func savingUnvisitedStrokesPreservesIdentificationAfterDeletingFirst() throws {
        let document = try #require(ReadingPDFDocument(data: fixture(twoStrokes: true)))
        // Save without first rendering or accessing either stroke's custom keys.
        let saved = try #require(document.dataRepresentation())
        let reopened = try #require(ReadingPDFDocument(data: saved))
        let page = try #require(reopened.page(at: 0))
        #expect(page.annotations.count == 2)
        page.removeAnnotation(try #require(page.annotations.first))
        #expect(!page.displaysAnnotations)
        let remaining = try #require(page.annotations.first)
        #expect(remaining.value(forAnnotationKey: PDFAnnotationKey(rawValue: "onyxtag")) as? String == "{\"type\":\"BrushStrokeV2\",\"id\":\"preserve-me\"}")
    }

    @Test func ordinaryStampPagesKeepNativeRendering() throws {
        let document = try #require(ReadingPDFDocument(data: fixture(name: "Approved")))
        let page = try #require(document.page(at: 0))
        #expect(page.displaysAnnotations)
    }
}
