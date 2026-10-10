//
//  PaperLensApp.swift
//  PaperLens
//
//  Created by Chong Pin Shin on 7/12/25.
//

import SwiftUI
import PDFKit

@main
struct PaperLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var updater = AppUpdater.shared
    @State private var recentFilesManager = RecentFilesManager()
    @State private var settingsManager = SettingsManager.shared

    init() { _ = PluginManager.shared
        AppUpdater.shared.start() }

    // MARK: - Focused Values

    @FocusedValue(\.tabManager) private var focusedSceneTabManager
    @FocusedValue(\.showingSearch) private var focusedShowingSearch
    @FocusedValue(\.searchFocusRequest) private var focusedSearchFocusRequest

    /// Reactive frontmost-window fallback for the menu commands. `@FocusedValue`
    /// resolves nil when the key window (e.g. a manually-created ⌘N / tear-off
    /// window) holds no focused SwiftUI view, so commands routed purely through
    /// it would no-op AND grey out. Resolving `focused ?? frontmost` keeps both
    /// the action targets and the enabled state on the window the user is in.
    @State private var activeWindow = ActiveWindowModel.shared

    /// The TabManager every menu command (⌘T/⌘W/⌘S/Find/…) targets: the focused
    /// window's, else the frontmost window's. Reactive on both inputs.
    private var focusedTabManager: TabManager? {
        focusedSceneTabManager ?? activeWindow.tabManager
    }

    @State private var firstLaunchManager = FirstLaunchManager()

    // MARK: - Computed Properties

    private var hasDocument: Bool {
        focusedTabManager?.activePDFManager?.hasDocument == true
    }

    private var pdfManager: PDFManager? {
        focusedTabManager?.activePDFManager
    }

    private var canEditPages: Bool {
        guard let manager = focusedTabManager, let id = manager.activeTabID else { return false }
        // Page commands belong to the visible thumbnail sidebar.
        if NSApp.keyWindow?.firstResponder is NSTextView || NSApp.keyWindow?.firstResponder is NSTextField {
            return false
        }
        return manager.showingSidebar(for: id) && manager.sidebarMode(for: id) == .thumbnails
    }

    private var pageCount: Int {
        pdfManager?.pageCount ?? 0
    }

    private var showingSidebarLabel: String {
        "Toggle Sidebar"  // Static to prevent body re-evaluation
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            TabContainerView()
                .environment(recentFilesManager)
                .onAppear {
                    appDelegate.windowContentBuilder = { tabManager in
                        AnyView(
                            TabContainerView(tabManager: tabManager)
                                .environment(recentFilesManager)
                        )
                    }
                }
        }
        .defaultSize(width: DesignTokens.defaultWindowWidth, height: DesignTokens.defaultWindowHeight)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppIdentity.displayName)") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: AppIdentity.displayName, .applicationIcon: AppIdentity.icon,
                        .applicationVersion: AppIdentity.versionLabel, .version: ""])
                }
                Divider()
                appMenuContent
            }
            CommandGroup(replacing: .newItem) { fileNewMenuContent }
            CommandGroup(after: .importExport) { fileSaveMenuContent }
            CommandGroup(replacing: .undoRedo) { editUndoMenuContent }
            CommandGroup(after: .pasteboard) { editFindMenuContent }
            // Document commands belong INSIDE the system View menu. Declaring a
            // `CommandMenu("View")` here instead produced a second, empty "View"
            // menu in the menu bar (AppKit already creates the real one), so the
            // items are inserted into that menu through its placement group.
            CommandGroup(replacing: .sidebar) { viewMenuContent }
            CommandMenu("Go") { goMenuContent }
            CommandMenu("Tools") { toolsMenuContent }
            CommandMenu("Tab") { tabMenuContent }
            CommandGroup(after: .appSettings) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }

        // MARK: Settings Window
        Settings {
            SettingsView()
        }
        .defaultSize(width: DesignTokens.settingsWindowWidth, height: DesignTokens.settingsWindowHeight)
        .windowResizability(.contentMinSize)
    }

    // MARK: - App Menu

    @ViewBuilder
    private var appMenuContent: some View {
        Button(firstLaunchManager.isDefaultPDFReader ? "✓ Default PDF Reader" : "Set as Default PDF Reader…") {
            firstLaunchManager.setAsDefaultPDFReader()
        }
        .disabled(firstLaunchManager.isDefaultPDFReader)
    }

    // MARK: - File Menu

    @ViewBuilder
    private var fileNewMenuContent: some View {
        Button("New Tab") {
            focusedTabManager?.createNewTab()
        }
        .keyboardShortcut(for: "newTab")
        .disabled(focusedTabManager == nil)

        Button("New Window") {
            openNewWindow()
        }
        .keyboardShortcut(for: "newWindow")

        Divider()

        Button("Open…") {
            focusedTabManager?.openFilePicker()
        }
        .keyboardShortcut(for: "openFile")
        .disabled(focusedTabManager == nil)

        Menu("Open Recent") {
            ForEach(recentFilesManager.recentFiles) { recentFile in
                Button(recentFile.displayName) {
                    openRecentFile(recentFile)
                }
            }

            if !recentFilesManager.recentFiles.isEmpty {
                Divider()
                Button("Clear Menu") {
                    recentFilesManager.clearRecentFiles()
                }
            }
        }
        .disabled(recentFilesManager.recentFiles.isEmpty)

        Divider()

        Button("Close Tab") {
            focusedTabManager?.closeActiveTab()
        }
        .keyboardShortcut(for: "closeTab")
        .disabled(focusedTabManager?.tabs.isEmpty != false)
    }

    @ViewBuilder
    private var fileSaveMenuContent: some View {
        Button("Save") {
            Task { await handleSave() }
        }
        .keyboardShortcut(for: "save")
        .disabled(!hasDocument)
    }

    // MARK: - Edit Menu

    private var activeUndoManager: UndoManager? {
        focusedTabManager?.activeUndoManager
    }

    private var canUndo: Bool {
        (focusedTabManager?.activeCanUndo ?? false) ||
            (focusedTabManager?.activeCommentManager?.hasPendingTextEdit ?? false)
    }

    private var canRedo: Bool {
        focusedTabManager?.activeCanRedo ?? false
    }

    @ViewBuilder
    private var editUndoMenuContent: some View {
        Button("Undo") {
            focusedTabManager?.activeCommentManager?.stopEditing()
            let um = activeUndoManager
            #if DEBUG
            Swift.print("[UNDO] pressed: um=\(um.map { "\(ObjectIdentifier($0))" } ?? "nil"), canUndo=\(um?.canUndo ?? false)")
            #endif
            um?.undo()
        }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(!canUndo)

        Button("Redo") {
            let um = activeUndoManager
            #if DEBUG
            Swift.print("[REDO] pressed: um=\(um.map { "\(ObjectIdentifier($0))" } ?? "nil"), canRedo=\(um?.canRedo ?? false)")
            #endif
            um?.redo()
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(!canRedo)
    }

    @ViewBuilder
    private var editFindMenuContent: some View {
        Divider()

        Button("Find…") {
            if hasDocument {
                focusedShowingSearch?.wrappedValue = true
                focusedSearchFocusRequest?.wrappedValue += 1
            }
        }
        .keyboardShortcut(for: "search")
        .disabled(!hasDocument)

        Divider()

        Button("Delete Page") {
            guard let manager = pdfManager,
                  manager.pageCount > 1 else { return }
            manager.deletePage(at: manager.currentPageIndex)
        }
        .keyboardShortcut(for: "deletePage")
        .disabled(!hasDocument || !canEditPages || pageCount <= 1)

        Divider()

        Button("Copy Page") {
            guard let manager = pdfManager else { return }
            manager.copyPage(at: manager.currentPageIndex)
        }
        .keyboardShortcut(for: "copyPage")
        .disabled(!hasDocument || !canEditPages)

        Button("Cut Page") {
            guard let manager = pdfManager,
                  manager.pageCount > 1 else { return }
            manager.cutPage(at: manager.currentPageIndex)
        }
        .keyboardShortcut(for: "cutPage")
        .disabled(!hasDocument || !canEditPages || pageCount <= 1)

        Button("Paste Page") {
            guard let manager = pdfManager else { return }
            _ = manager.pastePage(after: manager.currentPageIndex)
        }
        .keyboardShortcut(for: "pastePage")
        .disabled(!hasDocument || !canEditPages || !(pdfManager?.canPaste ?? false))
    }

    // MARK: - View Menu

    @ViewBuilder
    private var viewMenuContent: some View {
        Button("Zoom In") {
            pdfManager?.zoomIn()
        }
        .keyboardShortcut(for: "zoomIn")
        .disabled(!hasDocument)

        Button("Zoom Out") {
            pdfManager?.zoomOut()
        }
        .keyboardShortcut(for: "zoomOut")
        .disabled(!hasDocument)

        Button("Fit Page") {
            pdfManager?.requestFitOnce(mode: .page)
        }
        .keyboardShortcut(for: "actualSize")
        .disabled(!hasDocument)

        Button("Fit Width") {
            pdfManager?.requestFitOnce()
        }
        .keyboardShortcut(for: "zoomToFit")
        .disabled(!hasDocument)

        // Auto-Scale is a sizing command like the ones above, so it sits in that
        // group instead of its own section.
        Toggle("Auto-Scale", isOn: Binding(
            get: { pdfManager?.isAutoScaling ?? false },
            set: { newValue in
                guard let manager = pdfManager else { return }
                manager.isAutoScaling = newValue
                manager.pendingFit = nil
            }
        ))
        .disabled(!hasDocument || (pdfManager?.displayMode == .twoUp || pdfManager?.displayMode == .twoUpContinuous))

        Divider()

        PageDisplayModeMenuItems(pdfManager: pdfManager)

        Divider()

        Button(showingSidebarLabel) {
            focusedTabManager?.showingOutline.toggle()
        }
        .keyboardShortcut(for: "toggleSidebar")
        .disabled(!hasDocument)

        Toggle("Show Tab Bar", isOn: Binding(get: { focusedTabManager?.isTabBarVisible ?? false }, set: { focusedTabManager?.setTabBarVisible($0) }))
            .disabled(focusedTabManager == nil)
        Toggle("Show Toolbar", isOn: Binding(get: { focusedTabManager?.isToolbarExpanded ?? true }, set: { focusedTabManager?.isToolbarExpanded = $0 }))
            .keyboardShortcut(for: "toggleToolbar")

        // No "Enter Full Screen" item here: AppKit already puts its own in the View
        // menu, and a second one was the duplicate users kept hitting.
    }

    // MARK: - Go Menu

    @ViewBuilder
    private var goMenuContent: some View {
        // Menus and toolbar arrows share the same page navigation rules.
        Button("Next Page") {
            pdfManager?.nextPage()
        }
        .keyboardShortcut(for: "nextPage")
        .disabled(!(pdfManager?.canGoToNextPage ?? false))

        Button("Previous Page") {
            pdfManager?.previousPage()
        }
        .keyboardShortcut(for: "previousPage")
        .disabled(!(pdfManager?.canGoToPreviousPage ?? false))

        Divider()

        Button("First Page") {
            pdfManager?.goToFirstPage()
        }
        .keyboardShortcut(for: "firstPage")
        .disabled(!hasDocument)

        Button("Last Page") {
            pdfManager?.goToLastPage()
        }
        .keyboardShortcut(for: "lastPage")
        .disabled(!hasDocument)

        Divider()

        Button("Go to Page…") {
            guard let tabManager = focusedTabManager else { return }
            tabManager.showingGoToPage.toggle()
        }
        .keyboardShortcut(for: "goToPage")
        .disabled(!hasDocument)
    }

    // MARK: - Tools Menu

    @ViewBuilder
    private var toolsMenuContent: some View {
        Button("Select Mode") {
            pdfManager?.interactionMode = .select
        }
        .disabled(!hasDocument || pdfManager?.interactionMode == .select)

        Button("Pan Mode") {
            pdfManager?.interactionMode = .pan
        }
        .disabled(!hasDocument || pdfManager?.interactionMode == .pan)

        Divider()

        Toggle("Highlight", isOn: Binding(
            get: { pdfManager?.interactionMode == .highlight },
            set: { pdfManager?.interactionMode = $0 ? .highlight : .select }
        ))
        .keyboardShortcut(for: "highlight")
        .disabled(!hasDocument)

        Toggle("Add Comment", isOn: Binding(
            get: { pdfManager?.interactionMode == .comment },
            set: { pdfManager?.interactionMode = $0 ? .comment : .select }
        ))
        .keyboardShortcut(for: "comment")
        .disabled(!hasDocument)

        Divider()

        Button("Toggle Bookmark") {
            if let manager = focusedTabManager?.activeBookmarkManager,
               let pageIndex = pdfManager?.currentPageIndex {
                manager.toggleBookmark(at: pageIndex)
            }
        }
        .keyboardShortcut(for: "bookmark")
        .disabled(!hasDocument)

        Divider()

        Button("Rotate Clockwise") {
            pdfManager?.rotateClockwise()
        }
        .keyboardShortcut(for: "rotateClockwise")
        .disabled(!hasDocument)

        Button("Rotate Counter-Clockwise") {
            pdfManager?.rotateCounterClockwise()
        }
        .keyboardShortcut(for: "rotateCounterClockwise")
        .disabled(!hasDocument)

    }

    // MARK: - Tab Menu

    @ViewBuilder
    private var tabMenuContent: some View {
        Button("Recent Files…") {
            TabSwitcherController.shared.toggle(forWindow: NSApp.keyWindow, hostTabManager: focusedTabManager)
        }
        .keyboardShortcut(for: "searchTabs")
        .disabled(focusedTabManager == nil)

        Divider()

        Button("Select Next Tab") {
            focusedTabManager?.selectNextTab()
        }
        .keyboardShortcut(for: "selectNextTab")
        .disabled(focusedTabManager?.tabCount ?? 0 <= 1)

        Button("Select Previous Tab") {
            focusedTabManager?.selectPreviousTab()
        }
        .keyboardShortcut(for: "selectPreviousTab")
        .disabled(focusedTabManager?.tabCount ?? 0 <= 1)

        Divider()

        ForEach(1...9, id: \.self) { index in
            Button("Select Tab \(index)") {
                focusedTabManager?.selectTabByIndex(index - 1)
            }
            .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
            .disabled(index > (focusedTabManager?.tabCount ?? 0))
        }
    }

    // MARK: - Helper Methods

    private func openRecentFile(_ recentFile: RecentFile) {
        guard let resolved = recentFilesManager.resolveRecentFile(recentFile) else { return }

        // `focusedTabManager` already folds in the frontmost-window fallback,
        // which is nil only when no window exists at all — exactly when we want
        // the new-window branch below.
        if let tabManager = focusedTabManager {
            tabManager.openDocument(url: resolved.url, isSecurityScoped: resolved.isSecurityScoped)
        } else {
            appDelegate.enqueuePendingURLs([resolved.url], isSecurityScoped: resolved.isSecurityScoped)
            openNewWindow()
        }
    }

    private func handleSave() async {
        guard let tabManager = focusedTabManager else { return }
        let result = await tabManager.saveActiveDocument()
        if case .failure(let message) = result {
            showAlert(message: message)
        }
    }

    private func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func openNewWindow() {
        let contentView = TabContainerView()
            .environment(recentFilesManager)
        appDelegate.createNewWindow(with: contentView)
    }

}
