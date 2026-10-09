import AppKit
import Foundation
import PDFKit
import SwiftUI
import Testing
@testable import PaperLens

/// Opening a document that has no saved reading position must land on page 1.
///
/// Regression: the "scroll to top" pass wrote `docHeight - clipHeight` into the
/// scroll view's y origin, but PDFKit's document view is flipped (y = 0 is the
/// top edge), so `docHeight - clipHeight` *is the bottom* — a freshly opened PDF
/// landed on its last page (and then saved that state, so it stuck).
@MainActor
struct FreshOpenLandingTests {
    @Test func openingWithoutSavedPositionLandsOnTheFirstPage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperLens-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("fresh.pdf")
        // Letter-size pages, so exactly one page fits the viewport (a 32pt fixture
        // would fit three pages and PDFKit's "current page" would be ambiguous).
        #expect(makeLetterDocument(pageCount: 5).write(to: url))

        let suite = "PaperLensOpen.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recent = RecentFilesManager(defaults: defaults)

        let manager = TabManager()
        defer { manager.closeActiveTab() }
        // The Finder / "default PDF reader" path: the document is loaded before the
        // window hosting it exists, so the first layout performs the fit + scroll.
        manager.openDocument(url: url, isSecurityScoped: false)

        let window = AppDelegate.makeHostedWindow(
            contentView: TabContainerView(tabManager: manager).environment(recent),
            contentSize: NSSize(width: 900, height: 600)
        )
        defer { window.contentView = nil; window.close() }

        // Let SwiftUI mount, then let the fit's readiness retries and the layout
        // settle delay run (0.1s + 0.05s) with a comfortable margin.
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(250))
            window.contentView?.layoutSubtreeIfNeeded()
        }

        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let content = try #require(window.contentView)
        let pdfView = try #require(descendants(content).compactMap { $0 as? StablePDFView }.first)
        let scrollView = try #require(pdfView.documentScrollView)
        let documentView = try #require(scrollView.documentView)

        // The convention the scroll maths relies on.
        #expect(documentView.isFlipped, "PDFKit's document view is flipped: page 1 is at y = 0")

        let clip = scrollView.contentView
        #expect(clip.bounds.origin.y <= 1,
                "a fresh document must sit at the top; clip origin.y = \(clip.bounds.origin.y), document height = \(documentView.bounds.height)")
        #expect(manager.activePDFManager?.currentPageIndex == 0,
                "the reading position must stay on page 1; got \(manager.activePDFManager?.currentPageIndex ?? -1)")
        #expect(pdfView.currentPage === pdfView.document?.page(at: 0),
                "the view's current page must be the first one")
    }
}

/// Letter-size pages, so one page fills the viewport.
@MainActor
private func makeLetterDocument(pageCount: Int) -> PDFDocument {
    let document = PDFDocument()
    for index in 0..<pageCount {
        let image = NSImage(size: NSSize(width: 612, height: 792))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 612, height: 792)).fill()
        image.unlockFocus()
        guard let page = PDFPage(image: image) else {
            fatalError("Failed to create a letter-size test page.")
        }
        document.insert(page, at: index)
    }
    return document
}
