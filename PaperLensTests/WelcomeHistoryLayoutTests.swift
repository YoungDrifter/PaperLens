import AppKit
import SwiftUI
import Testing
@testable import PaperLens

/// The welcome card owns a fixed-height list: every remembered document stays
/// reachable by scrolling inside the card instead of stretching the page.
@MainActor
@Suite(.serialized)
struct WelcomeHistoryLayoutTests {
    @Test func welcomeCardScrollsTheWholeHistoryInsideItsFrame() async throws {
        let suite = "WelcomeLayout.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recent = RecentFilesManager(defaults: defaults)
        for index in 0..<10 {
            let url = directory.appendingPathComponent("Paper \(index).pdf")
            try Data().write(to: url)
            recent.addRecentFile(url)
        }
        #expect(recent.recentFiles.count == 10)

        let window = AppDelegate.makeHostedWindow(
            contentView: WelcomeView(tabManager: TabManager()).environment(recent),
            contentSize: NSSize(width: 900, height: 700)
        )
        defer { window.contentView = nil; window.close() }
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(400))
        let root = try #require(window.contentView)
        root.layoutSubtreeIfNeeded()

        let rows = CGFloat(recent.recentFiles.count)
        let expectedContentHeight = rows * DesignTokens.welcomeRecentRowHeight
            + (rows - 1) * DesignTokens.spacingSM + 4
        let scrollers = descendants(root).compactMap { $0 as? NSScrollView }
        let list = try #require(scrollers.first { abs(($0.documentView?.frame.height ?? 0) - expectedContentHeight) < 2 },
                               "the welcome card must list every recent file inside its own scroller")
        #expect(abs(list.contentView.bounds.height - DesignTokens.welcomeHistoryMaxHeight) < 2,
                "the card caps the list instead of growing with the history")
        #expect(list.documentView!.frame.height > list.contentView.bounds.height,
                "the remaining entries must be reachable by scrolling inside the card")
        #expect(recent.recentFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })

        if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            descendants(root).forEach { $0.needsDisplay = true }
            root.display()
            root.cacheDisplay(in: root.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("paperlens-welcome-history.png"))
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
