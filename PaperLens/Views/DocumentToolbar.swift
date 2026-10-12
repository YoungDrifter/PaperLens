//
//  DocumentToolbar.swift
//  PaperLens
//
//  Reading-column toolbar: document, zoom, annotation, and
//  page-navigation controls.
//

import SwiftUI
import PDFKit

struct DocumentToolbar: View {
    @Bindable var pdfManager: PDFManager
    @Bindable var annotationManager: AnnotationManager
    @Bindable var commentManager: CommentManager
    @Bindable var bookmarkManager: BookmarkManager
    var availableWidth: CGFloat = 400
    @State private var showingReadingModes = false
    @State private var showingMore = false
    @State private var showingHighlightMenu = false
    @State private var showingCommentMenu = false
    @State private var settingsManager = SettingsManager.shared

    var body: some View {
        controls(level: Self.controlLevel(availableWidth: availableWidth))
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: DesignTokens.chromeButtonSize)
    }

    static let minimumWidth = width(buttonCount: 5, divider: false)
    static let intermediateWidth = width(buttonCount: 7, divider: true)
    static let fullWidth = width(buttonCount: 8, divider: true)
    private static func width(buttonCount: Int, divider: Bool) -> CGFloat {
        CGFloat(buttonCount) * DesignTokens.chromeButtonSize
            + CGFloat(buttonCount - 1 + (divider ? 1 : 0)) * DesignTokens.chromeSpacing
            + (divider ? 1 : 0)
    }

    static func controlLevel(availableWidth: CGFloat) -> Int {
        if availableWidth >= fullWidth { return 2 }
        if availableWidth >= intermediateWidth { return 1 }
        return 0
    }

    private func controls(level: Int) -> some View {
        HStack(spacing: 4) {
            if level >= 1 {
                toolbarButton(icon: "minus.magnifyingglass", help: "Zoom Out", action: { pdfManager.zoomOut() }, disabled: !pdfManager.hasDocument)
                toolbarButton(icon: "plus.magnifyingglass", help: "Zoom In", action: { pdfManager.zoomIn() }, disabled: !pdfManager.hasDocument)
            }
            if level >= 2 {
                toolbarButton(icon: "arrow.down.forward.and.arrow.up.backward", help: "Fit Page", action: { pdfManager.requestFitOnce(mode: .page) }, disabled: !pdfManager.hasDocument)
            }
            toolbarButton(icon: "arrow.left.and.right", help: "Fit Width", action: { pdfManager.requestFitOnce(mode: .width) }, disabled: !pdfManager.hasDocument)
            if level >= 1 { Divider().frame(height: 20) }
            ChromeButton("rectangle.split.2x1", help: "Reading Mode", glass: false, selected: showingReadingModes) {
                showingReadingModes.toggle()
            }
            .accessibilityValue(pdfManager.displayMode.menuTitle)
            .disabled(!pdfManager.hasDocument)
            .popover(isPresented: $showingReadingModes) {
                PopupActionList(title: "Reading Mode", actions: readingActions, onDismiss: { showingReadingModes = false })
            }
            annotationTool(icon: "highlighter", title: "Highlight", mode: .highlight)
                .onRightClick { showingHighlightMenu = true }
                .popover(isPresented: $showingHighlightMenu) {
                    PopupActionList(title: "Highlight", actions: highlightActions, width: 220,
                                    onDismiss: { showingHighlightMenu = false })
                }
            annotationTool(icon: "text.bubble", title: "Add Comment", mode: .comment)
                .onRightClick { showingCommentMenu = true }
                .popover(isPresented: $showingCommentMenu) {
                    PopupActionList(title: "Comment Color", actions: commentActions, width: 220,
                                    onDismiss: { showingCommentMenu = false })
                }
            ChromeButton("ellipsis", help: "More", glass: false, selected: showingMore) { showingMore.toggle() }
                .disabled(!pdfManager.hasDocument)
                .popover(isPresented: $showingMore) {
                    PopupActionList(title: "Document Tools", actions: moreActions, onDismiss: { showingMore = false })
                }
        }
    }

    private var readingActions: [PopupAction] {
        PDFDisplayMode.menuChoices.enumerated().map { index, mode in
            PopupAction(title: mode.menuTitle,
                        symbol: ["rectangle", "rectangle.portrait.on.rectangle.portrait", "rectangle.split.2x1", "square.grid.2x2"][index],
                        selected: pdfManager.displayMode == mode, enabled: pdfManager.hasDocument) {
                pdfManager.displayMode = mode
            }
        }
    }

    var moreActions: [PopupAction] {
        [
            PopupAction(title: "Previous Page", symbol: "chevron.left", enabled: pdfManager.canGoToPreviousPage) { pdfManager.previousPage() },
            PopupAction(title: "Next Page", symbol: "chevron.right", enabled: pdfManager.canGoToNextPage) { pdfManager.nextPage() },
            PopupAction(title: "Zoom Out", symbol: "minus.magnifyingglass", separatorBefore: true) { pdfManager.zoomOut() },
            PopupAction(title: "Zoom In", symbol: "plus.magnifyingglass") { pdfManager.zoomIn() },
            PopupAction(title: "Fit Page", symbol: "arrow.down.forward.and.arrow.up.backward") { pdfManager.requestFitOnce(mode: .page) },
            PopupAction(title: "Fit Width", symbol: "arrow.left.and.right") { pdfManager.requestFitOnce(mode: .width) },
            PopupAction(title: "Auto-Scale", symbol: "arrow.up.left.and.arrow.down.right", selected: pdfManager.isAutoScaling) { pdfManager.toggleAutoScale() }
        ] + readingActions.enumerated().map { index, item in
            var row = item; row.separatorBefore = index == 0; return row
        } + [
            PopupAction(title: "Rotate Clockwise", symbol: "rotate.right", separatorBefore: true) { pdfManager.rotateClockwise() },
            PopupAction(title: "Select", symbol: "cursorarrow", selected: pdfManager.interactionMode == .select, enabled: pdfManager.interactionMode != .select) { pdfManager.interactionMode = .select },
            PopupAction(title: "Pan", symbol: "hand.draw", selected: pdfManager.interactionMode == .pan, enabled: pdfManager.interactionMode != .pan) { pdfManager.interactionMode = .pan },
            PopupAction(title: "Highlight", symbol: "highlighter", selected: pdfManager.interactionMode == .highlight, separatorBefore: true) { pdfManager.toggleAnnotationTool(.highlight) },
            PopupAction(title: "Add Comment", symbol: "text.bubble", selected: pdfManager.interactionMode == .comment) { pdfManager.toggleAnnotationTool(.comment) },
            PopupAction(title: "Toggle Bookmark", symbol: "bookmark") { bookmarkManager.toggleBookmark(at: pdfManager.currentPageIndex) }
        ]
    }

    private func annotationTool(icon: String, title: String, mode: InteractionMode) -> some View {
        ChromeButton(icon, help: title, glass: false, selected: pdfManager.interactionMode == mode) {
            pdfManager.toggleAnnotationTool(mode)
        }
        .disabled(!pdfManager.hasDocument)
        .accessibilityValue(pdfManager.interactionMode == mode ? "Selected" : "Off")
    }

    /// Highlight colours and markup styles, in the same rows as every other popup.
    private var highlightActions: [PopupAction] {
        var actions = settingsManager.highlightPresets.map { preset in
            PopupAction(title: preset.name, swatch: preset.color,
                        selected: annotationManager.selectionStyle == .highlight
                            && preset.color.isEqual(to: annotationManager.highlightColor)) {
                annotationManager.highlightColor = preset.color
                annotationManager.selectionStyle = .highlight
                pdfManager.interactionMode = .highlight
            }
        }
        actions.append(PopupAction(title: "Underline", symbol: "underline",
                                   selected: annotationManager.selectionStyle == .underline,
                                   separatorBefore: true) { selectMarkup(.underline) })
        actions.append(PopupAction(title: "Strikethrough", symbol: "strikethrough",
                                   selected: annotationManager.selectionStyle == .strikethrough) { selectMarkup(.strikethrough) })
        return actions
    }

    private func selectMarkup(_ style: SelectionMarkupStyle) {
        annotationManager.selectionStyle = style
        pdfManager.interactionMode = .highlight
    }

    private var commentActions: [PopupAction] {
        settingsManager.commentPresets.map { preset in
            PopupAction(title: preset.name, swatch: preset.color,
                        selected: preset.color.isEqual(to: commentManager.commentColor)) {
                commentManager.chooseCommentColor(preset.color)
            }
        }
    }

    private func toolbarButton(icon: String, help: String, action: @escaping () -> Void, disabled: Bool = false) -> some View {
        ChromeButton(icon, help: help, glass: false, action: action).disabled(disabled)
    }

}
