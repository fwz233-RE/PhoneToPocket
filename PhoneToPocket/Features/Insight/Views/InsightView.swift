import SwiftUI

struct InsightView: View {
    @State private var metaGlassesService = MetaGlassesService()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "即将上线",
                systemImage: "hand.tap",
                description: Text("AI 驱动的智能视频剪辑与内容输出")
            )
            .navigationTitle("灼见")
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
    }
}
