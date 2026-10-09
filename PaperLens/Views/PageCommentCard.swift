import AppKit
import PDFKit
import QuartzCore

/// Native page overlays use PDFView's coordinate conversion so rotation and zoom
/// share the same geometry as the annotations written into the file.
@MainActor
extension StablePDFView {
    func syncCommentOverlays() {
        guard let manager = pageCommentManager, let document else { return }
        window?.invalidateCursorRects(for: self)
        let ids = Set(manager.comments.map(\.id))
        for id in Array(commentMarkers.keys) where !ids.contains(id) {
            commentMarkers.removeValue(forKey: id)?.removeFromSuperview()
        }
        for comment in manager.comments {
            guard let page = document.page(at: comment.pageIndex) else { continue }
            let marker = commentMarkers[comment.id] ?? CommentMarker()
            if marker.superview == nil {
                addSubview(marker)
                commentMarkers[comment.id] = marker
                marker.actionHandler = { [weak manager] in manager?.toggleComment(comment.id) }
            }
            let pageMarker = manager.markerBounds(for: comment.id) ?? comment.bounds
            let visual = convert(pageMarker, from: page)
            let hitSize = CGSize(width: max(32, visual.width), height: max(32, visual.height))
            marker.frame = CGRect(x: visual.midX - hitSize.width / 2, y: visual.midY - hitSize.height / 2,
                                  width: hitSize.width, height: hitSize.height)
            marker.visualSize = visual.size
            marker.contentTintColor = manager.annotation(for: comment.id)?.color.withAlphaComponent(1)
            marker.isEditing = manager.editingCommentID == comment.id
            marker.needsDisplay = true
            marker.toolTip = comment.text.isEmpty ? "Edit comment" : comment.text
            marker.isHidden = !bounds.intersects(marker.frame)
            marker.configureDrag(manager: manager, pdfView: self, id: comment.id)
        }
        if let id = manager.editingCommentID, let model = manager.comments.first(where: { $0.id == id }),
           let page = document.page(at: model.pageIndex), let rect = manager.cardBounds(for: id) {
            let newCard = pageCommentCard?.commentID != id
            if newCard {
                pageCommentCard?.animateClose()
                let card = PageCommentCard(id: id, text: model.text)
                card.manager = manager
                card.pdfView = self
                pageCommentCard = card
                addSubview(card)
            }
            let cardFrame = convert(rect, from: page)
            let markerFrame = convert(manager.markerBounds(for: id) ?? rect, from: page)
            if pageCommentCard?.frame != cardFrame { pageCommentCard?.frame = cardFrame }
            pageCommentCard?.anchorPoint = CGPoint(x: markerFrame.midX, y: markerFrame.midY)
            pageCommentCard?.updateConnector(marker: markerFrame)
            if let marker = commentMarkers[id] {
                addSubview(marker, positioned: .above, relativeTo: pageCommentCard)
            }
            if newCard { pageCommentCard?.animateOpen() }
            pageCommentCard?.updateText(model.text, scale: CGFloat(scaleFactor))
            if let color = manager.annotation(for: id)?.color {
                pageCommentCard?.layer?.backgroundColor = CommentManager.cardColor(for: color).cgColor
                pageCommentCard?.editor.textColor = CommentManager.textColor(on: color)
                pageCommentCard?.updateTitleColor(CommentManager.textColor(on: color).withAlphaComponent(0.55))
                pageCommentCard?.layer?.borderColor = NSColor.black.withAlphaComponent(0.20).cgColor
            }
        } else {
            pageCommentCard?.animateClose()
            pageCommentCard = nil
        }
    }

    @objc func commentViewportChanged(_ notification: Notification) { syncCommentOverlays() }

    func observeCommentViewport() {
        NotificationCenter.default.removeObserver(self, name: .PDFViewScaleChanged, object: self)
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(commentViewportChanged(_:)),
                                               name: .PDFViewScaleChanged, object: self)
        if let clip = documentScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(commentViewportChanged(_:)),
                                                   name: NSView.boundsDidChangeNotification, object: clip)
        }
    }
}

@MainActor
private final class CommentConnector: NSView {
    var path: CGPath?
    var color = NSColor.gray
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let path, let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(path)
        context.setStrokeColor(color.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(1.5 * ((superview as? StablePDFView)?.scaleFactor ?? 1))
        context.setLineCap(.round); context.strokePath()
    }
}

@MainActor
final class CommentMarker: NSButton {
    var actionHandler: (() -> Void)?
    var visualSize = CGSize(width: 8, height: 8)
    var isEditing = false
    override func draw(_ dirtyRect: NSRect) {
        let rect = CGRect(x: bounds.midX - visualSize.width / 2, y: bounds.midY - visualSize.height / 2,
                          width: visualSize.width, height: visualSize.height)
        if let context = NSGraphicsContext.current?.cgContext {
            PageCommentAnnotation.drawMarker(in: rect, color: contentTintColor ?? .gray, context: context)
        }
    }
    private weak var manager: CommentManager?
    private weak var pdfView: StablePDFView?
    private var commentID: UUID?
    private var origin = CGPoint.zero
    private var originalBounds = CGRect.zero
    private var originalAnnotation: PDFAnnotation?
    private var originalAnnotationBounds = CGRect.zero
    private var dragged = false
    func configureDrag(manager: CommentManager, pdfView: StablePDFView, id: UUID) {
        self.manager = manager; self.pdfView = pdfView; commentID = id
    }
    init() {
        super.init(frame: .zero)
        setAccessibilityLabel("Toggle comment")
        contentTintColor = .gray
        bezelStyle = .circular
        isBordered = false
        target = self
        action = #selector(activate)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    @objc private func activate() { actionHandler?() }
    override func mouseDown(with event: NSEvent) {
        origin = event.locationInWindow
        originalBounds = commentID.flatMap { manager?.markerBounds(for: $0) } ?? .zero
        originalAnnotation = commentID.flatMap { manager?.geometrySnapshot(for: $0) }
        originalAnnotationBounds = originalAnnotation?.bounds ?? originalBounds
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let delta = CGPoint(x: event.locationInWindow.x - origin.x, y: event.locationInWindow.y - origin.y)
        guard hypot(delta.x, delta.y) > 3, let id = commentID, let pdfView,
              let manager, let page = manager.annotation(for: id)?.page else { return }
        dragged = true
        let next = pdfView.convert(originalBounds, from: page).offsetBy(dx: delta.x, dy: delta.y)
        manager.setMarkerBounds(id, bounds: pdfView.convert(next, to: page), registerUndo: false)
        pdfView.syncCommentOverlays()
    }
    override func mouseUp(with event: NSEvent) {
        if dragged, let id = commentID, let originalAnnotation {
            manager?.commitGeometry(id, previousAnnotation: originalAnnotation, previousBounds: originalAnnotationBounds)
        } else { actionHandler?() }
    }
}

/// Screen-sized target around the page-space connector endpoint.
@MainActor
final class CommentConnectionHandle: NSView {
    private weak var manager: CommentManager?
    private weak var pdfView: StablePDFView?
    private var id: UUID?
    private var origin = CGPoint.zero
    private var snapshot: PDFAnnotation?
    private var dragged = false
    func configure(manager: CommentManager, pdfView: StablePDFView, id: UUID) {
        self.manager = manager; self.pdfView = pdfView; self.id = id
        toolTip = "Drag to choose a connection point on the card border"
        setAccessibilityLabel("Comment connection point")
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        let dot = CGRect(x: bounds.midX - 3.5, y: bounds.midY - 3.5, width: 7, height: 7)
        let path = NSBezierPath(ovalIn: dot)
        NSColor.white.setFill(); path.fill()
        NSColor.black.setStroke(); path.lineWidth = 1.2; path.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        origin = event.locationInWindow
        snapshot = id.flatMap { manager?.geometrySnapshot(for: $0) }
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) > 3,
              let id, let manager, let pdfView, let page = manager.annotation(for: id)?.page else { return }
        dragged = true
        let screenPoint = pdfView.convert(event.locationInWindow, from: nil)
        manager.setConnectionPoint(id, point: pdfView.convert(screenPoint, to: page), registerUndo: false)
        pdfView.syncCommentOverlays()
    }
    override func mouseUp(with event: NSEvent) {
        if dragged, let id, let snapshot {
            manager?.commitGeometry(id, previousAnnotation: snapshot, previousBounds: snapshot.bounds)
        }
        snapshot = nil
    }
}

@MainActor
final class CommentDoneButton: NSButton {
    private var hoverTracking: NSTrackingArea?
    private var hovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero,
                                      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        let pressed = cell?.isHighlighted == true
        let emphasis = isEnabled && (hovered || pressed)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if emphasis, let context = NSGraphicsContext.current?.cgContext {
            let scale: CGFloat = pressed ? 0.96 : 1.04
            context.translateBy(x: bounds.midX, y: bounds.midY)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.midX, y: -bounds.midY)
            let color = contentTintColor ?? .gray
            color.withAlphaComponent(pressed ? 0.16 : 0.09).setFill()
            let inset = bounds.insetBy(dx: 0, dy: bounds.height * 0.12)
            NSBezierPath(roundedRect: inset, xRadius: 4, yRadius: 4).fill()
        }
        super.draw(dirtyRect)
    }
}

@MainActor
final class PageCommentCard: NSView, NSTextViewDelegate {
    let commentID: UUID
    weak var manager: CommentManager?
    weak var pdfView: StablePDFView?
    private let scroll = NSScrollView()
    let editor = CardTextView()
    private let header = CardHandle()
    private let resize = CardHandle()
    private let done = CommentDoneButton(title: "Done", target: nil, action: nil)
    private let more = NSButton()
    private let leftEdge = CardHandle()
    private let rightEdge = CardHandle()
    private let bottomEdge = CardHandle()
    private let divider = NSView()
    private let title = NSTextField(labelWithString: "Comment")
    private var originalBounds = CGRect.zero
    private var originalAnnotation: PDFAnnotation?
    private var originalAnnotationBounds = CGRect.zero
    private var gestureChanged = false
    override var isFlipped: Bool { true }

    init(id: UUID, text: String) {
        commentID = id
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 8 * CommentCardMetrics.scale
        layer?.borderColor = NSColor.black.withAlphaComponent(0.20).cgColor
        layer?.borderWidth = 1
        layer?.shadowOpacity = 0.08
        layer?.shadowRadius = 5
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        title.font = .systemFont(ofSize: 10, weight: .regular)
        title.textColor = .gray
        title.isSelectable = false
        header.addSubview(title)
        addSubview(header)
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        addSubview(divider)
        done.imagePosition = .noImage
        done.isBordered = false
        done.contentTintColor = title.textColor
        done.toolTip = "Done"
        done.setAccessibilityLabel("Done")
        done.bezelStyle = .regularSquare
        done.target = self
        done.action = #selector(finish)
        addSubview(done)
        more.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Comment actions")
        more.imagePosition = .imageOnly
        more.bezelStyle = .regularSquare
        more.isBordered = false
        more.toolTip = "Comment actions"
        more.target = self
        more.action = #selector(showMenu)
        addSubview(more)
        editor.string = text
        editor.delegate = self
        editor.isEditable = true
        editor.isSelectable = true
        editor.isRichText = false
        editor.allowsUndo = false
        editor.undoAction = { [weak self] in
            self?.manager?.undoEditing()
            self?.pdfView?.syncCommentOverlays()
        }
        editor.drawsBackground = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.containerSize = CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = CGSize(width: 4 * CommentCardMetrics.scale, height: 6 * CommentCardMetrics.scale)
        scroll.documentView = editor
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        addSubview(scroll)
        resize.resizeCursor = true
        resize.showsGrip = true
        resize.toolTip = "Drag to resize comment"
        addSubview(resize)
        for edge in [leftEdge, rightEdge, bottomEdge] {
            edge.resizeCursor = true
            edge.toolTip = "Drag to resize comment"
            addSubview(edge)
            edge.begin = { [weak self] in self?.beginGeometry() }
            edge.end = { [weak self] in self?.endGeometry() }
        }
        leftEdge.drag = { [weak self] delta in self?.dragEdge(delta, edge: 0) }
        rightEdge.drag = { [weak self] delta in self?.dragEdge(delta, edge: 1) }
        bottomEdge.drag = { [weak self] delta in self?.dragEdge(delta, edge: 2) }
        header.begin = { [weak self] in self?.beginGeometry() }
        resize.begin = header.begin
        header.drag = { [weak self] delta in self?.dragGeometry(delta, resizing: false) }
        resize.drag = { [weak self] delta in self?.dragGeometry(delta, resizing: true) }
        header.end = { [weak self] in self?.endGeometry() }
        resize.end = header.end
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var anchorPoint = CGPoint.zero
    private let connector = CommentConnector()
    private let connectionHandle = CommentConnectionHandle()
    private var outsideClickMonitor: Any?
    private var closing = false

    func updateConnector(marker: CGRect) {
        guard let parent = superview else { return }
        if connector.superview == nil { parent.addSubview(connector, positioned: .below, relativeTo: self) }
        connector.frame = parent.bounds
        if let pdfView, let manager, let page = manager.annotation(for: commentID)?.page,
           let card = manager.cardBounds(for: commentID), let savedMarker = manager.markerBounds(for: commentID) {
            let origin = pdfView.convert(CGPoint.zero, from: page)
            let x = pdfView.convert(CGPoint(x: 1, y: 0), from: page)
            let y = pdfView.convert(CGPoint(x: 0, y: 1), from: page)
            var transform = CGAffineTransform(a: x.x - origin.x, b: x.y - origin.y,
                                              c: y.x - origin.x, d: y.y - origin.y, tx: origin.x, ty: origin.y)
            let attachment = (manager.annotation(for: commentID) as? PageCommentAnnotation)?.geometry.attachment
            let connection = CommentConnection(marker: savedMarker, card: card, attachment: attachment)
            connector.path = connection.path?.copy(using: &transform)
            let endpoint = connection.endpoint.applying(transform)
            connectionHandle.frame = CGRect(x: endpoint.x - 12, y: endpoint.y - 12, width: 24, height: 24)
            connectionHandle.configure(manager: manager, pdfView: pdfView, id: commentID)
            if connectionHandle.superview == nil { parent.addSubview(connectionHandle, positioned: .above, relativeTo: self) }
        } else { connector.path = nil }
        connector.color = CommentManager.connectionColor(for: manager?.annotation(for: commentID)?.color ?? .white)
        connector.needsDisplay = true
    }

    private func removeOutsideMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        closing ? nil : super.hitTest(point)
    }

    func animateOpen() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer else { return }
        let expand = CASpringAnimation(keyPath: "transform")
        expand.fromValue = CATransform3DMakeScale(0.94, 0.94, 1)
        expand.toValue = CATransform3DIdentity
        expand.damping = 30
        expand.stiffness = 380
        expand.duration = 0.24
        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = CGPoint(x: layer.position.x + (anchorPoint.x - frame.midX) * 0.06,
                                     y: layer.position.y + (anchorPoint.y - frame.midY) * 0.06)
        position.toValue = layer.position
        position.duration = 0.2
        position.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.15
        layer.add(expand, forKey: "comment.expand")
        layer.add(position, forKey: "comment.position")
        layer.add(fade, forKey: "comment.fade")
    }

    func animateClose() {
        guard !closing else { return }
        closing = true
        removeOutsideMonitor()
        connector.removeFromSuperview(); connectionHandle.removeFromSuperview()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer else {
            removeFromSuperview(); return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.removeFromSuperview() }
        let shrink = CABasicAnimation(keyPath: "transform")
        shrink.fromValue = layer.presentation()?.transform ?? CATransform3DIdentity
        shrink.toValue = CATransform3DMakeScale(0.94, 0.94, 1)
        shrink.duration = 0.16
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = layer.presentation()?.position ?? layer.position
        position.toValue = CGPoint(x: layer.position.x + (anchorPoint.x - frame.midX) * 0.06,
                                   y: layer.position.y + (anchorPoint.y - frame.midY) * 0.06)
        position.duration = 0.16
        position.fillMode = .forwards
        position.isRemovedOnCompletion = false
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.16
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        layer.add(shrink, forKey: "comment.collapse")
        layer.add(position, forKey: "comment.position")
        layer.add(fade, forKey: "comment.fade")
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeOutsideMonitor()
        guard window != nil else { connector.removeFromSuperview(); connectionHandle.removeFromSuperview(); return }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, !self.closing, event.window === self.window, let parent = self.superview else { return event }
            let point = parent.convert(event.locationInWindow, from: nil)
            let hit = parent.hitTest(point)
            if hit === self || hit?.isDescendant(of: self) == true || hit is CommentMarker || hit is CommentConnectionHandle { return event }
            self.manager?.updateComment(self.commentID, text: self.editor.string)
            self.manager?.stopEditing()
            self.pdfView?.syncCommentOverlays()
            return event
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, !self.closing else { return }
            self.window?.makeFirstResponder(self.editor)
        }
    }
    func updateTitleColor(_ color: NSColor) {
        title.textColor = color
        done.contentTintColor = color
    }

    override func layout() {
        super.layout()
        let scale = CGFloat(pdfView?.scaleFactor ?? 1) * CommentCardMetrics.scale
        layer?.cornerRadius = 8 * scale
        editor.textContainerInset = CGSize(width: 4 * scale, height: 6 * scale)
        editor.textContainer?.lineFragmentPadding = 5 * scale
        let headerHeight = 24 * scale
        let headerCenterY = 16 * scale
        // Typography and action widths stay in screen points, independently of card size and PDF zoom.
        title.font = .systemFont(ofSize: 10, weight: .regular)
        done.font = title.font
        more.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        more.frame = CGRect(x: bounds.width - 10 * scale - 12, y: headerCenterY - headerHeight / 2,
                            width: 12, height: headerHeight)
        done.frame = CGRect(x: more.frame.minX - 4 * scale - 28, y: more.frame.minY,
                            width: 28, height: headerHeight)
        header.frame = CGRect(x: 10 * scale, y: more.frame.minY,
                              width: max(0, done.frame.minX - 14 * scale), height: headerHeight)
        let titleHeight = title.fittingSize.height
        title.frame = CGRect(x: 4 * scale, y: (headerHeight - titleHeight) / 2,
                             width: max(0, header.bounds.width - 4 * scale), height: titleHeight)
        divider.frame = CGRect(x: 12 * scale, y: 27 * scale, width: max(1, bounds.width - 24 * scale), height: 0.5 * scale)
        scroll.frame = CGRect(x: 12 * scale, y: 34 * scale, width: max(1, bounds.width - 24 * scale), height: max(1, bounds.height - 44 * scale))
        editor.setFrameSize(CGSize(width: scroll.contentSize.width, height: max(scroll.contentSize.height, editor.frame.height)))
        leftEdge.frame = CGRect(x: 0, y: 34 * scale, width: 8 * scale, height: max(0, bounds.height - 60 * scale))
        rightEdge.frame = CGRect(x: bounds.width - 8 * scale, y: 34 * scale, width: 8 * scale, height: max(0, bounds.height - 60 * scale))
        bottomEdge.frame = CGRect(x: 12 * scale, y: bounds.height - 8 * scale, width: max(0, bounds.width - 40 * scale), height: 8 * scale)
        resize.frame = CGRect(x: bounds.width - 24 * scale, y: bounds.height - 24 * scale, width: 24 * scale, height: 24 * scale)
    }

    func updateText(_ text: String, scale: CGFloat) {
        if editor.string != text && !editor.hasMarkedText() { editor.string = text }
        // Editor typography stays independent of both card proportions and PDF zoom.
        editor.font = .systemFont(ofSize: CommentCardMetrics.bodyFontSize)
        needsLayout = true
    }
    func textDidChange(_ notification: Notification) { manager?.updateComment(commentID, text: editor.string) }
    @objc private func finish() {
        manager?.updateComment(commentID, text: editor.string)
        manager?.stopEditing()
        pdfView?.syncCommentOverlays()
        pdfView?.window?.makeFirstResponder(pdfView)
    }
    @objc private func showMenu() {
        let menu = NSMenu()
        for (index, preset) in SettingsManager.shared.commentPresets.enumerated() {
            let item = NSMenuItem(title: preset.name, action: #selector(colorAction(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let automatic = NSMenuItem(title: "Restore Automatic Connection", action: #selector(restoreConnection), keyEquivalent: "")
        automatic.target = self
        automatic.isEnabled = (manager?.annotation(for: commentID) as? PageCommentAnnotation)?.geometry.attachment != nil
        menu.addItem(automatic)
        menu.addItem(.separator())
        let delete = NSMenuItem(title: "Delete Comment", action: #selector(deleteAction), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: more.bounds.maxY), in: more)
    }
    @objc private func colorAction(_ sender: NSMenuItem) {
        let presets = SettingsManager.shared.commentPresets
        guard presets.indices.contains(sender.tag) else { return }
        manager?.chooseCommentColor(presets[sender.tag].color)
        pdfView?.syncCommentOverlays()
    }
    @objc private func restoreConnection() {
        manager?.setConnectionPoint(commentID, point: nil)
        pdfView?.syncCommentOverlays()
    }
    @objc private func deleteAction() {
        manager?.deleteComment(commentID)
        pdfView?.syncCommentOverlays()
    }
    private func dragEdge(_ delta: CGPoint, edge: Int) {
        guard let pdfView, let manager, let page = manager.annotation(for: commentID)?.page else { return }
        var next = pdfView.convert(originalBounds, from: page)
        switch edge {
        case 0: next.origin.x += delta.x; next.size.width -= delta.x
        case 1: next.size.width += delta.x
        default: next.origin.y += delta.y; next.size.height -= delta.y
        }
        next.size.width = max(1, next.width)
        next.size.height = max(1, next.height)
        manager.setBounds(commentID, bounds: pdfView.convert(next, to: page), registerUndo: false)
        gestureChanged = true
        pdfView.syncCommentOverlays()
    }
    private func beginGeometry() {
        originalBounds = manager?.cardBounds(for: commentID) ?? .zero
        originalAnnotation = manager?.geometrySnapshot(for: commentID)
        originalAnnotationBounds = originalAnnotation?.bounds ?? originalBounds
        gestureChanged = false
    }
    private func dragGeometry(_ delta: CGPoint, resizing: Bool) {
        guard let pdfView, let manager, let annotation = manager.annotation(for: commentID), let page = annotation.page else { return }
        var next = pdfView.convert(originalBounds, from: page)
        if resizing { next.size.width += delta.x; next.origin.y += delta.y; next.size.height -= delta.y }
        else { next.origin.x += delta.x; next.origin.y += delta.y }
        next.size.width = max(1, next.width)
        next.size.height = max(1, next.height)
        manager.setBounds(commentID, bounds: pdfView.convert(next, to: page), registerUndo: false)
        gestureChanged = true
        pdfView.syncCommentOverlays()
    }
    private func endGeometry() {
        guard gestureChanged, let manager, let originalAnnotation else { return }
        manager.commitGeometry(commentID, previousAnnotation: originalAnnotation, previousBounds: originalAnnotationBounds)
    }
}

@MainActor
private final class CardHandle: NSView {
    var begin: (() -> Void)?
    var drag: ((CGPoint) -> Void)?
    var end: (() -> Void)?
    var resizeCursor = false
    var showsGrip = false
    private var origin = CGPoint.zero
    override func resetCursorRects() { addCursorRect(bounds, cursor: resizeCursor ? .crosshair : .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        if showsGrip {
            NSColor.secondaryLabelColor.withAlphaComponent(0.6).setStroke()
            let path = NSBezierPath()
            let scale = bounds.width / 24
            path.lineWidth = scale
            path.move(to: CGPoint(x: 10 * scale, y: 7 * scale)); path.line(to: CGPoint(x: 21 * scale, y: 18 * scale))
            path.move(to: CGPoint(x: 15 * scale, y: 7 * scale)); path.line(to: CGPoint(x: 21 * scale, y: 13 * scale))
            path.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) { origin = event.locationInWindow; begin?() }
    override func mouseDragged(with event: NSEvent) { drag?(CGPoint(x: event.locationInWindow.x - origin.x, y: event.locationInWindow.y - origin.y)) }
    override func mouseUp(with event: NSEvent) { end?() }
}

@MainActor
final class CardTextView: NSTextView {
    var undoAction: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift),
           event.charactersIgnoringModifiers == "z", !hasMarkedText() {
            undoAction?()
            return
        }
        super.keyDown(with: event)
    }
}
