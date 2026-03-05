import SwiftUI

struct ChatInputBar: View {
    @Bindable var viewModel: ChatViewModel
    @FocusState private var isFocused: Bool
    @State private var showModeMenu = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .center, spacing: 10) {
                modeButton

                inputField

                if viewModel.chatMode == .text {
                    sendButton
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.2), value: viewModel.chatMode)
        }
        .background {
            Color(UIColor.secondarySystemBackground)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Mode Button

    @ViewBuilder
    private var modeButton: some View {
        Menu {
            ForEach(ChatMode.allCases) { mode in
                Button {
                    viewModel.switchMode(mode)
                } label: {
                    Label(mode.rawValue, systemImage: mode.icon)
                }
            }
        } label: {
            Image(systemName: viewModel.chatMode.icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.1), in: Circle())
        }
        .disabled(viewModel.isProcessing)
    }

    // MARK: - Input Field

    @ViewBuilder
    private var inputField: some View {
        Group {
            if viewModel.chatMode == .text {
                TextField("输入消息...", text: $viewModel.inputText, axis: .vertical)
                    .focused($isFocused)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .disabled(viewModel.isProcessing)
            } else {
                Text(displayText)
                    .foregroundStyle(displayText == placeholderText ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1...3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 20))
    }

    private var displayText: String {
        if viewModel.speechService.isListening, !viewModel.speechService.recognizedText.isEmpty {
            return viewModel.speechService.recognizedText
        }
        if viewModel.isStreaming, viewModel.speechService.isListening {
            return "随时可语音打断..."
        }
        if viewModel.isProcessing { return "正在思考回复中..." }
        return placeholderText
    }

    private var placeholderText: String {
        switch viewModel.chatMode {
        case .visual: return "视觉聊天 · 等待语音..."
        case .voice: return "语音聊天 · 等待语音..."
        case .text: return "输入消息..."
        }
    }

    // MARK: - Send Button

    @ViewBuilder
    private var sendButton: some View {
        Button {
            viewModel.sendMessage()
            isFocused = false
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(canSend ? .blue : .gray)
        }
        .disabled(!canSend)
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isProcessing
    }
}
