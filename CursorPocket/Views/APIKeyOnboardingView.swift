import SwiftUI

struct APIKeyOnboardingView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var apiKey = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Cursor Pocket connects to the official Cloud Agents API using your personal Cursor API key. Usage is billed to your Cursor subscription.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("API key") {
                    SecureField("cur_…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Link("Create a key in Cursor Dashboard", destination: URL(string: "https://cursor.com/dashboard")!)
                }

                if let error = appModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Save and continue")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .navigationTitle("Cursor Pocket")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await appModel.saveAPIKey(apiKey)
        } catch {
            appModel.errorMessage = error.localizedDescription
        }
    }
}
