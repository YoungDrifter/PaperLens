import SwiftUI

/// A single source of truth: editing always happens in the page card.
struct CommentsSidebar: View {
    @Bindable var commentManager: CommentManager
    let onClose: () -> Void

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
                                Menu {
                                    Button("Edit on Page") { commentManager.selectComment(comment.id) }
                                    Button("Delete", role: .destructive) { commentManager.deleteComment(comment.id) }
                                } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            }
                            Button { commentManager.selectComment(comment.id) } label: {
                                Text(comment.text.isEmpty ? "Add a comment…" : comment.text)
                                    .font(.system(size: 12))
                                    .foregroundStyle(comment.text.isEmpty ? .secondary : .primary)
                                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                            commentManager.selectedCommentID == comment.id ? Color.black.opacity(0.35) : Color.black.opacity(0.10), lineWidth: 1))
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
