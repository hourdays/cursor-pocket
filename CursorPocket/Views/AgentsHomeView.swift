import SwiftUI

struct AgentsHomeView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showingNewChat = false

    var body: some View {
        List {
            if appModel.settings.chatOnlyMode {
                Section {
                    Label("Chat-only mode — no GitHub repo attached", systemImage: "text.bubble")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(appModel.agents) { agent in
                    NavigationLink {
                        ChatView(
                            session: ChatSessionModel(
                                agentId: agent.id,
                                agentName: agent.name,
                                latestRunId: agent.latestRunId,
                                appModel: appModel
                            )
                        )
                    } label: {
                        AgentRow(agent: agent)
                    }
                }

                if appModel.agents.isEmpty && !appModel.isLoadingAgents {
                    ContentUnavailableView(
                        "No agents yet",
                        systemImage: "tray",
                        description: Text("Start a new chat to launch your first cloud agent.")
                    )
                }
            } header: {
                Text("Recent agents")
            }
        }
        .overlay {
            if appModel.isLoadingAgents && appModel.agents.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle("Cursor Pocket")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewChat = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New chat")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await appModel.reloadAgents() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(appModel.isLoadingAgents)
            }
        }
        .refreshable {
            await appModel.reloadAgents()
        }
        .sheet(isPresented: $showingNewChat) {
            NavigationStack {
                NewChatView()
            }
        }
        .alert("Error", isPresented: Binding(
            get: { appModel.errorMessage != nil },
            set: { if !$0 { appModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appModel.errorMessage ?? "")
        }
    }
}

private struct AgentRow: View {
    let agent: AgentSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(agent.name)
                .font(.headline)
                .lineLimit(2)
            HStack {
                Text(agent.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let updated = agent.updatedAt {
                    Text(updated, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
