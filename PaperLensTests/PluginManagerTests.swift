import Foundation
import Testing
@testable import PaperLens

@MainActor
struct PluginManagerTests {
    @Test func updateChecksAreCoreAndDaily() throws {
        #expect(PluginManager.shared.plugins.isEmpty)
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool == true)
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUScheduledCheckInterval") as? Int == 86400)
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUAllowsAutomaticUpdates") as? Bool == false)
        #expect(Bundle.main.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool == true)
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String == "https://github.com/YoungDrifter/PaperLens/releases/latest/download/appcast.xml")
    }

    @Test func switchesPersistAndControlPluginLifecycleIndependently() throws {
        let suite = "PluginManagerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var starts = 0
        var stops = 0
        var otherStarts = 0
        let plugin = AppPlugin(id: "sample", name: "Sample", summary: "Test extension", symbol: "sparkles",
                               activate: { starts += 1 }, deactivate: { stops += 1 })
        let other = AppPlugin(id: "other", name: "Other", summary: "Independent extension", symbol: "puzzlepiece.extension",
                              activate: { otherStarts += 1 }, deactivate: {})
        let manager = PluginManager(plugins: [plugin, other], defaults: defaults)
        #expect(!manager.isEnabled("sample") && starts == 0)
        manager.setEnabled(true, for: "sample")
        manager.setEnabled(true, for: "sample")
        #expect(manager.isEnabled("sample") && starts == 1 && stops == 0)
        #expect(!manager.isEnabled("other") && otherStarts == 0)
        let reloaded = PluginManager(plugins: [plugin, other], defaults: defaults)
        #expect(reloaded.isEnabled("sample") && starts == 2)
        defaults.set("retained user data", forKey: "sample.document")
        reloaded.setEnabled(false, for: "sample")
        reloaded.setEnabled(false, for: "sample")
        #expect(!reloaded.isEnabled("sample") && stops == 1)
        let disabled = PluginManager(plugins: [plugin, other], defaults: defaults)
        #expect(!disabled.isEnabled("sample") && starts == 2)
        disabled.setEnabled(true, for: "unknown")
        #expect(!disabled.isEnabled("unknown") && defaults.object(forKey: "plugins.unknown.enabled") == nil)
        #expect(defaults.string(forKey: "sample.document") == "retained user data")
        #expect(PluginManager(plugins: [], defaults: defaults).plugins.isEmpty)
    }
}
