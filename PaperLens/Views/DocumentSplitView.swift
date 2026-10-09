import SwiftUI
import AppKit

/// Native divider; resizing the window clamps the displayed width without losing
/// the tab's preferred width. Only a deliberate divider drag writes that preference.
struct DocumentSplitView<Sidebar: View, Reader: View>: NSViewRepresentable {
    let isSidebarVisible: Bool
    @Binding var sidebarWidth: CGFloat
    let sidebar: Sidebar
    let reader: Reader

    func makeNSView(context: Context) -> DocumentSplitNSView {
        let split = DocumentSplitNSView()
        let left = NSHostingView(rootView: sidebar)
        let right = NSHostingView(rootView: reader)
        left.sizingOptions = []; right.sizingOptions = []
        split.addArrangedSubview(left); split.addArrangedSubview(right)
        configure(split)
        return split
    }
    func updateNSView(_ split: DocumentSplitNSView, context: Context) {
        (split.arrangedSubviews[0] as? NSHostingView<Sidebar>)?.rootView = sidebar
        (split.arrangedSubviews[1] as? NSHostingView<Reader>)?.rootView = reader
        configure(split)
    }
    private func configure(_ split: DocumentSplitNSView) {
        // A drag owns the width until the mouse comes up; SwiftUI's re-render
        // still carries the pre-drag value, and writing it back mid-drag made
        // the divider snap away from the cursor.
        if !split.isDraggingDivider { split.preferredWidth = sidebarWidth }
        split.sidebarVisible = isSidebarVisible
        split.onWidthChange = { value in if abs(sidebarWidth - value) > 0.5 { sidebarWidth = value } }
        split.applyLayout()
    }
}

/// The sidebar/reader split, laid out by hand.
///
/// This deliberately does **not** subclass `NSSplitView` any more. macOS 26 gave
/// `NSSplitView` the `NSSplitViewSidebar` behaviour, whose `respondsToSelector:`
/// override loads a weak reference; when an `NSSplitView` that died while still
/// reachable from the responder chain is asked about a menu action, that load
/// faults and takes the app down (SIGSEGV in
/// `-[NSSplitView(NSSplitViewSidebar) respondsToSelector:]` → `objc_loadWeakRetained`
/// — the crash reported five times in ~/Library/Logs/DiagnosticReports). The
/// panes here are positioned explicitly anyway, so the split view's own
/// machinery only ever bought that failure mode.
final class DocumentSplitNSView: NSView {
    var preferredWidth: CGFloat = DesignTokens.outlineSidebarDefaultWidth {
        didSet { if !isDraggingDivider { applyLayout() } }
    }
    var sidebarVisible = false {
        didSet { if sidebarVisible != oldValue { applyLayout() } }
    }
    var onWidthChange: ((CGFloat) -> Void)?

    /// Panes, left (sidebar) then right (reader). Kept as a plain array so call
    /// sites read like the arranged-subview API this replaces.
    private(set) var arrangedSubviews: [NSView] = []
    let dividerThickness: CGFloat = 1
    /// True while the user is dragging the divider (see `DocumentSplitView.configure`).
    private(set) var isDraggingDivider = false

    /// Invisible grab area around the 1pt divider line.
    private static let dividerHitWidth: CGFloat = 13
    private let dividerHandle = DividerHandleView()
    private var isApplying = false
    /// Whether the current press actually moved the divider (so a bare click on
    /// the handle doesn't write a width back to the tab state).
    private var dragDidChangeWidth = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        dividerHandle.onDrag = { [weak self] x in self?.dragDivider(to: x) }
        dividerHandle.onDragEnd = { [weak self] in self?.endDividerDrag() }
        addSubview(dividerHandle)
        setAccessibilityLabel("Document sidebar divider")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func addArrangedSubview(_ view: NSView) {
        arrangedSubviews.append(view)
        // Manual frames need the autoresizing bridge, or AppKit's own layout
        // engine fights the positions `applyLayout` writes.
        view.translatesAutoresizingMaskIntoConstraints = true
        addSubview(view, positioned: .below, relativeTo: dividerHandle)
        applyLayout()
    }

    static func maximumSidebarWidth(totalWidth: CGFloat) -> CGFloat {
        max(0, min(DesignTokens.outlineSidebarMaxWidth, totalWidth - 320 - dividerInset))
    }

    /// A fixed 1pt divider plus the pane gap it implies.
    private static var dividerInset: CGFloat { 1 }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if !dividerHandle.isHidden, dividerHandle.frame.contains(local) {
            return dividerHandle
        }
        return super.hitTest(point)
    }

    override func layout() {
        super.layout()
        applyLayout()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyLayout()
    }

    func applyLayout() {
        guard arrangedSubviews.count == 2, !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        let left = arrangedSubviews[0], right = arrangedSubviews[1]
        left.isHidden = !sidebarVisible
        dividerHandle.isHidden = !sidebarVisible

        let maximum = Self.maximumSidebarWidth(totalWidth: bounds.width)
        let width = sidebarVisible
            ? DesignTokens.outlineSidebarWidth(preferredWidth, available: maximum)
            : 0
        let readerStart = width + (sidebarVisible ? dividerThickness : 0)

        left.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        right.frame = NSRect(x: readerStart, y: 0, width: max(0, bounds.width - readerStart), height: bounds.height)
        dividerHandle.frame = NSRect(
            x: max(0, width - (Self.dividerHitWidth - dividerThickness) / 2),
            y: 0,
            width: Self.dividerHitWidth,
            height: bounds.height
        )
    }

    /// Moves the divider to `position` (x of the divider in this view's
    /// coordinates), clamping to the sidebar limits. Mirrors
    /// `NSSplitView.setPosition(_:ofDividerAt:)` so the layout tests and any
    /// programmatic caller keep working.
    func setPosition(_ position: CGFloat, ofDividerAt index: Int) {
        dragDivider(to: position)
        endDividerDrag()
    }

    private func dragDivider(to x: CGFloat) {
        guard sidebarVisible, arrangedSubviews.count == 2 else { return }
        let maximum = Self.maximumSidebarWidth(totalWidth: bounds.width)
        let minimum = min(DesignTokens.outlineSidebarMinWidth, maximum)
        let width = min(maximum, max(minimum, x))
        guard abs(preferredWidth - width) > 0.5 else { return }
        isDraggingDivider = true
        dragDidChangeWidth = true
        preferredWidth = width
        applyLayout()
    }

    private func endDividerDrag() {
        let changed = dragDidChangeWidth
        isDraggingDivider = false
        dragDidChangeWidth = false
        guard changed, sidebarVisible, arrangedSubviews.count == 2 else { return }
        // Report the width the layout actually settled on, not the raw cursor x.
        let value = DesignTokens.outlineSidebarWidth(
            arrangedSubviews[0].frame.width,
            available: Self.maximumSidebarWidth(totalWidth: bounds.width)
        )
        preferredWidth = value
        let notify = onWidthChange
        DispatchQueue.main.async { notify?(value) }
    }
}

/// Transparent grab strip for the divider: drag to resize, resize cursor on hover.
private final class DividerHandleView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?

    private var hoverTrackingArea: NSTrackingArea?
    private var cursorMonitor: Any?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let cursorMonitor { NSEvent.removeMonitor(cursorMonitor) }
        cursorMonitor = nil
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        cursorMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .cursorUpdate]) { [weak self] event in
            guard let self, let window = self.window,
                  event.window === window, !self.isHiddenOrHasHiddenAncestor,
                  self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
            // SwiftUI/PDFKit can set their own cursor after a native tracking
            // callback. Reassert the divider cursor after this event finishes.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window,
                      window.isKeyWindow, !self.isHiddenOrHasHiddenAncestor,
                      self.bounds.contains(self.convert(window.mouseLocationOutsideOfEventStream, from: nil)) else { return }
                NSCursor.resizeLeftRight.set()
            }
            return event
        }
    }

    deinit {
        if let cursorMonitor { NSEvent.removeMonitor(cursorMonitor) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved,
                      .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    // Cursor updates run after mouse movement, so adjacent PDF/SwiftUI cursor
    // regions cannot immediately replace the divider's resize cursor.
    override func cursorUpdate(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.resizeLeftRight.set() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: (bounds.width - 1) / 2, y: 0, width: 1, height: bounds.height).fill()
    }

    override func mouseDown(with event: NSEvent) {
        // Swallow the press so the divider drag starts here and the panes
        // underneath never see it.
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
        guard let container = superview else { return }
        onDrag?(container.convert(event.locationInWindow, from: nil).x)
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnd?()
    }
}
