//
//  DocumentToolbar.swift
//  PaperLens
//
//  Reading-column toolbar: document, zoom, annotation, and
//  page-navigation controls.
//

import SwiftUI

struct DocumentToolbar: View {
    @Bindable var pdfManager: PDFManager
    @Bindable var annotationManager: AnnotationManager
    @Bindable var commentManager: CommentManager
    @Bindable var bookmarkManager: BookmarkManager
    var availableWidth: CGFloat = 400
    @State private var settingsManager = SettingsManager.shared

    var body: some View {
        controls(level: Self.controlLevel(availableWidth: availableWidth))
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: DesignTokens.chromeButtonSize)
    }

    static func controlLevel(availableWidth: CGFloat) -> Int {
        if availableWidth >= 260 { return 2 }
        if availableWidth >= 219 { return 1 }
        return 0
    }

    private func controls(level: Int) -> some View {
        HStack(spacing: 4) {
            toolbarButton(icon: "minus.magnifyingglass", help: "Zoom Out", action: { pdfManager.zoomOut() }, disabled: !pdfManager.hasDocument)
            toolbarButton(icon: "plus.magnifyingglass", help: "Zoom In", action: { pdfManager.zoomIn() }, disabled: !pdfManager.hasDocument)
            if level >= 1 {
                toolbarButton(icon: "arrow.down.forward.and.arrow.up.backward", help: "Fit Page", action: { pdfManager.requestFitOnce(mode: .page) }, disabled: !pdfManager.hasDocument)
                if level >= 2 { toolbarButton(icon: "arrow.left.and.right", help: "Fit Width", action: { pdfManager.requestFitOnce(mode: .width) }, disabled: !pdfManager.hasDocument) }
                Divider().frame(height: 20)
            }
            annotationTool(icon: "highlighter", title: "Highlight", mode: .highlight)
                .contextMenu { highlightColors }
            annotationTool(icon: "text.bubble", title: "Add Comment", mode: .comment)
                .contextMenu { commentColors }
            Menu {
                Group {
                    Button("Previous Page") { pdfManager.previousPage() }.disabled(!pdfManager.canGoToPreviousPage)
                    Button("Next Page") { pdfManager.nextPage() }.disabled(!pdfManager.canGoToNextPage)
                    Button("Zoom Out") { pdfManager.zoomOut() }
                    Button("Zoom In") { pdfManager.zoomIn() }
                    Button("Fit Page") { pdfManager.requestFitOnce(mode: .page) }
                    Button("Fit Width") { pdfManager.requestFitOnce(mode: .width) }
                    Toggle("Auto-Scale", isOn: Binding(get: { pdfManager.isAutoScaling }, set: { _ in pdfManager.toggleAutoScale() }))
                    Divider()
                    // Page display: the same shared items the View menu shows.
                    PageDisplayModeMenuItems(pdfManager: pdfManager)
                    Divider()
                    Button("Rotate Clockwise") { pdfManager.rotateClockwise() }
                    // Two choices, not one flipping toggle: the mode in use is
                    // dimmed, exactly like Tools → Select Mode / Pan Mode.
                    Button("Select") { pdfManager.interactionMode = .select }
                        .disabled(pdfManager.interactionMode == .select)
                    Button("Pan") { pdfManager.interactionMode = .pan }
                        .disabled(pdfManager.interactionMode == .pan)
                    Divider()
                    Toggle("Highlight", isOn: toolBinding(.highlight))
                    Toggle("Add Comment", isOn: toolBinding(.comment))
                    Button("Toggle Bookmark") { bookmarkManager.toggleBookmark(at: pdfManager.currentPageIndex) }
                }.disabled(!pdfManager.hasDocument)
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: DesignTokens.chromeIconSize)).frame(width: DesignTokens.chromeButtonSize, height: DesignTokens.chromeButtonSize) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More")
        }
    }

    private func toolBinding(_ mode: InteractionMode) -> Binding<Bool> {
        Binding(get: { pdfManager.interactionMode == mode },
                set: { pdfManager.interactionMode = $0 ? mode : .select })
    }

    private func annotationTool(icon: String, title: String, mode: InteractionMode) -> some View {
        ChromeButton(icon, help: title, glass: false, selected: pdfManager.interactionMode == mode) {
            pdfManager.toggleAnnotationTool(mode)
        }
        .disabled(!pdfManager.hasDocument)
        .accessibilityValue(pdfManager.interactionMode == mode ? "Selected" : "Off")
    }

    @ViewBuilder
    private var highlightColors: some View {
        ForEach(settingsManager.highlightPresets) { preset in
            Toggle(isOn: Binding(
                get: { annotationManager.selectionStyle == .highlight && preset.color.isEqual(to: annotationManager.highlightColor) },
                set: { _ in
                    annotationManager.highlightColor = preset.color
                    annotationManager.selectionStyle = .highlight
                    pdfManager.interactionMode = .highlight
                }
            )) { colorLabel(preset.name, color: preset.color) }
        }
        Divider()
        Toggle("Underline", isOn: markupBinding(.underline))
        Toggle("Strikethrough", isOn: markupBinding(.strikethrough))
    }

    private func markupBinding(_ style: SelectionMarkupStyle) -> Binding<Bool> {
        Binding(get: { annotationManager.selectionStyle == style }, set: { _ in
            annotationManager.selectionStyle = style
            pdfManager.interactionMode = .highlight
        })
    }

    private var commentColors: some View {
        ForEach(settingsManager.commentPresets) { preset in
            Toggle(isOn: Binding(
                get: { preset.color.isEqual(to: commentManager.commentColor) },
                set: { _ in commentManager.chooseCommentColor(preset.color) }
            )) { colorLabel(preset.name, color: preset.color) }
        }
    }

    private func colorLabel(_ name: String, color: NSColor) -> some View {
        Label { Text(name) } icon: { Image(nsImage: colorSwatch(color)) }
    }

    private func colorSwatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            color.withAlphaComponent(1).setFill()
            circle.fill()
            NSColor.black.withAlphaComponent(0.15).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
    }

    private func toolbarButton(icon: String, help: String, action: @escaping () -> Void, disabled: Bool = false) -> some View {
        ChromeButton(icon, help: help, glass: false, action: action).disabled(disabled)
    }

}
