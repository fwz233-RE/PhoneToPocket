import SwiftUI

struct TTSVoiceSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var previewingVoice: String?
    @State private var previewTask: Task<Void, Never>?

    private let standardVoices = Array(AppSettings.voiceOptions.prefix(7))
    private let dialectVoices = Array(AppSettings.voiceOptions.dropFirst(7))

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                voiceSection(title: "标准音色", voices: standardVoices)
                voiceSection(title: "方言音色", voices: dialectVoices)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("TTS 音色")
        .onDisappear {
            previewTask?.cancel()
            previewTask = nil
            previewingVoice = nil
        }
    }

    @ViewBuilder
    private func voiceSection(title: String, voices: [(id: String, name: String, desc: String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 8) {
                ForEach(voices, id: \.id) { voice in
                    voiceCard(voice)
                }
            }
        }
    }

    @ViewBuilder
    private func voiceCard(_ voice: (id: String, name: String, desc: String)) -> some View {
        let isSelected = settings.ttsVoice == voice.id
        let isPreviewing = previewingVoice == voice.id

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(voice.name)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .blue : .primary)

                Text(voice.desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                togglePreview(voice)
            } label: {
                Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(isPreviewing ? .white : .blue)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isPreviewing ? Color.red : Color.blue.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue.opacity(0.06) : Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.3) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            settings.ttsVoice = voice.id
        }
    }

    private func togglePreview(_ voice: (id: String, name: String, desc: String)) {
        if previewingVoice == voice.id {
            previewTask?.cancel()
            previewTask = nil
            previewingVoice = nil
            return
        }

        previewTask?.cancel()
        previewingVoice = voice.id

        previewTask = Task {
            let service = QwenTTSService()
            service.selectedVoice = voice.id
            await service.speak(text: "你好，我是\(voice.name)，很高兴为你服务。")
            if !Task.isCancelled, previewingVoice == voice.id {
                previewingVoice = nil
            }
        }
    }
}
