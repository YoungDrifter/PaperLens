import AppKit
import PDFKit
import SwiftUI
import Testing
@testable import PaperLens

@MainActor
struct PreviewLayoutTests {
    @Test func nativeMenuHoverActuallyChangesRenderedBackground() async throws {
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap { descendants($0) }
        }
        let host = NSHostingView(rootView:
            Menu { Button("Item") {} } label: {
                Image(systemName: "ellipsis.circle").frame(width: 38, height: 38)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .frame(width: DesignTokens.chromeButtonSize, height: DesignTokens.chromeButtonSize)
            .modifier(ChromeMenuHoverFeedback()).padding(8).background(Color.white)
        )
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 54, height: 54), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        let pointer = NSEvent.mouseLocation
        let outsideOrigin = NSPoint(x: pointer.x + 100, y: pointer.y + 100)
        window.setFrameOrigin(outsideOrigin)
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let tracker = try #require(descendants(host).compactMap { $0 as? ChromeMenuHoverView }.first)
        #expect(tracker.bounds.width >= 38 && tracker.bounds.height >= 38)
        let event = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        func sampleBackground() throws -> CGFloat {
            descendants(host).forEach { $0.needsDisplay = true }
            host.display()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let point = tracker.convert(NSPoint(x: tracker.bounds.midX, y: 4), to: host)
            let x = Int(point.x / host.bounds.width * CGFloat(bitmap.pixelsWide))
            let y = Int(point.y / host.bounds.height * CGFloat(bitmap.pixelsHigh))
            return try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)).redComponent
        }
        tracker.mouseExited(with: event)
        try await Task.sleep(for: .milliseconds(50))
        let normal = try sampleBackground()
        tracker.mouseEntered(with: event)
        try await Task.sleep(for: .milliseconds(50))
        let hovered = try sampleBackground()
        #expect(normal > 0.98)
        #expect(hovered < normal - 0.02, "native menu must visibly draw its hover background")
        tracker.mouseExited(with: event)
        try await Task.sleep(for: .milliseconds(50))
        #expect(abs(try sampleBackground() - normal) < 0.01)
    }

    @Test func nativeMenuHoverTracksEntryExitAndDisabledStateWithoutInterceptingClicks() async throws {
        let view = ChromeMenuHoverView(frame: NSRect(x: 0, y: 0, width: 38, height: 38))
        var states: [Bool] = []
        view.onHover = { states.append($0) }
        view.updateTrackingAreas()
        #expect(view.trackingAreas.count == 1)
        #expect(view.trackingAreas[0].options.contains(.inVisibleRect))
        #expect(view.hitTest(NSPoint(x: 19, y: 19)) == nil)
        let event = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: NSPoint(x: 19, y: 19),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        view.mouseEntered(with: event)
        try await Task.sleep(for: .milliseconds(20))
        #expect(states == [true])
        view.mouseExited(with: event)
        try await Task.sleep(for: .milliseconds(20))
        #expect(states == [true, false])
        view.isControlEnabled = false
        view.mouseEntered(with: event)
        try await Task.sleep(for: .milliseconds(20))
        #expect(states == [true, false])
    }

    @Test func sidebarStateIsExclusiveAndTravelsWithTab() throws {
        let source = TabManager()
        let id = try #require(source.activeTabID)
        #expect(!source.showingSidebar(for: id))
        #expect(source.sidebarMode(for: id) == .outline)
        source.toggleSidebar()
        source.setSidebarMode(.bookmarks, for: id)
        source.setOutlineSidebarWidth(330, for: id)
        source.toggleSidebar(); source.toggleSidebar()
        #expect(source.sidebarMode(for: id) == .bookmarks)
        source.setShowingComments(true, for: id)
        #expect(source.showingComments && !source.showingOutline)
        source.setShowingOutline(true, for: id)
        #expect(source.showingOutline && !source.showingComments)
        source.setSidebarMode(.thumbnails, for: id)
        let destination = TabManager(createInitialTab: false)
        destination.isToolbarExpanded = false
        #expect(source.moveTab(id, to: destination, at: 0))
        #expect(destination.sidebarMode(for: id) == .thumbnails)
        #expect(destination.outlineSidebarWidth(for: id) == 330)
        #expect(destination.showingSidebar(for: id))
        #expect(!destination.isToolbarExpanded)
        #expect(TabUIState().sidebarMode == .outline)
    }

    @Test func tabBarVisibilityFollowsCountUntilManualChoiceAndStaysWindowLocal() throws {
        let manager = TabManager()
        #expect(!manager.isTabBarVisible)
        let first = try #require(manager.activeTabID)
        manager.createNewTab()
        #expect(manager.isTabBarVisible)
        manager.toggleTabBar()
        #expect(!manager.isTabBarVisible)
        manager.createNewTab()
        manager.selectTab(first)
        #expect(!manager.isTabBarVisible)
        manager.toggleTabBar()
        for tab in manager.tabs where tab.id != first { manager.closeTab(tab.id) }
        #expect(manager.tabs.count == 1)
        #expect(manager.isTabBarVisible)
        #expect(!TabManager().isTabBarVisible)
        let automatic = TabManager()
        automatic.createNewTab()
        automatic.closeTab(try #require(automatic.activeTabID))
        #expect(!automatic.isTabBarVisible)
        automatic.setTabBarVisible(true)
        #expect(automatic.isTabBarVisible)
        automatic.setTabBarVisible(false)
        automatic.toggleTabBar()
        #expect(automatic.isTabBarVisible)
    }

    @Test func documentSplitReservesReaderWidth() {
        let split = DocumentSplitNSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        split.addArrangedSubview(NSView()); split.addArrangedSubview(NSView())
        split.preferredWidth = 420; split.sidebarVisible = true; split.applyLayout()
        #expect(split.arrangedSubviews[0].frame.width == 420)
        #expect(split.arrangedSubviews[1].frame.minX >= 420)
        #expect(split.arrangedSubviews[1].frame.width >= 320)
        split.setFrameSize(NSSize(width: 560, height: 600)); split.applyLayout()
        #expect(split.arrangedSubviews[0].frame.width <= 239)
        #expect(split.arrangedSubviews[1].frame.width >= 320)
        #expect(split.preferredWidth == 420)
        split.setFrameSize(NSSize(width: 900, height: 600)); split.applyLayout()
        #expect(split.arrangedSubviews[0].frame.width == 420)
        split.sidebarVisible = false; split.applyLayout()
        #expect(split.arrangedSubviews[0].isHidden)
        #expect(split.arrangedSubviews[1].frame.width == 900)
    }

    @Test func dividerTracksHoverCursorUpdatesAndDrag() throws {
        let split = DocumentSplitNSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        split.addArrangedSubview(NSView()); split.addArrangedSubview(NSView())
        split.sidebarVisible = true
        split.applyLayout()
        let handle = try #require(split.subviews.first { !split.arrangedSubviews.contains($0) })
        handle.updateTrackingAreas()
        #expect(handle.trackingAreas.contains {
            $0.options.contains(.cursorUpdate) && $0.options.contains(.mouseMoved)
                && $0.options.contains(.enabledDuringMouseDrag)
        })
        handle.updateTrackingAreas()
        #expect(handle.trackingAreas.count == 1)
    }

    @Test func dividerWinsHitTestingOnBothSidesOfVisibleLine() throws {
        let split = DocumentSplitNSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        split.addArrangedSubview(NSHostingView(rootView: Color.clear))
        split.addArrangedSubview(NSHostingView(rootView: Color.clear))
        split.sidebarVisible = true
        split.applyLayout()
        let handle = try #require(split.subviews.first { !split.arrangedSubviews.contains($0) })
        let lineX = split.arrangedSubviews[0].frame.maxX + 0.5
        for offset: CGFloat in [-5, 0, 5] {
            #expect(split.hitTest(NSPoint(x: lineX + offset, y: 300)) === handle)
        }
        split.sidebarVisible = false
        #expect(split.hitTest(NSPoint(x: lineX, y: 300)) !== handle)
    }

    @Test func dividerChangeSurvivesLayout() async {
        let split = DocumentSplitNSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        split.addArrangedSubview(NSView()); split.addArrangedSubview(NSView())
        split.sidebarVisible = true; split.applyLayout()
        var storedWidth: CGFloat = 240
        split.onWidthChange = { storedWidth = $0 }
        split.setPosition(350, ofDividerAt: 0)
        split.layoutSubtreeIfNeeded()
        await Task.yield()
        #expect(abs(split.preferredWidth - 350) < 1)
        #expect(abs(storedWidth - 350) < 1)
        #expect(abs(split.arrangedSubviews[0].frame.width - 350) < 1)
    }

    @Test func trafficLightsAlignWithFixedTitleRowAfterResizeAndFullscreen() throws {
        let window = AppDelegate.makeHostedWindow(contentView: Color.clear, contentSize: NSSize(width: 800, height: 600))
        defer { window.close() }
        let controller = WindowChromeController.installIfNeeded(on: window)
        for size in [NSSize(width: 800, height: 600), NSSize(width: 560, height: 400)] {
            window.setContentSize(size)
            controller.setTrafficLightsVisible(true, animated: false)
            let content = try #require(window.contentView)
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                let button = try #require(window.standardWindowButton(kind))
                let rect = button.convert(button.bounds, to: nil)
                let contentInWindow = content.convert(content.bounds, to: nil)
                #expect(abs(rect.midY - (contentInWindow.maxY - TopChromeView.height / 2)) < 0.5)
                #expect(button.alphaValue == 1)
            }
        }
        #expect(TopChromeView.trafficLightInset(isFullScreen: true) == 0)
        #expect(TopChromeView.trafficLightInset(isFullScreen: false) == 78)
        #expect(TopChromeView.height == 54)
        #expect(TopChromeView.expandedToolsWidth(windowWidth: 900) == 178)
        // The top chrome must actually allocate enough room for every control.
        #expect(DocumentToolbar.controlLevel(availableWidth: TopChromeView.expandedToolsWidth(windowWidth: 1200)) == 2)
    }

    @Test func trafficLightsRecoverFromDocumentTitleLayoutWithoutResize() async throws {
        let window = AppDelegate.makeHostedWindow(contentView: Color.clear, contentSize: NSSize(width: 900, height: 600))
        defer { window.close() }
        _ = WindowChromeController.installIfNeeded(on: window)
        let content = try #require(window.contentView)
        let titleView = WindowTitleView()
        content.addSubview(titleView)
        let originalWindowFrame = window.frame
        for title in ["First document", "第二个文档 with a longer title"] {
            titleView.title = title
            // AppKit can reset these native frames during its titlebar layout,
            // after SwiftUI updates the document title, without resizing a window.
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                let button = try #require(window.standardWindowButton(kind))
                button.setFrameOrigin(NSPoint(x: button.frame.minX, y: button.frame.minY - 6))
            }
            try await Task.sleep(for: .milliseconds(50))
            #expect(window.frame == originalWindowFrame)
            let expectedY = content.convert(content.bounds, to: nil).maxY - TopChromeView.height / 2
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                let button = try #require(window.standardWindowButton(kind))
                #expect(abs(button.convert(button.bounds, to: nil).midY - expectedY) < 0.5)
            }
        }
    }

    @Test func hostedPreviewLayoutUsesIndependentDocument() async throws {
        let manager = TabManager()
        let id = try #require(manager.activeTabID)
        let document = makeTestDocument(pageCount: 3)
        let root = PDFOutline()
        for index in 0..<3 {
            let item = PDFOutline()
            item.label = index == 0 ? "中文长目录：这是一个独立的布局测试文档 English title wrapping" : "Chapter \(index + 1)"
            item.destination = PDFDestination(page: document.page(at: index)!, at: .zero)
            root.insertChild(item, at: index)
        }
        document.outlineRoot = root
        manager.createNewTab()
        manager.selectTab(id)
        manager.tabs[0].title = "pde_notes"
        manager.activePDFManager?.document = document
        manager.activePDFManager?.isDirty = true
        manager.setShowingSidebar(true, for: id)
        let suiteName = "PaperLens-layout-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let recent = RecentFilesManager(defaults: defaults)
        let window = AppDelegate.makeHostedWindow(contentView: TabContainerView(tabManager: manager).environment(recent), contentSize: NSSize(width: 900, height: 600))
        defer { window.contentView = nil; window.close(); defaults.removePersistentDomain(forName: suiteName) }
        try await Task.sleep(for: .milliseconds(300))
        window.contentView?.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let content = try #require(window.contentView)
        let split = try #require(descendants(content).compactMap { $0 as? DocumentSplitNSView }.first { !$0.arrangedSubviews[0].isHidden })
        // No NSSplitView may exist in the window at all: AppKit's
        // `NSSplitViewSidebar` behaviour crashed this app while enabling menu
        // items when an NSSplitView sat in the responder chain.
        #expect(descendants(content).allSatisfy { !($0 is NSSplitView) },
                "document layout must not build an NSSplitView")
        #expect(split.arrangedSubviews[0].frame.width == 240)
        #expect(split.arrangedSubviews[1].frame.width >= 320)
        let pdf = try #require(descendants(split).compactMap { $0 as? StablePDFView }.first)
        #expect(pdf.frame.width > 500)
        print("QA_GEOMETRY: split=\(split.bounds) reader=\(split.arrangedSubviews[1].frame) pdf=\(pdf.frame) pdfHost=\(String(describing: pdf.superview?.frame))")
        #expect(abs(pdf.frame.height + TopChromeView.tabRowHeight - split.bounds.height) < 2)
        let tabMouse = try #require(descendants(content).compactMap { $0 as? TabBarMouseNSView }.first)
        let barRect = tabMouse.convert(tabMouse.bounds, to: content)
        let readerRect = split.arrangedSubviews[1].convert(split.arrangedSubviews[1].bounds, to: content)
        #expect(abs(barRect.minX - readerRect.minX) < 1)
        #expect(abs(barRect.width - readerRect.width) < 1)
        #expect(abs(barRect.height - 32) < 1)
        let splitHeight = split.bounds.height
        manager.toggleTabBar()
        try await Task.sleep(for: .milliseconds(100))
        content.layoutSubtreeIfNeeded()
        #expect(!descendants(content).contains { $0 is TabBarMouseNSView })
        #expect(!TabDragController.shared.isRegisteredBar(tabMouse, for: manager))
        #expect(abs(split.bounds.height - splitHeight) < 1)
        #expect(abs(pdf.frame.height - splitHeight) < 1)
        manager.toggleTabBar()
        try await Task.sleep(for: .milliseconds(100))
        content.layoutSubtreeIfNeeded()
        #expect(abs(split.bounds.height - splitHeight) < 1)
        for size in [NSSize(width: 900, height: 600), NSSize(width: 720, height: 600)] {
            window.setContentSize(size)
            try await Task.sleep(for: .milliseconds(100))
            content.layoutSubtreeIfNeeded()
            let resizedBar = try #require(descendants(content).compactMap { $0 as? TabBarMouseNSView }.first)
            #expect(abs(resizedBar.bounds.width - split.arrangedSubviews[1].bounds.width) < 1)
            #expect(split.arrangedSubviews[1].frame.width >= 320)
        }
        for visible in [true, false] {
            manager.setTabBarVisible(visible)
            try await Task.sleep(for: .milliseconds(100))
            content.layoutSubtreeIfNeeded()
            #expect(abs(split.bounds.height - splitHeight) < 1)
            #expect(abs(pdf.frame.height + (visible ? TopChromeView.tabRowHeight : 0) - splitHeight) < 2)
            #expect(descendants(content).contains { $0 is TabBarMouseNSView } == visible)
        }
        manager.setTabBarVisible(true)
        try await Task.sleep(for: .milliseconds(100))
        let close = try #require(window.standardWindowButton(.closeButton))
        #expect(close.convert(close.bounds, to: nil).midY > window.frame.height - 44)
        split.setPosition(320, ofDividerAt: 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(abs(manager.outlineSidebarWidth(for: id) - 320) < 1)
        let resizedBar = try #require(descendants(content).compactMap { $0 as? TabBarMouseNSView }.first)
        let resizedReader = split.arrangedSubviews[1]
        #expect(abs(resizedBar.bounds.width - resizedReader.bounds.width) < 1)
        #expect(abs(resizedBar.convert(resizedBar.bounds, to: content).minX - resizedReader.convert(resizedReader.bounds, to: content).minX) < 1)
        manager.setShowingSidebar(false, for: id)
        try await Task.sleep(for: .milliseconds(100))
        content.layoutSubtreeIfNeeded()
        #expect(abs(resizedBar.bounds.width - content.bounds.width) < 1)
        manager.setShowingSidebar(true, for: id)
        try await Task.sleep(for: .milliseconds(100))
        manager.isToolbarExpanded = false
        try await Task.sleep(for: .milliseconds(100))
        content.layoutSubtreeIfNeeded()
        manager.isToolbarExpanded = true
        try await Task.sleep(for: .milliseconds(100))
        content.layoutSubtreeIfNeeded()
    }

    @Test func overflowingTabsScrollAndRevealSelectionAfterWindowShrink() async throws {
        let manager = TabManager()
        for _ in 0..<9 { manager.createNewTab() }
        for index in manager.tabs.indices {
            manager.tabs[index].title = "Long document title number \(index) with overflow"
        }
        let first = try #require(manager.tabs.first?.id)
        let last = try #require(manager.tabs.last?.id)
        manager.selectTab(first)
        let suite = "PaperLens-tab-scroll-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let recent = RecentFilesManager(defaults: defaults)
        let window = AppDelegate.makeHostedWindow(contentView: TabContainerView(tabManager: manager).environment(recent), contentSize: NSSize(width: 1200, height: 600))
        defer { window.contentView = nil; window.close(); defaults.removePersistentDomain(forName: suite) }
        try await Task.sleep(for: .milliseconds(150))
        let content = try #require(window.contentView)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let mouse = try #require(descendants(content).compactMap { $0 as? TabBarMouseNSView }.first)
        var scroll = try #require(TabBarMouseNSView.tabScrollView(overlapping: mouse))
        let document = try #require(scroll.documentView)
        #expect(window.contentMinSize.width >= 720)
        #expect(document.frame.width > scroll.contentView.bounds.width)
        let close = try #require(window.standardWindowButton(.closeButton))
        let controlsBefore = close.convert(close.bounds, to: nil)
        let before = scroll.contentView.bounds.minX
        #expect(TabBarMouseNSView.scrollTabStrip(from: mouse, delta: -80, precise: true))
        #expect(scroll.contentView.bounds.minX > before)
        try await Task.sleep(for: .milliseconds(30))
        #expect(mouse.hitTest(NSPoint(x: -1, y: 16)) == nil)
        #expect(close.convert(close.bounds, to: nil) == controlsBefore)
        #expect(TabBarMouseNSView.scrollTabStrip(from: mouse, delta: 10000, precise: true))
        #expect(abs(scroll.contentView.bounds.minX) < 1)
        manager.selectTab(last)
        try await Task.sleep(for: .milliseconds(150))
        let activeMouse = try #require(descendants(content).compactMap { $0 as? TabBarMouseNSView }.first)
        scroll = try #require(TabBarMouseNSView.tabScrollView(overlapping: activeMouse))
        let selectedOffset = scroll.contentView.bounds.minX
        #expect(selectedOffset > 0)
        window.setContentSize(NSSize(width: 720, height: 600))
        content.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        #expect(scroll.contentView.bounds.minX > selectedOffset)
        manager.selectTab(first)
        try await Task.sleep(for: .milliseconds(150))
        let firstMouse = try #require(descendants(content).compactMap { $0 as? TabBarMouseNSView }.first)
        scroll = try #require(TabBarMouseNSView.tabScrollView(overlapping: firstMouse))
        #expect(scroll.contentView.bounds.minX < 10)
    }

    @Test func nativeOutlineWrapsTitlesAndExcludesStructuralSelection() throws {
        let document = makeTestDocument(pageCount: 3)
        let root = PDFOutline()
        let structural = PDFOutline(); structural.label = "Structural heading without destination"
        let long = PDFOutline(); long.label = String(repeating: "中文目录 long English chapter title ", count: 4)
        long.destination = PDFDestination(page: document.page(at: 0)!, at: .zero)
        structural.insertChild(long, at: 0); root.insertChild(structural, at: 0)
        let items = OutlineItem.buildRoot(from: root)
        let view = NativeOutlineView(items: items, activeItemID: OutlineItem.activeItemID(in: items, pageIndex: 0), onSelect: { _ in })
        let coordinator = view.makeCoordinator()
        let outline = OutlineTable(frame: NSRect(x: 0, y: 0, width: 240, height: 500))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("outline")); column.width = 240
        outline.addTableColumn(column); outline.outlineTableColumn = column
        outline.dataSource = coordinator; outline.delegate = coordinator
        coordinator.outline = outline; coordinator.update(view)
        let parent = try #require(coordinator.roots.first)
        let child = try #require(parent.children.first)
        #expect(coordinator.outlineView(outline, isItemExpandable: parent))
        #expect(!coordinator.outlineView(outline, shouldSelectItem: parent))
        #expect(coordinator.outlineView(outline, shouldSelectItem: child))
        let wideHeight = coordinator.outlineView(outline, heightOfRowByItem: child)
        column.width = 180
        #expect(coordinator.outlineView(outline, heightOfRowByItem: child) > wideHeight)
        #expect(outline.selectionHighlightStyle == .regular)
        #expect(outline.selectedRow >= 0)
    }

    @Test func hostedOutlineKeepsWrappedTitlesInsideActualRows() async throws {
        let document = makeTestDocument(pageCount: 168)
        let root = PDFOutline()
        let titles = ["第一章 线性方程组的直接法", "第二章 线性方程组的迭代法",
                      "第三章 最小二乘问题的数值方法", "第四章 特征值问题的数值解法"]
        for (index, title) in titles.enumerated() {
            let entry = PDFOutline()
            entry.label = title
            entry.destination = PDFDestination(page: document.page(at: [8, 45, 76, 102][index])!, at: .zero)
            let child = PDFOutline()
            child.label = "小节：迭代收敛条件与误差估计"
            child.destination = entry.destination
            let nested = PDFOutline()
            nested.label = "4.1.3 特征值定位与误差界的推导"
            nested.destination = entry.destination
            child.insertChild(nested, at: 0)
            entry.insertChild(child, at: 0)
            root.insertChild(entry, at: index)
        }
        let items = OutlineItem.buildRoot(from: root)
        let host = NSHostingView(rootView: NativeOutlineView(items: items, activeItemID: items[3].id, onSelect: { _ in }).background(Color.white))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 250, height: 500),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for width: CGFloat in [250, 180, 320, 240] {
            window.setContentSize(NSSize(width: width, height: 500))
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let outline = try #require(descendants(host).compactMap { $0 as? OutlineTable }.first)
            for expand in [false, true, false] {
                if expand { outline.expandItem(nil, expandChildren: true) }
                else { outline.collapseItem(nil, collapseChildren: true) }
                host.layoutSubtreeIfNeeded()
                // Realize the cells first, then allow AppKit's disclosure layout and
                // the measured-width height pass to settle before inspecting frames.
                for row in 0..<outline.numberOfRows {
                    _ = outline.view(atColumn: 0, row: row, makeIfNecessary: true)
                }
                try await Task.sleep(for: .milliseconds(300))
                host.layoutSubtreeIfNeeded()
                for row in 0..<outline.numberOfRows {
                    let cell = try #require(outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? OutlineCell)
                    cell.layoutSubtreeIfNeeded()
                    let neededHeight = cell.title.sizeThatFits(NSSize(width: cell.title.frame.width, height: .greatestFiniteMagnitude)).height
                    #expect(cell.bounds.height >= ceil(neededHeight) + 12,
                            "width \(width), row \(row): \(cell.bounds.height) vs title \(neededHeight)")
                    #expect(cell.title.frame.minY >= 6)
                    #expect(cell.title.frame.maxY <= cell.bounds.height - 6)
                    #expect(outline.rect(ofRow: row).height >= ceil(neededHeight) + 12)
                    #expect(cell.title.stringValue == (outline.item(atRow: row) as? NativeOutlineView.Node)?.value.title)
                    #expect(!cell.title.isHidden && !cell.isHidden)
                    #expect(cell.superview != nil)
                    let clip = try #require(outline.enclosingScrollView?.contentView)
                    #expect(outline.frame.width <= clip.bounds.width + 0.5)
                    let pageRect = cell.page.convert(cell.page.bounds, to: outline)
                    #expect(pageRect.minX >= outline.visibleRect.minX)
                    #expect(pageRect.maxX <= outline.visibleRect.maxX,
                            "page label clipped at width \(width), row \(row)")
                    let rowView = try #require(outline.rowView(atRow: row, makeIfNecessary: true) as? OutlineHoverRow)
                    let pageInRow = cell.page.convert(cell.page.bounds, to: rowView)
                    #expect(pageInRow.maxX <= rowView.backgroundRect.maxX - 8,
                            "page label must remain inside the rounded highlight with padding")
                    if outline.isExpandable(outline.item(atRow: row)) {
                        #expect(outline.frameOfOutlineCell(atRow: row).minX >= rowView.backgroundRect.minX)
                    }
                }
                if width == 250 && !expand,
                   let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    descendants(host).forEach { $0.needsDisplay = true }
                    host.display()
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("paperlens-outline-layout-fixed.png"))
                    }
                }
            }
        }
    }

    /// The Settings scene used to be a `NavigationSplitView`, i.e. a second
    /// `NSSplitView` in the app. It must stay free of one (see
    /// `DocumentSplitNSView` for the crash this guards against).
    @Test func settingsWindowBuildsNoSplitView() async throws {
        let window = AppDelegate.makeHostedWindow(
            contentView: SettingsView(),
            contentSize: NSSize(width: DesignTokens.settingsWindowWidth, height: DesignTokens.settingsWindowHeight)
        )
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(200))
        let content = try #require(window.contentView)
        content.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        #expect(descendants(content).allSatisfy { !($0 is NSSplitView) },
                "settings layout must not build an NSSplitView")
        #expect(content.frame.width >= 640)
    }
}

@MainActor
struct RecentHistoryTests {
    @Test func historyDeduplicatesSortsResolvesMissingAndClears() throws {
        let name = "PaperLens-history-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("a.pdf"), second = directory.appendingPathComponent("b.pdf")
        try Data().write(to: first); try Data().write(to: second)
        let manager = RecentFilesManager(defaults: defaults)
        manager.addRecentFile(first); manager.addRecentFile(second); manager.addRecentFile(first)
        #expect(manager.recentFiles.map(\.url) == [first, second])
        let loaded = RecentFilesManager(defaults: defaults)
        #expect(loaded.recentFiles.count == 2)
        #expect(manager.resolveRecentFile(manager.recentFiles[0])?.url == first)
        try FileManager.default.removeItem(at: second)
        let missing = try #require(manager.recentFiles.last)
        #expect(manager.resolveRecentFile(missing) == nil)
        #expect(manager.recentFiles.count == 1)
        manager.clearRecentFiles()
        #expect(manager.recentFiles.isEmpty)
        #expect(RecentFilesManager(defaults: defaults).recentFiles.isEmpty)
    }
}
