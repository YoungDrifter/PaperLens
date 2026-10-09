import SwiftUI

/// Empty tabs stay here until the user chooses a document.
struct WelcomeView: View {
    @Environment(RecentFilesManager.self) private var recentFiles
    var tabManager: TabManager
    @State private var host = WelcomeWindowReference()

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 36) {
                    VStack(spacing: 12) {
                        Image(nsImage: AppIdentity.icon)
                            .resizable().frame(width: 88, height: 88)
                            .accessibilityHidden(true)
                        Text(AppIdentity.displayName).font(.title2.weight(.semibold))
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
                            Text("Recent").font(.headline).foregroundStyle(.secondary)
                            Spacer()
                            Button("View all") {
                                TabSwitcherController.shared.show(forWindow: host.window, hostTabManager: tabManager)
                            }
                            .buttonStyle(WelcomeHoverButtonStyle()).foregroundStyle(.secondary)
                            .disabled(recentFiles.recentFiles.isEmpty)
                        }.padding(.horizontal, 12)
                        if recentFiles.welcomeFiles.isEmpty {
                            Text("Your recently opened PDFs will appear here.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        } else {
                            ForEach(recentFiles.welcomeFiles) { file in
                                WelcomeRecentRow(file: file) { open(file) }
                            }
                        }
                    }
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 32).padding(.vertical, 36)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .background(Color.white)
        .background(WelcomeWindowAccessor { host.window = $0 })
    }

    private func open(_ file: RecentFile) {
        guard let resolved = recentFiles.resolveRecentFile(file) else { NSSound.beep(); return }
        if WindowRegistry.shared.activateExistingDocument(for: resolved.url) {
            recentFiles.addRecentFile(resolved.url, isSecurityScoped: resolved.isSecurityScoped)
        } else {
            tabManager.openDocument(url: resolved.url, isSecurityScoped: resolved.isSecurityScoped)
        }
    }
}

private struct WelcomeRecentRow: View {
    let file: RecentFile
    var onOpen: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text").font(.system(size: 20)).foregroundStyle(.secondary)
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
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(hovering ? 0.045 : 0)))
        }
        .buttonStyle(.plain).help(file.url.path)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}

private struct WelcomeWindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> Accessor { Accessor(onWindow: onWindow) }
    func updateNSView(_ view: Accessor, context: Context) { view.onWindow = onWindow }
    final class Accessor: NSView {
        var onWindow: (NSWindow?) -> Void
        init(onWindow: @escaping (NSWindow?) -> Void) { self.onWindow = onWindow; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in guard let self else { return }; self.onWindow(self.window) }
        }
    }
}

private final class WelcomeWindowReference {
    weak var window: NSWindow?
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
            .scaleEffect(!isEnabled || reduceMotion ? 1 : (isPressed ? 0.98 : (hovering ? 1.04 : 1)))
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isPressed)
    }
}

private struct WelcomeHoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(WelcomeHoverFeedback(isPressed: configuration.isPressed))
    }
}
