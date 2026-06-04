import SwiftUI

struct NewChatView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NewChatSessionView(appModel: appModel) {
            dismiss()
        }
    }
}

private struct NewChatSessionView: View {
    @StateObject private var session: ChatSessionModel
    let onDismiss: () -> Void

    init(appModel: AppModel, onDismiss: @escaping () -> Void) {
        _session = StateObject(wrappedValue: ChatSessionModel(
            agentId: "",
            agentName: "New chat",
            latestRunId: nil,
            appModel: appModel
        ))
        self.onDismiss = onDismiss
    }

    var body: some View {
        ChatScreen(session: session, title: "New chat", isNewAgent: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onDismiss()
                    }
                }
            }
    }
}
