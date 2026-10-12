import SwiftUI
import AppKit

/// Shared, shadow-free surface for app-owned in-window overlays (the search bar,
/// the HUD fills). Floating popovers use the system's own chrome instead.
struct PaperLensPanelSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius, style: .continuous)
        content
            .background {
                if reduceTransparency { shape.fill(DesignTokens.controlSurface) }
                else { shape.fill(.regularMaterial).overlay(shape.fill(Color.white.opacity(0.65))) }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(DesignTokens.hairline, lineWidth: 0.7).allowsHitTesting(false))
            .foregroundStyle(DesignTokens.primaryInk)
            .preferredColorScheme(.light)
    }
}

/// Content of a native popover: the system supplies the panel chrome (arrow,
/// material, dismissal), so this only fixes padding, ink and the light
/// appearance — the PaperLens counterpart of QuillTeX's `QuillPopoverContent`.
struct PaperLensPopoverContent: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(DesignTokens.panelPadding)
            .foregroundStyle(DesignTokens.primaryInk)
            .background(DesignTokens.controlSurface)
            .preferredColorScheme(.light)
    }
}

struct PaperLensSheetContent: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(DesignTokens.spacingLG)
            .foregroundStyle(DesignTokens.primaryInk)
            .background(DesignTokens.controlSurface)
            .preferredColorScheme(.light)
    }
}

extension View {
    func paperLensPopoverContent() -> some View { modifier(PaperLensPopoverContent()) }

    /// One row inside an app-owned popup list: the same quiet wash everywhere, so
    /// recent files, tool menus and the other popups read alike.
    func paperLensPopupRow(active: Bool) -> some View {
        background(RoundedRectangle(cornerRadius: 8).fill(DesignTokens.primaryInk.opacity(active ? DesignTokens.selectedOpacity : 0)))
    }
}

/// Icon, title and secondary path — the shared content of a popup list row.
struct PaperLensPopupRowLabel: View {
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Hover-revealed delete control for a popup row. The slot is always part of the
/// layout, so revealing the control never reflows the row.
struct PaperLensPopupDeleteButton: View {
    let title: String
    var visible: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.secondaryInk)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Remove from Recents")
        .accessibilityLabel("Remove \(title) from Recents")
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
    }
}

struct PopupAction: Identifiable {
    let title: String
    var symbol: String = ""
    /// Preset colours draw a swatch in place of the SF Symbol.
    var swatch: NSColor?
    var selected = false
    var enabled = true
    var destructive = false
    var separatorBefore = false
    let action: () -> Void
    var id: String { title }
}

/// Arrow-key navigation and row semantics are identical in every action popup.
/// `onDismiss` lets the owning popover close when an action (or Escape) runs.
struct PopupActionList: View {
    let title: String
    let actions: [PopupAction]
    var width: CGFloat = 280
    var onDismiss: (() -> Void)?
    @State private var focusedID: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(actions) { item in
                            if item.separatorBefore { Divider().padding(.vertical, 5) }
                            Button { invoke(item) } label: {
                                HStack(spacing: 10) {
                                    if let swatch = item.swatch {
                                        PopupColorSwatch(color: swatch)
                                            .frame(width: 19, height: 19, alignment: .leading)
                                    } else {
                                        Image(systemName: item.symbol).font(.system(size: 19, weight: .regular))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(item.title).font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(item.destructive ? Color.red : DesignTokens.primaryInk)
                                    Spacer(minLength: 12)
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                                        .opacity(item.selected ? 1 : 0)
                                }
                                .foregroundStyle(DesignTokens.primaryInk.opacity(item.enabled ? 1 : 0.3))
                                .padding(.horizontal, 10).frame(height: 34)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).disabled(!item.enabled)
                            .accessibilityAddTraits(item.selected ? .isSelected : [])
                            .paperLensPopupRow(active: focusedID == item.id && item.enabled)
                            .onHover { if $0 { focusedID = item.id } }
                            .id(item.id)
                        }
                    }
                }
                .frame(height: min(CGFloat(actions.count) * 36 + CGFloat(actions.filter(\.separatorBefore).count) * 11, 440))
                .onChange(of: focusedID) { _, id in if let id { proxy.scrollTo(id) } }
            }
        }
        .frame(width: width)
        .focusable().focusEffectDisabled()
        .onKeyPress(.escape) { onDismiss?(); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) {
            if let item = actions.first(where: { $0.id == focusedID && $0.enabled }) { invoke(item) }
            return .handled
        }
        .paperLensPopoverContent()
    }
    private func move(_ delta: Int) {
        let available = actions.filter(\.enabled)
        guard !available.isEmpty else { return }
        let current = available.firstIndex { $0.id == focusedID } ?? (delta > 0 ? -1 : available.count)
        focusedID = available[min(max(current + delta, 0), available.count - 1)].id
    }
    private func invoke(_ item: PopupAction) {
        guard item.enabled else { return }
        onDismiss?()
        item.action()
    }
}

/// A preset colour dot, the swatch the colour menus draw beside each name.
struct PopupColorSwatch: View {
    let color: NSColor
    var body: some View { Image(nsImage: Self.image(for: color)) }
    private static func image(for color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            color.withAlphaComponent(1).setFill()
            circle.fill()
            NSColor.black.withAlphaComponent(0.15).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
    }
}

/// Reports right-clicks on an otherwise SwiftUI control without taking its left
/// clicks: `hitTest` answers only for right-button events, so the view underneath
/// keeps its normal click, drag and hover behavior (AppKit hit-testing otherwise
/// ignores SwiftUI's `allowsHitTesting`).
struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void
    func makeNSView(context: Context) -> RightClickCatcherView {
        let view = RightClickCatcherView()
        view.action = action
        return view
    }
    func updateNSView(_ view: RightClickCatcherView, context: Context) { view.action = action }
}

final class RightClickCatcherView: NSView {
    var action: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    /// Only right-button events reach this view, so accepting first mouse keeps a
    /// right-click on an inactive window working (as the system menu did).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return super.hitTest(point)
        default:
            return nil
        }
    }
    override func rightMouseDown(with event: NSEvent) { action?() }
    /// The app-owned popover replaces the system context menu.
    override func menu(for event: NSEvent) -> NSMenu? { nil }
}

extension View {
    /// Right-click trigger for an app-owned popover; the system `contextMenu`
    /// cannot carry the shared row style.
    func onRightClick(perform action: @escaping () -> Void) -> some View {
        overlay(RightClickCatcher(action: action))
    }
}

/// Presents an app-owned SwiftUI popover from AppKit code (the comment card's ⋯
/// menu), so those menus read like every other popover.
@MainActor
enum PaperLensPopoverPresenter {
    private static var popover: NSPopover?

    static func present<Content: View>(_ content: Content, from view: NSView, edge: NSRectEdge = .maxY) {
        dismiss()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        let hosting = NSHostingController(rootView: content)
        hosting.view.layoutSubtreeIfNeeded()
        popover.contentViewController = hosting
        popover.contentSize = hosting.view.fittingSize
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: edge)
        self.popover = popover
    }

    static func dismiss() {
        popover?.performClose(nil)
        popover = nil
    }
}
