//
//  OutlineItemTests.swift
//  PaperLensTests
//
//  Outline tree identity, structural nodes and current-section selection.
//

import AppKit
import PDFKit
import Testing
@testable import PaperLens

@MainActor
struct OutlineItemTests {

    // MARK: - Fixtures

    /// An outline root whose children point at the given page indices
    /// (nil = an entry without a destination).
    private func makeOutlineRoot(in document: PDFDocument, pages: [Int?]) -> PDFOutline {
        let root = PDFOutline()
        for (index, pageIndex) in pages.enumerated() {
            let child = PDFOutline()
            child.label = "Section \(index)"
            if let pageIndex, let page = document.page(at: pageIndex) {
                child.destination = PDFDestination(page: page, at: NSPoint(x: 0, y: 0))
            }
            root.insertChild(child, at: index)
        }
        return root
    }

    @Test func rowHeightMatchesRenderedTitleAtWrapBoundary() {
        let text = "2.5 子空间拓扑与乘积拓扑"
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.maximumNumberOfLines = 0
        let singleLine = label.sizeThatFits(NSSize(width: 1000, height: CGFloat.greatestFiniteMagnitude)).height
        // Sweep the boundary to catch a row that reserves a second line while
        // the NSTextField still renders only one.
        for cellWidth in stride(from: CGFloat(170), through: 270, by: 1) {
            let height = label.sizeThatFits(NSSize(width: OutlineCell.titleWidth(for: cellWidth), height: CGFloat.greatestFiniteMagnitude)).height
            let rowHeight = OutlineCell.rowHeight(for: text, cellWidth: cellWidth)
            #expect(rowHeight == max(30, ceil(height) + 12))
            if height == singleLine { #expect(rowHeight == 30) }
        }
        #expect(OutlineCell.rowHeight(for: text, cellWidth: 170) > 30)
        #expect(OutlineCell.rowHeight(for: text, cellWidth: 270) == 30)
    }

    @Test func nestedOutlineRowsUseActualCellWidthWhenSidebarResizes() {
        let document = makeTestDocument(pageCount: 2)
        let root = makeOutlineRoot(in: document, pages: [0])
        let child = PDFOutline()
        child.label = "2.5 子空间拓扑与乘积拓扑"
        child.destination = PDFDestination(page: document.page(at: 1)!, at: .zero)
        root.child(at: 0)!.insertChild(child, at: 0)
        let items = OutlineItem.buildRoot(from: root)
        let owner = NativeOutlineView(items: items, activeItemID: OutlineItem.activeItemID(in: items, pageIndex: 1), onSelect: { _ in })
        let coordinator = NativeOutlineView.Coordinator(owner)
        let outline = OutlineTable(frame: NSRect(x: 0, y: 0, width: 280, height: 400))
        outline.headerView = nil
        outline.indentationPerLevel = 14
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("outline"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = coordinator
        outline.delegate = coordinator
        coordinator.outline = outline
        coordinator.update(owner)
        outline.expandItem(coordinator.roots[0])
        for width: CGFloat in [200, 240, 280, 400, 240] {
            column.width = width
            outline.frame.size.width = width
            outline.layoutSubtreeIfNeeded()
            outline.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<outline.numberOfRows))
            for row in 0..<outline.numberOfRows {
                let node = outline.item(atRow: row) as! NativeOutlineView.Node
                let cell = OutlineCell(frame: outline.frameOfCell(atColumn: 0, row: row))
                cell.title.stringValue = node.value.title
                cell.layoutSubtreeIfNeeded()
                let measured = coordinator.outlineView(outline, heightOfRowByItem: node)
                #expect(measured == max(30, ceil(cell.title.frame.height) + 12))
            }
        }
    }

    // MARK: - Sibling linking

    @Test
    func activeSectionUsesLatestPageRegardlessOfOutlineOrder() {
        let document = makeTestDocument(pageCount: 10)
        let items = OutlineItem.buildRoot(from: makeOutlineRoot(in: document, pages: [5, nil, 2, 8]))
        #expect(OutlineItem.activeItemID(in: items, pageIndex: 1) == nil)
        #expect(OutlineItem.activeItemID(in: items, pageIndex: 4) == items[2].id)
        #expect(OutlineItem.activeItemID(in: items, pageIndex: 7) == items[0].id)
        #expect(OutlineItem.activeItemID(in: items, pageIndex: 9) == items[3].id)
        #expect(OutlineItem.activeItemID(in: [], pageIndex: 0) == nil)
    }

    @Test
    func activeSectionPrefersDeepestEntryAtSamePage() {
        let document = makeTestDocument(pageCount: 10)
        let root = makeOutlineRoot(in: document, pages: [0, 5])
        let child = PDFOutline()
        child.label = "Subsection"
        child.destination = PDFDestination(page: document.page(at: 0)!, at: .zero)
        root.child(at: 0)!.insertChild(child, at: 0)
        let items = OutlineItem.buildRoot(from: root)
        #expect(OutlineItem.activeItemID(in: items, pageIndex: 0) == items[0].children![0].id)
        #expect(OutlineItem.activeItemID(in: items, pageIndex: 4) == items[0].children![0].id)
        #expect(OutlineItem.activeItemID(in: items, pageIndex: 5) == items[1].id)
    }

    @Test func samePageSectionsTrackForwardAndBackwardReadingPositions() {
        let document = makeTestDocument(pageCount: 2)
        let root = makeOutlineRoot(in: document, pages: [0, 0, 1])
        for (index, y) in [CGFloat(700), 400, 650].enumerated() {
            root.child(at: index)!.destination = PDFDestination(
                page: document.page(at: index == 2 ? 1 : 0)!, at: CGPoint(x: 30, y: y))
        }
        let items = OutlineItem.buildRoot(from: root)
        func active(_ page: Int, y: CGFloat) -> String? {
            OutlineItem.activeItemID(in: items, pageIndex: page, readingOffset: -y) {
                $0.destination.map { -$0.point.y }
            }
        }
        #expect(active(0, y: 750) == nil)
        #expect(active(0, y: 700) == items[0].id)
        #expect(active(0, y: 500) == items[0].id)
        #expect(active(0, y: 400) == items[1].id)
        #expect(active(0, y: 300) == items[1].id)
        #expect(active(0, y: 600) == items[0].id)
        #expect(active(1, y: 700) == items[1].id)
        #expect(active(1, y: 650) == items[2].id)
    }

    @Test func samePositionTiesPreferDepthThenStableOutlineOrder() {
        let document = makeTestDocument(pageCount: 1)
        let root = makeOutlineRoot(in: document, pages: [0, 0])
        let child = PDFOutline()
        child.label = "Nested"
        child.destination = PDFDestination(page: document.page(at: 0)!, at: .zero)
        let siblings = OutlineItem.buildRoot(from: root)
        #expect(OutlineItem.activeItemID(in: siblings, pageIndex: 0) == siblings[0].id)
        root.child(at: 0)!.insertChild(child, at: 0)
        let nested = OutlineItem.buildRoot(from: root)
        #expect(OutlineItem.activeItemID(in: nested, pageIndex: 0) == nested[0].children![0].id)
    }

    @Test func goToActionRetainsExactDestination() {
        let document = makeTestDocument(pageCount: 1)
        let root = PDFOutline()
        let entry = PDFOutline()
        entry.label = "Action destination"
        let destination = PDFDestination(page: document.page(at: 0)!, at: CGPoint(x: 40, y: 320))
        entry.action = PDFActionGoTo(destination: destination)
        root.insertChild(entry, at: 0)
        let items = OutlineItem.buildRoot(from: root)
        #expect(items[0].pageIndex == 0)
        #expect(items[0].destination?.point == destination.point)
    }

    @Test func initialOutlineIsCollapsedAndLaterSectionChangesRevealOnlyItsPath() {
        let document = makeTestDocument(pageCount: 3)
        let root = makeOutlineRoot(in: document, pages: [0, 2])
        for index in 0..<2 {
            let child = PDFOutline()
            child.label = "Subsection \(index)"
            child.destination = PDFDestination(page: document.page(at: index)!, at: CGPoint(x: 30, y: 400))
            root.child(at: 0)!.insertChild(child, at: index)
        }
        let otherChild = PDFOutline()
        otherChild.label = "Other subsection"
        otherChild.destination = PDFDestination(page: document.page(at: 2)!, at: .zero)
        root.child(at: 1)!.insertChild(otherChild, at: 0)
        let items = OutlineItem.buildRoot(from: root)
        let children = items[0].children!
        var navigations: [PDFDestination] = []
        let owner = NativeOutlineView(items: items, activeItemID: children[0].id,
                                      onSelect: { navigations.append($0) })
        let coordinator = NativeOutlineView.Coordinator(owner)
        let outline = OutlineTable(frame: NSRect(x: 0, y: 0, width: 240, height: 500))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("outline"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = coordinator
        outline.delegate = coordinator
        coordinator.outline = outline
        coordinator.update(owner)
        #expect(outline.numberOfRows == 2)
        #expect(!outline.isItemExpanded(coordinator.roots[0]))
        #expect(outline.selectedRow == 0)
        #expect(navigations.isEmpty)

        let next = NativeOutlineView(items: items, activeItemID: children[1].id, onSelect: owner.onSelect)
        coordinator.update(next)
        #expect(outline.isItemExpanded(coordinator.roots[0]))
        #expect(!outline.isItemExpanded(coordinator.roots[1]))
        #expect((outline.item(atRow: outline.selectedRow) as? NativeOutlineView.Node)?.value.id == children[1].id)
        #expect(navigations.isEmpty)

        outline.collapseItem(coordinator.roots[0])
        coordinator.update(next)
        #expect(!outline.isItemExpanded(coordinator.roots[0]))
        #expect(outline.selectedRow == 0)
        // Expanding and selecting a child navigates to its point, not just its page.
        outline.expandItem(coordinator.roots[0])
        outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: coordinator.roots[0].children[0])),
                                 byExtendingSelection: false)
        #expect(navigations.last?.point == children[0].destination?.point)
    }

}
