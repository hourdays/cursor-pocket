import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var apiKeyDraft = ""
    @State private var showingReplaceKey = false

    var body: some View {
        Form {
            Section("Account") {
                if let label = appModel.accountLabel {
                    LabeledContent("Signed in", value: label)
                }
                Button("Replace API key") {
                    showingReplaceKey = true
                }
                Button("Sign out", role: .destructive) {
                    try? appModel.signOut()
                }
            }

            Section {
                Toggle("Chat-only mode (no GitHub repo)", isOn: $appModel.settings.chatOnlyMode)
                Text("Use this for Q&A and planning. Turn off when you want the agent to edit code in a repository.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !appModel.settings.chatOnlyMode {
                Section("Repository") {
                    TextField("https://github.com/org/repo", text: $appModel.settings.repositoryURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField("Branch", text: $appModel.settings.startingBranch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            Section("About") {
                LabeledContent("API", value: "api.cursor.com/v1")
                Link("Cloud Agents documentation", destination: URL(string: "https://cursor.com/docs/cloud-agent/api/endpoints")!)
                Link("Open cursor.com/agents", destination: URL(string: "https://cursor.com/agents")!)
            }

            Section {
                Text("Cursor Pocket is an unofficial community client. Not affiliated with Cursor or Anysphere.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .onChange(of: appModel.settings) { _, _ in
            appModel.saveSettings()
        }
        .sheet(isPresented: $showingReplaceKey) {
            NavigationStack {
                Form {
                    SecureField("New API key", text: $apiKeyDraft)
                    Button("Save") {
                        Task {
                            try? await appModel.saveAPIKey(apiKeyDraft)
                            apiKeyDraft = ""
                            showingReplaceKey = false
                        }
                    }
                }
                .navigationTitle("API key")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingReplaceKey = false }
                    }
                }
            }
        }
    }
}
