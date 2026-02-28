import SwiftUI
import AVFoundation

@Observable
final class RecordingViewModel {

    let cameraService = CameraService()
    let speechService = SpeechRecognitionService()
    let fuzzyMatchService = FuzzyMatchService()

    var selectedAspectRatio: AspectRatio = .portrait3x4
    var isCenterStageOn = false
    var microphoneMode: MicrophoneMode = .standard
    var selectedFrameRate: FrameRate = .fps60
    var recordingFinished = false
    var lastRecordedURL: URL?
    var isConfigured = false
    var showError = false
    var errorText = ""

    var scriptLines: [String] = []

    var currentLine: Int { fuzzyMatchService.currentLineIndex }
    var currentCharInLine: Int { fuzzyMatchService.currentCharInLine }

    var isCenterStageAvailable: Bool { selectedAspectRatio != .fullGate }

    // MARK: - Setup

    func setup(lines: [String]) async {
        scriptLines = lines
        if !lines.isEmpty { fuzzyMatchService.configure(lines: lines) }

        let granted = await cameraService.requestPermissions()
        guard granted else {
            errorText = "需要摄像头权限才能拍摄"
            showError = true
            return
        }
        _ = await speechService.requestAuthorization()

        do {
            try await cameraService.configureSession()
            cameraService.startSession()
            isConfigured = true
            refreshSystemEffects()
            applyCameraSettings()
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
    }

    func refreshSystemEffects() {
        isCenterStageOn = cameraService.isCenterStageActive
    }

    // MARK: - Recording

    func startRecording() {
        do { try cameraService.startRecording() }
        catch {
            errorText = error.localizedDescription
            showError = true
            return
        }
        if !scriptLines.isEmpty {
            do { try speechService.startListening() } catch {}
        }
    }

    func stopRecording() async {
        speechService.stopListening()
        guard let url = await cameraService.stopRecording() else { return }
        lastRecordedURL = url
        do { try await cameraService.saveToPhotoLibrary(url: url) } catch {}
        recordingFinished = true
    }

    // MARK: - Speech & Line Navigation

    func updateSpeechMatch() {
        let text = speechService.recognizedText
        guard !text.isEmpty else { return }
        fuzzyMatchService.updateWithRecognizedText(text)
    }

    func advanceLine() {
        fuzzyMatchService.jumpToLine(currentLine + 1)
    }

    func retreatLine() {
        fuzzyMatchService.jumpToLine(currentLine - 1)
    }

    // MARK: - Settings

    func applyCameraSettings() {
        cameraService.applyCameraSettings(ratio: selectedAspectRatio, fps: selectedFrameRate)
        if selectedAspectRatio == .fullGate, isCenterStageOn {
            cameraService.toggleCenterStage()
            isCenterStageOn = false
        }
    }

    func changeFrameRate(_ fps: FrameRate) {
        selectedFrameRate = fps
        applyCameraSettings()
    }

    func toggleCenterStage() {
        guard isCenterStageAvailable else { return }
        cameraService.toggleCenterStage()
        isCenterStageOn = cameraService.isCenterStageActive
    }

    // MARK: - Lifecycle

    func cleanup() {
        cameraService.stopSession()
        speechService.stopListening()
    }

    func resetForNextRecording() {
        recordingFinished = false
        fuzzyMatchService.reset()
        speechService.recognizedText = ""
    }

    func openSystemPhotos() {
        #if os(iOS)
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    var formattedDuration: String {
        let total = Int(cameraService.recordingDuration)
        let m = total / 60, s = total % 60
        let t = Int((cameraService.recordingDuration - Double(total)) * 10)
        return String(format: "%02d:%02d.%d", m, s, t)
    }
}
