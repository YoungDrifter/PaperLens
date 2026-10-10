import PDFKit
import Testing
@testable import PaperLens

/// The page-display list shared by the View menu and the toolbar's More menu.
@MainActor
struct PDFDisplayModeMenuTests {
    @Test func menuChoicesOfferSingleContinuousAndTwoPageModes() {
        #expect(PDFDisplayMode.menuChoices == [.singlePage, .singlePageContinuous, .twoUp, .twoUpContinuous])
    }

    @Test func menuTitlesAreStable() {
        #expect(PDFDisplayMode.menuChoices.map(\.menuTitle) == [
            "Single Page", "Single Page Continuous", "Two Pages", "Two Pages Continuous"
        ])
    }

    /// The toolbar's More menu sets `displayMode` on the manager (which the
    /// projector applies to the live `PDFView`); every offered mode must survive
    /// that round trip, including the two-page ones that are excluded from
    /// auto-scale.
    @Test func everyOfferedModeRoundTripsThroughTheManager() {
        let manager = PDFManager()
        for mode in PDFDisplayMode.menuChoices {
            manager.displayMode = mode
            #expect(manager.displayMode == mode)
        }
    }
    @Test func pageNavigationControlsFollowNonContinuousModes() {
        #expect(PDFDisplayMode.singlePage.showsPageNavigationButtons)
        #expect(PDFDisplayMode.twoUp.showsPageNavigationButtons)
        #expect(!PDFDisplayMode.singlePageContinuous.showsPageNavigationButtons)
        #expect(!PDFDisplayMode.twoUpContinuous.showsPageNavigationButtons)
    }

}
