import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SettingsViewModel

    init(metaGlassesService: MetaGlassesService) {
        _viewModel = State(initialValue: SettingsViewModel(metaGlassesService: metaGlassesService))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Meta 智能眼镜") {
                    NavigationLink {
                        MetaGlassesSettingsView(metaService: viewModel.metaGlassesService)
                    } label: {
                        HStack {
                            Label("眼镜配对", systemImage: "eyeglasses")
                            Spacer()
                            Text(viewModel.metaGlassesService.connectionState.rawValue)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("语音") {
                    NavigationLink {
                        TTSVoiceSettingsView(settings: viewModel.settings)
                    } label: {
                        HStack {
                            Label("TTS 音色", systemImage: "speaker.wave.3.fill")
                            Spacer()
                            let voice = AppSettings.voiceOptions.first { $0.id == viewModel.settings.ttsVoice }
                            Text(voice?.name ?? viewModel.settings.ttsVoice)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("AI") {
                    NavigationLink {
                        PromptSettingsView(settings: viewModel.settings)
                    } label: {
                        Label("系统 Prompt", systemImage: "text.bubble")
                    }
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
