import SwiftUI
import AppKit

struct AnnotationsSettingsTab: View {
    private var settings: SettingsManager { SettingsManager.shared }
    @State private var confirmingReset = false

    var body: some View {
        SettingsPage(title: "Annotations", subtitle: "Customize highlight and comment colors.") {
            presetCard(title: "Highlight colors", kind: .highlight)
            presetCard(title: "Comment colors", kind: .comment)
            HStack {
                Button("Reset Colors…") { confirmingReset = true }.buttonStyle(SettingsActionStyle())
                Spacer()
            }
        }
        .alert("Reset annotation colors?", isPresented: $confirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { settings.resetColors() }
        } message: {
            Text("Restore default colors? Existing annotations are unchanged.")
        }
    }

    private enum Kind { case highlight, comment }
    private func presets(_ kind: Kind) -> [SettingsManager.ColorPreset] {
        kind == .highlight ? settings.highlightPresets : settings.commentPresets
    }
    private func update(_ preset: SettingsManager.ColorPreset, kind: Kind) {
        if kind == .highlight {
            guard let index = settings.highlightPresets.firstIndex(where: { $0.id == preset.id }) else { return }
            settings.highlightPresets[index] = preset
        } else {
            guard let index = settings.commentPresets.firstIndex(where: { $0.id == preset.id }) else { return }
            settings.commentPresets[index] = preset
        }
    }
    private func binding<Value>(_ id: UUID, kind: Kind, keyPath: WritableKeyPath<SettingsManager.ColorPreset, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { presets(kind).first { $0.id == id }?[keyPath: keyPath] ?? fallback }, set: { value in
            guard var preset = presets(kind).first(where: { $0.id == id }) else { return }
            preset[keyPath: keyPath] = value
            update(preset, kind: kind)
        })
    }
    private func presetCard(title: String, kind: Kind) -> some View {
        SettingsCard(title: title) {
            ForEach(Array(presets(kind).enumerated()), id: \.element.id) { index, preset in
                if index > 0 { Divider() }
                PresetRow(name: binding(preset.id, kind: kind, keyPath: \.name, fallback: ""),
                          color: binding(preset.id, kind: kind, keyPath: \.color, fallback: .gray),
                          canDelete: presets(kind).count > 1) {
                    guard let index = presets(kind).firstIndex(where: { $0.id == preset.id }) else { return }
                    if kind == .highlight { settings.removeHighlightPreset(at: index) }
                    else { settings.removeCommentPreset(at: index) }
                }
            }
            Divider()
            HStack {
                Button {
                    if kind == .highlight { settings.addHighlightPreset() }
                    else { settings.addCommentPreset() }
                } label: { Label("Add Color", systemImage: "plus") }
                .buttonStyle(SettingsActionStyle()).accessibilityLabel("Add \(title.lowercased()) preset")
                Spacer()
            }.padding(.vertical, 10)
        }
    }
}

struct PresetRow: View {
    @Binding var name: String
    @Binding var color: NSColor
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ColorWellView(color: $color)
                .frame(width: DesignTokens.colorWellWidth, height: DesignTokens.colorWellHeight)
                .accessibilityLabel("Color for \(name)")
            TextField("Color name", text: $name).textFieldStyle(.plain)
                .font(.system(size: 13)).accessibilityLabel("Color preset name")
            SettingsIconButton(symbol: "minus.circle", label: "Delete \(name) color", action: onDelete)
                .disabled(!canDelete)
        }
        .frame(minHeight: SettingsStyle.rowHeight).padding(.vertical, 4)
    }
}
