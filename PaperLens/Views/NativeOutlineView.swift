import SwiftUI
import AppKit
import PDFKit

struct NativeOutlineView: NSViewRepresentable {
    let items: [OutlineItem]
    let activeItemID: String?
    let onSelect: (PDFDestination) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        let outline = OutlineTable()
        outline.headerView = nil; outline.backgroundColor = .clear
        outline.style = .plain
        outline.selectionHighlightStyle = .regular
        // These cells lay out manually; automatic sizing otherwise overrides the
        // delegate's measured height with the cell's single-line intrinsic height.
        outline.usesAutomaticRowHeights = false
        outline.autoresizesOutlineColumn = false
        outline.autoresizingMask = [.width]
        outline.indentationPerLevel = 14
        outline.intercellSpacing = NSSize(width: 0, height: 2)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("outline"))
        column.minWidth = 0
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
        var lastActiveID: String?
        var hasInitialSection = false
        init(_ owner: NativeOutlineView) { self.owner = owner }
        func update(_ owner: NativeOutlineView) {
            self.owner = owner
            guard let outline else { return }
            func signatures(_ items: [OutlineItem]) -> [String] {
                items.flatMap { item in
                    let point = item.destination?.point ?? .zero
                    let page = (item.destination?.page).map { String(describing: ObjectIdentifier($0)) } ?? ""
                    return ["\(item.id)|\(page)|\(point.x)|\(point.y)"] + signatures(item.children ?? [])
                }
            }
            let ids = signatures(owner.items)
            if signature != ids {
                signature = ids
                roots = owner.items.map { Node($0) }
                lastActiveID = nil
                hasInitialSection = false
                synchronizing = true
                outline.renderedCellWidths.removeAll()
                outline.reloadData()
                outline.collapseItem(nil, collapseChildren: true)
                synchronizing = false
            }
            let sectionChanged = lastActiveID != owner.activeItemID
            lastActiveID = owner.activeItemID
            guard let target = owner.activeItemID else {
                synchronizing = true; outline.deselectAll(nil); synchronizing = false; return
            }
            func find(_ nodes: [Node]) -> Node? {
                for node in nodes { if node.value.id == target { return node }; if let match = find(node.children) { return match } }
                return nil
            }
            guard let node = find(roots) else { return }
            synchronizing = true
            // Start entirely collapsed. Only subsequent section transitions reveal a path.
            if sectionChanged && hasInitialSection {
                var parent = node.parent
                var ancestors: [Node] = []
                while let current = parent { ancestors.append(current); parent = current.parent }
                for ancestor in ancestors.reversed() { outline.expandItem(ancestor) }
            }
            hasInitialSection = true
            selectVisibleNode(node, scrollIfNeeded: sectionChanged)
            synchronizing = false
            outline.refreshHover()
        }

        private func selectVisibleNode(_ node: Node, scrollIfNeeded: Bool) {
            guard let outline else { return }
            var visibleNode = node
            while outline.row(forItem: visibleNode) < 0, let parent = visibleNode.parent {
                visibleNode = parent
            }
            let row = outline.row(forItem: visibleNode)
            guard row >= 0 else { return }
            if outline.selectedRow != row {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            if scrollIfNeeded && !outline.visibleRect.intersects(outline.rect(ofRow: row)) {
                outline.scrollRowToVisible(row)
            }
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !synchronizing else { return }
            update(owner)
        }
        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !synchronizing else { return }
            update(owner)
        }
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? Node)?.children.count ?? roots.count }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { ((item as? Node)?.children ?? roots)[index] }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !(item as! Node).children.isEmpty }
        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { (item as! Node).value.pageIndex != nil }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            let node = item as! Node
            let cell = OutlineCell()
            cell.outlineItemID = node.value.id
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
            let renderedWidth = (outlineView as? OutlineTable)?.renderedCellWidths[node.value.id]
            let cellWidth = renderedWidth ?? (row >= 0 ? outlineView.frameOfCell(atColumn: 0, row: row).width
                : (outlineView.tableColumns.first?.width ?? 240) - CGFloat(level + 1) * outlineView.indentationPerLevel)
            return OutlineCell.rowHeight(for: node.value.title, cellWidth: cellWidth)
        }
        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            let row = OutlineHoverRow(); row.canHover = (item as! Node).value.destination != nil; return row
        }
        func outlineView(_ outlineView: NSOutlineView, didAdd rowView: NSTableRowView, forRow row: Int) {
            outline?.refreshHover()
        }
        func outlineView(_ outlineView: NSOutlineView, didRemove rowView: NSTableRowView, forRow row: Int) {
            (rowView as? OutlineHoverRow)?.hovering = false
        }
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !synchronizing else { return }
            // Mouse navigation is handled by the action, including repeat clicks.
            if let type = NSApp.currentEvent?.type, type == .leftMouseDown || type == .leftMouseUp { return }
            navigate(row: outline?.selectedRow ?? -1)
        }
        @objc func clicked() { navigate(row: outline?.clickedRow ?? -1) }
        private func navigate(row: Int) {
            guard !synchronizing, let outline,
                  let node = outline.item(atRow: row) as? Node,
                  let destination = node.value.destination else { return }
            owner.onSelect(destination)
        }
    }
}

final class OutlineTable: NSOutlineView {
    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        var rect = super.frameOfOutlineCell(atRow: row)
        rect.origin.x += DesignTokens.outlineRowInset
        return rect
    }
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var rect = super.frameOfCell(atColumn: column, row: row)
        rect.origin.x += DesignTokens.outlineRowInset
        rect.size.width = max(0, rect.width - DesignTokens.outlineRowInset)
        return rect
    }
    private var lastWidth: CGFloat = 0
    var renderedCellWidths: [String: CGFloat] = [:]
    private var heightUpdateQueued = false
    private var rowsNeedingHeightUpdate = IndexSet()

    func scheduleHeightUpdate(for cell: OutlineCell) {
        guard let id = cell.outlineItemID else { return }
        renderedCellWidths[id] = cell.bounds.width
        let row = self.row(for: cell)
        guard row >= 0 else { return }
        rowsNeedingHeightUpdate.insert(row)
        guard !heightUpdateQueued else { return }
        heightUpdateQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.heightUpdateQueued = false
            let rows = self.rowsNeedingHeightUpdate.intersection(IndexSet(integersIn: 0..<self.numberOfRows))
            self.rowsNeedingHeightUpdate.removeAll()
            if !rows.isEmpty { self.updateRowHeights(rows) }
        }
    }
    private func updateRowHeights(_ rows: IndexSet) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            noteHeightOfRows(withIndexesChanged: rows)
        }
    }
    private var hoverTrackingArea: NSTrackingArea?
    private weak var hoveredRowView: OutlineHoverRow?
    private weak var observedWindow: NSWindow?
    private weak var observedClipView: NSClipView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observedWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: observedWindow)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: observedWindow)
        }
        if let observedClipView {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: observedClipView)
        }
        observedWindow = window
        observedClipView = enclosingScrollView?.contentView
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged(_:)),
                name: NSWindow.didResignKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged(_:)),
                name: NSWindow.didBecomeKeyNotification, object: window)
        }
        if let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged(_:)),
                name: NSView.boundsDidChangeNotification, object: clip)
        }
        refreshHover()
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func layout() {
        // Expanding deep outlines must never widen the document view beyond the
        // sidebar viewport: horizontal scrolling is intentionally unavailable.
        if let clip = enclosingScrollView?.contentView, clip.bounds.width > 0 {
            if abs(frame.width - clip.bounds.width) > 0.5 { frame.size.width = clip.bounds.width }
            if let column = tableColumns.first, abs(column.width - clip.bounds.width) > 0.5 {
                column.width = clip.bounds.width
            }
        }
        super.layout()
        if abs(bounds.width - lastWidth) > 0.5 {
            lastWidth = bounds.width
            updateRowHeights(IndexSet(integersIn: 0..<numberOfRows))
        }
        refreshHover()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.inVisibleRect, .activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
        refreshHover()
    }
    override func mouseEntered(with event: NSEvent) { refreshHover() }
    override func mouseMoved(with event: NSEvent) { refreshHover() }
    override func mouseExited(with event: NSEvent) { clearHover() }
    @objc private func viewportChanged(_ notification: Notification) { refreshHover() }
    private func clearHover() {
        hoveredRowView?.hovering = false
        hoveredRowView = nil
    }
    func refreshHover() {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { clearHover(); return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard visibleRect.contains(point) else { clearHover(); return }
        let row = self.row(at: point)
        let next = row >= 0 ? rowView(atRow: row, makeIfNecessary: false) as? OutlineHoverRow : nil
        guard next?.canHover == true else { clearHover(); return }
        if hoveredRowView !== next {
            clearHover()
            hoveredRowView = next
        }
        next?.hovering = true
    }
}
final class OutlineCell: NSTableCellView {
    private static let trailingWidth: CGFloat = 30 + DesignTokens.outlinePageTrailingInset + 8
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

    var outlineItemID: String?
    private var lastTitleWidth: CGFloat = -1
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
        if titleWidth != lastTitleWidth {
            lastTitleWidth = titleWidth
            var ancestor = superview
            while let view = ancestor {
                if let table = view as? OutlineTable { table.scheduleHeightUpdate(for: self); break }
                ancestor = view.superview
            }
        }
        let height = title.sizeThatFits(NSSize(width: titleWidth, height: .greatestFiniteMagnitude)).height
        title.frame = NSRect(x: 0, y: bounds.height - Self.verticalPadding - height, width: titleWidth, height: height)
        page.frame = NSRect(x: bounds.width - DesignTokens.outlinePageTrailingInset - 30, y: bounds.height - Self.verticalPadding - 16, width: 30, height: 16)
    }
}
final class OutlineHoverRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        DesignTokens.outlineSelection.setFill()
        NSBezierPath(roundedRect: backgroundRect, xRadius: DesignTokens.outlineRowCornerRadius, yRadius: DesignTokens.outlineRowCornerRadius).fill()
    }
    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if hovering && canHover && !isSelected {
            DesignTokens.outlineHover.setFill()
            NSBezierPath(roundedRect: backgroundRect, xRadius: DesignTokens.outlineRowCornerRadius, yRadius: DesignTokens.outlineRowCornerRadius).fill()
        }
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    var backgroundRect: NSRect { bounds.insetBy(dx: DesignTokens.outlineRowInset, dy: 2) }
    var canHover = false
    var hovering = false { didSet { if oldValue != hovering { needsDisplay = true } } }
    override var isSelected: Bool { didSet { needsDisplay = true } }
}
