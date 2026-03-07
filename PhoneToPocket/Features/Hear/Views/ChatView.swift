import SwiftUI
import SwiftData
import UIKit

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            videoStreamBackground
            messagesList
        }
        .navigationTitle(viewModel.conversation?.title ?? "新对话")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.modelContext = modelContext
            viewModel.toolCallService.modelContext = modelContext
            if viewModel.chatMode.usesVoiceInput {
                viewModel.startVoiceInputDeferred()
            }
        }
        .onDisappear {
            viewModel.stopAll()
        }
        .alert("错误", isPresented: $viewModel.showError) {
            Button("确定") {}
        } message: {
            Text(viewModel.errorText)
        }
    }

    // MARK: - Messages List

    @ViewBuilder
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    if let conv = viewModel.conversation {
                        ForEach(conv.displayMessages) { message in
                            ChatMessageBubble(message: message)
                                .id(message.id)
                        }
                    }

                    if viewModel.isStreaming {
                        if !viewModel.reasoningText.isEmpty {
                            reasoningBubble
                                .id("reasoning")
                        }
                        if !viewModel.streamingText.isEmpty {
                            streamingBubble
                                .id("streaming")
                        }
                    }

                    if let conv = viewModel.conversation, conv.roundCount >= 1 {
                        VideoScriptView(viewModel: viewModel)
                            .id("video-script")
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                ChatInputBar(viewModel: viewModel)
            }
            .onChange(of: viewModel.streamingText) {
                withAnimation {
                    if !viewModel.streamingText.isEmpty {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    } else if !viewModel.reasoningText.isEmpty {
                        proxy.scrollTo("reasoning", anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.reasoningText) {
                if viewModel.streamingText.isEmpty {
                    withAnimation {
                        proxy.scrollTo("reasoning", anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.conversation?.messages.count) {
                if let last = viewModel.conversation?.displayMessages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Reasoning Bubble

    @ViewBuilder
    private var reasoningBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Label("思考中...", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(viewModel.reasoningText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 150)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer(minLength: 60)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    // MARK: - Streaming Bubble

    @ViewBuilder
    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.streamingText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("回复中...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 60)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    // MARK: - Video Stream Background

    @ViewBuilder
    private var videoStreamBackground: some View {
        if viewModel.chatMode == .visual,
           let frameData = viewModel.metaGlassesService.lastCapturedFrame,
           let uiImage = UIImage(data: frameData) {
            GeometryReader { geometry in
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            .overlay(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.6)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}
