//
//  WindowDragArea.swift
//  PaperLens
//
//  NSView that enables window dragging for a specific area.
//  Simply returns mouseDownCanMoveWindow = true - macOS handles the rest.
//

import SwiftUI
import AppKit

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowDragView: NSView {
    override func scrollWheel(with event: NSEvent) {
        if !TabBarMouseNSView.scrollTabStrip(from: self, event: event) { super.scrollWheel(with: event) }
    }
    // This is the key - return true to enable window dragging from this area
    override var mouseDownCanMoveWindow: Bool {
        true
    }
}
