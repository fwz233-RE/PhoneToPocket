import SwiftUI
import SwiftData

#if os(iOS)
import MWDATCore
#endif

@main
struct PhoneToPocketApp: App {
    @State private var appState = AppState()

    init() {
        #if os(iOS)
        do {
            try Wearables.configure()
        } catch {
            print("[App] Wearables SDK configure failed: \(error)")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    #if os(iOS)
                    Task {
                        do {
                            _ = try await Wearables.shared.handleUrl(url)
                        } catch {
                            print("[App] Wearables handleUrl failed: \(error)")
                        }
                    }
                    #endif
                    appState.handleIncomingURL(url)
                }
        }
        .modelContainer(for: [
            Conversation.self,
            ChatMessage.self,
            TodoItem.self,
        ])
    }
}
