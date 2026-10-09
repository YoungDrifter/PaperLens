import SwiftUI

struct GeneralSettingsTab: View {
    var body: some View {
        AboutSettingsPane(appName: AppIdentity.displayName, icon: AppIdentity.icon,
                          summary: "A focused PDF reader.")
    }
}
