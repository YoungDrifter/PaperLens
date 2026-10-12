import SwiftUI

struct SidebarHeaderView: View {
    @Binding var mode: SidebarMode
    var body: some View {
        HStack(spacing: 0) {
            ForEach(SidebarMode.allCases, id: \.self) { option in
                SidebarModeButton(option: option, mode: $mode)
            }
        }
        .padding(3).paperLensGlassCapsule()
        .accessibilityElement(children: .contain).accessibilityLabel("Sidebar Mode")
        .frame(maxWidth: .infinity).frame(height: 58)
    }
}

private struct SidebarModeButton: View {
    let option: SidebarMode
    @Binding var mode: SidebarMode
    var body: some View {
        ChromeButton(option.icon, help: option.title, glass: false, selected: mode == option) {
            mode = option
        }
    }
}
