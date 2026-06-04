import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                AgentsHomeView()
            }
            .tabItem {
                Label("Agents", systemImage: "bubble.left.and.bubble.right")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}
