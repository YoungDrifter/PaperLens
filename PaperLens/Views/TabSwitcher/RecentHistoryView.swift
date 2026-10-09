import SwiftUI

struct RecentHistoryView: View {
    @Bindable var manager: RecentFilesManager
    let maxListHeight: CGFloat
    let onOpen: (RecentFile) -> Void
    let onClose: () -> Void
    @State private var selection = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent Files").font(.headline)
                Spacer()
                Text("⌘⇧A").font(.caption).foregroundStyle(.secondary)
            }.padding(14)
            Divider()
            if manager.recentFiles.isEmpty {
                Text("No recently opened files").foregroundStyle(.secondary).padding(24)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(manager.recentFiles.enumerated()), id: \.element.id) { index, file in
                            Button { onOpen(file) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.text").font(.system(size: 19)).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(file.url.lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                        Text(file.url.deletingLastPathComponent().path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(selection == index ? 0.055 : 0)))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).onHover { if $0 { selection = index } }
                        }
                    }.padding(6)
                }.frame(height: min(maxListHeight, CGFloat(manager.recentFiles.count) * 58 + 12))
                Divider()
                HStack { Spacer(); Button("Clear History") { manager.clearRecentFiles(); selection = 0 } }.padding(10)
            }
        }
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.12)))
        .preferredColorScheme(.light)
        .focusable().focusEffectDisabled()
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(.downArrow) { selection = min(selection + 1, max(0, manager.recentFiles.count - 1)); return .handled }
        .onKeyPress(.upArrow) { selection = max(0, selection - 1); return .handled }
        .onKeyPress(.return) {
            if manager.recentFiles.indices.contains(selection) { onOpen(manager.recentFiles[selection]) }
            return .handled
        }
        .padding(TabSwitcherMetrics.shadowPadding)
    }
}
