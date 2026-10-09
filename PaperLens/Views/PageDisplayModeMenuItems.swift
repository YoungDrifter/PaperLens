//
//  PageDisplayModeMenuItems.swift
//  PaperLens
//
//  The page-display choices as menu items, shared by the View menu and the
//  toolbar's More menu so the two surfaces can never drift apart.
//

import SwiftUI
import PDFKit

/// Checkmark items for Single Page / Single Page Continuous / Two Pages / Two
/// Pages Continuous. No picker label: inside a menu the label would render as a
/// grey section header the modes don't need.
struct PageDisplayModeMenuItems: View {
    let pdfManager: PDFManager?

    var body: some View {
        ForEach(PDFDisplayMode.menuChoices, id: \.self) { mode in
            Toggle(mode.menuTitle, isOn: selectionBinding(for: mode))
                .disabled(pdfManager?.hasDocument != true)
        }
    }

    /// Radio semantics: selecting a mode sets it, clearing the selected one is a
    /// no-op (the menu closes either way).
    private func selectionBinding(for mode: PDFDisplayMode) -> Binding<Bool> {
        Binding(
            get: { pdfManager?.displayMode == mode },
            set: { isSelected in if isSelected { pdfManager?.displayMode = mode } }
        )
    }
}
