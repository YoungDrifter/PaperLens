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
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selected: Bool { mode == option }
    var body: some View {
        Button { mode = option } label: {
            Image(systemName: option.icon).font(.system(size: 17, weight: selected ? .medium : .regular))
                .frame(width: 34, height: 34)
                .foregroundStyle(Color.black)
                .background {
                    Capsule().fill(selected ? Color.white : .clear)
                        .overlay(Capsule().strokeBorder(Color.black.opacity(selected ? 0.16 : 0), lineWidth: 0.8))
                        .shadow(color: .black.opacity(selected ? 0.13 : 0), radius: 2.5, y: 1.5)
                }
                .scaleEffect(hovering && !reduceMotion ? 1.04 : 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain).help(option.title).accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
