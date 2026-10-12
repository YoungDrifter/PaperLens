import SwiftUI

/// A single source of truth: editing always happens in the page card.
struct CommentsSidebar: View {
    @Bindable var commentManager: CommentManager
    let onClose: () -> Void
    /// Which row's ⋯ popover is open; the rows share one binding.
    @State private var showingMenuID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if commentManager.comments.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "text.bubble").font(.title2)
                            Text("No comments yet")
                            Button("Add Comment") { _ = commentManager.addComment() }
                            Text("Add a card and start typing.")
                                .font(.caption).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                    ForEach(commentManager.sortedComments) { comment in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Page \(comment.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button { commentManager.selectComment(comment.id) } label: {
                                    Image(systemName: "square.and.pencil")
                                }.buttonStyle(.plain).help("Edit on page")
                                Button { showingMenuID = comment.id } label: {
                                    Image(systemName: "ellipsis")
                                }
                                .buttonStyle(.plain)
                                .help("More")
                                .popover(isPresented: Binding(get: { showingMenuID == comment.id },
                                                              set: { if !$0 { showingMenuID = nil } })) {
                                    PopupActionList(title: "Comment", actions: [
                                        PopupAction(title: "Edit on Page", symbol: "square.and.pencil") {
                                            commentManager.selectComment(comment.id)
                                        },
                                        PopupAction(title: "Delete", symbol: "trash", destructive: true) {
                                            commentManager.deleteComment(comment.id)
                                        }
                                    ], width: 220, onDismiss: { showingMenuID = nil })
                                }
                            }
                            Button { commentManager.selectComment(comment.id) } label: {
                                Text(comment.text.isEmpty ? "Add a comment…" : comment.text)
                                    .font(.system(size: 13))
                                    .foregroundStyle(comment.text.isEmpty ? .secondary : .primary)
                                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius).stroke(
                            commentManager.selectedCommentID == comment.id ? Color.black.opacity(0.25) : DesignTokens.hairline, lineWidth: 1))
                        .shadow(color: .black.opacity(0.025), radius: 3, y: 1)
                        .id(comment.id)
                    }
                    if let message = commentManager.overflowMessage {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.padding(12)
            }
            .onChange(of: commentManager.selectedCommentID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}
