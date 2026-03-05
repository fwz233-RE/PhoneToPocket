import SwiftUI

struct PromptSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $settings.systemPrompt)
                .font(.system(.body, design: .monospaced))
                .padding()

            Divider()

            HStack {
                Button("恢复默认") {
                    settings.systemPrompt = AppSettings.defaultSystemPrompt
                }
                .foregroundStyle(.red)

                Spacer()

                Text("\(settings.systemPrompt.count) 字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("系统 Prompt")
    }
}
