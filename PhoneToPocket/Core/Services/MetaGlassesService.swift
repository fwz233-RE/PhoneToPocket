import Foundation
import SwiftUI

#if os(iOS)
import UIKit
import MWDATCore
import MWDATCamera
#endif

enum MetaConnectionState: String {
    case disconnected = "未连接"
    case scanning = "扫描中"
    case connecting = "连接中"
    case connected = "已连接"
    case streaming = "视频流传输中"
}

enum MetaStreamQuality: String, CaseIterable, Identifiable {
    case low = "低画质"
    case medium = "中画质"
    case high = "高画质"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: return "低 360×640"
        case .medium: return "中 504×896"
        case .high: return "高 720×1280"
        }
    }

    #if os(iOS)
    var resolution: StreamingResolution {
        switch self {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }
    #endif
}

@Observable
final class MetaGlassesService {
    var connectionState: MetaConnectionState = .disconnected
    var lastCapturedFrame: Data?
    #if os(iOS)
    var currentFrameImage: UIImage?
    #endif
    var errorMessage: String?

    var streamQuality: MetaStreamQuality {
        didSet {
            AppSettings.shared.metaStreamQuality = streamQuality.rawValue
            if connectionState == .streaming {
                updateStreamQuality()
            }
        }
    }

    #if os(iOS)
    @ObservationIgnored private var wearables: WearablesInterface?
    @ObservationIgnored private var streamSession: StreamSession?
    @ObservationIgnored private var deviceSelector: AutoDeviceSelector?
    @ObservationIgnored private var stateToken: AnyListenerToken?
    @ObservationIgnored private var videoFrameToken: AnyListenerToken?
    @ObservationIgnored private var photoToken: AnyListenerToken?
    @ObservationIgnored private var errorToken: AnyListenerToken?
    @ObservationIgnored private var deviceMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var registrationTask: Task<Void, Never>?
    @ObservationIgnored private var keepAliveTask: Task<Void, Never>?
    @ObservationIgnored private var photoContinuation: CheckedContinuation<Data?, Never>?
    @ObservationIgnored private var isInitialized = false
    #endif

    init() {
        let savedQuality = AppSettings.shared.metaStreamQuality
        streamQuality = MetaStreamQuality(rawValue: savedQuality) ?? .medium
    }

    func ensureSDKReady() {
        #if os(iOS)
        guard !isInitialized else {
            syncRegistrationState()
            return
        }
        let w = Wearables.shared
        wearables = w
        isInitialized = true

        if w.registrationState == .registered {
            monitorDevices()
        }

        monitorRegistrationState()
        print("[MetaGlasses] SDK service initialized, registrationState: \(w.registrationState)")
        #endif
    }

    func handleURL(_ url: URL) {
        #if os(iOS)
        ensureSDKReady()
        guard let wearables else { return }

        Task {
            do {
                let handled = try await wearables.handleUrl(url)
                if handled {
                    await MainActor.run {
                        self.syncRegistrationState()
                    }
                }
            } catch {
                print("[MetaGlasses] handleUrl failed: \(error)")
                await MainActor.run {
                    self.errorMessage = "配对回调处理失败: \(error.localizedDescription)"
                }
            }
        }
        #endif
    }

    private func syncRegistrationState() {
        #if os(iOS)
        guard let wearables else { return }
        let state = wearables.registrationState
        switch state {
        case .registered:
            if connectionState != .connected && connectionState != .streaming {
                errorMessage = nil
                monitorDevices()
            }
        case .registering:
            connectionState = .connecting
        case .unavailable, .available:
            break
        @unknown default:
            break
        }
        #endif
    }

    func startRegistration() {
        #if os(iOS)
        ensureSDKReady()
        guard let wearables else {
            errorMessage = "Meta SDK 不可用，请确认已安装 Meta AI 应用"
            return
        }

        let sdkState = wearables.registrationState
        if sdkState == .registered {
            errorMessage = nil
            monitorDevices()
            return
        }
        if sdkState == .registering {
            connectionState = .connecting
            return
        }

        connectionState = .scanning
        errorMessage = nil

        Task {
            do {
                try await wearables.startRegistration()
                await MainActor.run {
                    self.syncRegistrationState()
                }
            } catch {
                print("[MetaGlasses] registration error: \(error)")
                await MainActor.run {
                    if let regError = error as? RegistrationError {
                        switch regError {
                        case .alreadyRegistered:
                            self.errorMessage = nil
                            self.monitorDevices()
                            return
                        case .configurationInvalid:
                            self.errorMessage = "MWDAT 配置无效，请确认眼镜已开启 Developer Mode 并重新安装应用"
                        case .metaAINotInstalled:
                            self.errorMessage = "请先安装 Meta AI 应用"
                        case .networkUnavailable:
                            self.errorMessage = "网络不可用，请检查网络连接"
                        default:
                            self.errorMessage = "注册失败: \(regError.description)"
                        }
                    } else {
                        self.errorMessage = "注册失败: \(error.localizedDescription)"
                    }
                    self.connectionState = .disconnected
                }
            }
        }
        #endif
    }

    func disconnect() {
        stopVideoStream()
        #if os(iOS)
        guard let wearables else { return }
        Task {
            do {
                try await wearables.startUnregistration()
            } catch {
                print("[MetaGlasses] unregistration failed: \(error)")
            }
        }
        registrationTask?.cancel()
        registrationTask = nil
        deviceMonitorTask?.cancel()
        deviceMonitorTask = nil
        keepAliveTask?.cancel()
        keepAliveTask = nil
        #endif
        connectionState = .disconnected
    }

    // MARK: - Video Stream

    func startVideoStream() {
        ensureSDKReady()
        guard connectionState == .connected || connectionState == .streaming else { return }
        #if os(iOS)
        guard let wearables else { return }

        let selector = AutoDeviceSelector(wearables: wearables)
        deviceSelector = selector

        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: streamQuality.resolution,
            frameRate: 24
        )
        let session = StreamSession(streamSessionConfig: config, deviceSelector: selector)
        streamSession = session

        setupSessionListeners(session)

        Task {
            do {
                let status = try await wearables.checkPermissionStatus(.camera)
                if status != .granted {
                    _ = try await wearables.requestPermission(.camera)
                }
                await session.start()
            } catch {
                print("[MetaGlasses] stream start failed: \(error)")
                await MainActor.run { self.connectionState = .connected }
            }
        }
        #endif
    }

    func stopVideoStream() {
        #if os(iOS)
        if let session = streamSession {
            Task { await session.stop() }
        }
        teardownSessionListeners()
        streamSession = nil
        deviceSelector = nil
        #endif
        if connectionState == .streaming {
            connectionState = .connected
        }
    }

    func captureCurrentFrame() -> Data? {
        return lastCapturedFrame
    }

    func capturePhoto() async -> Data? {
        #if os(iOS)
        guard let session = streamSession else { return lastCapturedFrame }
        return await withCheckedContinuation { c in
            self.photoContinuation = c
            session.capturePhoto(format: .jpeg)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, let cont = self.photoContinuation else { return }
                self.photoContinuation = nil
                cont.resume(returning: self.lastCapturedFrame)
            }
        }
        #else
        return lastCapturedFrame
        #endif
    }

    func captureHighQualityPhoto() async -> Data? {
        #if os(iOS)
        ensureSDKReady()
        guard isConnected else { return nil }

        if connectionState == .streaming, streamSession != nil {
            return await capturePhoto()
        }

        guard let wearables else { return nil }

        do {
            let status = try await wearables.checkPermissionStatus(.camera)
            if status != .granted {
                _ = try await wearables.requestPermission(.camera)
            }
        } catch {
            print("[MetaGlasses] camera permission failed: \(error)")
            return nil
        }

        let savedSession = streamSession
        let savedSelector = deviceSelector

        let selector = AutoDeviceSelector(wearables: wearables)
        deviceSelector = selector

        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .high,
            frameRate: 30
        )
        let session = StreamSession(streamSessionConfig: config, deviceSelector: selector)
        streamSession = session
        setupSessionListeners(session)
        await session.start()

        for _ in 0..<150 {
            if connectionState == .streaming { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        guard connectionState == .streaming else {
            teardownSessionListeners()
            await session.stop()
            streamSession = savedSession
            deviceSelector = savedSelector
            connectionState = .connected
            return nil
        }

        try? await Task.sleep(nanoseconds: 500_000_000)

        let data = await capturePhoto()

        teardownSessionListeners()
        await session.stop()
        streamSession = savedSession
        deviceSelector = savedSelector
        if savedSession == nil {
            connectionState = .connected
        }
        lastCapturedFrame = nil
        currentFrameImage = nil

        return data
        #else
        return nil
        #endif
    }

    var isConnected: Bool {
        connectionState == .connected || connectionState == .streaming
    }

    // MARK: - Private

    #if os(iOS)
    private func updateStreamQuality() {
        guard let wearables, streamSession != nil else { return }

        Task {
            if let session = streamSession {
                await session.stop()
            }
            teardownSessionListeners()

            let selector = AutoDeviceSelector(wearables: wearables)
            deviceSelector = selector

            let config = StreamSessionConfig(
                videoCodec: .raw,
                resolution: streamQuality.resolution,
                frameRate: 24
            )
            let session = StreamSession(streamSessionConfig: config, deviceSelector: selector)
            streamSession = session
            setupSessionListeners(session)
            await session.start()
        }
    }

    private func setupSessionListeners(_ session: StreamSession) {
        stateToken = session.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleSessionState(state)
            }
        }

        videoFrameToken = session.videoFramePublisher.listen { [weak self] frame in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let image = frame.makeUIImage() {
                    self.currentFrameImage = image
                    if let data = image.jpegData(compressionQuality: 0.8) {
                        self.lastCapturedFrame = data
                    }
                }
            }
        }

        photoToken = session.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor [weak self] in
                self?.photoContinuation?.resume(returning: photoData.data)
                self?.photoContinuation = nil
            }
        }

        errorToken = session.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                print("[MetaGlasses] stream error: \(error)")
                self?.connectionState = .connected
            }
        }
    }

    private func teardownSessionListeners() {
        stateToken = nil
        videoFrameToken = nil
        photoToken = nil
        errorToken = nil
    }

    private func monitorRegistrationState() {
        guard let wearables else { return }
        registrationTask = Task {
            for await state in wearables.registrationStateStream() {
                await MainActor.run {
                    switch state {
                    case .registered:
                        self.errorMessage = nil
                    case .registering:
                        self.connectionState = .connecting
                    case .unavailable, .available:
                        break
                    @unknown default:
                        break
                    }
                }
                if state == .registered {
                    monitorDevices()
                }
            }
        }
    }

    private func monitorDevices() {
        guard let wearables else { return }
        deviceMonitorTask?.cancel()
        deviceMonitorTask = Task {
            for await devices in wearables.devicesStream() {
                await MainActor.run {
                if !devices.isEmpty {
                    if self.connectionState != .streaming {
                        self.connectionState = .connected
                    }
                } else {
                    if self.connectionState == .connected {
                        self.connectionState = .disconnected
                        print("[MetaGlasses] no devices found, set disconnected")
                    }
                }
                }
            }
        }
        startKeepAlive()
    }

    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func handleSessionState(_ state: StreamSessionState) {
        switch state {
        case .streaming:
            connectionState = .streaming
        case .stopped:
            if connectionState == .streaming {
                connectionState = .connected
            }
            lastCapturedFrame = nil
            currentFrameImage = nil
        case .waitingForDevice, .starting, .stopping, .paused:
            break
        @unknown default:
            break
        }
    }
    #endif
}
