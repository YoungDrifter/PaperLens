//
//  WindowRegistry.swift
//  PaperLens
//
//  Tracks all (TabManager, NSWindow) pairs across the app for app-level
//  operations: routing Finder/open events, dirty-document quit prompts,
//  bringing windows to front, and dismissing transient placeholder windows
//  spawned by external open events.
//
//  Drag-and-drop state lives elsewhere — see `TabDragController`.
//

import AppKit
import Foundation
import Observation

/// Registry of every open window and its `TabManager`, so cross-window
/// operations (open into an existing window, frontmost lookup, window teardown)
/// can find the right window without walking `NSApp.windows`.
@MainActor
final class WindowRegistry {
    static let shared = WindowRegistry()

    private struct Entry {
        let tabManager: TabManager
        weak var window: NSWindow?
        let isUserCreated: Bool
        let registeredAt: Date
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var mainWindowObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private weak var lastActiveTabManager: TabManager?

    private var pendingTransientPlaceholderDismissals = 0
    private var transientPlaceholderDismissalLowerBound: Date?
    private var transientPlaceholderDismissalDeadline: Date?

    private init() {}

    // MARK: - Registration

    func register(_ tabManager: TabManager, window: NSWindow?) {
        entries[ObjectIdentifier(tabManager)] = Entry(
            tabManager: tabManager,
            window: window,
            isUserCreated: window?.identifier == PaperLensWindowIdentifiers.userCreated,
            registeredAt: Date()
        )
        if window?.isMainWindow == true {
            lastActiveTabManager = tabManager
        }

        if let window {
            // One-turn-deferred front-most tracking is harmless (see helper doc).
            let token = NotificationCenter.default.addMainActorObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: window
            ) { [weak self, weak tabManager] in
                guard let self, let tabManager else { return }
                self.lastActiveTabManager = tabManager
                self.publishActiveWindow()
            }
            mainWindowObservers[ObjectIdentifier(tabManager)] = token
        }

        publishActiveWindow()
        dismissPendingTransientPlaceholderWindows()

        // Deliver any URLs buffered during cold launch (before this TabManager existed).
        Task { @MainActor in
            guard let appDelegate = AppDelegate.shared else { return }
            appDelegate.flushPendingURLs(to: tabManager)
        }
    }

    func unregister(_ tabManager: TabManager) {
        entries.removeValue(forKey: ObjectIdentifier(tabManager))
        if lastActiveTabManager === tabManager {
            lastActiveTabManager = nil
        }
        let token = mainWindowObservers.removeValue(forKey: ObjectIdentifier(tabManager))
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        publishActiveWindow()
    }

    /// Mirrors the resolved frontmost manager onto `ActiveWindowModel`, the
    /// reactive surface SwiftUI menu `Commands` read so their action targets
    /// AND enabled state follow the frontmost window. A manually-created ⌘N /
    /// tear-off window holds no focused SwiftUI view, so `@FocusedValue` alone
    /// cannot route to it — commands resolve `focusedTabManager ?? frontmost`.
    private func publishActiveWindow() {
        ActiveWindowModel.shared.update(frontmostTabManager())
    }

    // MARK: - Lookups

    func allDirtyPDFManagers() -> [(UUID, PDFManager)] {
        entries.values
            .filter { $0.window != nil }
            .flatMap { $0.tabManager.dirtyPDFManagers() }
    }

    /// Persists every open window's active-tab reading position to the store.
    /// Called on app termination so the last position survives a quit.
    func flushAllViewState() {
        for entry in entries.values where entry.window != nil {
            entry.tabManager.flushActiveTabViewState()
        }
    }

    /// TabManager whose window was most recently main. Stays correct even
    /// after Settings or another panel has stolen `keyWindow`/`mainWindow`.
    func frontmostTabManager() -> TabManager? {
        let tracked = lastActiveTabManager
        let values = entries.values.filter { $0.window != nil }

        if let tracked, values.contains(where: { $0.tabManager === tracked }) {
            return tracked
        }

        if let main = NSApp.mainWindow,
           let entry = values.first(where: { $0.window === main }) {
            return entry.tabManager
        }

        if let key = NSApp.keyWindow,
           let entry = values.first(where: { $0.window === key }) {
            return entry.tabManager
        }

        return values
            .sorted { $0.registeredAt > $1.registeredAt }
            .first?
            .tabManager
    }

    /// Any registered TabManager — used by Finder open routing.
    func anyTabManager() -> TabManager? {
        let values = entries.values.filter { $0.window != nil }
        return preferredEntry(from: values)?.tabManager
    }

    /// Whether `url`'s document is already open in any registered window. A
    /// read-only counterpart to `activateExistingDocument` — it never changes focus.
    func isDocumentOpen(_ url: URL) -> Bool {
        let canonicalURL = url.paperLensCanonicalDocumentURL
        for entry in entries.values where entry.window != nil {
            if entry.tabManager.tabID(for: canonicalURL) != nil { return true }
        }
        return false
    }

    /// Activates an existing tab for the given URL if already open. Returns
    /// `true` if handled (caller should not create a new tab/window).
    func activateExistingDocument(for url: URL) -> Bool {
        let canonicalURL = url.paperLensCanonicalDocumentURL
        let match: (TabManager, UUID, NSWindow?)? = {
            for entry in entries.values {
                guard let window = entry.window else { continue }
                if let tabID = entry.tabManager.tabID(for: canonicalURL) {
                    return (entry.tabManager, tabID, window)
                }
            }
            return nil
        }()

        guard let (tabManager, tabID, _) = match else { return false }
        activate(tabID, in: tabManager)
        return true
    }

    // MARK: - Window Front/Close

    func closeWindow(for tabManager: TabManager) {
        let window = entries[ObjectIdentifier(tabManager)]?.window
        DispatchQueue.main.async {
            window?.close()
        }
    }

    func bringToFront(for tabManager: TabManager) {
        let window = entries[ObjectIdentifier(tabManager)]?.window
        bringWindowToFront(window)
    }

    /// The canonical "go to this tab" action: select it in its window and raise
    /// that window. `activateExistingDocument` (URL-resolved) funnels through
    /// here, so the sequence lives once.
    private func activate(_ tabID: UUID, in tabManager: TabManager) {
        guard let window = entries[ObjectIdentifier(tabManager)]?.window else { return }
        tabManager.selectTab(tabID)
        bringWindowToFront(window)
    }

    private func bringWindowToFront(_ window: NSWindow?) {
        // Raise the target window FIRST, so the opened document's first paint never
        // waits on app-level activation timing.
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        // DO NOT "modernize" this to the no-arg cooperative `NSApp.activate()`:
        // although `ignoringOtherApps:` is advisory-deprecated, on macOS 26 the
        // cooperative form is best-effort and is DROPPED right after a sandboxed
        // NSOpenPanel (powerbox) resigns key — deferring the SwiftUI redraw that
        // paints a freshly opened document by ~5s. `ignoringOtherApps: true` still
        // force-activates and drives that redraw immediately.
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Transient Placeholder Cleanup

    /// Closes one transient placeholder window created by an external open
    /// event that rerouted into an existing PaperLens window.
    func dismissTransientPlaceholderWindowForExternalOpen(within seconds: TimeInterval = 1.0) {
        let now = Date()
        pendingTransientPlaceholderDismissals = 1
        transientPlaceholderDismissalLowerBound = now.addingTimeInterval(-seconds)
        transientPlaceholderDismissalDeadline = now.addingTimeInterval(seconds)
        dismissPendingTransientPlaceholderWindows()
    }

    private func dismissPendingTransientPlaceholderWindows() {
        let tabManagers: [TabManager] = {
            pruneExpiredTransientPlaceholderDismissals()

            guard pendingTransientPlaceholderDismissals > 0,
                  let lowerBound = transientPlaceholderDismissalLowerBound else {
                return []
            }

            return entries.values
                .filter { $0.window != nil }
                .filter { !$0.isUserCreated }
                .filter { $0.registeredAt >= lowerBound }
                .sorted { $0.registeredAt > $1.registeredAt }
                .map(\.tabManager)
        }()

        for tabManager in tabManagers {
            if tabManager.dismissPlaceholderWindowIfNeeded() {
                pendingTransientPlaceholderDismissals = max(0, pendingTransientPlaceholderDismissals - 1)
                if pendingTransientPlaceholderDismissals == 0 {
                    transientPlaceholderDismissalLowerBound = nil
                    transientPlaceholderDismissalDeadline = nil
                }
                break
            }
        }
    }

    private func pruneExpiredTransientPlaceholderDismissals() {
        guard let deadline = transientPlaceholderDismissalDeadline,
              deadline < Date() else {
            return
        }

        pendingTransientPlaceholderDismissals = 0
        transientPlaceholderDismissalLowerBound = nil
        transientPlaceholderDismissalDeadline = nil
    }

    // MARK: - Helpers

    private func preferredEntry(from values: [Entry]) -> Entry? {
        if let keyWindow = NSApp.keyWindow,
           let keyEntry = values.first(where: { $0.window === keyWindow }) {
            return keyEntry
        }

        if let mainWindow = NSApp.mainWindow,
           let mainEntry = values.first(where: { $0.window === mainWindow }) {
            return mainEntry
        }

        return values.first
    }
}

/// Reactive projection of "which window is frontmost," kept in sync by
/// `WindowRegistry` (its single writer) on every register / unregister and
/// `didBecomeMain`. SwiftUI menu `Commands` read `tabManager` so they
/// re-evaluate when the main window changes; resolve it as
/// `focusedTabManager ?? ActiveWindowModel.shared.tabManager` so a command
/// still targets a manual (⌘N / tear-off) window that holds no focused view.
@MainActor
@Observable
final class ActiveWindowModel {
    static let shared = ActiveWindowModel()

    private(set) var tabManager: TabManager?

    private init() {}

    func update(_ tabManager: TabManager?) {
        // Skip a redundant Observation mutation when the frontmost is unchanged,
        // so menu Commands don't re-evaluate on every window-registry churn.
        guard self.tabManager !== tabManager else { return }
        self.tabManager = tabManager
    }
}
