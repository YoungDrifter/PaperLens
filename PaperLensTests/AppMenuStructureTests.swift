import AppKit
import PDFKit
import Testing
@testable import PaperLens

/// The app builds its document menus with SwiftUI `Commands`, and the unit tests
/// are hosted by PaperLens.app itself, so `NSApp.mainMenu` here is the real menu
/// bar the user sees.
///
/// Regression: the app declared `CommandMenu("View")` on top of the View menu
/// AppKit already creates, so the menu bar carried two "View" menus (one of them
/// empty). The document commands now go into the system menu through its
/// `CommandGroupPlacement`.
@MainActor
struct AppMenuStructureTests {
    private func mainMenu() throws -> NSMenu {
        try #require(NSApp.mainMenu, Comment(rawValue: menuDump()))
    }

    private func viewMenu() throws -> NSMenu {
        let menu = try mainMenu()
        let views = menu.items.filter { $0.title == "View" }
        #expect(views.count == 1, Comment(rawValue: menuDump()))
        return try #require(views.first?.submenu, Comment(rawValue: menuDump()))
    }

    private func itemTitles(in menu: NSMenu) -> [String] {
        menu.items.filter { !$0.isSeparatorItem }.map(\.title)
    }

    /// Every line of the live menu bar, for failure messages.
    private func menuDump() -> String {
        guard let mainMenu = NSApp.mainMenu else { return "no main menu" }
        var lines: [String] = []
        for item in mainMenu.items {
            lines.append("[\(item.title)]")
            for child in item.submenu?.items ?? [] where !child.isSeparatorItem {
                lines.append("  \(child.title)")
            }
        }
        return lines.joined(separator: "\n")
    }

    @Test func viewMenuAppearsExactlyOnceInTheMenuBar() throws {
        let titles = try mainMenu().items.map(\.title)
        #expect(titles.filter { $0 == "View" }.count == 1, Comment(rawValue: menuDump()))
    }

    @Test func viewMenuCarriesTheDocumentCommands() throws {
        let titles = itemTitles(in: try viewMenu())
        // "Enter Full Screen" is deliberately absent: that item is AppKit's own
        // (see `viewMenuNeverOffersTwoFullScreenCommands`).
        for expected in ["Zoom In", "Zoom Out", "Fit Page", "Fit Width",
                         "Auto-Scale", "Toggle Sidebar", "Show Tab Bar", "Show Toolbar"] {
            #expect(titles.contains(expected), "View menu is missing \(expected): \(titles)")
        }
    }

    /// The comments panel is reached from the sidebar switcher and the toolbar,
    /// so the View menu no longer offers a (permanently confusing) comments
    /// toggle. `ShortcutCatalog` drops its binding with it.
    @Test func viewMenuHasNoCommentsToggle() throws {
        let titles = itemTitles(in: try viewMenu())
        #expect(!titles.contains("Show Comments"), Comment(rawValue: menuDump()))
        #expect(!titles.contains("Hide Comments"), Comment(rawValue: menuDump()))
        #expect(ShortcutCatalog.action(for: "toggleComments") == nil)
    }

    /// Go is page navigation. History Back/Forward moved out of it (the toolbar
    /// keeps them), so they must not reappear here.
    @Test func goMenuOffersPageNavigationWithoutHistoryItems() throws {
        let go = try #require(try mainMenu().items.first { $0.title == "Go" }?.submenu,
                              Comment(rawValue: menuDump()))
        let titles = itemTitles(in: go)
        #expect(!titles.contains("Back"), Comment(rawValue: menuDump()))
        #expect(!titles.contains("Forward"), Comment(rawValue: menuDump()))
        #expect(titles.contains("Next Page"))
        #expect(titles.contains("Go to Page…"))
        #expect(ShortcutCatalog.action(for: "goBack") == nil)
        #expect(ShortcutCatalog.action(for: "goForward") == nil)
    }

    @Test func viewMenuCarriesEveryPageDisplayMode() throws {
        let titles = Set(itemTitles(in: try viewMenu()))
        for mode in PDFDisplayMode.menuChoices {
            #expect(titles.contains(mode.menuTitle), "View menu is missing \(mode.menuTitle): \(titles)")
        }
    }

    /// PaperLens has its own tab strip, so AppKit's native window tabbing — the
    /// feature behind native tabs — stays off. The app owns Show Tab Bar.
    @Test func nativeWindowTabbingIsDisabled() throws {
        #expect(NSWindow.allowsAutomaticWindowTabbing == false)
        let titles = itemTitles(in: try viewMenu())
        #expect(titles.filter { $0 == "Show Tab Bar" }.count == 1, Comment(rawValue: menuDump()))
        let item = try #require(try viewMenu().items.first { $0.title == "Show Tab Bar" })
        #expect(item.action != NSSelectorFromString("toggleTabBar:"))
        #expect(!titles.contains("Show All Tabs"), Comment(rawValue: menuDump()))
    }

    /// Full screen is AppKit's own View-menu item. The app adds none — a second
    /// one was the duplicate that kept showing up — and with no app item there is
    /// no `ShortcutCatalog` binding for it either.
    @Test func viewMenuNeverOffersTwoFullScreenCommands() throws {
        #expect(ShortcutCatalog.action(for: "enterFullScreen") == nil)
        let titles = itemTitles(in: try viewMenu())
        #expect(titles.filter { $0 == "Enter Full Screen" }.count <= 1, Comment(rawValue: menuDump()))
    }
}
