import AppKit
import Testing
import PDFKit
@testable import PaperLens

/// The toolbar's More menu offers the interaction mode as two choices — the one
/// in use is dimmed — instead of one item that flips between them.
@MainActor
struct ToolbarMenuTests {
    @Test func selectAndPanRemainAvailableWithSelectAsDefault() {
        let manager = PDFManager()
        #expect(manager.interactionMode == .select)

        manager.interactionMode = .pan
        #expect(manager.interactionMode == .pan)
        #expect(manager.interactionMode != .select)

        manager.interactionMode = .select
        #expect(manager.interactionMode == .select)
        #expect(manager.interactionMode != .pan)
    }

    @Test func annotationToolsToggleOffAndAreMutuallyExclusive() {
        let pdf = PDFManager()
        pdf.toggleAnnotationTool(.highlight)
        #expect(pdf.interactionMode == .highlight)
        pdf.toggleAnnotationTool(.comment)
        #expect(pdf.interactionMode == .comment)
        pdf.toggleAnnotationTool(.comment)
        #expect(pdf.interactionMode == .select)
        pdf.toggleAnnotationTool(.highlight)
        pdf.toggleAnnotationTool(.highlight)
        #expect(pdf.interactionMode == .select)
    }

    @Test(arguments: [0, 90, 180, 270])
    func clickingCommentToolPlacesMarkerAtPagePoint(rotation: Int) throws {
        let pdf = PDFManager()
        pdf.document = makeTestDocument(pageCount: 1)
        let page = try #require(pdf.document?.page(at: 0))
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .cropBox)
        page.rotation = rotation
        defer { withExtendedLifetime(pdf) {} }
        let comments = CommentManager()
        let undo = UndoManager()
        comments.configure(pdfManager: pdf, defaultPlacementProvider: { nil }, undoManagerProvider: { undo })
        pdf.toggleAnnotationTool(.comment)
        #expect(comments.comments.isEmpty)
        let view = StablePDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 700))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        view.document = pdf.document
        view.scaleFactor = 0.65
        view.pageCommentManager = comments
        view.interactionMode = pdf.interactionMode
        view.layoutSubtreeIfNeeded()
        let point = CGPoint(x: 190, y: 430)
        let location = view.convert(view.convert(point, from: page), to: nil)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
                                                   timestamp: 0, windowNumber: window.windowNumber,
                                                   context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        view.mouseDown(with: event)
        let comment = try #require(comments.comments.first)
        let marker = try #require(comments.markerBounds(for: comment.id))
        #expect(abs(marker.midX - point.x) < 0.01)
        #expect(abs(marker.midY - point.y) < 0.01)
        #expect(comments.editingCommentID == comment.id)
    }

    @Test func highlightSelectionSpansPagesAndUndoesAsOneOperation() throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 300, height: 300)
        let context = try #require(CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil))
        for _ in 0..<2 {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSAttributedString(string: "Select this line", attributes: [.font: NSFont.systemFont(ofSize: 18)])
                .draw(at: CGPoint(x: 30, y: 180))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        let pdf = PDFManager()
        pdf.document = try #require(PDFDocument(data: data as Data))
        let first = try #require(pdf.document?.page(at: 0))
        let second = try #require(pdf.document?.page(at: 1))
        let selection = try #require(first.selection(for: NSRange(location: 0, length: 6)))
        selection.add(try #require(second.selection(for: NSRange(location: 0, length: 6))))
        let undo = UndoManager()
        undo.groupsByEvent = false
        let annotations = AnnotationManager()
        annotations.configure(pdfManager: pdf, selectionProvider: { (selection, first) }, undoManagerProvider: { undo })
        annotations.highlightColor = .green
        annotations.highlightSelection()
        #expect(first.annotations.count == 1)
        #expect(second.annotations.count == 1)
        #expect(first.annotations.first?.color == .green)
        undo.undo()
        #expect(first.annotations.isEmpty && second.annotations.isEmpty)
        undo.redo()
        #expect(first.annotations.count == 1 && second.annotations.count == 1)
        for (style, type) in [(SelectionMarkupStyle.underline, PDFMarkupType.underline), (.strikethrough, .strikeOut)] {
            annotations.selectionStyle = style
            annotations.highlightColor = .blue
            annotations.applySelectionMarkup()
            #expect(first.annotations.last?.markupType == type)
            #expect(first.annotations.last?.color == .red)
            undo.undo()
            #expect(first.annotations.count == 1 && second.annotations.count == 1)
        }
    }
}
