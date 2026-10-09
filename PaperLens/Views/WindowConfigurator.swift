//
//  WindowConfigurator.swift
//  PaperLens
//
//  Configures the NSWindow to hide system chrome and allow full-bleed content.
//

import SwiftUI
import AppKit

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowConfiguratorView { WindowConfiguratorView() }
    func updateNSView(_ nsView: WindowConfiguratorView, context: Context) { }
}

final class WindowConfiguratorView: NSView {
    private weak var configuredWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureIfNeeded()
    }

    private func configureIfNeeded() {
        guard let window else { return }

        if configuredWindow !== window {
            configuredWindow = window
            configureStaticWindowState(window)
        }

    }

    private func configureStaticWindowState(_ window: NSWindow) {
        // Allow window dragging from views that return mouseDownCanMoveWindow = true.
        // DO NOT set isMovable = false - that breaks everything.
        if window.isMovableByWindowBackground {
            window.isMovableByWindowBackground = false
        }

        window.level = .normal
        window.backgroundColor = DesignTokens.viewerBackground
        window.contentMinSize = NSSize(width: DesignTokens.minimumWindowWidth, height: DesignTokens.minimumWindowHeight)
        window.appearance = NSAppearance(named: .aqua)
        if !window.hasShadow {
            window.hasShadow = true
        }

        // Install the chrome controller (idempotent). The controller handles
        // titlebar transparency, fullSizeContentView, hiding the standard
        // window buttons, and hosting the custom traffic-light overlay.
        _ = WindowChromeController.installIfNeeded(on: window)
    }
}
