import Foundation

@MainActor
final class ChatSessionModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isSending = false
    @Published var runStatus: String?
    @Published var errorMessage: String?

    var agentId: String
    var agentName: String
    var latestRunId: String?

    private let appModel: AppModel
    private let client = CloudAgentsClient.shared
    private var streamTask: Task<Void, Never>?

    init(agentId: String, agentName: String, latestRunId: String?, appModel: AppModel) {
        self.agentId = agentId
        self.agentName = agentName
        self.latestRunId = latestRunId
        self.appModel = appModel
    }

    deinit {
        streamTask?.cancel()
    }

    func send(_ text: String, isNewAgent: Bool) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        guard appModel.hasAPIKey else {
            errorMessage = CloudAgentsError.missingAPIKey.localizedDescription
            return
        }

        messages.append(ChatMessage(role: .user, text: trimmed))
        isSending = true
        errorMessage = nil
        runStatus = "CREATING"

        do {
            let run: AgentRun
            if isNewAgent {
                let response = try await appModel.createAgent(prompt: trimmed)
                agentId = response.agent.id
                agentName = response.agent.name
                run = response.run
            } else {
                run = try await appModel.sendFollowUp(agentId: agentId, prompt: trimmed)
            }

            latestRunId = run.id
            await consumeStream(runId: run.id)
        } catch {
            errorMessage = error.localizedDescription
            isSending = false
            runStatus = nil
        }
    }

    func cancelCurrentRun() async {
        guard let apiKey = appModel.apiKey,
              let runId = latestRunId else { return }
        streamTask?.cancel()
        do {
            try await client.cancelRun(agentId: agentId, runId: runId, apiKey: apiKey)
            runStatus = "CANCELLED"
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }

    private func consumeStream(runId: String) async {
        guard let apiKey = appModel.apiKey else { return }

        streamTask?.cancel()
        var assistantIndex: Int?

        streamTask = Task {
            do {
                let stream = client.streamRun(agentId: agentId, runId: runId, apiKey: apiKey)
                for try await event in stream {
                    if Task.isCancelled { break }

                    switch event.kind {
                    case .status(let status):
                        runStatus = status
                    case .assistantDelta(let delta):
                        if let index = assistantIndex {
                            messages[index].text += delta
                        } else {
                            let message = ChatMessage(role: .assistant, text: delta, isStreaming: true)
                            messages.append(message)
                            assistantIndex = messages.count - 1
                        }
                    case .result(let text, let status):
                        runStatus = status
                        if let text, !text.isEmpty {
                            if let index = assistantIndex {
                                messages[index].text = text
                                messages[index].isStreaming = false
                            } else {
                                messages.append(ChatMessage(role: .assistant, text: text))
                            }
                        } else if let index = assistantIndex {
                            messages[index].isStreaming = false
                        }
                    case .done:
                        if let index = assistantIndex {
                            messages[index].isStreaming = false
                        }
                        isSending = false
                    case .error(let message):
                        errorMessage = message
                        isSending = false
                    }
                }

                if isSending {
                    if let final = try? await client.getRun(agentId: agentId, runId: runId, apiKey: apiKey),
                       let result = final.result,
                       !result.isEmpty {
                        if let index = assistantIndex {
                            messages[index].text = result
                            messages[index].isStreaming = false
                        } else {
                            messages.append(ChatMessage(role: .assistant, text: result))
                        }
                    }
                    isSending = false
                }
            } catch CloudAgentsError.streamExpired {
                await loadFinalRun(runId: runId, assistantIndex: assistantIndex)
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    isSending = false
                }
            }
        }
    }

    private func loadFinalRun(runId: String, assistantIndex: Int?) async {
        guard let apiKey = appModel.apiKey else { return }
        do {
            let run = try await client.getRun(agentId: agentId, runId: runId, apiKey: apiKey)
            runStatus = run.status
            if let result = run.result, !result.isEmpty {
                if let index = assistantIndex {
                    messages[index].text = result
                    messages[index].isStreaming = false
                } else {
                    messages.append(ChatMessage(role: .assistant, text: result))
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}
