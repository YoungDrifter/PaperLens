import AppKit

/// Public branding: the name, version and icon shown to users.
enum AppIdentity {
    static let displayName = "PaperLens"
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }
    static let icon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        if let url = Bundle.main.url(forResource: "icon_1024", withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: displayName)!
    }()
}
