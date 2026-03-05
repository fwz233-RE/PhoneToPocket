import Speech
import AVFoundation

@Observable
final class SpeechRecognitionService {

    var recognizedText: String = ""
    var isListening = false
    var error: String?

    var onSilenceDetected: (() -> Void)?

    @ObservationIgnored private var speechRecognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var silenceTimer: Timer?
    @ObservationIgnored private var lastTextChangeTime: Date = Date()
    @ObservationIgnored private var retryCount = 0
    @ObservationIgnored private var sessionGeneration: Int = 0

    var silenceTimeout: TimeInterval = 1.5

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { status in
                c.resume(returning: status == .authorized)
            }
        }
    }

    func startListening() throws {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            error = "语音识别不可用"
            return
        }

        if isListening { return }

        stopInternal()
        recognizedText = ""

        activateAudioSession()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let busFormat = inputNode.outputFormat(forBus: 0)

        guard busFormat.sampleRate > 0 else {
            print("[Speech] invalid bus format, retrying...")
            scheduleRetry()
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = false

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: busFormat) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()

        sessionGeneration += 1
        let currentGeneration = sessionGeneration

        audioEngine = engine
        recognitionRequest = request
        isListening = true
        error = nil
        retryCount = 0
        lastTextChangeTime = Date()

        startSilenceDetection()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, err in
            guard let self else { return }

            if let result {
                let newText = result.bestTranscription.formattedString
                Task { @MainActor in
                    guard currentGeneration == self.sessionGeneration else { return }
                    if newText != self.recognizedText {
                        self.recognizedText = newText
                        self.lastTextChangeTime = Date()
                    }
                }
            }

            if let err {
                let nsErr = err as NSError
                let isNormalCancel = nsErr.domain == "kAFAssistantErrorDomain" && nsErr.code == 216
                Task { @MainActor in
                    guard currentGeneration == self.sessionGeneration else { return }
                    if !isNormalCancel {
                        self.error = err.localizedDescription
                    }
                    self.stopSilenceDetection()
                    self.isListening = false
                }
            }

            if result?.isFinal == true {
                Task { @MainActor in
                    guard currentGeneration == self.sessionGeneration else { return }
                    self.stopSilenceDetection()
                    self.isListening = false
                }
            }
        }
    }

    func restartListening() {
        stopInternal()
        recognizedText = ""
        retryCount = 0
        try? startListening()
    }

    func stopListening() {
        stopInternal()
    }

    func ensureListening() {
        guard !isListening else { return }
        retryCount = 0
        try? startListening()
    }

    private func stopInternal() {
        stopSilenceDetection()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        isListening = false
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[Speech] audio session activation failed: \(error)")
        }
    }

    private func scheduleRetry() {
        guard retryCount < 3 else {
            print("[Speech] max retries reached")
            return
        }
        retryCount += 1
        let delay = Double(retryCount) * 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isListening else { return }
            try? self.startListening()
        }
    }

    // MARK: - Silence Detection

    private func startSilenceDetection() {
        stopSilenceDetection()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self, self.isListening else { return }
            let elapsed = Date().timeIntervalSince(self.lastTextChangeTime)
            if elapsed >= self.silenceTimeout, !self.recognizedText.isEmpty {
                self.stopSilenceDetection()
                self.onSilenceDetected?()
            }
        }
    }

    private func stopSilenceDetection() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
}
