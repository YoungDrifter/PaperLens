import AppKit
import PDFKit
import Testing
@testable import PaperLens

/// The Start Page button unloads the active tab's document but keeps the tab
/// (and its window), so the reader returns to the welcome page in place.
@MainActor
struct StartPageTests {

    @Test func closingTheDocumentKeepsTheTabOnTheStartPage() async throws {
        let (directory, first) = try makeDocument(named: "first.pdf", pageCount: 3)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manager = TabManager()
        manager.openDocument(url: first, isSecurityScoped: false)
        try await Task.sleep(for: .milliseconds(150))
        #expect(manager.tabs.count == 1)
        #expect(manager.activePDFManager?.hasDocument == true)
        let tabID = try #require(manager.activeTabID)
        let liveManager = try #require(manager.activePDFManager)

        manager.closeActiveDocument()

        #expect(manager.tabs.count == 1, "only the document goes away; the tab stays")
        #expect(manager.activeTab?.documentURL == nil)
        #expect(manager.activeTab?.title == "New Tab")
        #expect(manager.activePDFManager?.hasDocument == false)
        // The tab must stay in the window's warm set: an empty set collapses the
        // content stack (the chrome gets vertically centred) and the live view's
        // coordinator keeps the managers it was built with.
        #expect(manager.renderedTabIDs.contains(tabID))
        #expect(manager.activePDFManager === liveManager)
        // The tab is reusable: a later open loads into it instead of adding a tab.
        manager.openDocument(url: first, isSecurityScoped: false)
        try await Task.sleep(for: .milliseconds(150))
        #expect(manager.tabs.count == 1)
        #expect(manager.activePDFManager?.hasDocument == true)
    }

    @Test func closingOneDocumentLeavesTheOtherTabsAlone() async throws {
        let (directory, first) = try makeDocument(named: "first.pdf", pageCount: 3)
        defer { try? FileManager.default.removeItem(at: directory) }
        let second = directory.appendingPathComponent("second.pdf")
        #expect(makeTestDocument(pageCount: 2).write(to: second))

        let manager = TabManager()
        manager.openDocument(url: first, isSecurityScoped: false)
        try await Task.sleep(for: .milliseconds(150))
        manager.openDocument(url: second, isSecurityScoped: false)
        try await Task.sleep(for: .milliseconds(150))
        #expect(manager.tabs.count == 2)
        #expect(manager.activeTab?.documentURL?.lastPathComponent == "second.pdf")

        manager.closeActiveDocument()

        #expect(manager.tabs.count == 2, "the other tab is untouched")
        #expect(manager.activeTab?.documentURL == nil)
        #expect(manager.tabs.first?.documentURL?.lastPathComponent == "first.pdf")
        #expect(manager.activePDFManager?.hasDocument == false)
    }

    private func makeDocument(named name: String, pageCount: Int) throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        #expect(makeTestDocument(pageCount: pageCount).write(to: url))
        return (directory, url)
    }
}
