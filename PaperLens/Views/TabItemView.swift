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
                if isDirty {
                    Circle().fill(.secondary)
                        .frame(width: DesignTokens.tabDirtyIndicatorSize, height: DesignTokens.tabDirtyIndicatorSize)
                }
                Text(tab.displayTitle)
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .lineLimit(1).truncationMode(.middle)
            }.frame(maxWidth: .infinity)
            Color.clear.frame(width: DesignTokens.tabCloseButtonSize, height: DesignTokens.tabCloseButtonSize)
        }
        .padding(.horizontal, DesignTokens.spacingSM)
        .frame(height: DesignTokens.tabHeight)
        .frame(width: width)
        // Capsule, like QuillTeX's file tabs. Only the drawing changes: the pill
        // fills the same frame the tab bar reports, so the frame-based click and
        // drag handling is untouched.
        .background(Capsule().fill(isActive ? DesignTokens.tabActiveFill
                                            : Color.black.opacity(isHovering ? DesignTokens.tabHoverOpacity : 0)))
        .overlay {
            Capsule().strokeBorder(Color.black.opacity(isActive ? DesignTokens.tabStrokeOpacity : 0),
                                   lineWidth: DesignTokens.tabStrokeWidth)
        }
        .shadow(color: .black.opacity(isActive ? DesignTokens.tabActiveShadowOpacity : 0),
                radius: DesignTokens.tabShadowRadius, y: DesignTokens.tabShadowY)
        .contentShape(Rectangle())
    }
}
