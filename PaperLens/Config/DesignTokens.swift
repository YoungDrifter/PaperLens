//
//  DesignTokens.swift
//  PaperLens
//
//  Design system - Single source of truth for colors, spacing, and layout constants
//

import AppKit
import SwiftUI

struct DesignTokens {
    // MARK: - Colors (macOS native)

    static let background = NSColor.windowBackgroundColor
    static let text = NSColor.labelColor
    static let separator = NSColor.separatorColor
    static let viewerBackground = NSColor.white

    static let chromeSurface = Color.white
    static let sidebarTop = Color.white
    static let sidebarBottom = Color.white
    static let chromeButtonSize: CGFloat = 38
    static let chromeIconSize: CGFloat = 19
    static let chromeHoverOpacity: Double = 0.05

    // MARK: - Annotation Colors

    static let underlineColor = NSColor.black

    // MARK: - Search Highlight Colors

    static let searchCurrentResult = NSColor(red: 0.6, green: 0, blue: 0, alpha: 0.6)
    static let searchOtherResults = NSColor(red: 0, green: 0, blue: 0.6, alpha: 0.6)

    // MARK: - Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24

    // MARK: - Layout

    static let sidebarWidth: CGFloat = 200
    static let outlineSidebarDefaultWidth: CGFloat = 240
    static let outlineSidebarMinWidth: CGFloat = 180
    static let outlineSidebarMaxWidth: CGFloat = 420

    static func outlineSidebarWidth(_ proposed: CGFloat, available: CGFloat) -> CGFloat {
        let maximum = max(0, min(outlineSidebarMaxWidth, available))
        return min(max(proposed, min(outlineSidebarMinWidth, maximum)), maximum)
    }
    static let thumbnailWidth: CGFloat = 120
    static let dialogWidth: CGFloat = 300
    static let textFieldWidth: CGFloat = 200

    // MARK: - Thumbnail Grid

    static let thumbnailHeight: CGFloat = 170
    static let thumbnailRenderWidth: CGFloat = 240
    static let thumbnailRenderHeight: CGFloat = 340
    static let thumbnailGridPadding: CGFloat = 12
    static let thumbnailCornerRadius: CGFloat = 4
    static let thumbnailBorderWidth: CGFloat = 1
    static let thumbnailSelectedBorderWidth: CGFloat = 2
    static let thumbnailBorder = Color(white: 0.65)
    static let thumbnailSelectedBorder = Color(white: 0.3)
    static let outlineSelection = NSColor(white: 0.86, alpha: 1)
    static let outlineHover = NSColor(white: 0.95, alpha: 1)
    static let outlineRowInset: CGFloat = 8
    static let outlineRowCornerRadius: CGFloat = 7
    static let outlinePageTrailingInset: CGFloat = 20
    static let outlineReadingInset: CGFloat = 24
    static let thumbnailBadgeFontSize: CGFloat = 12

    // MARK: - Settings Window

    static let settingsWindowWidth: CGFloat = SettingsStyle.windowSize.width
    static let settingsWindowHeight: CGFloat = SettingsStyle.windowSize.height
    static let colorWellWidth: CGFloat = 44
    static let colorWellHeight: CGFloat = 20
    static let presetRowHeight: CGFloat = 24
    static let shortcutKeyDisplayWidth: CGFloat = 80
    static let shortcutButtonWidth: CGFloat = 100

    // MARK: - Floating Toolbar

    static let floatingToolbarCornerRadius: CGFloat = 14
    static let floatingToolbarBase = Color.black

    // MARK: - Liquid Glass

    static let glassPanelTintOpacity: CGFloat = 0.12
    static let sidebarGlassTintOpacity: CGFloat = 0.32
    static let glassElevationShadowOpacity: Double = 0.055
    static let glassTextPrimary = Color.black
    static let glassTextSecondary = Color(red: 0.24, green: 0.24, blue: 0.24)
    static let sidebarSecondaryText = glassTextSecondary

    // MARK: - Traffic Lights

    /// Reserved leading width in the top chrome so the tab strip clears the
    /// native window buttons (close / minimize / zoom).
    static let trafficLightClusterWidth: CGFloat = 70

    // MARK: - Animation

    static let animationFast: Double = 0.15

    // MARK: - Autoscroll (Thumbnail Drag)

    static let autoscrollEdgeZone: CGFloat = 60        // Edge detection zone from viewport edge
    static let autoscrollHysteresis: CGFloat = 10     // Buffer to prevent jitter at boundary
    static let autoscrollDwellTime: Double = 0.075    // Delay before activation (75ms)
    static let autoscrollMinInterval: Double = 0.08   // Fastest scroll speed (at edge)
    static let autoscrollMaxInterval: Double = 0.35   // Slowest scroll speed (at zone boundary)

    // MARK: - PDF Viewer

    static let pdfMinScale: CGFloat = 0.1
    static let pdfMaxScale: CGFloat = 4.0
    static let pdfDefaultScale: CGFloat = 1.0
    static let pdfZoomStep: CGFloat = 0.25
    static let pdfViewPadding: CGFloat = 20
    static let pdfTwoPageGap: CGFloat = 10
    static let pdfControlScrollZoomFactor: CGFloat = 1.1

    // MARK: - Search

    static let searchBarWidth: CGFloat = 200

    // MARK: - Comments

    // #80808099 - must match default preset in SettingsManager (0x99 = 153 = 0.6 alpha)
    static let commentHighlightColor: NSColor = {
        let gray = CGFloat(0x80) / 255.0
        let alpha = CGFloat(0x99) / 255.0
        return NSColor(srgbRed: gray, green: gray, blue: gray, alpha: alpha)
    }()

    // Comment card styling.
    //
    // The sidebar bubbles were too transparent: a translucent white bubble on the
    // translucent (white-tinted) glass sidebar let the dark PDF page bleed through,
    // collapsing text contrast. PaperLens's glass chrome is a *fixed* light-frosted
    // look (white tint + dark `glassTextPrimary` text) regardless of system
    // appearance, so the fix is an OPAQUE light card carrying that same dark glass
    // text — NOT an appearance-adaptive surface, which renders dark in the viewer's
    // dark appearance context and clashes with the light chrome. Glass stays on the
    // panel; text rides on the opaque card.
    /// The opaque content-card surface, shared by comment bubbles, the thumbnail
    /// letterbox fill, and the tab drag pill so they all read as the same card.
    static let contentCardSurface = Color.white

    // MARK: - Window

    static let windowDragRegionHeight: CGFloat = 6
    static let minimumWindowWidth: CGFloat = 720
    static let minimumWindowHeight: CGFloat = 360
    static let defaultWindowWidth: CGFloat = 1120
    static let defaultWindowHeight: CGFloat = 820

    // MARK: - Tabs

    static let tabHeight: CGFloat = 28
    static let tabMaxWidth: CGFloat = 200
    static let tabMinWidth: CGFloat = 100
    static let tabSpacing: CGFloat = 2
    static let tabCornerRadius: CGFloat = 6
    static let tabBarLeftMargin: CGFloat = 80
    static let tabCloseButtonSize: CGFloat = 14
    static let tabDirtyIndicatorSize: CGFloat = 6

    // MARK: - Timing (PDFKit workaround delays)

    /// Brief delay for PDFKit layout to settle after document/scale changes
    static let pdfLayoutSettleDelay: TimeInterval = 0.05
    /// Delay for PDFKit to update layout after display mode changes
    static let pdfDisplayModeSettleDelay: TimeInterval = 0.1
    /// Interval between retries when waiting for PDFView to become ready
    static let pdfViewReadyRetryInterval: TimeInterval = 0.1
    /// Maximum retries when waiting for PDFView/window readiness
    static let maxReadinessRetries: Int = 10
}
