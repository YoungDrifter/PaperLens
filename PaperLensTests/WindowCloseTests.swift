//
//  WindowCloseTests.swift
//  PaperLensTests
//
//  Closing a window's only tab must close the window itself
//  (closeTab → WindowRegistry.closeWindow).
//

import AppKit
import Testing
@testable import PaperLens

/// Records `close()` calls. The window is kept off screen: a visible test window
/// becoming "the last window" used to trigger
/// `applicationShouldTerminateAfterLastWindowClosed` in the test host and take the
/// suite down with it (that delegate now returns `false`, see `AppLifecycleTests`,
/// but an off-screen window is still the cheaper fixture).
@MainActor
private final class CloseSpyWindow: NSWindow {
    var closeCount = 0
    override func close() {
        closeCount += 1
        super.close()
    }
}

@MainActor
struct WindowCloseTests {

    @Test
    func closingTheOnlyTabClosesItsWindow() async throws {
        let manager = TabManager()
        let window = CloseSpyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        WindowRegistry.shared.register(manager, window: window)
        defer { WindowRegistry.shared.unregister(manager) }

        let onlyTab = try #require(manager.activeTabID)
        manager.closeTab(onlyTab)

        #expect(manager.tabs.isEmpty)
        // closeWindow defers the actual close by one main-queue turn.
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.closeCount == 1)
    }
}
