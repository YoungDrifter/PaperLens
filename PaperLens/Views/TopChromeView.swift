import SwiftUI
import AppKit

/// Window title row and its full-width content separator.
struct TopChromeView: View {
    @State private var showingFileInfo = false
    @Bindable var tabManager: TabManager
    @State private var isFullScreen = false
    @State private var showingCompactTools = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings

    static let height: CGFloat = 54
    static let tabRowHeight: CGFloat = 32
    static func trafficLightInset(isFullScreen: Bool) -> CGFloat { isFullScreen ? 0 : 78 }

    private var titleWidth: CGFloat {
        let name = tabManager.activeTab?.displayTitle ?? "PaperLens"
        let width = (name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)]).width
        return min(240, ceil(width) + 30)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            Divider()
        }
        .background(DesignTokens.chromeSurface)
    }

    private var titleRow: some View {
        GeometryReader { geometry in
            HStack(spacing: 4) {
                if !isFullScreen {
                    Color.clear.frame(width: Self.trafficLightInset(isFullScreen: false))
                }
                ChromeButton("sidebar.left", help: "Toggle Sidebar", action: tabManager.toggleSidebar)
                    .disabled(tabManager.activePDFManager?.hasDocument != true)
                HStack(spacing: 2) {
                    ChromeButton("macwindow.badge.plus", help: "New Tab", glass: false, size: 32) { tabManager.createNewTab() }
                    ChromeButton("rectangle.topthird.inset.filled", help: tabManager.isTabBarVisible ? "Hide Tab Bar" : "Show Tab Bar",
                                 glass: false, selected: tabManager.isTabBarVisible, size: 32, iconOffsetY: -2, action: tabManager.toggleTabBar)
                        .accessibilityValue(tabManager.isTabBarVisible ? "Shown" : "Hidden")
                    Divider().frame(height: 14).padding(.horizontal, 2)
                    ChromeButton("chevron.left", help: "Back", glass: false, size: 32) { tabManager.activePDFManager?.goBack() }
                        .disabled(tabManager.activePDFManager?.canGoBack != true)
                    ChromeButton("chevron.right", help: "Forward", glass: false, size: 32) { tabManager.activePDFManager?.goForward() }
                        .disabled(tabManager.activePDFManager?.canGoForward != true)
                }
                .padding(3).paperLensGlassCapsule()
                ZStack {
                    Button { showingFileInfo.toggle() } label: {
                        HStack(spacing: 5) {
                            if let id = tabManager.activeTabID, tabManager.isTabDirty(id) {
                                Circle().fill(Color.secondary).frame(width: 6, height: 6)
                            }
                            Text(tabManager.activeTab?.displayTitle ?? "PaperLens")
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1).truncationMode(.middle)
                                // Align the visible capital-height center, rather than
                                // the font line box (which includes descender space).
                                .alignmentGuide(VerticalAlignment.center) { dimensions in
                                    dimensions[.firstTextBaseline] - NSFont.systemFont(ofSize: 13, weight: .medium).capHeight / 2
                                }
                            Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: titleWidth)
                        .frame(height: 38)
                        .help(tabManager.activeTab?.displayTitle ?? "PaperLens")
                        .layoutPriority(-1)
                    }
                    .buttonStyle(.plain)
                    .onChange(of: tabManager.activeTabID) { _, _ in showingFileInfo = false }
                    .disabled(tabManager.activePDFManager?.documentURL == nil)
                    .popover(isPresented: $showingFileInfo) {
                        if let url = tabManager.activePDFManager?.documentURL {
                            DocumentFileInfoPopover(url: url, update: tabManager.updateActiveFile) { showingFileInfo = false }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: 4) {
                    if tabManager.isToolbarExpanded, Self.expandedToolsWidth(windowWidth: geometry.size.width) >= 206, let runtime = tabManager.activeRuntime {
                        DocumentToolbar(pdfManager: runtime.pdfManager, annotationManager: runtime.annotationManager,
                                        commentManager: runtime.commentManager, bookmarkManager: runtime.bookmarkManager,
                                        availableWidth: Self.expandedToolsWidth(windowWidth: geometry.size.width))
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    ChromeButton(tabManager.isToolbarExpanded ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver", help: "Show or Hide Tools", glass: false) {
                        if Self.expandedToolsWidth(windowWidth: geometry.size.width) < 206 {
                            showingCompactTools.toggle()
                        } else { tabManager.isToolbarExpanded.toggle() }
                    }
                }
                .padding(.horizontal, 4)
                .paperLensGlassCapsule()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: tabManager.isToolbarExpanded)
                .popover(isPresented: $showingCompactTools, arrowEdge: .bottom) {
                    if let runtime = tabManager.activeRuntime {
                        DocumentToolbar(pdfManager: runtime.pdfManager, annotationManager: runtime.annotationManager,
                                        commentManager: runtime.commentManager, bookmarkManager: runtime.bookmarkManager)
                            .fixedSize().padding(12).preferredColorScheme(.light)
                    }
                }
                pageControl(windowWidth: geometry.size.width)
                HStack(spacing: 4) {
                    TabSwitcherChevron(tabManager: tabManager, isInteractive: true, usesGlass: false)
                    ChromeButton("gearshape", help: "Settings", glass: false) { openSettings() }
                }
                .padding(.horizontal, 4)
                .paperLensGlassCapsule()
            }
            .padding(.horizontal, 8)
            .frame(width: geometry.size.width, height: Self.height)
        }
        .frame(height: Self.height)
        .background(DesignTokens.chromeSurface)
        .background(WindowChromeStateReporter(isFullScreen: $isFullScreen))
    }

    private func pageControl(windowWidth: CGFloat) -> some View {
        let pdf = tabManager.activePDFManager
        let page = (pdf?.currentPageIndex ?? 0) + 1
        let total = pdf?.pageCount ?? 0
        return Button { tabManager.showingGoToPage = true } label: {
            Text(total == 0 ? "—" : (windowWidth >= 900 ? "Page \(page) of \(total)" : "\(page) / \(total)"))
                .font(.system(size: 12, weight: .medium)).monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: Self.pageControlWidth(windowWidth: windowWidth), height: DesignTokens.chromeButtonSize)
                .paperLensGlassCapsule()
        }
        .buttonStyle(.plain).disabled(total == 0).help("Go to Page")
        .accessibilityLabel("Page \(page) of \(total); Go to Page")
    }
    static func pageControlWidth(windowWidth: CGFloat) -> CGFloat {
        windowWidth >= 900 ? 128 : 76
    }
    static func expandedToolsWidth(windowWidth: CGFloat) -> CGFloat {
        // Preserve room for tabs and fixed controls; additional tools extend left.
        // Allow the complete toolbar to fit; Fit Width stays in compact layouts.
        min(337, max(0, windowWidth - 594 - pageControlWidth(windowWidth: windowWidth)))
    }

}

struct ChromeButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    let glass: Bool
    let selected: Bool
    let size: CGFloat
    let iconOffsetY: CGFloat
    @State private var hovering = false
    init(_ icon: String, help: String, glass: Bool = true, selected: Bool = false, size: CGFloat = DesignTokens.chromeButtonSize, iconOffsetY: CGFloat = 0, action: @escaping () -> Void) {
        self.icon = icon; self.help = help; self.glass = glass; self.selected = selected; self.size = size; self.iconOffsetY = iconOffsetY; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Group {
                if glass { iconLabel.paperLensGlassCapsule() } else { iconLabel }
            }
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
    private var iconLabel: some View {
        Image(systemName: icon).foregroundStyle(Color.black).font(.system(size: DesignTokens.chromeIconSize))
            .offset(y: iconOffsetY)
            .frame(width: size, height: size)
            .background(Capsule().fill(Color.black.opacity(selected ? 0.12 : (hovering ? DesignTokens.chromeHoverOpacity : 0))))
            .contentShape(Capsule())
    }

}

/// Native borderless menus need the same hover feedback as chrome buttons.
struct ChromeMenuHoverFeedback: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .overlay(ChromeMenuHoverTracker(isEnabled: isEnabled).allowsHitTesting(false))
    }
}

private struct ChromeMenuHoverTracker: NSViewRepresentable {
    let isEnabled: Bool
    func makeNSView(context: Context) -> ChromeMenuHoverView { ChromeMenuHoverView() }
    func updateNSView(_ view: ChromeMenuHoverView, context: Context) {
        view.isControlEnabled = isEnabled
        view.refreshHover()
    }
    static func dismantleNSView(_ view: ChromeMenuHoverView, coordinator: ()) {
        view.onHover = nil
    }
}

/// Track the actual native menu bounds without intercepting clicks or menu events.
final class ChromeMenuHoverView: NSView {
    var isControlEnabled = true
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?
    private var lastHover = false
    override func draw(_ dirtyRect: NSRect) {
        guard lastHover, isControlEnabled else { return }
        NSColor.black.withAlphaComponent(DesignTokens.chromeHoverOpacity).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero,
            options: [.inVisibleRect, .activeInActiveApp, .mouseEnteredAndExited], owner: self)
        addTrackingArea(next); area = next
        refreshHover()
    }
    override func mouseEntered(with event: NSEvent) { setHover(isControlEnabled) }
    override func mouseExited(with event: NSEvent) { setHover(false) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshHover() }
    func refreshHover() {
        guard isControlEnabled, let window, !isHiddenOrHasHiddenAncestor, NSApp.isActive else { setHover(false); return }
        setHover(visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
    }
    private func setHover(_ value: Bool) {
        guard value != lastHover else { return }
        lastHover = value
        needsDisplay = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lastHover == value else { return }
            self.onHover?(value)
        }
    }
}

private struct WindowChromeStateReporter: NSViewRepresentable {
    @Binding var isFullScreen: Bool
    func makeNSView(context: Context) -> WindowChromeStateView {
        let view = WindowChromeStateView()
        view.onState = { value in if isFullScreen != value { isFullScreen = value } }
        return view
    }
    func updateNSView(_ view: WindowChromeStateView, context: Context) {
        view.onState = { value in if isFullScreen != value { isFullScreen = value } }
    }
}

private final class WindowChromeStateView: NSView {
    var onState: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        guard let window else { return }
        WindowChromeController.installIfNeeded(on: window).setTrafficLightsVisible(true, animated: false)
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.publishState() }
            })
        }
        publishState()
    }
    private func publishState() {
        let fullScreen = window?.styleMask.contains(.fullScreen) == true
        DispatchQueue.main.async { [weak self] in self?.onState?(fullScreen) }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

/// File metadata editor presented from the document title.
private struct DocumentFileInfoPopover: View {
    let url: URL
    let update: (URL, [String]) throws -> Void
    let dismiss: () -> Void
    @State private var name = ""
    @State private var tags = ""
    @State private var error: String?
    @FocusState private var nameFocused: Bool
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Text("Name:").foregroundStyle(.secondary)
                TextField("File name", text: $name).textFieldStyle(.roundedBorder)
                    .focused($nameFocused).onSubmit(apply)
            }
            GridRow {
                Text("Tags:").foregroundStyle(.secondary)
                TextField("Separate tags with commas", text: $tags).textFieldStyle(.roundedBorder).onSubmit(apply)
            }
            if let error { Text(error).foregroundStyle(.red).gridCellColumns(2).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel", action: dismiss)
                Button("Done", action: apply).keyboardShortcut(.defaultAction)
            }.gridCellColumns(2)
        }
        .padding(18).frame(width: 380)
        .onAppear {
            name = url.lastPathComponent
            tags = ((try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []).joined(separator: ", ")
            nameFocused = true
        }
    }
    private func apply() {
        do {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != ".", trimmed != "..", !trimmed.contains("/"), !trimmed.contains("\0") else {
                throw NSError(domain: "DocumentName", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter a valid file name."])
            }
            let destination = url.deletingLastPathComponent().appendingPathComponent(trimmed)
            let names = Array(NSOrderedSet(array: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })) as? [String] ?? []
            try update(destination, names)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
