import SwiftUI

enum AppTab: Hashable {
    case hear
    case see
    case insight
}

@Observable
final class AppState {
    var selectedTab: AppTab = .see
    var scriptText: String = ""
    var scriptLines: [String] = []
    var showSettings: Bool = false

    func prepareScript() {
        scriptLines = scriptText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func navigateToSeeWithScript(_ script: String) {
        scriptText = script
        selectedTab = .see
    }

    var pendingURL: URL?

    func handleIncomingURL(_ url: URL) {
        pendingURL = url
    }
}
