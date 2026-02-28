import SwiftUI

enum AppScreen: Hashable {
    case scriptInput
    case recording
}

@Observable
final class AppState {
    var currentScreen: AppScreen = .scriptInput
    var scriptText: String = ""
    var scriptLines: [String] = []

    func prepareScript() {
        scriptLines = scriptText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func navigateTo(_ screen: AppScreen) {
        withAnimation(.spring(duration: 0.6, bounce: 0.15)) {
            currentScreen = screen
        }
    }
}
