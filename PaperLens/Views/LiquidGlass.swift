//
//  LiquidGlass.swift
//  PaperLens
//
//  Shared Liquid Glass styling for PaperLens controls and navigation chrome.
//

import AppKit
import SwiftUI

enum PaperLensGlassVariant: Equatable {
    case regular
    case clear
}

enum PaperLensGlassTint: Equatable {
    case dark
    case light

    func color(opacity: CGFloat) -> Color {
        switch self {
        case .dark:
            return DesignTokens.floatingToolbarBase.opacity(Double(opacity))
        case .light:
            return Color.white.opacity(Double(opacity))
        }
    }

    func nsColor(opacity: CGFloat) -> NSColor {
        switch self {
        case .dark:
            return NSColor(white: 0.196, alpha: opacity)
        case .light:
            return NSColor.white.withAlphaComponent(opacity)
        }
    }
}

extension View {
    @ViewBuilder
    func paperLensLiquidGlassSurface(
        cornerRadius: CGFloat,
        tint: PaperLensGlassTint = .dark,
        tintOpacity: CGFloat = 0.12,
        interactive: Bool = false,
        variant: PaperLensGlassVariant = .regular,
        strokeOpacity: Double = 0.22
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        self.background(Color.white, in: shape)
            .overlay(shape.strokeBorder(Color.black.opacity(0.10), lineWidth: 0.7).allowsHitTesting(false))
    }

    func paperLensLiquidGlassPanel(
        cornerRadius: CGFloat = DesignTokens.floatingToolbarCornerRadius,
        tint: PaperLensGlassTint = .dark,
        tintOpacity: CGFloat = 0.12,
        interactive: Bool = false,
        variant: PaperLensGlassVariant = .regular,
        strokeOpacity: Double = 0.22,
        shadowRadius: CGFloat = 10,
        shadowY: CGFloat = 5
    ) -> some View {
        paperLensLiquidGlassSurface(
            cornerRadius: cornerRadius,
            tint: tint,
            tintOpacity: tintOpacity,
            interactive: interactive,
            variant: variant,
            strokeOpacity: strokeOpacity
        )
        .shadow(color: .black.opacity(DesignTokens.glassElevationShadowOpacity), radius: shadowRadius, y: shadowY)
    }
}

@available(macOS 26.0, *)
private func paperLensGlass(
    variant: PaperLensGlassVariant,
    tint: PaperLensGlassTint,
    tintOpacity: CGFloat,
    interactive: Bool
) -> Glass {
    let base: Glass = variant == .clear ? .clear : .regular
    let glass = tintOpacity > 0
        ? base.tint(tint.color(opacity: tintOpacity))
        : base

    return glass.interactive(interactive)
}

// MARK: - Named Glass Styles

/// A named bundle of the glass-surface parameters, so call sites read
/// `.paperLensLiquidGlassPanel(.toolbar)` instead of repeating an opaque tuple of
/// magic numbers. Presets are exposed as static members (see the extension
/// below), mirroring how SwiftUI surfaces `.bordered` / `.plain` styles.
///
/// Defaults mirror the underlying `paperLensLiquidGlassSurface` / `Panel`
/// modifier defaults exactly, so a preset that omits a field reproduces the same
/// value the call site would have gotten by omitting that argument. `shadowRadius`
/// / `shadowY` are only consumed by the panel overload; the surface overload
/// ignores them.
struct GlassStyle {
    var cornerRadius: CGFloat
    var tint: PaperLensGlassTint = .dark
    var tintOpacity: CGFloat = 0.12
    var interactive: Bool = false
    var variant: PaperLensGlassVariant = .regular
    var strokeOpacity: Double = 0.22
    var shadowRadius: CGFloat = 10
    var shadowY: CGFloat = 5

    /// Returns a copy with the given fields overridden — an escape hatch for the
    /// one or two call sites that differ from a preset by a single value, without
    /// minting a whole new named style.
    func with(
        cornerRadius: CGFloat? = nil,
        tint: PaperLensGlassTint? = nil,
        tintOpacity: CGFloat? = nil,
        interactive: Bool? = nil,
        variant: PaperLensGlassVariant? = nil,
        strokeOpacity: Double? = nil,
        shadowRadius: CGFloat? = nil,
        shadowY: CGFloat? = nil
    ) -> GlassStyle {
        var copy = self
        if let cornerRadius { copy.cornerRadius = cornerRadius }
        if let tint { copy.tint = tint }
        if let tintOpacity { copy.tintOpacity = tintOpacity }
        if let interactive { copy.interactive = interactive }
        if let variant { copy.variant = variant }
        if let strokeOpacity { copy.strokeOpacity = strokeOpacity }
        if let shadowRadius { copy.shadowRadius = shadowRadius }
        if let shadowY { copy.shadowY = shadowY }
        return copy
    }
}

extension GlassStyle {
    // Chrome panels (carry their own elevation shadow).
    static let toolbar = GlassStyle(
        cornerRadius: DesignTokens.floatingToolbarCornerRadius,
        tint: .light, tintOpacity: 0.14, variant: .clear,
        strokeOpacity: 0.22, shadowRadius: 4, shadowY: -2
    )
    /// Shared by the outline sidebar and the comments sidebar (identical tuple).
    static let sidebar = GlassStyle(
        cornerRadius: DesignTokens.floatingToolbarCornerRadius,
        tint: .light, tintOpacity: DesignTokens.sidebarGlassTintOpacity, variant: .clear,
        strokeOpacity: 0.22, shadowRadius: 4, shadowY: -2
    )
    /// Shared by the search bar and the toast (identical after defaults).
    static let glassPanel = GlassStyle(
        cornerRadius: DesignTokens.floatingToolbarCornerRadius,
        tint: .light, tintOpacity: DesignTokens.glassPanelTintOpacity, variant: .regular,
        strokeOpacity: 0.22, shadowRadius: 10, shadowY: 5
    )
    /// The drag-and-drop target panel.
    static let dropZone = GlassStyle(
        cornerRadius: DesignTokens.spacingMD,
        tint: .light, tintOpacity: 0.18, variant: .regular,
        strokeOpacity: 0.4, shadowRadius: 16, shadowY: 6
    )

    // Chrome surfaces (no built-in shadow; an external .shadow stays at the call site).
    static let newTabButton = GlassStyle(
        cornerRadius: DesignTokens.tabCornerRadius,
        tint: .light, tintOpacity: 0.14, variant: .clear, strokeOpacity: 0.22
    )

    /// Settings-tab rows omit `tint` (so they keep the default `.dark`).
    static let settingsRow = GlassStyle(
        cornerRadius: DesignTokens.spacingSM,
        tintOpacity: 0.08, interactive: true, variant: .clear, strokeOpacity: 0.16
    )

    /// A tab pill; `active` drives tint and stroke. The pill's drop shadow is
    /// also state-dependent and stays as an external `.shadow` at the call site.
    static func tab(active: Bool) -> GlassStyle {
        GlassStyle(
            cornerRadius: DesignTokens.tabCornerRadius,
            tint: .light,
            tintOpacity: active ? 0.22 : 0.14,
            variant: .clear,
            strokeOpacity: active ? 0.3 : 0.18
        )
    }

    /// A settings action button whose emphasis depends on `enabled`. `activeTint`
    /// is the enabled tint opacity (0.08 for General's Reset, 0.10 for Shortcuts).
    static func settingsAction(enabled: Bool, activeTint: CGFloat) -> GlassStyle {
        GlassStyle(
            cornerRadius: DesignTokens.spacingSM,
            tintOpacity: enabled ? activeTint : 0.04,
            interactive: enabled,
            variant: .clear,
            strokeOpacity: enabled ? 0.16 : 0.08
        )
    }
}

extension View {
    /// Applies a named glass surface. Forwards every field to the parameterized
    /// `paperLensLiquidGlassSurface`, so it is behavior-identical to spelling the
    /// tuple out. `shadowRadius` / `shadowY` are intentionally unused here.
    func paperLensLiquidGlassSurface(_ style: GlassStyle) -> some View {
        paperLensLiquidGlassSurface(
            cornerRadius: style.cornerRadius,
            tint: style.tint,
            tintOpacity: style.tintOpacity,
            interactive: style.interactive,
            variant: style.variant,
            strokeOpacity: style.strokeOpacity
        )
    }

    /// Applies a named glass panel (surface + elevation shadow). Forwards every
    /// field to the parameterized `paperLensLiquidGlassPanel`.
    func paperLensLiquidGlassPanel(_ style: GlassStyle) -> some View {
        paperLensLiquidGlassPanel(
            cornerRadius: style.cornerRadius,
            tint: style.tint,
            tintOpacity: style.tintOpacity,
            interactive: style.interactive,
            variant: style.variant,
            strokeOpacity: style.strokeOpacity,
            shadowRadius: style.shadowRadius,
            shadowY: style.shadowY
        )
    }
}

// MARK: - Chrome Glyph Button

/// A 24×24 liquid-glass chrome glyph, shared by the tab bar's "+" and the Tab
/// Switcher chevron so the two stay visually identical by construction instead
/// of by copy-paste.
struct ChromeGlassIcon: View {
    let systemName: String
    var pointSize: CGFloat = DesignTokens.chromeIconSize
    var body: some View {
        Image(systemName: systemName).font(.system(size: pointSize))
            .foregroundStyle(.primary).frame(width: DesignTokens.chromeButtonSize, height: DesignTokens.chromeButtonSize)
            .paperLensGlassCapsule()
            .contentShape(Capsule())
    }
}

/// Consistent light capsule chrome. Native Liquid Glass on macOS 26+, with a
/// material fallback on the older supported systems; labels keep crisp edges.
extension View {
    @ViewBuilder
    func paperLensGlassCapsule(selected: Bool = false) -> some View {
        self.background(Color.white, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.black.opacity(selected ? 0.22 : 0.10), lineWidth: 0.7).allowsHitTesting(false))
    }
}
