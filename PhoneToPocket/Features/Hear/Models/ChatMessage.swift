import Foundation
import SwiftData

@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var role: String
    var content: String
    var toolCallId: String?
    var toolCallName: String?
    var toolCallArguments: String?
    var toolCallsJSON: String?
    var reasoningContent: String?
    var imageDescription: String?
    var timestamp: Date
    var conversation: Conversation?

    init(
        role: String,
        content: String,
        toolCallId: String? = nil,
        toolCallName: String? = nil,
        toolCallArguments: String? = nil,
        toolCallsJSON: String? = nil,
        reasoningContent: String? = nil,
        imageDescription: String? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.toolCallId = toolCallId
        self.toolCallName = toolCallName
        self.toolCallArguments = toolCallArguments
        self.toolCallsJSON = toolCallsJSON
        self.reasoningContent = reasoningContent
        self.imageDescription = imageDescription
        self.timestamp = Date()
    }

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
    var isTool: Bool { role == "tool" }
    var isToolCall: Bool { (toolCallsJSON != nil || toolCallName != nil) && role == "assistant" }
}
