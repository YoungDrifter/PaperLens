import AppKit
import SwiftUI
import Testing
@testable import PaperLens

@MainActor
struct PaperLensBrandingTests {
    @Test func publicIdentityUsesNewVersionAndBundledIcon() throws {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String == "PaperLens")
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == AppIdentity.displayName)
        #expect(AppIdentity.version == "1.0.0")
        #expect(Bundle.main.bundleIdentifier == "com.raccoontechnologies.PaperLens")
        let url = try #require(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"))
        #expect(NSImage(contentsOf: url)?.isValid == true)
        #expect(AppIdentity.icon.isValid)
        let masterURL = try #require(Bundle.main.url(forResource: "icon_1024", withExtension: "png"))
        let masterData = try Data(contentsOf: masterURL)
        let bitmap = try #require(NSBitmapImageRep(data: masterData))
        #expect(bitmap.pixelsWide == 1024)
    }

    @Test func settingsShowAnnotationsAtDefaultSizeAndKeepNativeWindowControls() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsStyle.windowSize.width, height: SettingsStyle.windowSize.height),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(150))
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(window.contentMinSize.width >= SettingsStyle.minimumSize.width)
        #expect(window.contentMinSize.height >= SettingsStyle.minimumSize.height)
        #expect(window.appearance?.name == .aqua)
        #expect(window.level == .normal)
        #expect(window.standardWindowButton(.closeButton)?.keyEquivalent == "\u{1b}")
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let content = try #require(window.contentView)
        #expect(!descendants(content).compactMap { $0 as? NSColorWell }.isEmpty)
    }
}

@MainActor
struct WelcomeTests {
    @Test func recentOpeningTimesPersistAndLegacyRecordsRemainReadable() throws {
        let suite = "WelcomeTimes.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("welcome-\(UUID().uuidString).pdf")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let legacy = "[{\"url\":\"\(file.absoluteString)\"}]"
        defaults.set(Data(legacy.utf8), forKey: "recentFiles")
        let manager = RecentFilesManager(defaults: defaults)
        #expect(manager.recentFiles.first?.lastOpenedAt == nil)
        manager.addRecentFile(file)
        let recorded = try #require(manager.recentFiles.first?.lastOpenedAt)
        #expect(abs(recorded.timeIntervalSinceNow) < 2)
        #expect(RecentFilesManager(defaults: defaults).recentFiles.first?.lastOpenedAt == recorded)
        #expect(manager.recentFiles.count == 1)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(RecentFileTime.label(for: nil, relativeTo: now) == "Earlier")
        #expect(RecentFileTime.label(for: now, relativeTo: now) == "Just now")
        #expect(RecentFileTime.label(for: now.addingTimeInterval(-10_800), relativeTo: now) == "3 hours ago")
        #expect(RecentFileTime.label(for: now.addingTimeInterval(-86_400), relativeTo: now) == "yesterday")
    }

    @Test func loadedHistorySortsByOpeningTimeAndKeepsLegacyOrder() throws {
        let suite = "WelcomeOrder.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let times: [Date?] = [nil, Date(timeIntervalSince1970: 100), nil, Date(timeIntervalSince1970: 300), Date(timeIntervalSince1970: 300)]
        let files = try times.enumerated().map { index, time in
            let url = directory.appendingPathComponent("\(index).pdf")
            try Data().write(to: url)
            return RecentFile(url: url, securityScopedBookmarkData: nil, lastOpenedAt: time)
        }
        defaults.set(try JSONEncoder().encode(files), forKey: "recentFiles")
        let manager = RecentFilesManager(defaults: defaults)
        #expect(manager.recentFiles.map(\.url.lastPathComponent) == ["3.pdf", "4.pdf", "1.pdf", "0.pdf", "2.pdf"])
        #expect(manager.welcomeFiles == manager.recentFiles)
        manager.addRecentFile(files[0].url)
        #expect(manager.recentFiles.first?.url == files[0].url)
    }

    @Test func welcomeShowsFiveNewestWithoutTruncatingFullHistory() throws {
        let suite = "WelcomeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = RecentFilesManager(defaults: defaults)
        manager.recentFiles = (0..<8).map {
            RecentFile(url: URL(fileURLWithPath: "/tmp/recent-\($0).pdf"), securityScopedBookmarkData: nil)
        }
        #expect(manager.welcomeFiles.count == 5)
        #expect(manager.welcomeFiles.map(\.id) == Array(manager.recentFiles.prefix(5)).map(\.id))
        #expect(manager.recentFiles.count == 8)
        manager.clearRecentFiles()
        #expect(manager.welcomeFiles.isEmpty)
    }
}
