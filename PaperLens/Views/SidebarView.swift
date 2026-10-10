//
//  SidebarView.swift
//  PaperLens
//
//  Displays the PDF sidebar with Outline (Table of Contents) and Thumbnails.
//

import SwiftUI
import PDFKit

enum SidebarMode: String, CaseIterable, Sendable {
    case thumbnails, outline, bookmarks, comments
    var title: String {
        switch self { case .thumbnails: "Thumbnails"; case .outline: "Outline"; case .bookmarks: "Bookmarks"; case .comments: "Comments" }
    }
    var icon: String {
        switch self { case .thumbnails: "square.grid.2x2"; case .outline: "list.bullet.indent"; case .bookmarks: "bookmark"; case .comments: "text.bubble" }
    }
}

struct SidebarView: View {
    @Bindable var pdfManager: PDFManager
    @Bindable var bookmarkManager: BookmarkManager
    let items: [OutlineItem]
    @Bindable var commentManager: CommentManager
    @Binding var mode: SidebarMode

    @State private var editingBookmarkID: UUID?
    @State private var editingTitle: String = ""
    @FocusState private var isEditingBookmarkFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            SidebarHeaderView(mode: $mode)
            Text(mode.title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 10)
            switch mode {
            case .outline:
                if items.isEmpty {
                    Text("No Outline Available").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)
                } else {
                    NativeOutlineView(items: items, activeItemID: pdfManager.activeOutlineItemID,
                                      onSelect: { destination in
                                          let samePage = destination.page === pdfManager.currentPage
                                          if samePage { pdfManager.pushNavigationState() }
                                          pdfManager.goToDestination(destination)
                                      })
                }
            case .thumbnails:
                ThumbnailGridView(pdfManager: pdfManager, bookmarkManager: bookmarkManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 4)
            case .bookmarks: bookmarksView
            case .comments: CommentsSidebar(commentManager: commentManager, onClose: {})
            }
        }
        .background(LinearGradient(colors: [DesignTokens.sidebarTop, DesignTokens.sidebarBottom], startPoint: .top, endPoint: .bottom))
    }

    // MARK: - Bookmarks View

    private var bookmarksView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if bookmarkManager.bookmarks.isEmpty {
                    Text("No Bookmarks")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.sidebarSecondaryText)

                        .padding(DesignTokens.spacingMD)
                } else {
                    ForEach(bookmarkManager.sortedBookmarks) { bookmark in
                        bookmarkRow(bookmark)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.spacingMD + DesignTokens.spacingSM)
            .padding(.bottom, DesignTokens.spacingMD)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .scrollContentBackground(.hidden)
    }

    private func bookmarkRow(_ bookmark: BookmarkModel) -> some View {
        HStack {
            Button {
                if editingBookmarkID == nil {
                    pdfManager.pushNavigationState()
                    bookmarkManager.selectBookmark(bookmark.id)
                }
            } label: {
                HStack {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.sidebarSecondaryText)

                    if editingBookmarkID == bookmark.id {
                        TextField("", text: $editingTitle)
                            .textFieldStyle(.plain)
                            .focused($isEditingBookmarkFocused)
                            .onSubmit { commitBookmarkEdit(bookmark.id) }
                            .onExitCommand { cancelBookmarkEdit() }
                    } else {
                        Text(bookmark.title)
                            .lineLimit(1)
                            .onTapGesture { startEditingBookmark(bookmark) }
                    }

                    Spacer()
                    Text("\(bookmark.pageIndex + 1)")
                        .foregroundStyle(DesignTokens.sidebarSecondaryText)
                }

                .padding(.vertical, DesignTokens.spacingXS)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
            }

            Button {
                bookmarkManager.removeBookmark(bookmark.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignTokens.sidebarSecondaryText)
                    .frame(width: DesignTokens.tabCloseButtonSize, height: DesignTokens.tabCloseButtonSize)

            }
            .buttonStyle(.plain)
            .opacity(0.6)
            .onHover { hovering in
                (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
            }
        }
    }

    // MARK: - Bookmark Editing

    private func startEditingBookmark(_ bookmark: BookmarkModel) {
        editingBookmarkID = bookmark.id
        editingTitle = bookmark.title
        isEditingBookmarkFocused = true
    }

    private func commitBookmarkEdit(_ id: UUID) {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            bookmarkManager.renameBookmark(id, to: trimmed)
        }
        editingBookmarkID = nil
        editingTitle = ""
    }

    private func cancelBookmarkEdit() {
        editingBookmarkID = nil
        editingTitle = ""
    }
}
