import SwiftUI
import SwiftData
import AVFoundation

@Observable
final class ChatViewModel {
    var conversation: Conversation?
    var streamingText: String = ""
    var reasoningText: String = ""
    var isStreaming = false
    var chatMode: ChatMode = .text
    var inputText: String = ""
    var showError = false
    var errorText = ""
    var generatedScript: String?
    var scriptReasoningText: String = ""
    var isGeneratingScript = false
    var scriptGenerated = false

    var isProcessing: Bool { isStreaming || isGeneratingScript }

    let deepSeekService = DeepSeekService()
    let ttsService = QwenTTSService()
    let speechService = SpeechRecognitionService()
    let metaGlassesService: MetaGlassesService
    let toolCallService: ToolCallService

    @ObservationIgnored var modelContext: ModelContext?
    @ObservationIgnored private var currentStreamTask: Task<Void, Never>?
    @ObservationIgnored private var scriptTask: Task<Void, Never>?
    @ObservationIgnored private var speechMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var isExecutingTools = false
    @ObservationIgnored private var lastCapturePhotoResult: String?
    @ObservationIgnored private var stopGeneration = 0

    init(metaGlassesService: MetaGlassesService) {
        self.metaGlassesService = metaGlassesService
        self.toolCallService = ToolCallService(metaGlassesService: metaGlassesService)

        speechService.onSilenceDetected = { [weak self] in
            Task { @MainActor in
                self?.onSilenceDetected()
            }
        }
    }

    // MARK: - Conversation Management

    func createNewConversation() {
        let conv = Conversation()
        modelContext?.insert(conv)
        try? modelContext?.save()
        conversation = conv
        streamingText = ""
        reasoningText = ""
        generatedScript = nil
        scriptReasoningText = ""
        scriptGenerated = false
    }

    func loadConversation(_ conv: Conversation) {
        conversation = conv
        streamingText = ""
        reasoningText = ""
        generatedScript = nil
        scriptReasoningText = ""
        scriptGenerated = false
    }

    // MARK: - Send Message

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if isStreaming {
            interruptCurrentStream()
        }

        guard !isGeneratingScript else { return }

        inputText = ""

        if ttsService.isSpeaking {
            ttsService.stop()
        }

        speechService.stopListening()

        currentStreamTask = Task {
            var imageDesc: String?
            if chatMode.usesMetaVideoStream {
                imageDesc = await captureAndDescribeFrame()
            }

            toolCallService.lastFrameDescription = imageDesc
            addUserMessage(text, imageDescription: imageDesc)
            await performChat()
        }
    }

    func onSilenceDetected() {
        guard chatMode.usesVoiceInput,
              !speechService.recognizedText.isEmpty
        else { return }

        if isExecutingTools { return }

        let text = speechService.recognizedText
        speechService.stopListening()
        inputText = text

        if isStreaming {
            interruptCurrentStream()
        }

        sendMessage()
    }

    // MARK: - Interruption

    private func interruptCurrentStream() {
        currentStreamTask?.cancel()
        currentStreamTask = nil
        ttsService.stop()
        isStreaming = false
        streamingText = ""
        reasoningText = ""
    }

    // MARK: - Core Chat Flow

    private func performChat() async {
        guard let conversation else { return }

        isStreaming = true
        streamingText = ""
        reasoningText = ""
        lastCapturePhotoResult = nil

        let settings = AppSettings.shared
        var systemPrompt = settings.systemPrompt
        if chatMode.usesTTS {
            systemPrompt += AppSettings.voicePromptSuffix
        }

        var messages = buildMessages(systemPrompt: systemPrompt)

        let tools = ToolCallService.tools
        toolCallService.modelContext = modelContext

        if chatMode.usesTTS {
            ttsService.selectedVoice = settings.ttsVoice
            await ttsService.startSession()
        }

        do {
            let maxIterations = 5
            var iteration = 0

            while iteration < maxIterations {
                guard !Task.isCancelled else { break }
                iteration += 1

                if iteration > 1, chatMode.usesTTS {
                    await ttsService.waitUntilDone()
                    guard !Task.isCancelled else { break }
                    ttsService.selectedVoice = settings.ttsVoice
                    await ttsService.startSession()
                }

                var fullResponse = ""
                var pendingToolCalls: [ToolCallDelta] = []
                var hasResumedListening = false
                var reasoningBuf = ""
                var lastReasoningFlush = Date.distantPast

                let stream = deepSeekService.streamChat(
                    messages: messages,
                    tools: tools
                )

                for try await delta in stream {
                    guard !Task.isCancelled else { break }

                    switch delta {
                    case .reasoning(let chunk):
                        reasoningBuf += chunk
                        let now = Date()
                        if now.timeIntervalSince(lastReasoningFlush) >= 0.08 {
                            reasoningText = reasoningBuf
                            lastReasoningFlush = now
                        }

                    case .text(let chunk):
                        fullResponse += chunk
                        streamingText = stripDSML(fullResponse)
                        if chatMode.usesTTS {
                            ttsService.feed(cleanForTTS(chunk))
                        }
                        if !hasResumedListening && chatMode.usesVoiceInput {
                            hasResumedListening = true
                            speechService.restartListening()
                        }

                    case .toolCall(let tc):
                        pendingToolCalls.append(tc)

                    case .done:
                        break
                    }
                }

                guard !Task.isCancelled else { break }

                reasoningText = reasoningBuf

                if !pendingToolCalls.isEmpty {
                    if chatMode.usesTTS {
                        ttsService.finishSession()
                    }

                    streamingText = ""
                    reasoningText = ""

                    let dsToolCalls = pendingToolCalls.map { $0.toDSToolCall() }
                    let toolCallsData = try? JSONEncoder().encode(dsToolCalls)
                    let toolCallsJSONStr = toolCallsData.flatMap { String(data: $0, encoding: .utf8) }

                    let assistantMsg = ChatMessage(
                        role: "assistant",
                        content: "",
                        toolCallName: pendingToolCalls.map(\.name).joined(separator: ","),
                        toolCallsJSON: toolCallsJSONStr
                    )
                    conversation.messages.append(assistantMsg)

                    messages.append(DSMessage(
                        role: "assistant",
                        content: fullResponse.isEmpty ? nil : fullResponse,
                        toolCalls: dsToolCalls
                    ))

                    isExecutingTools = true
                    for tc in pendingToolCalls {
                        let result = await toolCallService.execute(name: tc.name, arguments: tc.arguments)
                        if tc.name == "capture_photo" {
                            lastCapturePhotoResult = extractImageSummary(result)
                        }
                        let toolMsg = ChatMessage(role: "tool", content: result, toolCallId: tc.id, toolCallName: tc.name)
                        conversation.messages.append(toolMsg)
                        messages.append(DSMessage(role: "tool", content: result, toolCallId: tc.id, name: tc.name))
                    }
                    isExecutingTools = false

                    fullResponse = ""
                    continue
                }

                let cleaned = stripDSML(fullResponse)
                streamingText = ""
                reasoningText = ""

                if !cleaned.isEmpty {
                    let msg = ChatMessage(role: "assistant", content: cleaned, imageDescription: lastCapturePhotoResult)
                    lastCapturePhotoResult = nil
                    conversation.messages.append(msg)
                }
                break
            }

            if chatMode.usesTTS {
                ttsService.finishSession()
            }

            conversation.updatedAt = Date()
            if conversation.title == "新对话", let first = conversation.messages.first(where: { $0.isUser }) {
                conversation.title = String(first.content.prefix(20))
            }
            try? modelContext?.save()

        } catch {
            if !Task.isCancelled {
                errorText = error.localizedDescription
                showError = true
            }
            if chatMode.usesTTS {
                ttsService.stop()
            }
        }

        isStreaming = false

        if chatMode.usesVoiceInput, !Task.isCancelled, !speechService.isListening {
            speechService.restartListening()
        }
    }

    // MARK: - Speech Monitor

    func startSpeechMonitor() {
        speechMonitorTask?.cancel()
        speechMonitorTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if chatMode.usesVoiceInput
                    && !speechService.isListening
                    && !isExecutingTools {
                    speechService.ensureListening()
                }
            }
        }
    }

    func stopSpeechMonitor() {
        speechMonitorTask?.cancel()
        speechMonitorTask = nil
    }

    // MARK: - Visual Mode

    private func captureAndDescribeFrame() async -> String? {
        guard let frameData = metaGlassesService.captureCurrentFrame() else { return nil }
        do {
            return try await toolCallService.qwenVLService.analyzeImage(
                imageData: frameData,
                prompt: "请简洁描述这张图片中的内容"
            )
        } catch {
            return nil
        }
    }

    // MARK: - Video Script Generation

    func generateVideoScript() {
        guard let conversation, conversation.roundCount >= 1, !isProcessing else { return }

        speechService.stopListening()
        stopSpeechMonitor()

        scriptTask?.cancel()
        isGeneratingScript = true
        generatedScript = nil
        scriptReasoningText = ""

        scriptTask = Task {
            let chatHistory = conversation.sortedMessages.map { msg in
                "\(msg.role == "user" ? "用户" : "助手")：\(msg.content)"
            }.joined(separator: "\n")

            let prompt = """
                这是我的聊天记录
                \(chatHistory)

                我需要拍一个视频讲明白自己的优势
                你扮演一个顶级短视频博主的文案
                写一个精炼的视频文案,大约400字,如果你觉得400字说不明白可以稍微多点字
                注意文案不要出现ai味道,比如 不是...而是...这种句式
                注意是视频文案,要符合视频观众观看的习惯,节奏
                来写文案 要求文案一行一行的 不要有特殊符号,比如不要有1. 2. 3. 这样的文字
                直接给我文案就行,不要任何过多的内容
                """

            let messages = [DSMessage(role: "user", content: prompt)]

            do {
                var result = ""
                var reasoningBuf = ""
                var lastFlush = Date.distantPast
                let stream = deepSeekService.streamChat(messages: messages, model: "deepseek-reasoner")
                for try await delta in stream {
                    guard !Task.isCancelled else { break }
                    switch delta {
                    case .reasoning(let chunk):
                        reasoningBuf += chunk
                        let now = Date()
                        if now.timeIntervalSince(lastFlush) >= 0.2 {
                            scriptReasoningText = reasoningBuf
                            lastFlush = now
                        }
                    case .text(let chunk):
                        result += chunk
                        generatedScript = result
                    case .toolCall, .done:
                        break
                    }
                }
                if !Task.isCancelled {
                    scriptReasoningText = reasoningBuf
                }
            } catch {
                if !Task.isCancelled {
                    errorText = "文案生成失败：\(error.localizedDescription)"
                    showError = true
                }
            }

            isGeneratingScript = false
            if !Task.isCancelled {
                scriptGenerated = true
                if chatMode.usesVoiceInput {
                    startVoiceInputDeferred()
                }
            }
        }
    }

    // MARK: - Mode Management

    func switchMode(_ mode: ChatMode) {
        let oldMode = chatMode
        chatMode = mode
        toolCallService.chatMode = mode

        if !mode.usesVoiceInput && oldMode.usesVoiceInput {
            speechService.stopListening()
            stopSpeechMonitor()
        }

        if mode.usesMetaVideoStream && !oldMode.usesMetaVideoStream {
            metaGlassesService.startVideoStream()
        } else if !mode.usesMetaVideoStream && oldMode.usesMetaVideoStream {
            metaGlassesService.stopVideoStream()
        }

        if mode.usesVoiceInput {
            configureAudioSession()
            if !speechService.isListening {
                try? speechService.startListening()
            }
            startSpeechMonitor()
        }
    }

    func startVoiceInput() {
        guard chatMode.usesVoiceInput else { return }
        configureAudioSession()
        try? speechService.startListening()
        startSpeechMonitor()
        if chatMode.usesMetaVideoStream {
            metaGlassesService.startVideoStream()
        }
    }

    func startVoiceInputDeferred() {
        guard chatMode.usesVoiceInput else { return }
        let gen = stopGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, gen == self.stopGeneration, !self.speechService.isListening else { return }
            self.configureAudioSession()
            try? self.speechService.startListening()
            self.startSpeechMonitor()
            if self.chatMode.usesMetaVideoStream {
                self.metaGlassesService.startVideoStream()
            }
        }
    }

    func stopAll() {
        stopGeneration += 1
        currentStreamTask?.cancel()
        currentStreamTask = nil
        scriptTask?.cancel()
        scriptTask = nil
        isStreaming = false
        isGeneratingScript = false
        streamingText = ""
        reasoningText = ""
        stopSpeechMonitor()
        ttsService.stop()
        speechService.stopListening()
        metaGlassesService.stopVideoStream()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
            try session.setActive(true)
        } catch {
            print("[ChatVM] audio session config failed: \(error)")
        }
    }

    // MARK: - Helpers

    private func addUserMessage(_ text: String, imageDescription: String? = nil) {
        guard let conversation else { return }
        let msg = ChatMessage(role: "user", content: text, imageDescription: imageDescription)
        conversation.messages.append(msg)
        try? modelContext?.save()
    }

    private func buildMessages(systemPrompt: String) -> [DSMessage] {
        guard let conversation else { return [] }

        var msgs = [DSMessage(role: "system", content: systemPrompt)]

        for msg in conversation.sortedMessages {
            if msg.role == "tool" {
                msgs.append(DSMessage(role: "tool", content: msg.content, toolCallId: msg.toolCallId, name: msg.toolCallName))
            } else if msg.isToolCall {
                var toolCalls: [DSToolCall]?
                if let json = msg.toolCallsJSON,
                   let data = json.data(using: .utf8) {
                    toolCalls = try? JSONDecoder().decode([DSToolCall].self, from: data)
                }
                msgs.append(DSMessage(role: "assistant", content: nil, toolCalls: toolCalls))
            } else {
                var content = msg.content
                if msg.isUser {
                    if let desc = msg.imageDescription {
                        content = "（当前眼镜画面：\(desc)）\n\(content)"
                    }
                    content += AppSettings.forcePrompt
                }
                msgs.append(DSMessage(role: msg.role, content: content))
            }
        }

        return msgs
    }

    private func cleanForTTS(_ text: String) -> String {
        var result = text
        if result.contains("<| DSML") || result.contains("</| DSML") { return "" }
        let markdownChars: [Character] = ["*", "#", "`", ">", "|", "~", "_"]
        result = String(result.filter { !markdownChars.contains($0) })
        result = result.replacingOccurrences(of: "- ", with: "")
        return result
    }

    private func stripDSML(_ text: String) -> String {
        guard text.contains("DSML") else { return text }
        guard let startRange = text.range(of: "<|") else { return text }
        let before = String(text[text.startIndex..<startRange.lowerBound])
        if let endRange = text.range(of: "function_calls>", options: .backwards) {
            let after = String(text[endRange.upperBound...])
            return (before + after).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return before.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractImageSummary(_ result: String) -> String {
        let cleaned = result
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let desc = json["description"] as? String {
            return desc
        }

        let lines = cleaned.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("{") && !$0.hasPrefix("}") && !$0.hasPrefix("\"") }
        return lines.first ?? result
    }
}
