//
//  TabBarView.swift
//  PaperLens
//
//  Pure SwiftUI renderer for one window's tab strip. All drag state lives
//  in `TabDragController.shared`; this view is a projection of it. Mouse
//  events flow through `TabBarMouseView` (an AppKit overlay) so we never
//  re-enter SwiftUI's body during a drag.
//

import SwiftUI

struct TabBarView: View {
    @Bindable var tabManager: TabManager
    let isInteractive: Bool

    @State private var dragController = TabDragController.shared
    @State private var tabFrames: [UUID: CGRect] = [:]
    @State private var newTabButtonFrame: CGRect = .zero
    @State private var hoveredTabID: UUID?

    init(tabManager: TabManager, isInteractive: Bool = true) {
        self.tabManager = tabManager
        self.isInteractive = isInteractive
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ZStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
                                tabView(for: tab, width: max(140, (geometry.size.width - 16) / CGFloat(max(tabManager.tabs.count, 1)) - 2))
                                    .overlay(alignment: .trailing) {
                                        if !dragController.isActive, index + 1 < tabManager.tabs.count,
                                           tabManager.activeTabID != tab.id,
                                           tabManager.activeTabID != tabManager.tabs[index + 1].id {
                                            RoundedRectangle(cornerRadius: 0.5).fill(Color.black.opacity(0.18))
                                                .frame(width: 1, height: 16).offset(x: 1)
                                                .allowsHitTesting(false).accessibilityHidden(true)
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 2)
                    }
                    .clipped()
                    .onPreferenceChange(TabFramePreferenceKey.self) { frames in
                        guard isInteractive, tabFrames != frames else { return }
                        tabFrames = frames
                    }
                    .onPreferenceChange(NewTabButtonFramePreferenceKey.self) { frame in
                        let newFrame = frame ?? .zero
                        guard isInteractive, newTabButtonFrame != newFrame else { return }
                        newTabButtonFrame = newFrame
                    }

                    if isInteractive {
                        WindowDragArea()
                        TabBarMouseView(
                            tabManager: tabManager,
                            tabFrames: tabFrames,
                            newTabButtonFrame: newTabButtonFrame,
                            hoveredTabID: hoveredTabID,
                            activeTabID: tabManager.activeTabID,
                            onHover: { hoveredTabID = $0 },
                            onClick: handleClick
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .coordinateSpace(name: Self.coordinateSpace)
                .onAppear { revealActiveTab(using: scrollProxy) }
                .onChange(of: geometry.size.width) { _, _ in revealActiveTab(using: scrollProxy) }
                .onChange(of: tabManager.activeTabID) { _, _ in revealActiveTab(using: scrollProxy) }
                .onChange(of: tabManager.tabs.map(\.id)) { _, _ in revealActiveTab(using: scrollProxy) }
                .onChange(of: isInteractive) { _, interactive in
                    guard !interactive else { return }
                    tabFrames = [:]
                    newTabButtonFrame = .zero
                    hoveredTabID = nil
                }
            }
        }
    }

    private func revealActiveTab(using proxy: ScrollViewProxy) {
        guard !dragController.isActive, let id = tabManager.activeTabID else { return }
        // Wait until the resized viewport / newly inserted tab has its new frame.
        DispatchQueue.main.async { proxy.scrollTo(id) }
    }

    // MARK: - Tab View

    @ViewBuilder
    private func tabView(for tab: TabModel, width: CGFloat) -> some View {
        let isDragging = draggingLocalTabID == tab.id

        TabItemView(
            tab: tab,
            isActive: tab.id == tabManager.activeTabID,
            isDirty: tabManager.isTabDirty(tab.id),
            isHovering: hoveredTabID == tab.id,
            isDragInProgress: dragController.isActive,
            width: width
        )
        .id(tab.id)
        .background(tabFrameReporter(for: tab.id))
        .offset(x: shiftOffset(for: tab.id))
        // The source tab stays in its layout slot at opacity 0 while the
        // floating preview owns the visible drag affordance.
        .opacity(isDragging ? 0 : 1)
        .allowsHitTesting(false)
        // Animate gap shifts only when the insertion index actually changes.
        // The controller dedupes per-pixel updates, so this fires at most
        // once per tab boundary crossed — not 60 times per second.
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: localInsertionIndex)
    }

    @ViewBuilder
    private func tabFrameReporter(for tabID: UUID) -> some View {
        if isInteractive {
            GeometryReader { geo in
                Color.clear.preference(
                    key: TabFramePreferenceKey.self,
                    value: [tabID: geo.frame(in: .named(Self.coordinateSpace))]
                )
            }
        }
    }

    // MARK: - Drag State Projections

    private var draggingLocalTabID: UUID? {
        guard let drag = dragController.activeDrag,
              drag.sourceManagerID == ObjectIdentifier(tabManager) else {
            return nil
        }
        return drag.tabID
    }

    private var localInsertionIndex: Int? {
        guard let drag = dragController.activeDrag,
              drag.insertionTargetID == ObjectIdentifier(tabManager) else {
            return nil
        }
        return drag.insertionIndex
    }

    private func shiftOffset(for tabID: UUID) -> CGFloat {
        guard let drag = dragController.activeDrag,
              drag.tabID != tabID,
              let targetIndex = localInsertionIndex,
              let thisIndex = tabManager.tabs.firstIndex(where: { $0.id == tabID }) else {
            return 0
        }

        let shiftWidth = drag.draggedWidth + DesignTokens.tabSpacing
        let isLocalDrag = drag.sourceManagerID == ObjectIdentifier(tabManager)

        if isLocalDrag {
            // Source bar: tabs between the source slot and the insertion
            // gap shift toward the source slot to open the gap.
            guard let sourceIndex = tabManager.tabs.firstIndex(where: { $0.id == drag.tabID }) else {
                return 0
            }
            if sourceIndex < targetIndex,
               (sourceIndex + 1..<targetIndex).contains(thisIndex) {
                return -shiftWidth
            }
            if targetIndex < sourceIndex,
               (targetIndex..<sourceIndex).contains(thisIndex) {
                return shiftWidth
            }
            return 0
        }

        // Cross-window drop: dragged tab isn't in this list. Tabs at and
        // after the insertion index shift right to make room for it.
        return thisIndex >= targetIndex ? shiftWidth : 0
    }

    // MARK: - Click Routing

    private func handleClick(_ target: TabBarClickTarget) {
        switch target {
        case .newTab:
            tabManager.createNewTab()
        case .selectTab(let tabID):
            tabManager.selectTab(tabID)
        case .closeTab(let tabID):
            tabManager.closeTab(tabID)
        }
    }

    // MARK: - Constants

    private static let coordinateSpace = "tabBar"
}

// MARK: - Preference Keys

private struct TabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct NewTabButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}
