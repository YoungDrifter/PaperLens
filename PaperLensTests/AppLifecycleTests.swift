import AppKit
import Testing
@testable import PaperLens

/// App-level lifecycle: PaperLens must not disappear because the last window
/// went away, and it must be able to come back afterwards.
@MainActor
struct AppLifecycleTests {
    @Test func closingTheLastWindowDoesNotQuitTheApp() throws {
        let delegate = try #require(AppDelegate.shared)
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp) == false)
    }

    @Test func reopenWithNoVisibleWindowBuildsOneAndSuppressesSystemRestoration() throws {
        let delegate = try #require(AppDelegate.shared)
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))

        #expect(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false) == false)

        let created = NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) }
        defer { created.forEach { $0.close() } }
        #expect(created.count == 1)
        let window = try #require(created.first, "reopen should have created a window")
        #expect(window.identifier == PaperLensWindowIdentifiers.userCreated)
        #expect(window.isVisible)
    }

    @Test func reopenWithVisibleWindowsLeavesThemAlone() throws {
        let delegate = try #require(AppDelegate.shared)
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        #expect(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true) == true)
        #expect(Set(NSApp.windows.map(ObjectIdentifier.init)) == before)
    }
}
