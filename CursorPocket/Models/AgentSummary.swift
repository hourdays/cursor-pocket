import Foundation

struct AgentSummary: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var status: String
    var url: String?
    var latestRunId: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, status, url, latestRunId, createdAt, updatedAt
    }
}

struct AgentsListResponse: Codable {
    let items: [AgentSummary]
    let nextCursor: String?
}

struct AgentDetail: Codable {
    let id: String
    var name: String
    var status: String
    var url: String?
    var latestRunId: String?
    var repos: [AgentRepo]?
    var env: AgentEnvironment?
}

struct AgentRepo: Codable, Hashable {
    let url: String
    var startingRef: String?
}

struct AgentEnvironment: Codable {
    let type: String
    var name: String?
}

struct CreateAgentResponse: Codable {
    let agent: AgentDetail
    let run: AgentRun
}

struct AgentRun: Codable, Identifiable, Hashable {
    let id: String
    let agentId: String
    var status: String
    var result: String?
    var durationMs: Int?
    var createdAt: Date?
    var updatedAt: Date?
}

struct CreateRunResponse: Codable {
    let run: AgentRun
}

struct RunsListResponse: Codable {
    let items: [AgentRun]
}

struct APIKeyInfo: Codable {
    let apiKeyName: String?
    let userEmail: String?
    let userFirstName: String?
    let userLastName: String?
}
