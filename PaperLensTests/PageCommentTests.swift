import AppKit
import PDFKit
import Testing
@testable import PaperLens

@MainActor
struct PageCommentTests {
    @Test func doneButtonDrawsDistinctHoverAndPressedFeedback() throws {
        let button = CommentDoneButton(title: "Done", target: nil, action: nil)
        button.frame = CGRect(x: 0, y: 0, width: 64, height: 28)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.contentTintColor = .gray
        func rendered() throws -> Data {
            let bitmap = try #require(button.bitmapImageRepForCachingDisplay(in: button.bounds))
            button.cacheDisplay(in: button.bounds, to: bitmap)
            return try #require(bitmap.representation(using: .png, properties: [:]))
        }
        let idle = try rendered()
        let event = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil))
        button.mouseEntered(with: event)
        let hovered = try rendered()
        #expect(hovered != idle)
        button.cell?.isHighlighted = true
        #expect(try rendered() != hovered)
        button.cell?.isHighlighted = false
        button.mouseExited(with: event)
        #expect(try rendered() == idle)
    }

    @Test(arguments: [0.5, 1.0, 2.5, 5.0])
    func cardHeaderKeepsTextAndActionsCenteredAtEachZoom(scale: Double) throws {
        let view = StablePDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.scaleFactor = scale
        let card = PageCommentCard(id: UUID(), text: "A note")
        card.pdfView = view
        card.frame = CGRect(x: 0, y: 0, width: 160 * scale * (2.0 / 3.0), height: 90 * scale * (2.0 / 3.0))
        card.updateText("A note", scale: CGFloat(scale))
        card.layout()
        #expect(card.editor.font?.pointSize == 12)
        let done = try #require(card.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Done" })
        let more = try #require(card.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == "Comment actions" })
        let title = try #require(card.subviews.flatMap(\.subviews).compactMap { $0 as? NSTextField }.first)
        let titleBounds = title.convert(title.bounds, to: card)
        #expect(abs(titleBounds.midY - done.frame.midY) < 0.01)
        #expect(abs(more.frame.midY - done.frame.midY) < 0.01)
        #expect(titleBounds.maxX <= done.frame.minX)
        #expect(done.image == nil)
        #expect(done.font == title.font)
        #expect(title.font?.pointSize == 10)
        #expect(done.frame.width == 28)
        #expect(card.bounds.contains(more.frame))
        let color = NSColor.white.withAlphaComponent(0.55)
        card.updateTitleColor(color)
        #expect(done.contentTintColor == title.textColor)
    }

    private func fixture() -> (PDFManager, CommentManager, PDFPage, UndoManager) {
        let pdf = PDFManager()
        pdf.document = makeTestDocument(pageCount: 2)
        let page = pdf.document!.page(at: 0)!
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .cropBox)
        let undo = UndoManager()
        undo.groupsByEvent = false
        let manager = CommentManager()
        manager.configure(pdfManager: pdf, defaultPlacementProvider: { (page, CGPoint(x: 306, y: 396)) }, undoManagerProvider: { undo })
        return (pdf, manager, page, undo)
    }

    @Test func neutralCommentDefaultsMigrateWithoutChangingCustomPresets() throws {
        let domain = "PaperLens-CommentDefaults-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let gray = SettingsManager.ColorPreset(name: "White", hex: "#FFFFFFFF")
        defaults.set(try JSONEncoder().encode([gray]), forKey: "settings.commentPresets")
        let migrated = SettingsManager(defaults: defaults)
        #expect(migrated.commentPresets.first?.hex == "#80808099")
        let custom = SettingsManager.ColorPreset(name: "My gray", hex: "#80808099")
        defaults.set(try JSONEncoder().encode([custom]), forKey: "settings.commentPresets")
        #expect(SettingsManager(defaults: defaults).commentPresets == [custom])
        let standard = SettingsManager.ColorPreset(name: "Gray", hex: "#80808099")
        defaults.set(try JSONEncoder().encode([standard]), forKey: "settings.commentPresets")
        let expanded = SettingsManager(defaults: defaults)
        #expect(expanded.commentPresets.map(\.name) == ["Gray", "Yellow", "Blue"])
        #expect(expanded.commentPresets.first?.id == standard.id)
        let grayCard = CommentManager.cardColor(for: NSColor.gray.withAlphaComponent(0.6))
        #expect(abs(grayCard.redComponent - 0.7) < 0.001)
        #expect(CommentManager.cardColor(for: .red).redComponent == 1)
        #expect(CommentManager.cardColor(for: .red).greenComponent == 0)
        #expect(CommentManager.connectionColor(for: .white) == .black)
        #expect(CommentManager.connectionColor(for: .gray) == .black)
    }

    @Test func customBorderPositionSurvivesMovementUndoAndPDFSave() throws {
        let (pdf, manager, page, undo) = fixture()
        undo.beginUndoGrouping()
        let id = try #require(manager.addComment(on: page, at: CGPoint(x: 100, y: 500)))
        undo.endUndoGrouping()
        let card = try #require(manager.cardBounds(for: id))
        let original = try #require(manager.geometrySnapshot(for: id))
        manager.setConnectionPoint(id, point: CGPoint(x: card.maxX + 40, y: card.minY + card.height * 0.7), registerUndo: false)
        undo.beginUndoGrouping()
        manager.commitGeometry(id, previousAnnotation: original, previousBounds: original.bounds)
        undo.endUndoGrouping()
        let attachment = try #require((manager.annotation(for: id) as? PageCommentAnnotation)?.geometry.attachment)
        #expect(abs(attachment.x - 1) < 0.001)
        #expect(abs(attachment.y - 0.7) < 0.001)
        undo.undo()
        #expect((manager.annotation(for: id) as? PageCommentAnnotation)?.geometry.attachment == nil)
        undo.redo()
        #expect((manager.annotation(for: id) as? PageCommentAnnotation)?.geometry.attachment == attachment)
        manager.setBounds(id, bounds: CGRect(x: 200, y: 200, width: 300, height: 200), registerUndo: false)
        manager.setMarkerBounds(id, bounds: CGRect(x: 40, y: 300, width: 14, height: 14), registerUndo: false)
        let geometry = try #require((manager.annotation(for: id) as? PageCommentAnnotation)?.geometry)
        #expect(geometry.attachment == attachment)
        let curve = CommentConnection(marker: geometry.marker, card: geometry.card, attachment: attachment)
        #expect(abs(curve.endpoint.x - 500) < 0.001)
        #expect(abs(curve.endpoint.y - 340) < 0.001)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        pdf.documentURL = url
        #expect(pdf.saveSync())
        let saved = try #require(PDFDocument(url: url)?.page(at: 0)?.annotations.first)
        let restored = PageCommentAnnotation.restoring(saved).geometry
        #expect(restored.card == geometry.card)
        #expect(restored.marker == geometry.marker)
        #expect(abs(try #require(restored.attachment).y - attachment.y) < 0.00001)
        undo.beginUndoGrouping(); manager.setConnectionPoint(id, point: nil); undo.endUndoGrouping()
        #expect((manager.annotation(for: id) as? PageCommentAnnotation)?.geometry.attachment == nil)
        undo.undo()
        #expect((manager.annotation(for: id) as? PageCommentAnnotation)?.geometry.attachment == attachment)
    }

    @Test func borderProjectionAndLegacyMarkerMigration() {
        let card = CGRect(x: 100, y: 100, width: 240, height: 140)
        for (input, expected) in [(CGPoint(x: 101, y: 150), CGPoint(x: 100, y: 150)),
                                  (CGPoint(x: 339, y: 150), CGPoint(x: 340, y: 150)),
                                  (CGPoint(x: 200, y: 101), CGPoint(x: 200, y: 100)),
                                  (CGPoint(x: 200, y: 239), CGPoint(x: 200, y: 240))] {
            #expect(CommentConnection.borderPoint(input, card: card).point == expected)
        }
        let old = PageCommentAnnotation(bounds: card, forType: .freeText, withProperties: nil)
        old.setGeometry(CommentGeometry(card: card, marker: CGRect(x: 20, y: 300, width: 28, height: 28)))
        #expect(old.geometry.marker == CGRect(x: 30, y: 310, width: 8, height: 8))
        for attachment in [CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5), CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)] {
            let connection = CommentConnection(marker: old.geometry.marker, card: card, attachment: attachment)
            #expect(connection.path != nil)
            #expect(connection.path?.boundingBoxOfPath.isInfinite == false)
            #expect(card.contains(connection.endpoint) || connection.endpoint.x == card.maxX || connection.endpoint.y == card.maxY)
        }
    }

    @Test func independentGeometryAndSmoothConnections() {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let g = CommentGeometry.initial(card: CGRect(x: 100, y: 250, width: 240, height: 140), page: page)
        #expect(g.marker.width == 8)
        #expect(page.contains(g.card))
        #expect(!g.card.intersects(g.marker))
        for origin in [CGPoint(x: 10, y: 100), CGPoint(x: 450, y: 100), CGPoint(x: 100, y: 500), CGPoint(x: 100, y: 10)] {
            let marker = CGRect(origin: origin, size: CGSize(width: 28, height: 28))
            let card = CGRect(x: 140, y: 160, width: 240, height: 140)
            let path = CommentConnection(marker: marker, card: card).path
            #expect(path != nil)
            #expect(path?.boundingBoxOfPath.isInfinite == false)
        }
        #expect(CommentConnection(marker: g.marker, card: g.marker).path == nil)
    }

    @Test(arguments: [0, 90, 180, 270], [0.65, 1.4])
    func expandedMarkerRemainsAtCollapsedPosition(rotation: Int, scale: Double) throws {
        let (pdf, manager, page, undo) = fixture()
        page.rotation = rotation
        let view = StablePDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.document = pdf.document
        view.displayMode = .singlePage
        view.scaleFactor = scale
        view.layoutDocumentView()
        view.pageCommentManager = manager
        undo.beginUndoGrouping()
        let id = try #require(manager.addComment(on: page, at: CGPoint(x: 180, y: 500)))
        undo.endUndoGrouping()
        let saved = manager.cardBounds(for: id)
        view.syncCommentOverlays()
        let marker = try #require(view.commentMarkers[id])
        let expandedPosition = marker.frame
        #expect(!marker.isHidden)
        #expect(view.pageCommentCard != nil)
        #expect(!expandedPosition.intersects(try #require(view.pageCommentCard?.frame)))
        manager.stopEditing()
        view.syncCommentOverlays()
        #expect(marker.frame == expandedPosition)
        #expect(manager.cardBounds(for: id) == saved)
        #expect(view.pageCommentCard == nil)
        view.document = nil
    }

    /// Mirrors `CommentMarker`'s drag gesture: the saved rect moves by a view-space
    /// delta, the collapsed anchor travels with it, and the open card follows.
    @Test func draggingExpandedAnchorKeepsCardAndMarkerConnected() throws {
        let (pdf, manager, page, undo) = fixture()
        page.rotation = 0
        let view = StablePDFView(frame: CGRect(x: 0, y: 0, width: 900, height: 700))
        view.document = pdf.document
        view.displayMode = .singlePage
        view.scaleFactor = 1
        view.layoutDocumentView()
        view.pageCommentManager = manager
        undo.beginUndoGrouping()
        let id = try #require(manager.addComment(on: page, at: CGPoint(x: 200, y: 600)))
        undo.endUndoGrouping()
        view.syncCommentOverlays()
        let saved = try #require(manager.cardBounds(for: id))
        let annotation = try #require(manager.geometrySnapshot(for: id))
        let savedMarker = try #require(manager.markerBounds(for: id))
        let marker = try #require(view.commentMarkers[id])
        let card = try #require(view.pageCommentCard)
        let startMarker = marker.frame
        let startCard = card.frame

        let delta = CGPoint(x: -70, y: -90)
        let movedInView = view.convert(savedMarker, from: page).offsetBy(dx: delta.x, dy: delta.y)
        manager.setMarkerBounds(id, bounds: view.convert(movedInView, to: page), registerUndo: false)
        view.syncCommentOverlays()

        let moved = try #require(manager.cardBounds(for: id))
        #expect(moved == saved)
        #expect(approximately(marker.frame, startMarker.offsetBy(dx: delta.x, dy: delta.y)))
        #expect(!marker.isHidden)
        #expect(approximately(card.frame, startCard))
        #expect(!card.frame.intersects(marker.frame))

        // Releasing the anchor commits a single undo step back to the original drop point.
        undo.beginUndoGrouping()
        manager.commitGeometry(id, previousAnnotation: annotation, previousBounds: annotation.bounds)
        undo.endUndoGrouping()
        undo.undo()
        view.syncCommentOverlays()
        #expect(manager.cardBounds(for: id) == saved)
        #expect(approximately(marker.frame, startMarker))
        #expect(approximately(card.frame, startCard))
        #expect(!card.frame.intersects(marker.frame))
        view.document = nil
    }

    @Test func defaultCreationCentersCardAndCommitsPreviousText() throws {
        let (pdf, manager, _, undo) = fixture()
        defer { withExtendedLifetime(pdf) {} }
        undo.beginUndoGrouping()
        let first = try #require(manager.addComment())
        undo.endUndoGrouping()
        #expect(approximately(try #require(manager.cardBounds(for: first)), CGRect(x: 338 - 160.0 / 3.0, y: 366, width: 320.0 / 3.0, height: 60)))
        manager.updateComment(first, text: "中文\n第二行")
        undo.beginUndoGrouping()
        let second = try #require(manager.addComment())
        undo.endUndoGrouping()
        #expect(manager.editingCommentID == second)
        #expect(manager.selectedCommentID == second)
        #expect(manager.comments.first?.text == "中文\n第二行")
        #expect(!manager.hasPendingTextEdit)
        undo.undo()
        #expect(manager.comments.count == 1)
        #expect(manager.comments.first?.text == "")
        undo.redo()
        #expect(manager.comments.count == 2)
        #expect(manager.comments.first?.text == "中文\n第二行")
    }

    @Test func toggleCommitsTextAndKeepsMarker() throws {
        let (pdf, manager, page, undo) = fixture()
        defer { withExtendedLifetime(pdf) {} }
        undo.beginUndoGrouping()
        let id = try #require(manager.addComment(on: page, at: CGPoint(x: 100, y: 600)))
        undo.endUndoGrouping()
        let marker = manager.markerBounds(for: id)
        manager.updateComment(id, text: "saved text")
        undo.beginUndoGrouping(); manager.toggleComment(id); undo.endUndoGrouping()
        #expect(manager.editingCommentID == nil)
        #expect(manager.markerBounds(for: id) == marker)
        #expect(manager.comments.first?.text == "saved text")
        manager.toggleComment(id)
        #expect(manager.editingCommentID == id)
        undo.beginUndoGrouping()
        let second = try #require(manager.addComment(on: page, at: CGPoint(x: 80, y: 300)))
        undo.endUndoGrouping()
        manager.toggleComment(id)
        #expect(manager.editingCommentID == id)
        #expect(manager.editingCommentID != second)
    }

    @Test func movingCardPreservesMarkerAndMarkerUndoPreservesCard() throws {
        let (pdf, manager, page, undo) = fixture()
        defer { withExtendedLifetime(pdf) {} }
        undo.beginUndoGrouping()
        let id = try #require(manager.addComment(on: page, at: CGPoint(x: 100, y: 600)))
        undo.endUndoGrouping()
        let marker = try #require(manager.markerBounds(for: id))
        undo.beginUndoGrouping(); manager.setBounds(id, bounds: CGRect(x: 300, y: 100, width: 240, height: 140)); undo.endUndoGrouping()
        let card = manager.cardBounds(for: id)
        #expect(manager.markerBounds(for: id) == marker)
        undo.beginUndoGrouping(); manager.setMarkerBounds(id, bounds: marker.offsetBy(dx: 50, dy: -60)); undo.endUndoGrouping()
        #expect(manager.cardBounds(for: id) == card)
        #expect(manager.markerBounds(for: id) != marker)
        undo.undo()
        #expect(manager.markerBounds(for: id) == marker)
        #expect(manager.cardBounds(for: id) == card)
        undo.redo()
        #expect(manager.markerBounds(for: id) == marker.offsetBy(dx: 50, dy: -60))
    }

    @Test func missingOrStalePlacementDoesNotCreateComment() throws {
        let (pdf, manager, _, undo) = fixture()
        manager.configure(pdfManager: pdf, defaultPlacementProvider: { nil }, undoManagerProvider: { undo })
        #expect(manager.addComment() == nil)
        let foreign = PDFPage()
        manager.configure(pdfManager: pdf, defaultPlacementProvider: { (foreign, .zero) }, undoManagerProvider: { undo })
        #expect(manager.addComment() == nil)
        #expect(manager.comments.isEmpty)
        #expect(!pdf.isDirty)
    }

    @Test(arguments: [0, 90, 180, 270], [0.65, 1.4])
    func defaultPlacementUsesVisibleCenterAcrossZoomAndRotation(rotation: Int, scale: Double) throws {
        let (pdf, manager, page, undo) = fixture()
        page.rotation = rotation
        let view = StablePDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.displayMode = .singlePage
        view.document = pdf.document
        view.scaleFactor = scale
        view.layoutDocumentView()
        let (target, point) = try #require(view.defaultCommentPlacement())
        #expect(target === page)
        let visible = view.bounds.intersection(view.convert(page.bounds(for: .cropBox), from: page))
        let centerInView = view.convert(point, from: page)
        #expect(abs(centerInView.x - visible.midX) < 0.01)
        #expect(abs(centerInView.y - visible.midY) < 0.01)
        let before = view.currentDestination?.point
        let previousScale = view.scaleFactor
        manager.configure(pdfManager: pdf, defaultPlacementProvider: { view.defaultCommentPlacement() }, undoManagerProvider: { undo })
        undo.beginUndoGrouping()
        let id = try #require(manager.addComment())
        undo.endUndoGrouping()
        #expect(page.bounds(for: .cropBox).contains(try #require(manager.cardBounds(for: id))))
        #expect(view.scaleFactor == previousScale)
        #expect(view.currentDestination?.point == before)
        view.document = nil
    }

    @Test func placementCreatesEditableFreeTextAndClampsToPage() throws {
        let (pdf, manager, page, undo) = fixture()
        defer { withExtendedLifetime(pdf) {} }
        undo.beginUndoGrouping()
        let id = try #require(manager.addComment(on: page, at: CGPoint(x: 10000, y: -10000)))
        undo.endUndoGrouping()
        let annotation = try #require(manager.annotation(for: id))
        #expect(annotation.type == "FreeText")
        #expect(!annotation.shouldDisplay)
        #expect(annotation.shouldPrint)
        #expect(page.bounds(for: .cropBox).contains(annotation.bounds))
        #expect(manager.editingCommentID == id)
        undo.undo()
        #expect(manager.comments.isEmpty)
        undo.redo()
        #expect(manager.comments.count == 1)
    }

    @Test func textGeometryAndDeleteUndoRestoreSharedState() throws {
        let (pdf, manager, page, undo) = fixture()
        defer { withExtendedLifetime(pdf) {} }
        undo.beginUndoGrouping()
        let id = try #require(manager.addComment(on: page, at: CGPoint(x: 40, y: 400)))
        undo.endUndoGrouping()
        let originalModel = try #require(manager.comments.first)
        undo.beginUndoGrouping()
        manager.updateComment(id, text: "中文批注\nSecond line")
        manager.stopEditing()
        undo.endUndoGrouping()
        #expect(manager.comments.first != originalModel)
        #expect(manager.annotation(for: id)?.contents == "中文批注\nSecond line")
        undo.undo()
        #expect(manager.comments.first?.text == "")
        undo.redo()
        #expect(manager.comments.first?.text == "中文批注\nSecond line")
        let initial = try #require(manager.cardBounds(for: id))
        undo.beginUndoGrouping()
        manager.setBounds(id, bounds: CGRect(x: 80, y: 90, width: 300, height: 200))
        undo.endUndoGrouping()
        let moved = try #require(manager.cardBounds(for: id))
        #expect(moved != initial)
        #expect(manager.comments.first?.bounds == moved)
        undo.undo()
        #expect(manager.cardBounds(for: id) == initial)
        undo.redo()
        #expect(manager.cardBounds(for: id) == moved)
        undo.beginUndoGrouping()
        manager.deleteComment(id)
        undo.endUndoGrouping()
        #expect(manager.comments.isEmpty)
        undo.undo()
        #expect(manager.comments.first?.text == "中文批注\nSecond line")
    }

    @Test func savedPDFContainsVisibleTextAndReloadCollapsesIt() throws {
        let (pdf, manager, page, undo) = fixture()
        undo.beginUndoGrouping()
        let id = try #require(manager.addComment(on: page, at: CGPoint(x: 50, y: 400), text: "中文批注\nPaperLens comment"))
        undo.endUndoGrouping()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        pdf.documentURL = url
        #expect(pdf.saveSync())
        #expect(manager.annotation(for: id)?.shouldDisplay == false)
        let document = try #require(PDFDocument(url: url))
        let annotation = try #require(document.page(at: 0)?.annotations.first)
        #expect(annotation.type == "FreeText")
        #expect(annotation.shouldDisplay)
        #expect(annotation.contents == "中文批注\nPaperLens comment")
        #expect(annotation.bounds.contains(try #require(manager.cardBounds(for: id))))
        let loaded = CommentManager()
        loaded.loadComments(from: document)
        #expect(loaded.comments.first?.id == id)
        #expect(loaded.comments.first?.text == "中文批注\nPaperLens comment")
        #expect(loaded.annotation(for: id)?.shouldDisplay == false)
        #expect(approximately(try #require(loaded.cardBounds(for: id)), try #require(manager.cardBounds(for: id))))
        #expect(loaded.markerBounds(for: id) == manager.markerBounds(for: id))
        #expect(annotation.hasAppearanceStream)
    }

    @Test func yellowMarkerMatchesLiveOverlayAndSavedPDFAppearance() throws {
        let (pdf, manager, page, undo) = fixture()
        let view = StablePDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.document = pdf.document
        view.scaleFactor = 1
        view.pageCommentManager = manager
        defer { view.document = nil }
        undo.beginUndoGrouping()
        let id = try #require(manager.addComment(on: page, at: CGPoint(x: 80, y: 400)))
        manager.chooseCommentColor(NSColor(srgbRed: 1, green: 0.85, blue: 0, alpha: 0.6))
        undo.endUndoGrouping()
        view.syncCommentOverlays()
        let marker = try #require(view.commentMarkers[id])
        let bitmap = try #require(marker.bitmapImageRepForCachingDisplay(in: marker.bounds))
        marker.cacheDisplay(in: marker.bounds, to: bitmap)
        let live = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        #expect(live.redComponent > 0.95)
        #expect(abs(live.greenComponent - 0.85) < 0.05)
        #expect(live.blueComponent < 0.05)

        let markerBounds = try #require(manager.markerBounds(for: id))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        pdf.documentURL = url
        #expect(pdf.saveSync())
        let savedDocument = try #require(PDFDocument(url: url))
        let savedPage = try #require(savedDocument.page(at: 0))
        let savedAnnotation = try #require(savedPage.annotations.first)
        #expect(savedAnnotation.hasAppearanceStream)
        let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: image)?.cgContext)
        context.translateBy(x: 16 - markerBounds.midX, y: 16 - markerBounds.midY)
        savedPage.draw(with: .mediaBox, to: context)
        let saved = try #require(image.colorAt(x: 16, y: 16)?.usingColorSpace(.deviceRGB))
        #expect(abs(saved.redComponent - live.redComponent) < 0.05)
        #expect(abs(saved.greenComponent - live.greenComponent) < 0.05)
        #expect(abs(saved.blueComponent - live.blueComponent) < 0.05)
        let loaded = CommentManager()
        loaded.loadComments(from: savedDocument)
        let restored = try #require(loaded.annotation(for: id)?.color.usingColorSpace(.deviceRGB))
        #expect(abs(restored.greenComponent - 0.85) < 0.01)
        #expect(abs(restored.alphaComponent - 0.6) < 0.01)
    }

    @Test func commentColorUsesPresetAndRoundTripsChanges() throws {
        let (pdf, manager, page, undo) = fixture()
        let preset = try #require(SettingsManager.shared.commentPresets.first)
        #expect(manager.commentColor.isEqual(to: preset.color))
        let color = NSColor(srgbRed: 0.3, green: 0.6, blue: 0.85, alpha: 0.7)
        manager.chooseCommentColor(color)
        undo.beginUndoGrouping()
        let id = try #require(manager.addComment(on: page, at: CGPoint(x: 50, y: 400)))
        undo.endUndoGrouping()
        #expect(manager.annotation(for: id)?.color == color)
        undo.beginUndoGrouping()
        manager.chooseCommentColor(.systemPink)
        undo.endUndoGrouping()
        #expect(manager.annotation(for: id)?.color == .systemPink)
        undo.undo()
        #expect(manager.annotation(for: id)?.color == color)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        pdf.documentURL = url
        #expect(pdf.saveSync())
        let loaded = CommentManager()
        loaded.loadComments(from: try #require(PDFDocument(url: url)))
        let reloaded = try #require(loaded.annotation(for: id)?.color.usingColorSpace(.deviceRGB))
        #expect(abs(reloaded.alphaComponent - 0.7) < 0.01)
        #expect(abs(reloaded.blueComponent - (color.usingColorSpace(.deviceRGB)?.blueComponent ?? 0)) < 0.01)
    }

    @Test func openingVisibleCommentDoesNotNavigatePDF() throws {
        let (pdf, manager, page, undo) = fixture()
        undo.beginUndoGrouping()
        let id = try #require(manager.addComment(on: page, at: CGPoint(x: 50, y: 400)))
        manager.stopEditing()
        undo.endUndoGrouping()
        manager.isAnnotationVisible = { _ in true }
        manager.selectComment(id)
        #expect(manager.editingCommentID == id)
        #expect(pdf.pendingNavigation == nil)
    }

    @Test func liveLegacyResizeUndoRestoresOriginalHighlightBounds() throws {
        let (pdf, manager, page, undo) = fixture()
        let originalBounds = CGRect(x: 30, y: 300, width: 100, height: 18)
        let legacy = PDFAnnotation(bounds: originalBounds, forType: .highlight, withProperties: nil)
        let id = UUID()
        legacy.userName = id.uuidString
        legacy.contents = "Old note"
        page.addAnnotation(legacy)
        manager.loadComments(from: pdf.document!)
        manager.setBounds(id, bounds: CGRect(x: 30, y: 200, width: 260, height: 160), registerUndo: false)
        undo.beginUndoGrouping()
        manager.commitGeometry(id, previousAnnotation: legacy, previousBounds: originalBounds)
        undo.endUndoGrouping()
        undo.undo()
        #expect(manager.annotation(for: id) === legacy)
        #expect(legacy.bounds == originalBounds)
        #expect(manager.comments.first?.bounds == originalBounds)
    }

    @Test func legacyHighlightOnlyConvertsOnGeometryChangeAndUndoRestoresType() throws {
        let (pdf, manager, page, undo) = fixture()
        let legacy = PDFAnnotation(bounds: CGRect(x: 20, y: 300, width: 100, height: 18), forType: .highlight, withProperties: nil)
        let id = UUID()
        legacy.userName = id.uuidString
        legacy.contents = "Legacy note"
        page.addAnnotation(legacy)
        manager.loadComments(from: pdf.document!)
        #expect(manager.comments.count == 1)
        manager.selectComment(id)
        manager.updateComment(id, text: "Edited legacy")
        #expect(manager.annotation(for: id) === legacy)
        undo.beginUndoGrouping()
        manager.setBounds(id, bounds: CGRect(x: 20, y: 200, width: 240, height: 140))
        undo.endUndoGrouping()
        #expect(manager.annotation(for: id)?.type == "FreeText")
        undo.undo()
        #expect(manager.annotation(for: id) === legacy)
        #expect(manager.comments.first?.text == "Edited legacy")
        undo.redo()
        #expect(manager.annotation(for: id)?.type == "FreeText")
    }
}

/// Overlay frames round-trip through PDFView conversions, so compare with a tolerance.
private func approximately(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.01) -> Bool {
    abs(lhs.minX - rhs.minX) < tolerance && abs(lhs.minY - rhs.minY) < tolerance &&
        abs(lhs.width - rhs.width) < tolerance && abs(lhs.height - rhs.height) < tolerance
}
