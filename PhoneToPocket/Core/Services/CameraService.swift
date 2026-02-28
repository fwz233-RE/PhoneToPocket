import AVFoundation
import Photos

@Observable
final class CameraService: NSObject {

    // MARK: - UI State

    var isSessionRunning = false
    var isRecording = false
    var recordingDuration: TimeInterval = 0
    var errorMessage: String?

    // MARK: - Internal

    @ObservationIgnored nonisolated let captureSession = AVCaptureSession()
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "com.ptp.camera.session")
    @ObservationIgnored private var movieOutput: AVCaptureMovieFileOutput?
    @ObservationIgnored private var recordingTimer: Timer?
    @ObservationIgnored private var recordingStartTime: Date?
    @ObservationIgnored private var recordingContinuation: CheckedContinuation<URL?, Never>?

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let vStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let vOK: Bool = if vStatus == .notDetermined {
            await AVCaptureDevice.requestAccess(for: .video)
        } else { vStatus == .authorized }
        let aStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if aStatus == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .audio) }
        return vOK
    }

    // MARK: - Session

    func configureSession() async throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .videoRecording, options: [
            .defaultToSpeaker, .allowBluetoothHFP, .interruptSpokenAudioAndMixWithOthers,
        ])
        try audio.setActive(true, options: .notifyOthersOnDeactivation)

        let output = try await withCheckedThrowingContinuation {
            (c: CheckedContinuation<AVCaptureMovieFileOutput, Error>) in
            sessionQueue.async { [self] in
                do { c.resume(returning: try buildCaptureSession()) }
                catch { c.resume(throwing: error) }
            }
        }
        movieOutput = output
    }

    private nonisolated func buildCaptureSession() throws -> AVCaptureMovieFileOutput {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        else { throw CameraError.deviceNotFound }

        let vi = try AVCaptureDeviceInput(device: cam)
        guard captureSession.canAddInput(vi) else { throw CameraError.cannotAddInput }
        captureSession.addInput(vi)

        if let mic = AVCaptureDevice.default(for: .audio) {
            let ai = try AVCaptureDeviceInput(device: mic)
            if captureSession.canAddInput(ai) { captureSession.addInput(ai) }
        }

        let output = AVCaptureMovieFileOutput()
        guard captureSession.canAddOutput(output) else { throw CameraError.cannotAddOutput }
        captureSession.addOutput(output)

        captureSession.commitConfiguration()
        return output
    }

    func startSession() {
        sessionQueue.async { [captureSession] in
            guard !captureSession.isRunning else { return }
            captureSession.startRunning()
            Task { @MainActor in self.isSessionRunning = true }
        }
    }

    func stopSession() {
        sessionQueue.async { [captureSession] in
            guard captureSession.isRunning else { return }
            captureSession.stopRunning()
            Task { @MainActor in self.isSessionRunning = false }
        }
    }

    // MARK: - Unified Format + Frame Rate

    /// Finds the best camera format matching the requested aspect ratio and frame rate,
    /// then applies it. For fullGate, picks the largest resolution available.
    func applyCameraSettings(ratio: AspectRatio, fps: FrameRate) {
        sessionQueue.async { [captureSession] in
            guard let device = Self.frontDevice(from: captureSession) else { return }

            let targetFPS = Float64(fps.rawValue)
            let videoFormats = device.formats.filter {
                CMFormatDescriptionGetMediaType($0.formatDescription) == kCMMediaType_Video
            }

            let candidates: [AVCaptureDevice.Format]

            if ratio == .fullGate {
                candidates = videoFormats.filter { fmt in
                    fmt.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= targetFPS }
                }
            } else {
                let targetSensor = ratio.sensorRatio
                candidates = videoFormats.filter { fmt in
                    let dim = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
                    let r = CGFloat(dim.width) / CGFloat(dim.height)
                    let ratioOK = abs(r - targetSensor) < 0.15
                    let fpsOK = fmt.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= targetFPS }
                    return ratioOK && fpsOK
                }
            }

            guard let best = candidates.max(by: {
                let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
                return Int(a.width) * Int(a.height) < Int(b.width) * Int(b.height)
            }) else { return }

            captureSession.beginConfiguration()
            do {
                try device.lockForConfiguration()
                device.activeFormat = best
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
                device.unlockForConfiguration()
            } catch {}
            captureSession.commitConfiguration()
        }
    }

    /// Returns all frame rates supported by ANY video format of the front camera.
    func allSupportedFrameRates() -> [FrameRate] {
        guard let device = Self.frontDevice(from: captureSession) else { return [.fps30] }
        var found = Set<FrameRate>()
        for fmt in device.formats where CMFormatDescriptionGetMediaType(fmt.formatDescription) == kCMMediaType_Video {
            for range in fmt.videoSupportedFrameRateRanges {
                for fps in FrameRate.allCases where Float64(fps.rawValue) <= range.maxFrameRate {
                    found.insert(fps)
                }
            }
        }
        return FrameRate.allCases.filter { found.contains($0) }
    }

    // MARK: - Recording

    func startRecording() throws {
        guard let output = movieOutput else { throw CameraError.notConfigured }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd_HHmmss"
        let url = docs.appendingPathComponent("PTP_\(fmt.string(from: Date())).mov")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }

        output.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        recordingStartTime = Date()
        startTimer()
    }

    func stopRecording() async -> URL? {
        guard let output = movieOutput, output.isRecording else { return nil }
        return await withCheckedContinuation { c in
            recordingContinuation = c
            output.stopRecording()
        }
    }

    func saveToPhotoLibrary(url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    // MARK: - Camera Effects

    func toggleCenterStage() {
        AVCaptureDevice.centerStageControlMode = .cooperative
        AVCaptureDevice.isCenterStageEnabled.toggle()
    }
    var isCenterStageActive: Bool { AVCaptureDevice.isCenterStageEnabled }

    // MARK: - Helpers

    private nonisolated static func frontDevice(from session: AVCaptureSession) -> AVCaptureDevice? {
        session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
            .first { $0.device.hasMediaType(.video) }?.device
    }

    private func startTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let t = self.recordingStartTime else { return }
            self.recordingDuration = Date().timeIntervalSince(t)
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput, didFinishRecordingTo url: URL,
        from connections: [AVCaptureConnection], error: Error?
    ) {
        Task { @MainActor in
            self.isRecording = false
            self.recordingDuration = 0
            self.stopTimer()
            self.recordingContinuation?.resume(returning: error == nil ? url : nil)
            self.recordingContinuation = nil
        }
    }
}

enum CameraError: LocalizedError {
    case notAuthorized, deviceNotFound, cannotAddInput, cannotAddOutput, notConfigured
    var errorDescription: String? {
        switch self {
        case .notAuthorized:  "未获得摄像头使用权限"
        case .deviceNotFound: "未找到前置摄像头"
        case .cannotAddInput: "无法添加摄像头输入"
        case .cannotAddOutput:"无法添加视频输出"
        case .notConfigured:  "摄像头未配置"
        }
    }
}
