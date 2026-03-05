import Foundation
import SwiftData

@Model
final class Conversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage] = []

    init(title: String = "新对话") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var sortedMessages: [ChatMessage] {
        messages.sorted { $0.timestamp < $1.timestamp }
    }

    var displayMessages: [ChatMessage] {
        sortedMessages.filter { msg in
            msg.role != "system" && msg.role != "tool" && !msg.isToolCall
        }
    }

    var roundCount: Int {
        let userCount = messages.filter { $0.role == "user" }.count
        let assistantCount = messages.filter { $0.role == "assistant" && !$0.isToolCall }.count
        return min(userCount, assistantCount)
    }

    var preview: String {
        if let first = sortedMessages.first(where: { $0.role == "user" }) {
            return String(first.content.prefix(50))
        }
        return "空对话"
    }
}
