import SwiftUI
import AppKit

struct NativeOutlineView: NSViewRepresentable {
    let items: [OutlineItem]
    let pageIndex: Int
    let onSelect: (Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let outline = OutlineTable()
        outline.headerView = nil; outline.backgroundColor = .clear
        outline.selectionHighlightStyle = .regular
        outline.indentationPerLevel = 14
        outline.intercellSpacing = NSSize(width: 0, height: 2)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("outline"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column); outline.outlineTableColumn = column
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.dataSource = context.coordinator; outline.delegate = context.coordinator
        outline.target = context.coordinator; outline.action = #selector(Coordinator.clicked)
        scroll.documentView = outline
        context.coordinator.outline = outline
        context.coordinator.update(self)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.update(self) }

    final class Node: NSObject {
        let value: OutlineItem
        let children: [Node]
        weak var parent: Node?
        init(_ item: OutlineItem) {
            value = item; children = (item.children ?? []).map { Node($0) }
            super.init(); children.forEach { $0.parent = self }
        }
    }
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var owner: NativeOutlineView
        weak var outline: OutlineTable?
        var roots: [Node] = []
        var signature: [String] = []
        var synchronizing = false
        var clickedID: String?
        var clickedPage: Int?
        init(_ owner: NativeOutlineView) { self.owner = owner }
        func update(_ owner: NativeOutlineView) {
            self.owner = owner
            guard let outline else { return }
            let ids = owner.items.map(\.id)
            if signature != ids {
                signature = ids
                roots = owner.items.map { Node($0) }
                clickedID = nil; clickedPage = nil
                synchronizing = true; outline.reloadData(); synchronizing = false
            }
            if clickedPage != owner.pageIndex { clickedID = nil; clickedPage = nil }
            let target = clickedID ?? OutlineItem.activeItemID(in: owner.items, pageIndex: owner.pageIndex)
            guard let target else {
                synchronizing = true; outline.deselectAll(nil); synchronizing = false; return
            }
            func find(_ nodes: [Node]) -> Node? {
                for node in nodes { if node.value.id == target { return node }; if let match = find(node.children) { return match } }
                return nil
            }
            guard let node = find(roots) else { return }
            synchronizing = true
            var parent = node.parent
            var ancestors: [Node] = []
            while let current = parent { ancestors.append(current); parent = current.parent }
            for ancestor in ancestors.reversed() { outline.expandItem(ancestor) }
            let row = outline.row(forItem: node)
            if row >= 0, outline.selectedRow != row {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outline.scrollRowToVisible(row)
            }
            synchronizing = false
        }
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? Node)?.children.count ?? roots.count }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { ((item as? Node)?.children ?? roots)[index] }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !(item as! Node).children.isEmpty }
        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { (item as! Node).value.pageIndex != nil }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            let node = item as! Node
            let cell = OutlineCell()
            cell.title.stringValue = node.value.title
            cell.page.stringValue = node.value.pageIndex.map { String($0 + 1) } ?? ""
            cell.setAccessibilityLabel(node.value.title)
            return cell
        }
        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            let node = item as! Node
            var level = 0; var parent = node.parent
            while let current = parent { level += 1; parent = current.parent }
            let row = outlineView.row(forItem: node)
            // Use AppKit's actual cell rectangle, including disclosure indentation
            // and native table insets, rather than estimating a narrower width.
            let cellWidth = row >= 0 ? outlineView.frameOfCell(atColumn: 0, row: row).width
                : (outlineView.tableColumns.first?.width ?? 240) - CGFloat(level + 1) * outlineView.indentationPerLevel
            return OutlineCell.rowHeight(for: node.value.title, cellWidth: cellWidth)
        }
        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            let row = OutlineHoverRow(); row.canHover = (item as! Node).value.pageIndex != nil; return row
        }
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !synchronizing, let outline, let node = outline.item(atRow: outline.selectedRow) as? Node, let index = node.value.pageIndex else { return }
            clickedID = node.value.id; clickedPage = index
            owner.onSelect(index)
        }
        @objc func clicked() {
            guard let outline, let node = outline.item(atRow: outline.clickedRow) as? Node,
                  let page = node.value.pageIndex, clickedID != node.value.id else { return }
            clickedID = node.value.id; clickedPage = page; owner.onSelect(page)
        }

    }
}

final class OutlineTable: NSOutlineView {
    private var lastWidth: CGFloat = 0
    override func layout() {
        super.layout()
        if abs(bounds.width - lastWidth) > 0.5 {
            lastWidth = bounds.width
            noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<numberOfRows))
        }
    }
}
final class OutlineCell: NSTableCellView {
    private static let trailingWidth: CGFloat = 38
    private static let verticalPadding: CGFloat = 6

    static func titleWidth(for cellWidth: CGFloat) -> CGFloat { max(24, cellWidth - trailingWidth) }

    private static func titleField(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 13)
        field.maximumNumberOfLines = 0
        return field
    }

    static func rowHeight(for text: String, cellWidth: CGFloat) -> CGFloat {
        let height = titleField(text).sizeThatFits(NSSize(width: titleWidth(for: cellWidth), height: .greatestFiniteMagnitude)).height
        return max(30, ceil(height) + 2 * verticalPadding)
    }

    let title = OutlineCell.titleField("")
    let page = NSTextField(labelWithString: "")
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        page.font = .systemFont(ofSize: 11); page.alignment = .right
        addSubview(title); addSubview(page)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            title.textColor = .labelColor
            page.textColor = .secondaryLabelColor
        }
    }
    override func layout() {
        super.layout()
        let titleWidth = Self.titleWidth(for: bounds.width)
        let height = title.sizeThatFits(NSSize(width: titleWidth, height: .greatestFiniteMagnitude)).height
        title.frame = NSRect(x: 0, y: bounds.height - Self.verticalPadding - height, width: titleWidth, height: height)
        page.frame = NSRect(x: bounds.width - 34, y: bounds.height - Self.verticalPadding - 16, width: 30, height: 16)
    }
}
private final class OutlineHoverRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.68).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 2), xRadius: 7, yRadius: 7).fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    var canHover = false
    private var hovering = false
    private let hover = NSView()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hover.wantsLayer = true; hover.layer?.cornerRadius = 4
        hover.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.055).cgColor
        hover.alphaValue = 0; addSubview(hover, positioned: .below, relativeTo: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isSelected: Bool { didSet { updateHover(animated: false) } }
    override func layout() { super.layout(); hover.frame = bounds.insetBy(dx: 3, dy: 1) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; updateHover(animated: true) }
    override func mouseExited(with event: NSEvent) { hovering = false; updateHover(animated: true) }
    private func updateHover(animated: Bool) {
        let alpha: CGFloat = hovering && canHover && !isSelected ? 1 : 0
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in context.duration = 0.12; hover.animator().alphaValue = alpha }
        } else { hover.alphaValue = alpha }
    }
}
