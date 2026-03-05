import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        TabView(selection: $state.selectedTab) {
            Tab("听见", systemImage: "ear.fill", value: .hear) {
                HearView()
            }

            Tab("看见", systemImage: "eye.fill", value: .see) {
                SeeTabView()
            }

            Tab("灼见", systemImage: "wand.and.stars", value: .insight) {
                InsightView()
            }
        }
    }
}
