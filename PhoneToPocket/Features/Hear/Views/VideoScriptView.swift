import SwiftUI

struct VideoScriptView: View {
    @Bindable var viewModel: ChatViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            Divider()

            if viewModel.isGeneratingScript {
                generatingView
            } else if let script = viewModel.generatedScript {
                resultView(script: script)
            } else {
                generateButton
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 2)//---以后改
    }

    // MARK: - Generating State

    @ViewBuilder
    private var generatingView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("正在生成视频文案...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.scriptReasoningText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("思考过程", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(viewModel.scriptReasoningText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 180)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal, 16)
            }

            if let script = viewModel.generatedScript {
                Text(script)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Result State

    @ViewBuilder
    private func resultView(script: String) -> some View {
        ScrollView {
            Text(script)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)

        HStack(spacing: 12) {
            Button {
                viewModel.generateVideoScript()
            } label: {
                Label("再次生成", systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.quinary, in: Capsule())
            }
            .disabled(viewModel.isProcessing)

            Button {
                appState.navigateToSeeWithScript(script)
            } label: {
                Label("去拍摄", systemImage: "video.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.white, in: Capsule())
            }
        }
    }

    // MARK: - Initial State

    @ViewBuilder
    private var generateButton: some View {
        Button {
            viewModel.generateVideoScript()
        } label: {
            Label("生成视频文案", systemImage: "wand.and.stars")
                .font(.subheadline)
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.white, in: Capsule())
        }
        .disabled(viewModel.isProcessing)
    }
}
