//
//  CommentManager.swift
//  PaperLens
//
//  Manages creation, editing, deletion, and loading of PDF comments.
//

import AppKit
import Foundation
import Observation
import PDFKit
import os.log

@Observable
@MainActor
final class CommentManager {
    /// Annotation marker written into the PDF itself. The key/value strings are a
    /// file-format contract with previously annotated documents: they are frozen
    /// (they still read "PageFlow…") and must not follow the app's renaming.
    private static let commentMarkerKey = PDFAnnotationKey(rawValue: "PageFlowType")
    private static let commentMarkerValue = "pageflow-comment"
    private let logger = Logger(subsystem: "com.paperlens", category: "CommentManager")

    deinit {
        #if DEBUG
        Swift.print("[deinit] CommentManager")
        #endif
    }

    // MARK: - State

    var comments: [CommentModel] = []
    var selectedCommentID: UUID?
    var editingCommentID: UUID?
    var layoutRevision = 0
    var overflowMessage: String?
    private var editingOriginalText: String?
    private var chosenCommentColor: NSColor?
    var commentColor: NSColor {
        if let id = editingCommentID, let annotation = highlights[id] { return annotation.color }
        return chosenCommentColor ?? SettingsManager.shared.commentPresets.first?.color ?? NSColor.gray.withAlphaComponent(0.6)
    }

    func chooseCommentColor(_ color: NSColor) {
        chosenCommentColor = color
        if let id = editingCommentID { updateCommentColor(id, color: color) }
    }

    static func cardColor(for color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.deviceRGB) ?? .gray
        let a = rgb.alphaComponent
        return NSColor(deviceRed: rgb.redComponent * a + 1 - a,
                       green: rgb.greenComponent * a + 1 - a,
                       blue: rgb.blueComponent * a + 1 - a, alpha: 1)
    }

    static func textColor(on color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return .black }
        let alpha = rgb.alphaComponent
        let luminance = (0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent) * alpha + 1 - alpha
        return luminance < 0.45 ? .white : .black
    }

    static func connectionColor(for color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return .black }
        let spread = max(rgb.redComponent, max(rgb.greenComponent, rgb.blueComponent)) - min(rgb.redComponent, min(rgb.greenComponent, rgb.blueComponent))
        return spread < 0.02 ? .black : rgb.withAlphaComponent(1)
    }

    /// Comments in sidebar display order (creation time). Lives here so the
    /// display rule is testable through the manager's interface — same pattern
    /// as `BookmarkManager.sortedBookmarks`.
    var sortedComments: [CommentModel] {
        comments.sorted { $0.createdAt < $1.createdAt }
    }

    private weak var pdfManager: PDFManager?
    private var defaultPlacementProvider: (() -> (PDFPage, CGPoint)?)?
    var isAnnotationVisible: ((PDFAnnotation) -> Bool)?
    private var undoManagerProvider: (() -> UndoManager?)?
    private var highlights: [UUID: PDFAnnotation] = [:]

    // MARK: - Configuration

    func configure(
        pdfManager: PDFManager,
        defaultPlacementProvider: @escaping () -> (PDFPage, CGPoint)?,
        undoManagerProvider: @escaping () -> UndoManager?
    ) {
        self.pdfManager = pdfManager
        self.defaultPlacementProvider = defaultPlacementProvider
        self.undoManagerProvider = undoManagerProvider
    }

    private func getUndoManager(for action: String) -> UndoManager? {
        guard let undoManager = undoManagerProvider?() else {
            logger.error("UndoManager unavailable for action: \(action)")
            return nil
        }
        return undoManager
    }

    // MARK: - Actions

    /// The view supplies the visible page center in PDF coordinates.
    @discardableResult
    func addComment(text: String = "") -> UUID? {
        guard let (page, center) = defaultPlacementProvider?() else { return nil }
        return addComment(on: page, at: CGPoint(x: center.x - CommentCardMetrics.defaultSize.width / 2,
                                                     y: center.y + CommentCardMetrics.defaultSize.height / 2), text: text, centerMarker: false)
    }

    @discardableResult
    func addComment(on page: PDFPage, at point: CGPoint, text: String = "", centerMarker: Bool = true) -> UUID? {
        guard let document = pdfManager?.document, document.index(for: page) != NSNotFound else { return nil }
        stopEditing()
        let size = CommentCardMetrics.defaultSize
        let bounds = clamped(CGRect(x: point.x, y: point.y - size.height, width: size.width, height: size.height), on: page)
        let annotation = makeTextAnnotation(bounds: bounds, text: text)
        if !centerMarker {
            (annotation as? PageCommentAnnotation)?.setGeometry(CommentGeometry.initial(card: bounds, page: page.bounds(for: .cropBox)))
        } else if let annotation = annotation as? PageCommentAnnotation {
            let area = page.bounds(for: .cropBox)
            let size = min(CommentGeometry.markerSize, min(area.width, area.height))
            let marker = CGRect(x: min(max(point.x - size / 2, area.minX), area.maxX - size),
                                y: min(max(point.y - size / 2, area.minY), area.maxY - size),
                                width: size, height: size)
            var geometry = CommentGeometry.initial(card: CGRect(x: marker.minX, y: marker.maxY - bounds.height,
                                                                 width: bounds.width, height: bounds.height), page: area)
            geometry.marker = marker
            geometry.card = clamped(geometry.card, on: page)
            annotation.setGeometry(geometry)
        }
        let id = UUID()
        annotation.userName = id.uuidString
        annotation.setValue(Self.commentMarkerValue, forAnnotationKey: Self.commentMarkerKey)
        annotation.modificationDate = Date()
        page.addAnnotation(annotation)
        let model = CommentModel(id: id, text: text, pageIndex: document.index(for: page), bounds: (annotation as? PageCommentAnnotation)?.geometry.card ?? bounds)
        comments.append(model)
        highlights[id] = annotation
        selectedCommentID = id
        editingCommentID = id
        editingOriginalText = text
        layoutRevision += 1
        pdfManager?.noteVisibleEdit(on: page)
        registerUndoAdd(model, highlight: annotation, page: page)
        return id
    }

    private func makeTextAnnotation(bounds: CGRect, text: String) -> PDFAnnotation {
        let annotation = PageCommentAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        annotation.contents = text
        annotation.font = NSFont.systemFont(ofSize: CommentCardMetrics.bodyFontSize)
        annotation.color = commentColor
        annotation.fontColor = Self.textColor(on: annotation.color)
        annotation.recordColor()
        let border = PDFBorder()
        border.lineWidth = 1
        annotation.border = border
        annotation.shouldDisplay = false
        annotation.shouldPrint = true
        return annotation
    }

    func annotation(for id: UUID) -> PDFAnnotation? { highlights[id] }

    func cardBounds(for id: UUID) -> CGRect? {
        guard let annotation = highlights[id], let page = annotation.page else { return nil }
        if let annotation = annotation as? PageCommentAnnotation { return annotation.geometry.card }
        if annotation.type == "FreeText" { return annotation.bounds }
        return clamped(CGRect(x: annotation.bounds.minX, y: annotation.bounds.maxY - 140 * CommentCardMetrics.scale,
                              width: 240 * CommentCardMetrics.scale, height: 140 * CommentCardMetrics.scale), on: page)
    }

    func markerBounds(for id: UUID) -> CGRect? {
        if let annotation = highlights[id] as? PageCommentAnnotation { return annotation.geometry.marker }
        guard let card = cardBounds(for: id) else { return nil }
        return CGRect(x: card.minX, y: card.maxY - 8, width: 8, height: 8)
    }

    /// Copy page-comment metadata before live dragging mutates the annotation.
    func geometrySnapshot(for id: UUID) -> PDFAnnotation? {
        guard let annotation = highlights[id] else { return nil }
        return annotation is PageCommentAnnotation ? PageCommentAnnotation.restoring(annotation) : annotation
    }

    func setMarkerBounds(_ id: UUID, bounds: CGRect, registerUndo: Bool = true) {
        guard let old = geometrySnapshot(for: id), let original = highlights[id], let page = original.page else { return }
        if !(original is PageCommentAnnotation) { setBounds(id, bounds: cardBounds(for: id) ?? original.bounds, registerUndo: false) }
        guard let annotation = highlights[id] as? PageCommentAnnotation else { return }
        let area = page.bounds(for: .cropBox)
        let size = min(CommentGeometry.markerSize, min(area.width, area.height))
        let marker = CGRect(x: min(max(bounds.minX, area.minX), area.maxX - size),
                            y: min(max(bounds.minY, area.minY), area.maxY - size), width: size, height: size)
        annotation.setGeometry(CommentGeometry(card: annotation.geometry.card, marker: marker, attachment: annotation.geometry.attachment))
        layoutRevision += 1
        pdfManager?.noteVisibleEdit(on: page)
        if registerUndo { commitGeometry(id, previousAnnotation: old, previousBounds: old.bounds) }
    }

    /// A normalized border position follows card movement and resizing.
    func setConnectionPoint(_ id: UUID, point: CGPoint?, registerUndo: Bool = true) {
        guard let old = geometrySnapshot(for: id), let original = highlights[id], let page = original.page else { return }
        if !(original is PageCommentAnnotation) { setBounds(id, bounds: cardBounds(for: id) ?? original.bounds, registerUndo: false) }
        guard let annotation = highlights[id] as? PageCommentAnnotation else { return }
        var geometry = annotation.geometry
        geometry.attachment = point.map {
            let border = CommentConnection.borderPoint($0, card: geometry.card).point
            return CGPoint(x: min(1, max(0, (border.x - geometry.card.minX) / geometry.card.width)),
                           y: min(1, max(0, (border.y - geometry.card.minY) / geometry.card.height)))
        }
        annotation.setGeometry(geometry)
        layoutRevision += 1
        pdfManager?.noteVisibleEdit(on: page)
        if registerUndo { commitGeometry(id, previousAnnotation: old, previousBounds: old.bounds) }
    }

    func toggleComment(_ id: UUID) {
        if editingCommentID == id { stopEditing() } else { selectComment(id) }
    }

    private func clamped(_ rect: CGRect, on page: PDFPage) -> CGRect {
        let area = page.bounds(for: .cropBox)
        let width = min(area.width, max(min(CommentCardMetrics.minimumSize.width, area.width), rect.width))
        let height = min(area.height, max(min(CommentCardMetrics.minimumSize.height, area.height), rect.height))
        return CGRect(x: min(max(rect.minX, area.minX), area.maxX - width),
                      y: min(max(rect.maxY - height, area.minY), area.maxY - height), width: width, height: height)
    }

    func setBounds(_ id: UUID, bounds: CGRect, registerUndo: Bool = true) {
        guard let old = highlights[id], let page = old.page,
              let index = comments.firstIndex(where: { $0.id == id }) else { return }
        let snapshot = geometrySnapshot(for: id) ?? old
        let previous = snapshot.bounds
        let next = clamped(bounds, on: page)
        let annotation: PDFAnnotation
        if old.type != "FreeText" {
            annotation = makeTextAnnotation(bounds: next, text: comments[index].text)
            annotation.color = old.color
            annotation.fontColor = Self.textColor(on: old.color)
            (annotation as? PageCommentAnnotation)?.recordColor()
            (annotation as? PageCommentAnnotation)?.setGeometry(CommentGeometry(card: next, marker: markerBounds(for: id) ?? next))
            annotation.userName = old.userName
            annotation.modificationDate = old.modificationDate
            annotation.setValue(Self.commentMarkerValue, forAnnotationKey: Self.commentMarkerKey)
            page.removeAnnotation(old)
            page.addAnnotation(annotation)
            highlights[id] = annotation
        } else {
            annotation = old
            if let comment = annotation as? PageCommentAnnotation {
                comment.setGeometry(CommentGeometry(card: next, marker: comment.geometry.marker, attachment: comment.geometry.attachment))
            } else { annotation.bounds = next }
        }
        comments[index].bounds = next
        layoutRevision += 1
        pdfManager?.noteVisibleEdit(on: page)
        if registerUndo {
            undoManagerProvider?()?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.restoreGeometry(id, annotation: snapshot, bounds: previous)
                }
            }
            undoManagerProvider?()?.setActionName("Resize or Move Comment")
        }
    }

    func commitGeometry(_ id: UUID, previousAnnotation: PDFAnnotation, previousBounds: CGRect) {
        undoManagerProvider?()?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.restoreGeometry(id, annotation: previousAnnotation, bounds: previousBounds) }
        }
        undoManagerProvider?()?.setActionName("Resize or Move Comment")
    }

    var hasPendingTextEdit: Bool {
        guard let id = editingCommentID, let original = editingOriginalText else { return false }
        return comments.first(where: { $0.id == id })?.text != original
    }

    func undoEditing() {
        stopEditing()
        undoManagerProvider?()?.undo()
    }

    private func restoreGeometry(_ id: UUID, annotation: PDFAnnotation, bounds: CGRect) {
        guard let current = highlights[id], let page = current.page,
              let index = comments.firstIndex(where: { $0.id == id }) else { return }
        let redo = geometrySnapshot(for: id) ?? current
        let redoBounds = redo.bounds
        page.removeAnnotation(current)
        annotation.bounds = bounds
        annotation.contents = comments[index].text
        page.addAnnotation(annotation)
        highlights[id] = annotation
        comments[index].bounds = (annotation as? PageCommentAnnotation)?.geometry.card ?? bounds
        layoutRevision += 1
        pdfManager?.noteVisibleEdit(on: page)
        undoManagerProvider?()?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.restoreGeometry(id, annotation: redo, bounds: redoBounds) }
        }
    }

    func updateComment(_ id: UUID, text: String) {
        guard let index = comments.firstIndex(where: { $0.id == id }) else {
            return
        }

        guard let highlight = highlights[id] else {
            logger.error("Orphaned comment missing highlight for ID \(id.uuidString, privacy: .public)")
            removeOrphanedComment(at: index, id: id)
            return
        }

        comments[index].text = text
        highlight.contents = text
        layoutRevision += 1
        pdfManager?.isDirty = true
    }

    func deleteComment(_ id: UUID) {
        guard let index = comments.firstIndex(where: { $0.id == id }),
              let highlight = highlights[id] else {
            return
        }

        let comment = comments[index]
        let page = highlight.page

        page?.removeAnnotation(highlight)

        comments.remove(at: index)
        highlights.removeValue(forKey: id)

        if selectedCommentID == id { selectedCommentID = nil }
        if editingCommentID == id { editingCommentID = nil }
        pdfManager?.noteVisibleEdit(on: page)

        if let page {
            registerUndoDelete(comment, highlight: highlight, page: page)
        }
    }

    func selectComment(_ id: UUID?) {
        stopEditing()
        selectedCommentID = id

        guard let id,
              let comment = comments.first(where: { $0.id == id }) else {
            return
        }

        editingCommentID = id
        editingOriginalText = comment.text
        // Jump to the comment's location on its page, not just the page top.
        if let highlight = highlights[id], let page = highlight.page {
            if isAnnotationVisible?(highlight) == true { return }
            let pageBounds = page.bounds(for: .mediaBox)
            let bounds = highlight.bounds
            // A little headroom above the highlight so it isn't flush to the top edge.
            let y = min(bounds.maxY + DesignTokens.spacingLG, pageBounds.maxY)
            // Use the highlight's own x (not the page's left edge) so a right-side
            // comment stays on screen when the page is wider than the viewport (zoom).
            let destination = PDFDestination(page: page, at: CGPoint(x: bounds.minX, y: y))
            pdfManager?.goToDestination(destination)
        } else {
            pdfManager?.goToPage(comment.pageIndex)
        }
    }

    func selectAnnotation(_ annotation: PDFAnnotation) -> Bool {
        guard let match = highlights.first(where: { $0.value === annotation }) else {
            return false
        }

        selectComment(match.key)
        return true
    }

    func stopEditing() {
        if let id = editingCommentID, let original = editingOriginalText,
           let comment = comments.first(where: { $0.id == id }) {
            if original != comment.text { registerTextUndo(id, previous: original) }
            if let annotation = highlights[id], annotation.type == "FreeText", let page = annotation.page {
                let available = page.bounds(for: .cropBox)
                let card = cardBounds(for: id) ?? annotation.bounds
                let height = (comment.text as NSString).boundingRect(
                    with: CGSize(width: max(1, card.width - 24 * CommentCardMetrics.scale), height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: annotation.font ?? NSFont.systemFont(ofSize: CommentCardMetrics.bodyFontSize)]).height + 48 * CommentCardMetrics.scale
                if height > card.height {
                    let needed = min(height, available.height)
                    setBounds(id, bounds: CGRect(x: card.minX, y: card.maxY - needed,
                                                 width: card.width, height: needed))
                }
                overflowMessage = height > available.height ? "This comment is too long. Widen the card to show all text in the saved PDF." : nil
            }
        }
        editingOriginalText = nil
        editingCommentID = nil
        selectedCommentID = nil
    }

    private func registerTextUndo(_ id: UUID, previous: String) {
        undoManagerProvider?()?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                guard let current = target.comments.first(where: { $0.id == id })?.text else { return }
                target.updateComment(id, text: previous)
                target.registerTextUndo(id, previous: current)
            }
        }
        undoManagerProvider?()?.setActionName("Edit Comment")
    }

    func commentID(for annotation: PDFAnnotation) -> UUID? {
        annotation.userName.flatMap { UUID(uuidString: $0) }
    }

    func updateCommentColor(_ id: UUID, color: NSColor) {
        guard let highlight = highlights[id] else { return }
        let previousColor = highlight.color
        guard previousColor != color else { return }

        highlight.color = color
        (highlight as? PageCommentAnnotation)?.recordColor()
        if highlight.type == "FreeText" { highlight.fontColor = Self.textColor(on: color) }
        layoutRevision += 1
        pdfManager?.noteVisibleEdit(on: highlight.page)

        if let undoManager = getUndoManager(for: "Change Comment Color") {
            undoManager.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.updateCommentColor(id, color: previousColor)
                }
            }
            undoManager.setActionName("Change Comment Color")
        }
    }

    // MARK: - Document Loading

    func loadComments(from document: PDFDocument) {
        comments.removeAll()
        highlights.removeAll()
        selectedCommentID = nil
        editingCommentID = nil
        editingOriginalText = nil
        overflowMessage = nil

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            let commentHighlights = page.annotations.filter(isCommentHighlight)

            for original in commentHighlights {
                let highlight: PDFAnnotation
                if original.type == "FreeText" {
                    let restored = PageCommentAnnotation.restoring(original)
                    if !restored.hasGeometry { restored.setGeometry(CommentGeometry.initial(card: clamped(original.bounds, on: page), page: page.bounds(for: .cropBox))) }
                    highlight = restored
                    page.removeAnnotation(original)
                    page.addAnnotation(highlight)
                } else { highlight = original }
                let existingUUID = highlight.userName.flatMap { UUID(uuidString: $0) }
                let commentID = existingUUID ?? UUID()
                if existingUUID == nil {
                    // Regenerating UUID for comment with missing/invalid userName
                    highlight.userName = commentID.uuidString
                }

                let model = CommentModel(
                    id: commentID,
                    text: highlight.contents ?? "",
                    pageIndex: pageIndex,
                    bounds: (highlight as? PageCommentAnnotation)?.geometry.card ?? highlight.bounds,
                    createdAt: highlight.modificationDate ?? Date()
                )

                comments.append(model)
                highlights[commentID] = highlight
            }
        }
    }

    func clearComments() {
        comments.removeAll()
        highlights.removeAll()
        selectedCommentID = nil
        editingCommentID = nil
        editingOriginalText = nil
        overflowMessage = nil
    }

    func reconcilePageIndices() {
        guard let document = pdfManager?.document else { return }

        var updatedComments: [CommentModel] = []
        var updatedHighlights: [UUID: PDFAnnotation] = [:]
        var orphanedPairs: [(CommentModel, PDFAnnotation)] = []

        for comment in comments {
            guard let highlight = highlights[comment.id] else { continue }

            if let page = highlight.page {
                let pageIndex = document.index(for: page)
                if pageIndex != NSNotFound {
                    var updatedComment = comment
                    updatedComment.pageIndex = pageIndex
                    updatedComment.bounds = (highlight as? PageCommentAnnotation)?.geometry.card ?? highlight.bounds
                    updatedComments.append(updatedComment)
                    updatedHighlights[comment.id] = highlight
                    continue
                }
            }

            orphanedPairs.append((comment, highlight))
        }

        if let selectedCommentID, updatedHighlights[selectedCommentID] == nil {
            self.selectedCommentID = nil
        }

        if let editingCommentID, updatedHighlights[editingCommentID] == nil {
            self.editingCommentID = nil
        }

        comments = updatedComments
        highlights = updatedHighlights

        // Register undo for orphaned comments so they restore when the page returns.
        if !orphanedPairs.isEmpty, let undoManager = undoManagerProvider?() {
            undoManager.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.restoreCommentsForUndo(orphanedPairs)
                }
            }
        }
    }

    private func restoreCommentsForUndo(_ pairs: [(CommentModel, PDFAnnotation)]) {
        let document = pdfManager?.document

        for (comment, highlight) in pairs {
            var restored = comment
            if let document, let page = highlight.page {
                let pageIndex = document.index(for: page)
                if pageIndex != NSNotFound {
                    restored.pageIndex = pageIndex
                    restored.bounds = (highlight as? PageCommentAnnotation)?.geometry.card ?? highlight.bounds
                }
            }
            comments.append(restored)
            highlights[comment.id] = highlight
        }

        if let undoManager = undoManagerProvider?() {
            undoManager.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.removeCommentsForRedo(pairs)
                }
            }
        }
    }

    private func removeCommentsForRedo(_ pairs: [(CommentModel, PDFAnnotation)]) {
        let idsToRemove = Set(pairs.map { $0.0.id })
        comments.removeAll { idsToRemove.contains($0.id) }
        highlights = highlights.filter { !idsToRemove.contains($0.key) }

        if let selectedCommentID, idsToRemove.contains(selectedCommentID) {
            self.selectedCommentID = nil
        }
        if let editingCommentID, idsToRemove.contains(editingCommentID) {
            self.editingCommentID = nil
        }

        if let undoManager = undoManagerProvider?() {
            undoManager.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.restoreCommentsForUndo(pairs)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func isCommentHighlight(_ annotation: PDFAnnotation) -> Bool {
        guard annotation.type == "Highlight" ||
              annotation.type == "FreeText" else { return false }

        // Primary: userName is a valid UUID (created by PaperLens)
        if let userName = annotation.userName, UUID(uuidString: userName) != nil {
            return true
        }

        // Secondary: the annotation carries the frozen "PageFlowType" marker
        if let flowType = annotation.value(forAnnotationKey: Self.commentMarkerKey) as? String,
           flowType == Self.commentMarkerValue {
            return true
        }

        // Legacy fallback: color match for pre-fix saved files (only if userName is nil/empty)
        let hasUserName = annotation.userName.map { !$0.isEmpty } ?? false
        guard !hasUserName else { return false }

        guard let color = annotation.color.usingColorSpace(.deviceRGB),
              let target = DesignTokens.commentHighlightColor.usingColorSpace(.deviceRGB) else {
            return false
        }

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        target.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)

        let tolerance: CGFloat = 0.1
        return abs(r - tr) < tolerance &&
            abs(g - tg) < tolerance &&
            abs(b - tb) < tolerance &&
            abs(a - ta) < 0.15
    }

    private func removeOrphanedComment(at index: Int, id: UUID) {
        comments.remove(at: index)
        highlights.removeValue(forKey: id)

        if selectedCommentID == id {
            selectedCommentID = nil
        }
        if editingCommentID == id {
            editingCommentID = nil
        }
    }

    // MARK: - Undo/Redo

    private func registerUndoAdd(_ comment: CommentModel, highlight: PDFAnnotation, page: PDFPage) {
        guard let undoManager = getUndoManager(for: "Add Comment") else { return }

        undoManager.registerUndo(withTarget: self) { [highlight, page] target in
            MainActor.assumeIsolated {
                target.undoAdd(comment, highlight: highlight, page: page)
            }
        }
        undoManager.setActionName("Add Comment")
    }

    private func undoAdd(_ comment: CommentModel, highlight: PDFAnnotation, page: PDFPage) {
        // Capture current text before removing (user may have edited since creation)
        let currentText = comments.first { $0.id == comment.id }?.text ?? comment.text
        let updatedComment = CommentModel(
            id: comment.id,
            text: currentText,
            pageIndex: comment.pageIndex,
            bounds: comment.bounds,
            createdAt: comment.createdAt
        )

        let liveAnnotation = highlights[comment.id] ?? highlight
        liveAnnotation.page?.removeAnnotation(liveAnnotation)
        comments.removeAll { $0.id == comment.id }
        highlights.removeValue(forKey: comment.id)
        if selectedCommentID == comment.id { selectedCommentID = nil }
        if editingCommentID == comment.id { editingCommentID = nil }
        pdfManager?.noteVisibleEdit(on: page)

        guard let undoManager = getUndoManager(for: "Add Comment") else { return }
        undoManager.registerUndo(withTarget: self) { [page] target in
            MainActor.assumeIsolated {
                target.redoAdd(updatedComment, highlight: liveAnnotation, page: page)
            }
        }
        undoManager.setActionName("Add Comment")
    }

    private func redoAdd(_ comment: CommentModel, highlight: PDFAnnotation, page: PDFPage) {
        page.addAnnotation(highlight)
        highlight.contents = comment.text
        comments.append(comment)
        highlights[comment.id] = highlight
        pdfManager?.noteVisibleEdit(on: page)

        registerUndoAdd(comment, highlight: highlight, page: page)
    }

    private func registerUndoDelete(_ comment: CommentModel, highlight: PDFAnnotation, page: PDFPage) {
        guard let undoManager = getUndoManager(for: "Delete Comment") else { return }

        undoManager.registerUndo(withTarget: self) { [highlight, page] target in
            MainActor.assumeIsolated {
                target.undoDelete(comment, highlight: highlight, page: page)
            }
        }
        undoManager.setActionName("Delete Comment")
    }

    private func undoDelete(_ comment: CommentModel, highlight: PDFAnnotation, page: PDFPage) {
        page.addAnnotation(highlight)
        highlight.contents = comment.text
        comments.append(comment)
        highlights[comment.id] = highlight
        pdfManager?.noteVisibleEdit(on: page)

        guard let undoManager = getUndoManager(for: "Delete Comment") else { return }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.deleteComment(comment.id)
            }
        }
        undoManager.setActionName("Delete Comment")
    }
}
