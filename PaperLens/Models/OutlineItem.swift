//
//  OutlineItem.swift
//  PaperLens
//
//  Represents a PDF outline entry for the sidebar.
//

import Foundation
import PDFKit

struct OutlineItem: Identifiable {
    let id: String
    let title: String
    let pageIndex: Int?
    let children: [OutlineItem]?
    /// Retain the page-local point for exact outline navigation.
    let destination: PDFDestination?
    /// Latest reached destination; offsets increase in the visible reading direction.
    /// PDFView supplies the offsets so crop boxes, zoom and rotation use its transform.
    /// With no offset provider this preserves page-only matching for callers/tests.
    static func activeItemID(in items: [OutlineItem], pageIndex: Int,
                             readingOffset: CGFloat = .greatestFiniteMagnitude,
                             destinationOffset: (OutlineItem) -> CGFloat? = { _ in 0 }) -> String? {
        var best: (id: String, page: Int, offset: CGFloat, depth: Int)?
        func visit(_ entries: [OutlineItem], depth: Int) {
            for item in entries {
                if let page = item.pageIndex, page <= pageIndex,
                   let offset = destinationOffset(item), offset.isFinite,
                   page < pageIndex || offset <= readingOffset {
                    // Stable outline order breaks equal-position, equal-depth ties.
                    if best == nil || page > best!.page ||
                        (page == best!.page && (offset > best!.offset ||
                         (offset == best!.offset && depth > best!.depth))) {
                        best = (item.id, page, offset, depth)
                    }
                }
                if let children = item.children { visit(children, depth: depth + 1) }
            }
        }
        visit(items, depth: 0)
        return best?.id
    }
    // `buildRoot` is the single construction path for the outline tree.

    private init?(outline: PDFOutline, path: String) {
        let trimmedLabel = outline.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = trimmedLabel.isEmpty ? "Untitled" : trimmedLabel
        let target = outline.destination ?? (outline.action as? PDFActionGoTo)?.destination
        if let page = target?.page, let document = page.document,
           document.index(for: page) != NSNotFound {
            pageIndex = document.index(for: page)
            destination = target
        } else {
            pageIndex = nil
            destination = nil
        }

        let baseID = "\(path)|\(title)|\(pageIndex ?? -1)"
        id = baseID

        var items: [OutlineItem] = []
        let childCount = outline.numberOfChildren
        if childCount > 0 {
            for index in 0..<childCount {
                guard let child = outline.child(at: index),
                      let item = OutlineItem(outline: child, path: "\(baseID)-\(index)") else { continue }
                items.append(item)
            }
        }
        children = items.isEmpty ? nil : items
    }

    /// Builds the root-level outline items for a document's outline root,
    /// the single construction path for a tree.
    static func buildRoot(from root: PDFOutline) -> [OutlineItem] {
        var items: [OutlineItem] = []
        let childCount = root.numberOfChildren
        if childCount > 0 {
            for index in 0..<childCount {
                guard let child = root.child(at: index),
                      let item = OutlineItem(outline: child, path: "root-\(index)") else { continue }
                items.append(item)
            }
        }
        return items
    }

}
