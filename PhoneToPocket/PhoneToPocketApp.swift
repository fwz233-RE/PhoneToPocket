import SwiftUI

@main
struct PhoneToPocketApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.black.ignoresSafeArea()

                Group {
                    switch appState.currentScreen {
                    case .scriptInput:
                        ScriptInputView()
                            .transition(.move(edge: .leading).combined(with: .opacity))

                    case .recording:
                        RecordingView()
                            .transition(.blurReplace(.downUp).combined(with: .opacity))
                    }
                }
            }
            .environment(appState)
            .preferredColorScheme(.dark)
        }
    }
}
