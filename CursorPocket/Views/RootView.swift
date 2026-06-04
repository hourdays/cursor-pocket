import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Group {
            if appModel.hasAPIKey {
                MainTabView()
            } else {
                APIKeyOnboardingView()
            }
        }
        .task(id: appModel.hasAPIKey) {
            if appModel.hasAPIKey {
                await appModel.refreshAccountLabel()
                await appModel.reloadAgents()
            }
        }
    }
}
