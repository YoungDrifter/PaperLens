import Foundation
import AppKit
import UniformTypeIdentifiers

/// Manages first-launch experience and default PDF reader settings
@Observable
final class FirstLaunchManager {
    private let hasShownDefaultPromptKey = "hasShownDefaultPDFPrompt"

    /// Check if the app is currently the default PDF reader
    var isDefaultPDFReader: Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        let pdfUTI = UTType.pdf.identifier as CFString
        guard let currentHandler = LSCopyDefaultRoleHandlerForContentType(pdfUTI, .all)?.takeRetainedValue() as String? else {
            return false
        }
        return currentHandler.lowercased() == bundleIdentifier.lowercased()
    }

    /// Check if this is first launch and show default PDF reader prompt if needed
    func handleFirstLaunch() {
        // Test host: a modal alert here blocks the main actor and stalls the whole
        // suite (the same reason the quit-time save prompt is skipped under tests).
        guard !TestEnvironment.isRunningTests else { return }
        guard !hasShownDefaultPrompt else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showDefaultPDFReaderPrompt()
        }
    }

    private var hasShownDefaultPrompt: Bool {
        UserDefaults.standard.bool(forKey: hasShownDefaultPromptKey)
    }

    private func markPromptAsShown() {
        UserDefaults.standard.set(true, forKey: hasShownDefaultPromptKey)
    }

    /// Show native alert asking user to set the app as default PDF reader
    private func showDefaultPDFReaderPrompt() {
        let alert = NSAlert()
        alert.messageText = "Set \(AppIdentity.displayName) as Default PDF Reader?"
        alert.informativeText = "Would you like to set \(AppIdentity.displayName) as your default application for opening PDF files?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Set as Default")
        alert.addButton(withTitle: "Not Now")

        let response = alert.runModal()
        markPromptAsShown()

        if response == .alertFirstButtonReturn {
            setAsDefaultPDFReader()
        }
    }

    /// Set the app as the default handler for PDF documents (callable from menu)
    func setAsDefaultPDFReader() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            showErrorAlert(message: "Could not determine app bundle identifier.")
            return
        }

        let pdfUTI = UTType.pdf.identifier as CFString
        let status = LSSetDefaultRoleHandlerForContentType(pdfUTI, .all, bundleIdentifier as CFString)

        if status == noErr {
            // Verify it actually worked
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                if self?.isDefaultPDFReader == true {
                    self?.showSuccessAlert()
                } else {
                    self?.openSystemPreferencesForDefaultApps()
                }
            }
        } else {
            openSystemPreferencesForDefaultApps()
        }
    }

    /// Open System Settings to let user manually set default PDF app
    private func openSystemPreferencesForDefaultApps() {
        let alert = NSAlert()
        alert.messageText = "Set Default PDF Reader"
        alert.informativeText = """
        To set \(AppIdentity.displayName) as your default PDF reader:

        1. Right-click any PDF file in Finder
        2. Select "Get Info" (or press ⌘I)
        3. Under "Open with:", select \(AppIdentity.displayName)
        4. Click "Change All..."

        This will make \(AppIdentity.displayName) open all PDF files.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showSuccessAlert() {
        let alert = NSAlert()
        alert.messageText = "Success"
        alert.informativeText = "\(AppIdentity.displayName) is now your default PDF reader. All PDF files will open in \(AppIdentity.displayName)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
