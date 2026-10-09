//
//  TabBarMouseView.swift
//  PaperLens
//
//  AppKit gesture source for the tab bar. Owns no drag state — its only
//  job is to convert mouse events into calls on `TabDragController`, and
//  to surface hover / click callbacks back to SwiftUI.
//
//  By keeping the gesture layer below SwiftUI, we get sub-frame mouse
//  response without the layout-thrash that comes from running drag logic
//  inside a SwiftUI body.
//

import AppKit
import SwiftUI

enum TabBarClickTarget: Equatable {
    case newTab
    case selectTab(UUID)
    case closeTab(UUID)
}

struct TabBarMouseView: NSViewRepresentable {
    let tabManager: TabManager
    let tabFrames: [UUID: CGRect]
    let newTabButtonFrame: CGRect
    let hoveredTabID: UUID?
    let activeTabID: UUID?
    let onHover: (UUID?) -> Void
    let onClick: (TabBarClickTarget) -> Void

    func makeNSView(context: Context) -> TabBarMouseNSView {
        let view = TabBarMouseNSView()
        view.apply(
            tabManager: tabManager,
            tabFrames: tabFrames,
            newTabButtonFrame: newTabButtonFrame,
            hoveredTabID: hoveredTabID,
            activeTabID: activeTabID,
            onHover: onHover,
            onClick: onClick
        )
        return view
    }

    func updateNSView(_ nsView: TabBarMouseNSView, context: Context) {
        nsView.apply(
            tabManager: tabManager,
            tabFrames: tabFrames,
            newTabButtonFrame: newTabButtonFrame,
            hoveredTabID: hoveredTabID,
            activeTabID: activeTabID,
            onHover: onHover,
            onClick: onClick
        )
    }
}

@MainActor
final class TabBarMouseNSView: NSView, TabBarHandle {
    private static let dragThreshold: CGFloat = 5

    private weak var tabManagerRef: TabManager?
    private var tabFrames: [UUID: CGRect] = [:]
    private var newTabButtonFrame: CGRect = .zero
    private var hoveredTabID: UUID?
    private var activeTabID: UUID?
    private var onHover: (UUID?) -> Void = { _ in }
    private var onClick: (TabBarClickTarget) -> Void = { _ in }

    private var pressOrigin: NSPoint?
    private var pressedTabID: UUID?
    private var dragArmed = false
    /// True only when the current mouseDown was the second click of a
    /// double-click. Tab drag arms only on a held second-click — a plain
    /// single-click + drag is a no-op (the click still selects on
    /// mouseUp).
    private var canDrag = false
    private var trackingArea: NSTrackingArea?
    private var registered = false

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func scrollWheel(with event: NSEvent) {
        if !Self.scrollTabStrip(from: self, event: event) { super.scrollWheel(with: event) }
    }

    /// The click/drag overlay is above SwiftUI's scroll view. Forward wheel
    /// movement to that strip, including vertical mouse wheels, only on overflow.
    static func scrollTabStrip(from source: NSView, event: NSEvent) -> Bool {
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY
        return scrollTabStrip(from: source, delta: delta, precise: event.hasPreciseScrollingDeltas)
    }

    static func scrollTabStrip(from source: NSView, delta: CGFloat, precise: Bool) -> Bool {
        guard let scroll = tabScrollView(overlapping: source),
              let document = scroll.documentView else { return false }
        let clip = scroll.contentView
        let maximum = max(0, document.frame.width - clip.bounds.width)
        guard maximum > 0 else { return false }
        let distance = delta * (precise ? 1 : 10)
        clip.scroll(to: NSPoint(x: min(maximum, max(0, clip.bounds.minX - distance)), y: clip.bounds.minY))
        scroll.reflectScrolledClipView(clip)
        return true
    }

    static func tabScrollView(overlapping source: NSView) -> NSScrollView? {
        func search(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView,
               scroll.convert(scroll.bounds, to: source).intersects(source.bounds),
               scroll.bounds.height <= TopChromeView.height {
                return scroll
            }
            return view.subviews.lazy.compactMap(search).first
        }
        var ancestor = source.superview
        while let view = ancestor {
            if let scroll = search(view) { return scroll }
            ancestor = view.superview
        }
        return nil
    }

    // MARK: - Configuration from SwiftUI

    func apply(
        tabManager: TabManager,
        tabFrames: [UUID: CGRect],
        newTabButtonFrame: CGRect,
        hoveredTabID: UUID?,
        activeTabID: UUID?,
        onHover: @escaping (UUID?) -> Void,
        onClick: @escaping (TabBarClickTarget) -> Void
    ) {
        self.tabManagerRef = tabManager
        self.tabFrames = tabFrames
        self.newTabButtonFrame = newTabButtonFrame
        self.hoveredTabID = hoveredTabID
        self.activeTabID = activeTabID
        self.onHover = onHover
        self.onClick = onClick
        registerIfReady()
    }

    // MARK: - View Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        registerIfReady()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            if let trackingArea {
                removeTrackingArea(trackingArea)
                self.trackingArea = nil
            }
            // Window torn down mid-drag — abort only if this view's
            // manager is the drag's current host. (Single-tab tear-off
            // closes the original source window; the drag is by then
            // hosted by the new torn-off manager and must not be killed.)
            if let tabManager = tabManagerRef, TabDragController.shared.isRegisteredBar(self, for: tabManager) {
                TabDragController.shared.cancelDragIfSource(tabManager)
            }
            unregister()
        }
    }

    private func registerIfReady() {
        guard !registered, window != nil, let tabManager = tabManagerRef else { return }
        TabDragController.shared.registerBar(self, for: tabManager)
        registered = true
    }

    private func unregister() {
        guard registered, let tabManager = tabManagerRef else { return }
        TabDragController.shared.unregisterBar(for: tabManager, matching: self)
        registered = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingArea == nil else { return }

        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Hit Testing (Window Drag Fall-Through)

    /// Empty bar space falls through to the underlying `WindowDragArea`,
    /// so dragging the bar background drags the window — Chrome / Safari
    /// behavior. Tab pills and the `+` button still receive clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if findTab(at: point) != nil || newTabButtonFrame.contains(point) {
            return self
        }
        return nil
    }

    // MARK: - Hover

    override func mouseEntered(with event: NSEvent) {
        emitHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        emitHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard !TabDragController.shared.isActive else { return }
        if hoveredTabID != nil { onHover(nil) }
    }

    private func emitHover(at point: NSPoint) {
        guard !TabDragController.shared.isActive else { return }
        let next = findTab(at: point)
        if next != hoveredTabID { onHover(next) }
    }

    // MARK: - Mouse Down / Drag / Up

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressOrigin = point
        pressedTabID = findTab(at: point)
        dragArmed = false
        canDrag = event.clickCount >= 2
    }

    override func mouseDragged(with event: NSEvent) {
        // Once the controller's app-level monitor takes over, the
        // synchronous override would double-process events.
        if TabDragController.shared.isActive { return }

        // Single-click drags are intentionally ignored — only a held
        // second click of a double-click can initiate a tab drag.
        guard canDrag,
              !dragArmed,
              let origin = pressOrigin,
              let tabManager = tabManagerRef else { return }

        let current = convert(event.locationInWindow, from: nil)
        guard hypot(current.x - origin.x, current.y - origin.y) >= Self.dragThreshold else { return }

        guard let tabID = pressedTabID,
              !isCloseHit(for: tabID, at: origin),
              let snapshot = makeDragSnapshot(for: tabID, in: tabManager),
              let screen = screenPoint(for: current) else {
            return
        }

        dragArmed = true
        TabDragController.shared.beginDrag(
            tabID: tabID,
            in: tabManager,
            snapshot: snapshot,
            screenPoint: screen
        )
    }

    override func mouseUp(with event: NSEvent) {
        // Drag-mode mouseUp is handled by the controller's monitor; this
        // override only fires for plain clicks (no threshold crossed).
        defer { resetMousePressState() }
        if TabDragController.shared.isActive { return }
        guard let origin = pressOrigin,
              !dragArmed,
              let target = clickTarget(at: origin) else {
            return
        }
        onClick(target)
    }

    private func resetMousePressState() {
        pressOrigin = nil
        pressedTabID = nil
        dragArmed = false
        canDrag = false
    }

    // MARK: - Coordinate Conversion

    private func screenPoint(for localPoint: NSPoint) -> CGPoint? {
        guard let window else { return nil }
        return window.convertPoint(toScreen: convert(localPoint, to: nil))
    }

    private func localPoint(for screenPoint: CGPoint) -> NSPoint? {
        guard let window else { return nil }
        return convert(window.convertPoint(fromScreen: screenPoint), from: nil)
    }

    // MARK: - Hit Test Helpers

    private func clickTarget(at point: NSPoint) -> TabBarClickTarget? {
        if newTabButtonFrame.contains(point) {
            return .newTab
        }

        guard let tabID = findTab(at: point) else { return nil }
        return isCloseHit(for: tabID, at: point) ? .closeTab(tabID) : .selectTab(tabID)
    }

    private func findTab(at point: NSPoint) -> UUID? {
        guard let tabManager = tabManagerRef else { return nil }
        for tab in tabManager.tabs {
            guard let frame = tabFrames[tab.id] else { continue }
            if frame.contains(point) { return tab.id }
        }
        return nil
    }

    private func isCloseHit(for tabID: UUID, at point: NSPoint) -> Bool {
        guard let frame = tabFrames[tabID] else { return false }
        let isCloseVisible = hoveredTabID == tabID
        guard isCloseVisible else { return false }
        let closeMinX = frame.minX + DesignTokens.spacingSM
        let closeY = frame.midY - DesignTokens.tabCloseButtonSize / 2
        let closeRect = NSRect(
            x: closeMinX,
            y: closeY,
            width: DesignTokens.tabCloseButtonSize,
            height: DesignTokens.tabCloseButtonSize
        )
        return closeRect.contains(point)
    }

    private func makeDragSnapshot(for tabID: UUID, in tabManager: TabManager) -> TabDragPreviewSnapshot? {
        guard let tab = tabManager.tabs.first(where: { $0.id == tabID }) else { return nil }
        let baseWidth = tabFrames[tabID]?.width ?? DesignTokens.tabMinWidth
        let width = min(max(baseWidth, DesignTokens.tabMinWidth), DesignTokens.tabMaxWidth)
        return TabDragPreviewSnapshot(
            title: tab.displayTitle,
            isDirty: tabManager.isTabDirty(tabID),
            width: width
        )
    }

    // MARK: - TabBarHandle

    func contains(screenPoint: CGPoint) -> Bool {
        guard let local = localPoint(for: screenPoint) else { return false }
        return bounds.contains(local)
    }

    func screenFrame() -> CGRect {
        guard let window else { return .zero }
        let windowRect = convert(bounds, to: nil)
        return window.convertToScreen(windowRect)
    }

    func dropIndex(for screenPoint: CGPoint) -> Int? {
        guard let tabManager = tabManagerRef,
              let local = localPoint(for: screenPoint),
              bounds.contains(local) else {
            return nil
        }

        for (index, tab) in tabManager.tabs.enumerated() {
            guard let frame = tabFrames[tab.id] else { continue }
            if local.x < frame.midX { return index }
        }
        return tabManager.tabs.count
    }
}
