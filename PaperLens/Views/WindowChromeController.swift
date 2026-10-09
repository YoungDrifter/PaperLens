//
//  WindowChromeController.swift
//  PaperLens
//
//  Aligns native window buttons with the fixed title row. AppKit owns their
//  visibility and placement inside the full-screen system titlebar.
//
//  The buttons are the real `standardWindowButton`s — controlled by alphaValue,
//  never `isHidden` (which removes them from layout + accessibility and which
//  AppKit fights by re-showing them on key/main/full-screen transitions).
//

import AppKit

final class WindowChromeController: NSObject {
    private weak var window: NSWindow?
    private var isTrafficLightsVisible = false
    private var standardButtonFrames: [NSRect] = []
    private var alignmentScheduled = false
    private var isApplyingAlignment = false
    private var usesSystemFullScreenChrome = false

    init(window: NSWindow) {
        self.window = window
        super.init()
        Self.applyHiddenTitlebarChrome(to: window)
        standardButtonFrames = systemButtons.map(\.frame)
        setTrafficLightsVisible(true, animated: false)
        observeWindowChanges()
        observeButtonLayout()
        scheduleTrafficLightAlignment()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Window setup

    /// Applies PaperLens's hidden-titlebar, full-bleed-content chrome to `window`:
    /// transparent/hidden titlebar with no separator, content under the titlebar.
    /// The single source of truth for this styling — `init` applies it on install
    /// (covering the SwiftUI WindowGroup window), and `AppDelegate.makeHostedWindow`
    /// also calls it at construction so a programmatically-created window never
    /// flashes a solid titlebar before this controller installs.
    static func applyHiddenTitlebarChrome(to window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarSeparatorStyle = .none
        // PaperLens hosts its own tab strip, so a window must never join (or be
        // offered) AppKit's native tab group — see
        // `AppDelegate.disableNativeWindowTabbing()`.
        window.tabbingMode = .disallowed
    }

    private var systemButtons: [NSButton] {
        guard let window else { return [] }
        return [.closeButton, .miniaturizeButton, .zoomButton].compactMap {
            window.standardWindowButton($0)
        }
    }

    private func observeWindowChanges() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(prepareForFullScreen), name: NSWindow.willEnterFullScreenNotification, object: window)
        // AppKit can reset button geometry on window-state transitions.
        let names: [NSNotification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification
        ]
        for name in names {
            nc.addObserver(self, selector: #selector(windowStateChanged(_:)), name: name, object: window)
        }
    }

    private func observeButtonLayout() {
        // Document-title changes can relayout the native buttons without a
        // window resize. Observe their real frames rather than using a timer.
        for button in systemButtons {
            button.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(buttonLayoutChanged),
                name: NSView.frameDidChangeNotification, object: button)
        }
    }

    @objc private func buttonLayoutChanged() {
        guard !isApplyingAlignment else { return }
        scheduleTrafficLightAlignment()
    }

    /// Coalesce native titlebar and SwiftUI updates, then align after layout.
    func scheduleTrafficLightAlignment() {
        guard !alignmentScheduled, !usesSystemFullScreenChrome,
              window?.styleMask.contains(.fullScreen) != true else { return }
        alignmentScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.alignmentScheduled = false }
            guard !self.usesSystemFullScreenChrome,
                  let window = self.window, !window.styleMask.contains(.fullScreen) else { return }
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            self.applyTrafficLightAlpha(animated: false)
        }
    }

    @objc private func prepareForFullScreen() {
        usesSystemFullScreenChrome = true
        // Return the real buttons to AppKit before its full-screen titlebar
        // transition. Full-screen chrome is owned by the system, including reveal.
        for (index, button) in systemButtons.enumerated() {
            if standardButtonFrames.indices.contains(index) { button.frame = standardButtonFrames[index] }
            button.alphaValue = 1
        }
    }

    @objc private func windowStateChanged(_ notification: Notification) {
        if notification.name == NSWindow.didExitFullScreenNotification {
            usesSystemFullScreenChrome = false
        }
        applyTrafficLightAlpha(animated: false)
        scheduleTrafficLightAlignment()
    }

    // MARK: - Native window controls

    /// Normal-window controls remain visible; full-screen reveal belongs to AppKit.
    func setTrafficLightsVisible(_ visible: Bool, animated: Bool = true) {
        if animated && isTrafficLightsVisible == visible { return }
        isTrafficLightsVisible = visible
        applyTrafficLightAlpha(animated: animated)
        scheduleTrafficLightAlignment()
    }

    private func applyTrafficLightAlpha(animated: Bool) {
        guard !isApplyingAlignment else { return }
        isApplyingAlignment = true
        defer { isApplyingAlignment = false }
        let buttons = systemButtons
        guard !buttons.isEmpty else { return }
        if usesSystemFullScreenChrome || window?.styleMask.contains(.fullScreen) == true {
            // Never suppress the controls in macOS's temporarily revealed bar.
            buttons.forEach { $0.alphaValue = 1 }
            return
        }
        let target: CGFloat = isTrafficLightsVisible ? 1 : 0
        if let content = window?.contentView, target == 1 {
            for (index, button) in buttons.enumerated() {
                guard let parent = button.superview else { continue }
                let center = content.convert(NSPoint(x: 20 + CGFloat(index) * 20, y: content.isFlipped ? content.bounds.minY + 27 : content.bounds.maxY - 27), to: parent)
                button.setFrameOrigin(NSPoint(x: center.x - button.frame.width / 2, y: center.y - button.frame.height / 2))
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = DesignTokens.animationFast
                context.allowsImplicitAnimation = true
                buttons.forEach { $0.animator().alphaValue = target }
            }
        } else {
            buttons.forEach { $0.alphaValue = target }
        }
    }
}

// MARK: - Per-window installation

extension WindowChromeController {
    private static var controllerKey: UInt8 = 0

    /// Idempotently attach a chrome controller to `window`. Repeat calls (e.g.
    /// from SwiftUI re-renders) no-op. The controller is retained as an
    /// associated object so it lives exactly as long as the window does.
    static func installIfNeeded(on window: NSWindow) -> WindowChromeController {
        if let existing = objc_getAssociatedObject(window, &controllerKey) as? WindowChromeController {
            return existing
        }
        let controller = WindowChromeController(window: window)
        objc_setAssociatedObject(window, &controllerKey, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return controller
    }

    /// Returns the controller previously installed on `window`, if any.
    static func attached(to window: NSWindow) -> WindowChromeController? {
        objc_getAssociatedObject(window, &controllerKey) as? WindowChromeController
    }
}
