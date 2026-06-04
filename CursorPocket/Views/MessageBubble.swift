import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.text.isEmpty && message.isStreaming ? "…" : message.text)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(backgroundColor)
                    .foregroundStyle(foregroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if message.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if message.role != .user { Spacer(minLength: 48) }
        }
    }

    private var backgroundColor: Color {
        message.role == .user ? Color.accentColor : Color(.secondarySystemBackground)
    }

    private var foregroundColor: Color {
        message.role == .user ? Color.white : Color.primary
    }
}
