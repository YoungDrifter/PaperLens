import SwiftUI
import AppKit

struct ShortcutsSettingsTab: View {
    @State private var confirmingReset = false
    var body: some View {
        SettingsPage(title: "Shortcuts", subtitle: "Click a shortcut to change it.") {
            ForEach(ShortcutCatalog.grouped(), id: \.0) { group in
                SettingsCard(title: group.0.rawValue) {
                    ForEach(Array(group.1.enumerated()), id: \.element.id) { index, action in
                        if index > 0 { Divider() }
                        ShortcutRow(actionID: action.id, label: action.title)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Button("Reset Shortcuts…") { confirmingReset = true }.buttonStyle(SettingsActionStyle())
                Text("Restart to apply changes.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .alert("Reset all shortcuts?", isPresented: $confirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { SettingsManager.shared.resetShortcuts() }
        } message: {
            Text("Restore default shortcuts?")
        }
    }
}

struct ShortcutRow: View {
    let actionID: String
    let label: String

    @State private var isRecording = false
    @State private var pendingShortcut: ShortcutModel?
    @State private var eventMonitor: Any?

    var body: some View {
        SettingsRow(title: label) { shortcutControl }
        .onDisappear {
            // Clean up event monitor if view is removed while recording
            stopRecording()
        }
    }

    @ViewBuilder
    private var shortcutControl: some View {
        if isRecording {
            VStack(alignment: .trailing, spacing: 6) {
                Text(pendingShortcut?.displayString ?? "Press keys...")
                    .foregroundStyle(.secondary)
                    .frame(width: DesignTokens.shortcutKeyDisplayWidth)

                if let warning = validation?.warning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(validation?.blocksConfirm == true ? .red : .orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Button("Cancel") { cancelRecording() }.buttonStyle(SettingsActionStyle())
                    Button("Save") { confirmShortcut() }.buttonStyle(SettingsActionStyle())
                        .disabled(!canConfirm)
                }

            }
        } else {
            Button(currentDisplayString) {
                startRecording()
            }
            .buttonStyle(SettingsActionStyle())
            .frame(minWidth: DesignTokens.shortcutButtonWidth)
            .accessibilityLabel("Shortcut for \(label): \(currentDisplayString)")

        }
    }

    private var currentDisplayString: String {
        ShortcutModel.current(for: actionID).displayString
    }

    /// Vetting of the in-progress recording (nil until a key is captured).
    private var validation: ShortcutValidation? {
        pendingShortcut.map { ShortcutCatalog.validate($0, for: actionID) }
    }

    /// Confirm is allowed once a key is captured and it isn't reserved / too weak.
    /// A mere conflict only warns — the user may deliberately reassign.
    private var canConfirm: Bool {
        guard let validation else { return false }
        return !validation.blocksConfirm
    }

    private func startRecording() {
        isRecording = true
        pendingShortcut = nil

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                cancelRecording()
                return nil
            }

            if let shortcut = ShortcutModel.from(event: event) {
                pendingShortcut = shortcut
            }
            return nil
        }
    }

    private func confirmShortcut() {
        guard let shortcut = pendingShortcut,
              !ShortcutCatalog.validate(shortcut, for: actionID).blocksConfirm else { return }
        SettingsManager.shared.customShortcuts[actionID] = shortcut
        stopRecording()
    }

    private func cancelRecording() {
        stopRecording()
    }

    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
        pendingShortcut = nil
    }
}
