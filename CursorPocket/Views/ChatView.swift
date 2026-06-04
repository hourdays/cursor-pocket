import SwiftUI

struct ChatView: View {
    @StateObject private var session: ChatSessionModel

    init(session: ChatSessionModel) {
        _session = StateObject(wrappedValue: session)
    }

    var body: some View {
        ChatScreen(session: session, title: session.agentName, isNewAgent: false)
    }
}

struct ChatScreen: View {
    @ObservedObject var session: ChatSessionModel
    let title: String
    let isNewAgent: Bool

    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(session.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: session.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: session.messages.last?.text) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            if let status = session.runStatus, session.isSending {
                Text(status.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            if let error = session.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1 ... 6)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)

                if session.isSending {
                    Button {
                        Task { await session.cancelCurrentRun() }
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                    }
                } else {
                    Button {
                        Task { await sendMessage() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = agentURL {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .onAppear {
            if isNewAgent {
                isInputFocused = true
            }
        }
    }

    private var agentURL: URL? {
        guard !session.agentId.isEmpty else { return nil }
        return URL(string: "https://cursor.com/agents/\(session.agentId)")
    }

    private func sendMessage() async {
        let text = draft
        draft = ""
        await session.send(text, isNewAgent: isNewAgent)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = session.messages.last?.id {
            withAnimation {
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
    }
}
