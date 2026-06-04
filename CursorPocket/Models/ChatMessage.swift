import Foundation

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Hashable {
    let id: UUID
    let role: ChatRole
    var text: String
    var isStreaming: Bool

    init(id: UUID = UUID(), role: ChatRole, text: String, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
    }
}
