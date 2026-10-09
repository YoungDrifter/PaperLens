import SwiftUI

struct TabItemView: View {
    let tab: TabModel
    let isActive: Bool
    let isDirty: Bool
    let isHovering: Bool
    var isDragInProgress = false
    var width: CGFloat? = nil

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: DesignTokens.tabCloseButtonSize, height: DesignTokens.tabCloseButtonSize)
                .opacity(isHovering ? 1 : 0)
            HStack(spacing: 5) {
                if isDirty { Circle().fill(.secondary).frame(width: 6, height: 6) }
                Text(tab.displayTitle)
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .lineLimit(1).truncationMode(.middle)
            }.frame(maxWidth: .infinity)
            Color.clear.frame(width: DesignTokens.tabCloseButtonSize, height: DesignTokens.tabCloseButtonSize)
        }
        .padding(.horizontal, DesignTokens.spacingSM)
        .frame(height: 28)
        .frame(width: width)
        .background(Capsule().fill(isActive ? Color.white : Color.black.opacity(isHovering ? 0.04 : 0)))
        .overlay { Capsule().strokeBorder(Color.black.opacity(isActive ? 0.10 : 0), lineWidth: 0.7) }
        .contentShape(Rectangle())
    }
}
