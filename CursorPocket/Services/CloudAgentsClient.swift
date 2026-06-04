import Foundation

enum CloudAgentsError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case httpStatus(Int, String)
    case decoding(String)
    case agentBusy
    case streamExpired

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Cursor API key in Settings."
        case .invalidURL:
            return "Invalid API URL."
        case .httpStatus(let code, let body):
            return "API error \(code): \(body)"
        case .decoding(let detail):
            return "Unexpected API response: \(detail)"
        case .agentBusy:
            return "This agent already has a run in progress. Wait for it to finish."
        case .streamExpired:
            return "The live stream expired. Open the agent again to load the final reply."
        }
    }
}

struct StreamEvent {
    enum Kind {
        case status(String)
        case assistantDelta(String)
        case result(text: String?, status: String)
        case done
        case error(String)
    }

    let kind: Kind
}

final class CloudAgentsClient {
    static let shared = CloudAgentsClient()

    private let baseURL = URL(string: "https://api.cursor.com/v1")!
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        return decoder
    }()

    private init() {}

    func validateAPIKey(_ apiKey: String) async throws -> APIKeyInfo {
        try await request(path: "/me", apiKey: apiKey, method: "GET")
    }

    func listAgents(apiKey: String, limit: Int = 50) async throws -> [AgentSummary] {
        let response: AgentsListResponse = try await request(
            path: "/agents?limit=\(limit)",
            apiKey: apiKey,
            method: "GET"
        )
        return response.items
    }

    func getAgent(id: String, apiKey: String) async throws -> AgentDetail {
        try await request(path: "/agents/\(id)", apiKey: apiKey, method: "GET")
    }

    func createAgent(
        apiKey: String,
        prompt: String,
        settings: AppSettings,
        name: String? = nil
    ) async throws -> CreateAgentResponse {
        var body: [String: Any] = [
            "prompt": ["text": prompt],
            "env": ["type": "cloud"]
        ]

        if let name, !name.isEmpty {
            body["name"] = name
        }

        if !settings.chatOnlyMode,
           !settings.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let repoURL = settings.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let branch = settings.startingBranch.trimmingCharacters(in: .whitespacesAndNewlines)
            var repo: [String: Any] = ["url": repoURL]
            if !branch.isEmpty {
                repo["startingRef"] = branch
            }
            body["repos"] = [repo]
            body.removeValue(forKey: "env")
        }

        return try await request(
            path: "/agents",
            apiKey: apiKey,
            method: "POST",
            jsonBody: body
        )
    }

    func createRun(agentId: String, apiKey: String, prompt: String) async throws -> CreateRunResponse {
        let body: [String: Any] = [
            "prompt": ["text": prompt]
        ]
        return try await request(
            path: "/agents/\(agentId)/runs",
            apiKey: apiKey,
            method: "POST",
            jsonBody: body
        )
    }

    func getRun(agentId: String, runId: String, apiKey: String) async throws -> AgentRun {
        try await request(
            path: "/agents/\(agentId)/runs/\(runId)",
            apiKey: apiKey,
            method: "GET"
        )
    }

    func cancelRun(agentId: String, runId: String, apiKey: String) async throws {
        let _: CancelRunResponse = try await request(
            path: "/agents/\(agentId)/runs/\(runId)/cancel",
            apiKey: apiKey,
            method: "POST"
        )
    }

    func streamRun(
        agentId: String,
        runId: String,
        apiKey: String,
        lastEventID: String? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var url = baseURL.appendingPathComponent("agents/\(agentId)/runs/\(runId)/stream")
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    if let lastEventID {
                        request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
                    }

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse {
                        if http.statusCode == 410 {
                            throw CloudAgentsError.streamExpired
                        }
                        guard (200 ... 299).contains(http.statusCode) else {
                            throw CloudAgentsError.httpStatus(http.statusCode, "Stream failed")
                        }
                    }

                    var currentEvent = ""
                    var dataLines: [String] = []

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        if line.isEmpty {
                            if !currentEvent.isEmpty || !dataLines.isEmpty {
                                if let event = parseSSE(event: currentEvent, dataLines: dataLines) {
                                    continuation.yield(event)
                                    if case .done = event.kind {
                                        continuation.finish()
                                        return
                                    }
                                    if case .error = event.kind {
                                        continuation.finish()
                                        return
                                    }
                                }
                            }
                            currentEvent = ""
                            dataLines = []
                            continue
                        }

                        if line.hasPrefix("event:") {
                            currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func parseSSE(event: String, dataLines: [String]) -> StreamEvent? {
        let payload = dataLines.joined(separator: "\n")
        guard let data = payload.data(using: .utf8) else { return nil }

        switch event {
        case "status":
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String {
                return StreamEvent(kind: .status(status))
            }
        case "assistant":
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                return StreamEvent(kind: .assistantDelta(text))
            }
        case "result":
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let status = json["status"] as? String ?? "FINISHED"
                let text = json["text"] as? String
                return StreamEvent(kind: .result(text: text, status: status))
            }
        case "done":
            return StreamEvent(kind: .done)
        case "error":
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                return StreamEvent(kind: .error(message))
            }
            return StreamEvent(kind: .error(payload))
        default:
            break
        }
        return nil
    }

    private func request<T: Decodable>(
        path: String,
        apiKey: String,
        method: String,
        jsonBody: [String: Any]? = nil
    ) async throws -> T {
        guard !apiKey.isEmpty else { throw CloudAgentsError.missingAPIKey }
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw CloudAgentsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudAgentsError.invalidURL
        }

        if http.statusCode == 409,
           let body = String(data: data, encoding: .utf8),
           body.contains("agent_busy") {
            throw CloudAgentsError.agentBusy
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CloudAgentsError.httpStatus(http.statusCode, body)
        }

        if data.isEmpty, T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CloudAgentsError.decoding(error.localizedDescription)
        }
    }
}

private struct EmptyResponse: Decodable {
    init() {}
}

private struct CancelRunResponse: Decodable {
    let id: String
}
