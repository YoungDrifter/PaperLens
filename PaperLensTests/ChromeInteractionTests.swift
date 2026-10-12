import AppKit
import SwiftUI
import Testing
@testable import PaperLens

@MainActor
@Suite(.serialized)
struct ChromeInteractionTests {
    @Test func roundHitGeometryMatchesVisibleControl() {
        let round = NSRect(x: 0, y: 0, width: 38, height: 38)
        for point in [NSPoint(x: 19, y: 19), NSPoint(x: 19, y: 0.1), NSPoint(x: 37.9, y: 19)] {
            #expect(ChromeHitShape.contains(point, in: round))
        }
        for point in [NSPoint(x: 1, y: 1), NSPoint(x: 37, y: 37), NSPoint(x: 38.1, y: 19)] {
            #expect(!ChromeHitShape.contains(point, in: round))
        }
        #expect(ChromeHitShape.contains(NSPoint(x: 100, y: 19), in: NSRect(x: 0, y: 0, width: 128, height: 38)))
    }

    @Test func cornerBarrierConsumesRepeatedClicksWithoutZooming() throws {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 54))
        let barrier = ChromeEventBarrierView(frame: NSRect(x: 20, y: 8, width: 38, height: 38))
        barrier.cornersOnly = true
        root.addSubview(barrier)
        let window = NSWindow(contentRect: root.bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        defer { window.close() }
        #expect(root.hitTest(NSPoint(x: 21, y: 9)) === barrier)
        #expect(root.hitTest(NSPoint(x: 39, y: 27)) !== barrier)
        #expect(!barrier.mouseDownCanMoveWindow)
        let frame = window.frame
        for count in 1...5 {
            let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 21, y: 9), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: count, clickCount: count, pressure: 1))
            barrier.mouseDown(with: event)
            barrier.mouseUp(with: event)
        }
        #expect(window.frame == frame)
        #expect(!window.styleMask.contains(.fullScreen))
    }

    @Test func realChromeHasNoDraggableHolesInControlGroups() async throws {
        let manager = TabManager()
        for width in [720.0, 900, 1120, 1440] {
            let window = AppDelegate.makeHostedWindow(contentView: TopChromeView(tabManager: manager), contentSize: NSSize(width: width, height: 54))
            defer { window.close() }
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            let root = try #require(window.contentView)
            root.layoutSubtreeIfNeeded()
            let guards = descendants(root).compactMap { $0 as? ChromeEventBarrierView }
            #expect(!guards.isEmpty)
            for guardView in guards where guardView.cornersOnly {
                let bounds = guardView.convert(guardView.bounds, to: root)
                #expect(bounds.minX >= -0.5 && bounds.maxX <= width + 0.5)
                #expect(abs(bounds.height - 38) < 0.5)
                let local = NSPoint(x: guardView.bounds.minX + 0.5, y: guardView.bounds.minY + 0.5)
                let point = guardView.convert(local, to: root)
                let target = root.hitTest(root.convert(point, to: root.superview))
                #expect(Bool(target is ChromeEventBarrierView))
                #expect(target?.mouseDownCanMoveWindow == false)
            }
            let groups = guards.filter { !$0.cornersOnly && $0.bounds.width > 140 }
            for group in groups {
                // Insets above/below glyphs are still owned by the control group.
                let point = group.convert(NSPoint(x: 1, y: group.bounds.midY), to: root)
                #expect(root.hitTest(root.convert(point, to: root.superview))?.mouseDownCanMoveWindow == false)
            }
        }
        withExtendedLifetime(manager) {}
    }

    @Test func toolbarWidthsMatchRenderedButtons() {
        #expect(DocumentToolbar.minimumWidth == 206)
        #expect(DocumentToolbar.intermediateWidth == 295)
        #expect(DocumentToolbar.fullWidth == 337)
        #expect(DocumentToolbar.controlLevel(availableWidth: 294) == 0)
        #expect(DocumentToolbar.controlLevel(availableWidth: 295) == 1)
        #expect(DocumentToolbar.controlLevel(availableWidth: 337) == 2)
    }

    // MARK: - Titlebar double click

    /// The window runs the system double-click action itself, before the hit
    /// view sees the event, so the repeat click has to be dropped for every
    /// pixel the chrome owns — while blank chrome keeps native behavior.
    @Test func titlebarDoubleClickIsOwnedByChromeControlsOnly() async throws {
        let manager = TabManager()
        let window = AppDelegate.makeHostedWindow(contentView: TopChromeView(tabManager: manager), contentSize: NSSize(width: 1200, height: 700))
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(120))
        let root = try #require(window.contentView)
        root.layoutSubtreeIfNeeded()
        let chromeView = try #require(descendants(root).first { $0 is ChromeClickOwning })
        let owner = try #require(chromeView as? ChromeClickOwning)

        // The history button, its slot corners and the control-group padding.
        let chevron = try #require(descendants(chromeView).compactMap { $0 as? TabSwitcherChevronView }.first)
        for local in [NSPoint(x: chevron.bounds.midX, y: chevron.bounds.midY),
                      NSPoint(x: chevron.bounds.minX + 0.5, y: chevron.bounds.minY + 0.5),
                      NSPoint(x: chevron.bounds.maxX - 0.5, y: chevron.bounds.maxY - 0.5)] {
            let point = chevron.convert(local, to: nil)
            #expect(owner.ownsChromeClick(atWindowPoint: point))
            #expect(ChromeTitlebarDoubleClickFilter.shouldConsume(
                try doubleClick(at: point, in: window, clickCount: 2)))
        }

        // A single click always belongs to the control.
        let center = chevron.convert(NSPoint(x: chevron.bounds.midX, y: chevron.bounds.midY), to: nil)
        #expect(!ChromeTitlebarDoubleClickFilter.shouldConsume(
            try doubleClick(at: center, in: window, clickCount: 1)))

        // The gaps between the control groups stay titlebar space.
        let blank = try #require(blankChromePoint(in: chromeView, owner: owner))
        #expect(!owner.ownsChromeClick(atWindowPoint: blank))
        #expect(!ChromeTitlebarDoubleClickFilter.shouldConsume(
            try doubleClick(at: blank, in: window, clickCount: 2)))

        withExtendedLifetime(manager) {}
    }

    private func doubleClick(at point: NSPoint, in window: NSWindow, clickCount: Int) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: clickCount, clickCount: clickCount, pressure: 1))
    }

    /// First point in the chrome row that no control or control group owns.
    private func blankChromePoint(in chromeView: NSView, owner: ChromeClickOwning) -> NSPoint? {
        let midY = chromeView.bounds.midY
        var x = chromeView.bounds.minX + 1
        while x < chromeView.bounds.maxX - 1 {
            let point = chromeView.convert(NSPoint(x: x, y: midY), to: nil)
            if !owner.ownsChromeClick(atWindowPoint: point) { return point }
            x += 1
        }
        return nil
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
