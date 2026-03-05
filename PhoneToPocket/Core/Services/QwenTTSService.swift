import Foundation
import AVFoundation

@Observable
final class QwenTTSService: NSObject, URLSessionWebSocketDelegate {
    var isSpeaking = false

    @ObservationIgnored private var webSocketTask: URLSessionWebSocketTask?
    @ObservationIgnored private var urlSession: URLSession?
    @ObservationIgnored private var audioPlayerService: AudioPlayerService?
    @ObservationIgnored private var isConnected = false
    @ObservationIgnored private var isSessionReady = false
    @ObservationIgnored private var pendingTexts: [String] = []
    @ObservationIgnored private var pendingCommit = false
    @ObservationIgnored private var eventCounter = 0
    @ObservationIgnored private var connectionGeneration = 0

    var selectedVoice: String = "Cherry"

    private let baseURL = "wss://dashscope.aliyuncs.com/api-ws/v1/realtime"
    private let model = "qwen3-tts-flash-realtime"

    // MARK: - Session-Based API

    @MainActor
    func startSession() async {
        stop()
        isSpeaking = true

        let player = AudioPlayerService()
        player.onAllBuffersPlayed = { [weak self] in
            guard let self else { return }
            self.isSpeaking = false
        }
        audioPlayerService = player

        do {
            try await connect()
        } catch {
            print("[TTS] session start failed: \(error)")
            isSpeaking = false
        }
    }

    func feed(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, isSpeaking else { return }

        if isSessionReady {
            sendAppendText(cleaned)
        } else {
            pendingTexts.append(cleaned)
        }
    }

    func finishSession() {
        guard isSpeaking else { return }
        if isSessionReady {
            sendCommit()
        } else {
            pendingCommit = true
        }
    }

    func stop() {
        isSpeaking = false
        isSessionReady = false
        pendingTexts.removeAll()
        pendingCommit = false
        audioPlayerService?.stop()
        audioPlayerService = nil
        disconnect()
    }

    // MARK: - Convenience API

    func speak(text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await startSession()
        feed(text)
        finishSession()
        await waitUntilDone()
    }

    func speakStreaming(textStream: AsyncStream<String>) async {
        await startSession()

        var buffer = ""
        let delimiters: Set<Character> = ["。", "！", "？", "，", "；", "、", "\n",
                                           ".", "!", "?", ",", ";"]

        for await chunk in textStream {
            guard isSpeaking else { break }
            buffer += chunk

            if let last = buffer.last, delimiters.contains(last), buffer.count >= 2 {
                feed(buffer)
                buffer = ""
            }
        }

        if !buffer.isEmpty, isSpeaking {
            feed(buffer)
        }

        if isSpeaking {
            finishSession()
        }
    }

    func waitUntilDone() async {
        while isSpeaking {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // MARK: - WebSocket Connection

    private func connect() async throws {
        guard var components = URLComponents(string: baseURL) else { return }
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        guard let url = components.url else { return }

        connectionGeneration += 1

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        urlSession = session

        var request = URLRequest(url: url)
        request.setValue("Bearer \(APIKeys.dashScope)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
        isConnected = true

        startReceiving(generation: connectionGeneration)
    }

    private func disconnect() {
        connectionGeneration += 1
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        isSessionReady = false
        eventCounter = 0
    }

    // MARK: - Send Events

    private func sendSessionUpdate() {
        let event: [String: Any] = [
            "type": "session.update",
            "event_id": nextEventId(),
            "session": [
                "voice": selectedVoice,
                "response_format": "pcm",
                "mode": "server_commit",
            ],
        ]
        sendJSON(event)
    }

    private func sendAppendText(_ text: String) {
        let event: [String: Any] = [
            "type": "input_text_buffer.append",
            "event_id": nextEventId(),
            "text": text,
        ]
        sendJSON(event)
    }

    private func sendCommit() {
        let event: [String: Any] = [
            "type": "input_text_buffer.commit",
            "event_id": nextEventId(),
        ]
        sendJSON(event)
    }

    private func sendJSON(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let string = String(data: data, encoding: .utf8)
        else { return }

        webSocketTask?.send(.string(string)) { error in
            if let error {
                print("[TTS] send error: \(error)")
            }
        }
    }

    private func nextEventId() -> String {
        eventCounter += 1
        return "evt_\(eventCounter)"
    }

    // MARK: - Receive Events

    private func startReceiving(generation: Int) {
        webSocketTask?.receive { [weak self] result in
            guard let self, generation == self.connectionGeneration else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    Task { @MainActor in
                        guard generation == self.connectionGeneration else { return }
                        self.handleServerEvent(text)
                    }
                case .data:
                    break
                @unknown default:
                    break
                }
                self.startReceiving(generation: generation)

            case .failure(let error):
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    return
                }
                print("[TTS] receive error: \(error)")
                Task { @MainActor in
                    guard generation == self.connectionGeneration else { return }
                    self.isSpeaking = false
                }
            }
        }
    }

    private func handleServerEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        switch type {
        case "session.created":
            sendSessionUpdate()

        case "session.updated":
            isSessionReady = true
            flushPendingTexts()

        case "response.audio.delta":
            if let delta = json["delta"] as? String,
               let audioData = Data(base64Encoded: delta) {
                audioPlayerService?.enqueue(pcmData: audioData)
            }

        case "session.finished", "response.done":
            disconnect()
            audioPlayerService?.markSessionFinished()

        case "error":
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                print("[TTS] server error: \(message)")
            }
            isSpeaking = false
            disconnect()

        default:
            break
        }
    }

    private func flushPendingTexts() {
        let texts = pendingTexts
        let shouldCommit = pendingCommit
        pendingTexts.removeAll()
        pendingCommit = false

        for text in texts {
            sendAppendText(text)
        }

        if shouldCommit {
            sendCommit()
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask task: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {}

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask task: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            guard task == self.webSocketTask else { return }
            self.isConnected = false
            self.isSessionReady = false
        }
    }
}
