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
    /// Latest destination at or before the reading page; deeper entries win ties.
    static func activeItemID(in items: [OutlineItem], pageIndex: Int) -> String? {
        var best: (id: String, page: Int, depth: Int)?
        func visit(_ entries: [OutlineItem], depth: Int) {
            for item in entries {
                if let page = item.pageIndex, page <= pageIndex,
                   best == nil || page > best!.page || (page == best!.page && depth > best!.depth) {
                    best = (item.id, page, depth)
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
        if let page = outline.destination?.page, let document = page.document {
            pageIndex = document.index(for: page)
        } else {
            pageIndex = nil
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
