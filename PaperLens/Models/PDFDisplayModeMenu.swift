//
//  PDFDisplayModeMenu.swift
//  PaperLens
//
//  The page-display choices the app offers, in one place so the View menu and
//  the toolbar's More menu can never drift apart.
//

import PDFKit

extension PDFDisplayMode {
    var showsPageNavigationButtons: Bool { self == .singlePage || self == .twoUp }

    /// Menu order: one page at a time, then the continuous variants.
    static let menuChoices: [PDFDisplayMode] = [
        .singlePage,
        .singlePageContinuous,
        .twoUp,
        .twoUpContinuous
    ]

    /// The label both menus show for this mode.
    var menuTitle: String {
        switch self {
        case .singlePage: "Single Page"
        case .singlePageContinuous: "Single Page Continuous"
        case .twoUp: "Two Pages"
        case .twoUpContinuous: "Two Pages Continuous"
        @unknown default: "Single Page Continuous"
        }
    }
}
