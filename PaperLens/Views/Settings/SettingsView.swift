import SwiftUI
import AppKit

struct SettingsView: View {
    enum Section: String, CaseIterable {
        case annotations = "Annotations", shortcuts = "Shortcuts", plugins = "Plugins", about = "About"
        var symbol: String {
            switch self {
            case .annotations: "highlighter"
            case .shortcuts: "keyboard"
            case .plugins: "puzzlepiece.extension"
            case .about: "info.circle"
            }
        }
    }
    @State private var selection: Section

    init(initialSection: Section = .annotations) { _selection = State(initialValue: initialSection) }

    var body: some View {
        SettingsLayout(appName: AppIdentity.displayName, version: AppIdentity.version, icon: AppIdentity.icon,
                       categories: Section.allCases.map { SettingsCategory(id: $0, title: $0.rawValue, symbol: $0.symbol) },
                       selection: $selection) {
            switch selection {
            case .annotations: AnnotationsSettingsTab()
            case .shortcuts: ShortcutsSettingsTab()
            case .plugins: PluginSettingsPane()
            case .about: GeneralSettingsTab()
            }
        }
    }
}
