import SwiftUI
import SwiftData

@Observable
final class ConversationListViewModel {
    @ObservationIgnored var modelContext: ModelContext?

    func deleteConversation(_ conversation: Conversation) {
        modelContext?.delete(conversation)
        try? modelContext?.save()
    }
}
