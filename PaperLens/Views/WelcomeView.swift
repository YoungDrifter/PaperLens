import SwiftUI

/// Empty tabs stay here until the user chooses a document.
struct WelcomeView: View {
    @Environment(RecentFilesManager.self) private var recentFiles
    var tabManager: TabManager

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 12) {
                        Image(nsImage: AppIdentity.icon)
                            .resizable().frame(width: 88, height: 88)
                            .accessibilityHidden(true)
                        Text(AppIdentity.displayName).font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("Drop a PDF here, or open one from your files.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button { tabManager.openFilePicker() } label: {
                            Label("Open PDF", systemImage: "folder")
                                .font(.body.weight(.semibold))
                        }
                        .buttonStyle(BlackPrimaryButtonStyle())
                        .padding(.top, 8)
                    }
                    VStack(spacing: 8) {
                        HStack {
                            Text("Recent Documents").font(.system(size: 12, weight: .semibold)).foregroundStyle(DesignTokens.secondaryInk)
                            Spacer()
                            Button("Clear") { recentFiles.clearRecentFiles() }
                                .buttonStyle(WelcomeSecondaryButtonStyle())
                                .disabled(recentFiles.recentFiles.isEmpty)
                                .help("Clear Recent Documents")
                        }.padding(.horizontal, 12)
                        if recentFiles.recentFiles.isEmpty {
                            Text("Your recently opened PDFs will appear here.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        } else {
                            // Every remembered document stays reachable; the card
                            // scrolls instead of truncating the history.
                            ScrollView {
                                VStack(spacing: DesignTokens.spacingSM) {
                                    ForEach(recentFiles.recentFiles) { file in
                                        WelcomeRecentRow(
                                            file: file,
                                            onOpen: { open(file) },
                                            onDelete: { recentFiles.removeRecentFile(file) }
                                        )
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .frame(height: welcomeListHeight)
                        }
                    }
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DesignTokens.hairline, lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.035), radius: 18, y: 6)
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 32).padding(.vertical, 36)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .background(DesignTokens.subtleSurface)
    }

    private func open(_ file: RecentFile) {
        guard let resolved = recentFiles.resolveRecentFile(file) else { NSSound.beep(); return }
        if WindowRegistry.shared.activateExistingDocument(for: resolved.url) {
            recentFiles.addRecentFile(resolved.url, isSecurityScoped: resolved.isSecurityScoped)
        } else {
            tabManager.openDocument(url: resolved.url, isSecurityScoped: resolved.isSecurityScoped)
        }
    }

    /// The list grows with the history until the card caps it and scrolls.
    private var welcomeListHeight: CGFloat {
        let count = CGFloat(recentFiles.recentFiles.count)
        guard count > 0 else { return 0 }
        let rows = count * DesignTokens.welcomeRecentRowHeight + (count - 1) * DesignTokens.spacingSM + 4
        return min(rows, DesignTokens.welcomeHistoryMaxHeight)
    }
}

private struct WelcomeRecentRow: View {
    let file: RecentFile
    var onOpen: () -> Void
    var onDelete: () -> Void
    @State private var hovering = false
    @State private var deleteHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text").font(.system(size: 19, weight: .regular)).foregroundStyle(DesignTokens.secondaryInk)
                        .frame(width: 36, height: 40).background(DesignTokens.subtleSurface, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.url.lastPathComponent).font(.body.weight(.medium)).lineLimit(1)
                        Text(file.url.deletingLastPathComponent().path)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(RecentFileTime.label(for: file.lastOpenedAt, relativeTo: context.date))
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(file.url.path)

            // The slot is always reserved, so revealing the control never
            // reflows the row; only one history entry is forgotten.
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.secondaryInk)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(deleteHovering ? 0.09 : 0)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { deleteHovering = $0 }
            .help("Remove from Recents")
            .accessibilityLabel("Remove \(file.url.lastPathComponent) from Recents")
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .padding(.trailing, 10)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(hovering ? 0.045 : 0)))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}

/// Keep primary actions solid black rather than the system's translucent tint.
private struct BlackPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 22).padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.black))
            .contentShape(Capsule())
            .modifier(WelcomeHoverFeedback(isPressed: configuration.isPressed))
    }
}

/// The whole action capsule responds to hovering without changing its colour.
private struct WelcomeHoverFeedback: ViewModifier {
    var isPressed: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(!isEnabled || reduceMotion ? 1 : (isPressed ? 0.98 : (hovering ? 1.015 : 1)))
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isPressed)
    }
}

/// Secondary action in the welcome card. It reads as a button — quiet capsule
/// surface with a hairline edge, like the settings actions — and keeps the
/// primary button's feedback: a slight scale on hover, a smaller one on press.
private struct WelcomeSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DesignTokens.secondaryInk)
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(DesignTokens.subtleSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(DesignTokens.hairline, lineWidth: 0.7))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .modifier(WelcomeHoverFeedback(isPressed: configuration.isPressed))
    }
}
