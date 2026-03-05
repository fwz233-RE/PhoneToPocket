import SwiftUI

struct SeeTabView: View {
    @Environment(AppState.self) private var appState
    @State private var showRecording = false
    @State private var showSettings = false
    @State private var metaGlassesService = MetaGlassesService()

    var body: some View {
        NavigationStack {
            ScriptInputView {
                appState.prepareScript()
                showRecording = true
            }
            .navigationTitle("看见")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(metaGlassesService: metaGlassesService)
            }
        }
        .fullScreenCover(isPresented: $showRecording) {
            RecordingView()
        }
    }
}
