import SwiftUI

/// The Recent Files popover, presented by the chrome's history button (and by
/// the Tab menu's ⌘⇧A command). Layout, hover wash, per-row delete and the
/// header's Clear History mirror QuillTeX's Recent Projects popover so both apps
/// read the same.
struct RecentHistoryView: View {
    @Bindable var manager: RecentFilesManager
    let onOpen: (RecentFile) -> Void
    let onClose: () -> Void
    @State private var selection = 0

    /// The list scrolls inside a bounded height, like the other popovers.
    private var listHeight: CGFloat {
        min(CGFloat(manager.recentFiles.count) * 58 + 12, 320)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Files").font(.headline)
                Spacer(minLength: 12)
                if !manager.recentFiles.isEmpty {
                    Button("Clear History") { manager.clearRecentFiles(); selection = 0 }
                        .buttonStyle(SettingsActionStyle())
                }
            }
            if manager.recentFiles.isEmpty {
                Text("No recently opened files").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(manager.recentFiles.enumerated()), id: \.element.id) { index, file in
                            let active = selection == index
                            HStack(spacing: 0) {
                                Button { open(file) } label: {
                                    PaperLensPopupRowLabel(symbol: "doc.text", title: file.url.lastPathComponent,
                                                           subtitle: Self.shortPath(file.url.deletingLastPathComponent()))
                                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                // The slot stays reserved, so revealing the control
                                // never reflows the row; only this entry is forgotten.
                                PaperLensPopupDeleteButton(title: file.url.lastPathComponent, visible: active) { forget(file) }
                                    .padding(.trailing, 10)
                            }
                            .paperLensPopupRow(active: active)
                            .onHover { if $0 { selection = index } }
                        }
                    }
                    .padding(8)
                }.frame(height: listHeight)
            }
        }
        .frame(width: 340)
        .focusable().focusEffectDisabled()
        .onKeyPress(.downArrow) { selection = min(selection + 1, max(0, manager.recentFiles.count - 1)); return .handled }
        .onKeyPress(.upArrow) { selection = max(0, selection - 1); return .handled }
        .onKeyPress(.return) {
            if manager.recentFiles.indices.contains(selection) { open(manager.recentFiles[selection]) }
            return .handled
        }
        .paperLensPopoverContent()
    }

    /// Closes the popover first, then hands the entry to the caller, which
    /// resolves it and raises the tab that already has it (or opens it).
    private func open(_ file: RecentFile) {
        onClose()
        onOpen(file)
    }

    /// Only the chosen entry leaves the history; the rest keeps its order.
    private func forget(_ file: RecentFile) {
        manager.removeRecentFile(file)
        selection = min(selection, max(0, manager.recentFiles.count - 1))
    }

    /// Library paths read shorter from the home folder outwards.
    private static func shortPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
