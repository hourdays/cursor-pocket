import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var apiKey: String?
    @Published private(set) var accountLabel: String?
    @Published var settings: AppSettings = AppSettingsStore.load()
    @Published var agents: [AgentSummary] = []
    @Published var isLoadingAgents = false
    @Published var errorMessage: String?

    private let client = CloudAgentsClient.shared

    init() {
        apiKey = KeychainService.loadAPIKey()
    }

    var hasAPIKey: Bool {
        guard let apiKey else { return false }
        return !apiKey.isEmpty
    }

    func refreshAccountLabel() async {
        guard let apiKey else {
            accountLabel = nil
            return
        }
        do {
            let info = try await client.validateAPIKey(apiKey)
            if let email = info.userEmail {
                accountLabel = email
            } else if let name = info.apiKeyName {
                accountLabel = name
            } else {
                accountLabel = "Connected"
            }
        } catch {
            accountLabel = nil
        }
    }

    func saveAPIKey(_ key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try await client.validateAPIKey(trimmed)
        try KeychainService.saveAPIKey(trimmed)
        apiKey = trimmed
        errorMessage = nil
        await refreshAccountLabel()
        await reloadAgents()
    }

    func signOut() throws {
        try KeychainService.deleteAPIKey()
        apiKey = nil
        accountLabel = nil
        agents = []
    }

    func saveSettings() {
        AppSettingsStore.save(settings)
    }

    func reloadAgents() async {
        guard let apiKey else { return }
        isLoadingAgents = true
        defer { isLoadingAgents = false }

        do {
            agents = try await client.listAgents(apiKey: apiKey)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createAgent(prompt: String) async throws -> CreateAgentResponse {
        guard let apiKey else { throw CloudAgentsError.missingAPIKey }
        let response = try await client.createAgent(
            apiKey: apiKey,
            prompt: prompt,
            settings: settings
        )
        await reloadAgents()
        return response
    }

    func sendFollowUp(agentId: String, prompt: String) async throws -> AgentRun {
        guard let apiKey else { throw CloudAgentsError.missingAPIKey }
        let response = try await client.createRun(agentId: agentId, apiKey: apiKey, prompt: prompt)
        return response.run
    }
}
