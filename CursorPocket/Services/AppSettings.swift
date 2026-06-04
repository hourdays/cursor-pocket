import Foundation

struct AppSettings: Equatable {
    var repositoryURL: String
    var startingBranch: String
    var chatOnlyMode: Bool

    static let `default` = AppSettings(
        repositoryURL: "",
        startingBranch: "main",
        chatOnlyMode: true
    )
}

enum AppSettingsStore {
    private enum Keys {
        static let repositoryURL = "repositoryURL"
        static let startingBranch = "startingBranch"
        static let chatOnlyMode = "chatOnlyMode"
    }

    static func load() -> AppSettings {
        let defaults = UserDefaults.standard
        return AppSettings(
            repositoryURL: defaults.string(forKey: Keys.repositoryURL) ?? "",
            startingBranch: defaults.string(forKey: Keys.startingBranch) ?? "main",
            chatOnlyMode: defaults.object(forKey: Keys.chatOnlyMode) as? Bool ?? true
        )
    }

    static func save(_ settings: AppSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.repositoryURL, forKey: Keys.repositoryURL)
        defaults.set(settings.startingBranch, forKey: Keys.startingBranch)
        defaults.set(settings.chatOnlyMode, forKey: Keys.chatOnlyMode)
    }
}
