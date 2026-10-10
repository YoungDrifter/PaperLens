import AppKit

/// Public branding: the name, version and icon shown to users.
enum AppIdentity {
    static let displayName = "PaperLens"
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1" }
    static var buildNumber: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }
    static var versionLabel: String { versionLabel(version: version, build: buildNumber) }
    static func versionLabel(version: String, build: String?) -> String {
        guard let build, !build.isEmpty else { return version }
        return "\(version) (Build \(build))"
    }
    static let icon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        if let url = Bundle.main.url(forResource: "icon_1024", withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: displayName)!
    }()
}
