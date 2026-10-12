import AppKit
import SwiftUI

/// Geometry shared by native menu feedback, SwiftUI buttons and edge guards.
enum ChromeHitShape {
    static func contains(_ point: NSPoint, in bounds: NSRect) -> Bool {
        guard bounds.contains(point) else { return false }
        return NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2,
                            yRadius: bounds.height / 2).contains(point)
    }
}

/// The app-drawn chrome row answers which points belong to it. Blank chrome is
/// still titlebar space — it drags and zooms the window natively — while every
/// control, control boundary and control-group padding owns its own pixels.
protocol ChromeClickOwning: AnyObject {
    /// `point` is in window coordinates.
    func ownsChromeClick(atWindowPoint point: NSPoint) -> Bool
}

/// A hidden titlebar does not stop AppKit from running the system double-click
/// action (zoom or minimize) for a double click in the titlebar band, and the
/// window decides that for itself — before the hit view sees the event — so a
/// control that consumes mouse-down cannot prevent it. Double clicking the
/// history button, Back or any other chrome control therefore stretched the
/// window. Drop those second clicks for the regions the chrome owns, and leave
/// blank chrome to the native titlebar behavior.
enum ChromeTitlebarDoubleClickFilter {
    private static var monitor: Any?

    /// Idempotent; installed when a window adopts the PaperLens chrome.
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            shouldConsume(event) ? nil : event
        }
    }

    /// True when the click is the repeat of a double click inside app-drawn
    /// chrome, so the window must not run its double-click action.
    static func shouldConsume(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown, event.clickCount >= 2,
              let window = event.window, let content = window.contentView else { return false }
        let point = event.locationInWindow
        return chromeOwner(in: content, at: point)?.ownsChromeClick(atWindowPoint: point) == true
    }

    private static func chromeOwner(in view: NSView, at windowPoint: NSPoint) -> ChromeClickOwning? {
        if let owner = view as? ChromeClickOwning, owner.ownsChromeClick(atWindowPoint: windowPoint) { return owner }
        for child in view.subviews {
            if let owner = chromeOwner(in: child, at: windowPoint) { return owner }
        }
        return nil
    }
}

/// Controls own their entire rectangular slot. The corners are inert, rather
/// than holes through which AppKit can interpret a double click as titlebar zoom.
struct ChromeEventBarrier: NSViewRepresentable {
    var cornersOnly = false
    @Environment(\.isEnabled) private var isEnabled
    func makeNSView(context: Context) -> ChromeEventBarrierView { ChromeEventBarrierView() }
    func updateNSView(_ view: ChromeEventBarrierView, context: Context) { view.cornersOnly = cornersOnly; view.isControlEnabled = isEnabled }
}

final class ChromeEventBarrierView: NSView {
    var cornersOnly = false
    var isControlEnabled = true
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard !isHiddenOrHasHiddenAncestor, bounds.contains(local) else { return nil }
        return cornersOnly && ChromeHitShape.contains(local, in: bounds) ? nil : self
    }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
}

extension View {
    /// Apply AFTER the group padding, so separators and padding are protected too.
    func chromeControlGroup() -> some View {
        background(ChromeEventBarrier()).accessibilityElement(children: .contain)
    }
    func chromeControlBoundary() -> some View {
        background(ChromeEventBarrier())
            .overlay(ChromeEventBarrier(cornersOnly: true).accessibilityHidden(true))
    }
}

struct ChromeButtonStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(DesignTokens.primaryInk.opacity(isEnabled ? 1 : 0.3))
            .background(Capsule().fill(DesignTokens.primaryInk.opacity(
                isEnabled && configuration.isPressed ? DesignTokens.pressedOpacity :
                    (selected ? DesignTokens.selectedOpacity : 0))))
            .contentShape(Capsule())
    }
}

/// SwiftUI's outer hosting view can return itself for transparent control edges,
/// bypassing representable backgrounds, which would let a click start a window
/// drag. Route the title row at its hosting boundary: controls keep their own
/// slot and blank chrome stays draggable. (The window's own double-click action
/// is filtered separately — see `ChromeTitlebarDoubleClickFilter`.)
struct ChromeHostingContainer<Content: View>: NSViewRepresentable {
    let content: Content
    func makeNSView(context: Context) -> ChromeHostingView<Content> { ChromeHostingView(rootView: content) }
    func updateNSView(_ view: ChromeHostingView<Content>, context: Context) { view.rootView = content }
}

final class ChromeHostingView<Content: View>: NSHostingView<Content>, ChromeClickOwning {
    private let blankArea = ChromeBlankDragView()
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    required init(rootView: Content) {
        super.init(rootView: rootView)
        safeAreaRegions = []
        addSubview(blankArea)
    }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        blankArea.frame = bounds
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local), !isHiddenOrHasHiddenAncestor else { return nil }
        let guards = barrierViews(in: self)
        // Circular controls win over their enclosing group. SwiftUI owns the
        // action; native history targets retain their first-mouse behavior.
        if guards.contains(where: { view in
            view.cornersOnly && view.isControlEnabled && !view.isHiddenOrHasHiddenAncestor
                && ChromeHitShape.contains(view.convert(local, from: self), in: view.bounds)
        }) {
            let target = super.hitTest(point)
            return target is ChromeEventBarrierView ? self : (target ?? self)
        }
        if let barrier = guards.last(where: { view in
            !view.isHiddenOrHasHiddenAncestor && view.bounds.contains(view.convert(local, from: self))
        }) { return barrier }
        return blankArea
    }
    private func barrierViews(in view: NSView) -> [ChromeEventBarrierView] {
        view.subviews.flatMap { child in
            if let barrier = child as? ChromeEventBarrierView { return [barrier] }
            return barrierViews(in: child)
        }
    }

    // MARK: - Chrome ownership

    func ownsChromeClick(atWindowPoint point: NSPoint) -> Bool { ownsClick(at: convert(point, from: nil)) }

    /// Every control boundary — including the slot corners and the padding of a
    /// control group — belongs to the chrome; only the gaps between groups are
    /// blank, draggable titlebar space.
    func ownsClick(at point: NSPoint) -> Bool {
        guard bounds.contains(point), !isHiddenOrHasHiddenAncestor else { return false }
        return barrierViews(in: self).contains { barrier in
            !barrier.isHiddenOrHasHiddenAncestor && barrier.bounds.contains(barrier.convert(point, from: self))
        }
    }
}

private final class ChromeBlankDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
