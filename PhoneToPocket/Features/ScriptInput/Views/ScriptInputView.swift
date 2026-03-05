import SwiftUI

struct ScriptInputView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var isEditorFocused: Bool

    var onStartRecording: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            scriptEditor
                .padding(.top, 8)

            if !appState.scriptText.isEmpty {
                statsRow
                    .padding(.top, 8)
            }

            Spacer()

            startButton
                .padding(.bottom, 20)
        }
        .onTapGesture { isEditorFocused = false }
    }

    // MARK: - Editor

    @ViewBuilder
    private var scriptEditor: some View {
        @Bindable var state = appState

        ZStack(alignment: .topLeading) {
            TextEditor(text: $state.scriptText)
                .scrollContentBackground(.hidden)
                .font(.body)
                .foregroundStyle(.primary)
                .focused($isEditorFocused)
                .padding(16)

            if appState.scriptText.isEmpty {
                Text("在此输入视频文案…\n\n每行对应提词器一行\n留空则不使用提词器")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 21)
                    .padding(.vertical, 24)
                    .allowsHitTesting(false)
            }
        }
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Stats

    @ViewBuilder
    private var statsRow: some View {
        let text = appState.scriptText
        let charCount = text.count
        let lineCount = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let totalSec = Int(Double(charCount) / 4.0)
        let m = totalSec / 60, s = totalSec % 60

        HStack {
            Spacer()
            HStack(spacing: 6) {
                Text("\(charCount) 字 · \(lineCount) 行")
                Text("·")
                Image(systemName: "clock").font(.caption2)
                Text("≈ \(m > 0 ? "\(m)分" : "")\(s)秒")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Start Button

    @ViewBuilder
    private var startButton: some View {
        Button {
            isEditorFocused = false
            onStartRecording()
        } label: {
            Label("开始拍摄", systemImage: "video.fill")
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 20)
    }
}
