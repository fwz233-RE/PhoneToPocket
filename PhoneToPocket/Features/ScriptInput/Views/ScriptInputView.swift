import SwiftUI

struct ScriptInputView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var isEditorFocused: Bool
    @State private var animateIn = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header.padding(.top, 12)
                scriptEditor.padding(.top, 20)

                if !appState.scriptText.isEmpty {
                    statsRow.padding(.top, 8)
                }

                Spacer()
                startButton.padding(.bottom, 40)
            }
        }
        .onTapGesture { isEditorFocused = false }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { animateIn = true }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PhoneToPocket")
                    .font(.title2.bold()).foregroundStyle(.white)
                Text("视频文案")
                    .font(.caption).foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Editor

    @ViewBuilder
    private var scriptEditor: some View {
        @Bindable var state = appState

        ZStack(alignment: .topLeading) {
            TextEditor(text: $state.scriptText)
                .scrollContentBackground(.hidden)
                .font(.body).foregroundStyle(.white)
                .focused($isEditorFocused)
                .padding(16)

            if appState.scriptText.isEmpty {
                Text("在此输入视频文案…\n\n每行对应提词器一行\n留空则不使用提词器")
                    .font(.body).foregroundStyle(.white.opacity(0.25))
                    .padding(.horizontal, 21).padding(.vertical, 24)
                    .allowsHitTesting(false)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 20)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 20)
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
            .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Start Button

    @ViewBuilder
    private var startButton: some View {
        Button {
            isEditorFocused = false
            appState.prepareScript()
            appState.navigateTo(.recording)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "video.fill").font(.body)
                Text("开始拍摄").font(.headline)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(Capsule().fill(.white))
        }
        .padding(.horizontal, 40)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 30)
    }
}
