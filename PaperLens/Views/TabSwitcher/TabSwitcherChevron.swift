//
//  TabSwitcherChevron.swift
//  PaperLens
//
//  Chrome's "Recent Files" button, mounted in the top chrome just right of the
//  page control. Tapping it drops the Recent Files popover below the button; the
//  Tab menu's ⌘⇧A command asks the same button to toggle it.
//
//  Clicks are handled by an AppKit hit target (not a SwiftUI Button) for the
//  same reasons the tab strip uses TabBarMouseView: in this hidden-title-bar
//  chrome a SwiftUI button doesn't accept first-mouse (so a click while the
//  popover is key is swallowed activating the window) and competes with the
//  window-drag region.
//
//  Like TabBarMouseView, the target is mounted ONLY while the bar is interactive:
//  AppKit hit-testing ignores SwiftUI's `allowsHitTesting`, so a hidden bar must
//  unmount it rather than rely on opacity.
//

import SwiftUI
import AppKit

extension Notification.Name {
    /// The Tab menu's ⌘⇧A command asks the focused window's history button to
    /// toggle its popover; the notification's object is that window's TabManager,
    /// so only that window's button responds.
    static let paperLensToggleRecentFiles = Notification.Name("PaperLensToggleRecentFiles")
}

struct TabSwitcherChevron: View {
    let tabManager: TabManager
    let isInteractive: Bool
    var usesGlass = true
    @State private var isPresented = false

    var body: some View {
        Group {
            if usesGlass {
                ChromeGlassIcon(systemName: "clock", pointSize: DesignTokens.chromeIconSize)
            } else {
                Image(systemName: "clock").font(.system(size: DesignTokens.chromeIconSize))
                    .frame(width: DesignTokens.chromeButtonSize, height: DesignTokens.chromeButtonSize).contentShape(Capsule())
            }
        }
            .background(Circle().fill(Color.black.opacity(isPresented ? DesignTokens.selectedOpacity : 0)))
            .overlay {
                if isInteractive {
                    TabSwitcherChevronTarget(isPresented: isPresented, onRequestOpen: { isPresented = true })
                }
            }
            .modifier(ChromeMenuHoverFeedback())
            .chromeControlBoundary()
            .disabled(!isInteractive)
            .help("Recent Files")
            .accessibilityLabel("Recent Files")
            .accessibilityAddTraits(.isButton)
            .popover(isPresented: $isPresented) {
                RecentHistoryPopover(tabManager: tabManager, onClose: { isPresented = false })
            }
            .onReceive(NotificationCenter.default.publisher(for: .paperLensToggleRecentFiles, object: tabManager)) { _ in
                isPresented.toggle()
            }
    }
}

/// The popover's content reads the recent-files manager from the environment only
/// while it is actually presented, so hosting the chrome without one (tests)
/// never touches the environment.
private struct RecentHistoryPopover: View {
    @Environment(RecentFilesManager.self) private var recentFiles
    let tabManager: TabManager
    let onClose: () -> Void

    var body: some View {
        RecentHistoryView(manager: recentFiles, onOpen: { open($0) }, onClose: onClose)
    }

    /// Raise the tab (any window) that already shows this file, else open it in
    /// this window — the path the old floating panel used.
    private func open(_ file: RecentFile) {
        guard let resolved = recentFiles.resolveRecentFile(file) else {
            NSSound.beep()
            return
        }
        if WindowRegistry.shared.activateExistingDocument(for: resolved.url) {
            recentFiles.addRecentFile(resolved.url, isSecurityScoped: resolved.isSecurityScoped)
        } else {
            tabManager.openDocument(url: resolved.url, isSecurityScoped: resolved.isSecurityScoped)
        }
    }
}

private struct TabSwitcherChevronTarget: NSViewRepresentable {
    let isPresented: Bool
    let onRequestOpen: () -> Void

    func makeNSView(context: Context) -> TabSwitcherChevronView {
        let view = TabSwitcherChevronView()
        view.isPresented = isPresented
        view.onRequestOpen = onRequestOpen
        return view
    }

    func updateNSView(_ nsView: TabSwitcherChevronView, context: Context) {
        nsView.isPresented = isPresented
        nsView.onRequestOpen = onRequestOpen
    }
}

final class TabSwitcherChevronView: NSView {
    /// Mirrors the SwiftUI popover state so a click can tell "open" from "already
    /// open" — a click while it is open dismisses the popover by itself, and must
    /// not immediately reopen it.
    var isPresented = false
    var onRequestOpen: (() -> Void)?

    // Match TabBarMouseView so the click is robust in the custom chrome:
    // register even when the window isn't key, and never start a window drag.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard ChromeHitShape.contains(convert(event.locationInWindow, from: nil), in: bounds) else { return }
        guard !isPresented else { return }
        onRequestOpen?()
    }
}
