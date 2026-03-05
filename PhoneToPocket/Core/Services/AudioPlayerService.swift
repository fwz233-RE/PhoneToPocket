import AVFoundation
import Accelerate

final class AudioPlayerService {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let sampleRate: Double = 24000
    private let playbackFormat: AVAudioFormat
    private let processingQueue = DispatchQueue(label: "audio.player.processing", qos: .userInteractive)
    private var isEngineRunning = false

    private let countLock = NSLock()
    nonisolated(unsafe) private var pendingBufferCount = 0
    nonisolated(unsafe) private var sessionFinished = false

    var onAllBuffersPlayed: (() -> Void)?

    init() {
        playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
    }

    func enqueue(pcmData: Data) {
        if audioEngine == nil { setupEngine() }
        guard let playerNode, isEngineRunning else { return }

        processingQueue.async { [weak self] in
            guard let self,
                  let buffer = self.convertPCM16ToFloat32(pcmData) else { return }

            self.incrementCount()

            playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.handleBufferCompleted()
            }
            if !playerNode.isPlaying { playerNode.play() }
        }
    }

    func markSessionFinished() {
        countLock.lock()
        sessionFinished = true
        let remaining = pendingBufferCount
        countLock.unlock()

        if remaining == 0 {
            DispatchQueue.main.async { [weak self] in
                self?.onAllBuffersPlayed?()
            }
        }
    }

    func stop() {
        countLock.lock()
        pendingBufferCount = 0
        sessionFinished = false
        countLock.unlock()
        onAllBuffersPlayed = nil

        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        isEngineRunning = false
    }

    // MARK: - Buffer Tracking

    private func incrementCount() {
        countLock.lock()
        pendingBufferCount += 1
        countLock.unlock()
    }

    nonisolated private func handleBufferCompleted() {
        countLock.lock()
        pendingBufferCount = max(0, pendingBufferCount - 1)
        let remaining = pendingBufferCount
        let done = sessionFinished
        countLock.unlock()

        if done && remaining == 0 {
            DispatchQueue.main.async { [weak self] in
                self?.onAllBuffersPlayed?()
            }
        }
    }

    // MARK: - Engine Lifecycle

    private func setupEngine() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[AudioPlayer] audio session config failed: \(error)")
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

        do {
            try engine.start()
            player.play()
            audioEngine = engine
            playerNode = player
            isEngineRunning = true
        } catch {
            print("[AudioPlayer] engine start failed: \(error)")
        }
    }

    // MARK: - PCM Conversion

    private func convertPCM16ToFloat32(_ data: Data) -> AVAudioPCMBuffer? {
        let frameCount = data.count / MemoryLayout<Int16>.size
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(frameCount)),
              let channelData = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        data.withUnsafeBytes { raw in
            guard let src = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            let dst = channelData[0]
            vDSP_vflt16(src, 1, dst, 1, vDSP_Length(frameCount))
            var divisor: Float = 32768.0
            vDSP_vsdiv(dst, 1, &divisor, dst, 1, vDSP_Length(frameCount))
        }

        return buffer
    }
}
