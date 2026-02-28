import Speech
import AVFoundation

@Observable
final class SpeechRecognitionService {

    var recognizedText: String = ""
    var isListening = false
    var error: String?

    @ObservationIgnored private var speechRecognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var audioEngine: AVAudioEngine?

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

    /// Uses AVAudioEngine to tap the microphone independently of the camera pipeline.
    func startListening() throws {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            error = "语音识别不可用"
            return
        }

        stopListening()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let busFormat = inputNode.outputFormat(forBus: 0)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = false

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: busFormat) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        recognitionRequest = request
        isListening = true
        error = nil

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, err in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.recognizedText = result.bestTranscription.formattedString
                }
            }
            if let err {
                Task { @MainActor in
                    self.error = err.localizedDescription
                    self.isListening = false
                }
            }
            if result?.isFinal == true {
                Task { @MainActor in self.isListening = false }
            }
        }
    }

    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
    }
}
