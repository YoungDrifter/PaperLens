import AppKit
import Combine
import Sparkle

/// Core app maintenance, independent of optional document plugins.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = AppUpdater()
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var startupError: String?
    @Published private(set) var latestVersion: String?
    @Published private(set) var latestBuild: String?
    private let defaults: UserDefaults
    private let versionDisplayer = UpdateVersionDisplayer()
    var latestVersionLabel: String? {
        latestVersion.map { AppIdentity.versionLabel(version: $0, build: latestBuild) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        latestVersion = defaults.string(forKey: "updates.latestVerifiedVersion")
        latestBuild = defaults.string(forKey: "updates.latestVerifiedBuild")
        super.init()
    }

    func standardUserDriverRequestsVersionDisplayer() -> (any SUVersionDisplay)? { versionDisplayer }
    private var observation: AnyCancellable?
    private var started = false
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false,
        updaterDelegate: self, userDriverDelegate: self)

    func start() {
        guard !started else { return }
        // Hosted tests exercise their own isolated update state, without scheduling dialogs.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              NSClassFromString("XCTestCase") == nil else { return }
        do {
            try controller.updater.start()
            started = true
            // Automatic checks are mandatory; migrate any old opt-out preference.
            if !controller.updater.automaticallyChecksForUpdates {
                controller.updater.automaticallyChecksForUpdates = true
            }
            if controller.updater.updateCheckInterval != 86400 {
                controller.updater.updateCheckInterval = 86400
            }
            let lastCheck = controller.updater.lastUpdateCheckDate
            if lastCheck == nil || Date().timeIntervalSince(lastCheck!) >= 86400 {
                controller.updater.checkForUpdatesInBackground()
            } else if latestVersion == nil || latestBuild == nil {
                // Bootstrap the display once after upgrading from a build without this cache.
                controller.updater.checkForUpdateInformation()
            }
            observation = controller.updater.publisher(for: \.canCheckForUpdates)
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.canCheckForUpdates = $0 }
        } catch {
            startupError = "Restart to enable updates."
        }
    }

    func checkForUpdates() {
        start()
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        // The core update policy shows new releases as soon as the daily check finds them.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                  forUpdate update: SUAppcastItem,
                                                  state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        // Focus the existing verified update; this does not make another network check.
        controller.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        // This callback receives the signed feed after Sparkle verifies it.
        guard let latest = appcast.items.max(by: {
            $0.versionString.compare($1.versionString, options: .numeric) == .orderedAscending
        }) else { return }
        latestVersion = latest.displayVersionString
        latestBuild = latest.versionString
        defaults.set(latest.displayVersionString, forKey: "updates.latestVerifiedVersion")
        defaults.set(latest.versionString, forKey: "updates.latestVerifiedBuild")
    }
}

/// Changes display text only; Sparkle still compares and verifies the original versions.
final class UpdateVersionDisplayer: NSObject, SUVersionDisplay {
    func formatUpdateVersion(fromUpdate update: SUAppcastItem,
                                    andBundleDisplayVersion version: AutoreleasingUnsafeMutablePointer<NSString>,
                                    withBundleVersion build: String) -> String {
        version.pointee = AppIdentity.versionLabel(version: version.pointee as String, build: build) as NSString
        return AppIdentity.versionLabel(version: update.displayVersionString, build: update.versionString)
    }

    func formatBundleDisplayVersion(_ version: String, withBundleVersion build: String,
                                    matchingUpdate: SUAppcastItem?) -> String {
        AppIdentity.versionLabel(version: version, build: build)
    }
}
