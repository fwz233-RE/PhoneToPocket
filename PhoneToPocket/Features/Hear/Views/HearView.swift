import SwiftUI
import SwiftData
import AVFoundation
import UIKit

private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(shakes * .pi * 2) * 6, y: 0))
    }
}

struct HearView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var metaGlassesService = MetaGlassesService()
    @State private var chatViewModel: ChatViewModel?
    @State private var activeSheet: HearSheet?
    @State private var shakePhase: CGFloat = 0
    @State private var shakingId: UUID?

    enum HearSheet: Identifiable {
        case settings
        case history
        var id: Int {
            switch self {
            case .settings: return 0
            case .history: return 1
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let vm = chatViewModel {
                    ChatView(viewModel: vm)
                } else {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        activeSheet = .history
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            startNewConversation()
                        } label: {
                            Image(systemName: "plus.circle")
                        }

                        Button {
                            activeSheet = .settings
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .settings:
                    SettingsView(metaGlassesService: metaGlassesService)
                case .history:
                    historySheet
                }
            }
        }
        .task {
            metaGlassesService.ensureSDKReady()
            if chatViewModel == nil {
                configureAudioSession()
                await requestPermissions()
                startNewConversation()
            }
        }
        .onChange(of: appState.selectedTab) { _, newTab in
            if newTab == .hear {
                let targetMode: ChatMode = hasBluetoothAudioDevice() ? .voice : .text
                if let vm = chatViewModel, vm.chatMode != targetMode {
                    vm.switchMode(targetMode)
                }
                chatViewModel?.startVoiceInputDeferred()
            } else {
                chatViewModel?.stopAll()
            }
        }
        .onOpenURL { url in
            metaGlassesService.handleURL(url)
        }
        .onChange(of: appState.pendingURL) { _, url in
            guard let url else { return }
            metaGlassesService.handleURL(url)
            appState.pendingURL = nil
        }
    }

    // MARK: - History Sheet

    @ViewBuilder
    private var historySheet: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    ContentUnavailableView {
                        Label("暂无历史对话", systemImage: "bubble.left.and.bubble.right")
                    }
                } else {
                    List {
                        ForEach(conversations) { conv in
                            let isActive = chatViewModel?.conversation?.id == conv.id
                            historyRow(conv)
                                .modifier(ShakeEffect(shakes: shakingId == conv.id ? shakePhase : 0))
                                .swipeActions(edge: .trailing, allowsFullSwipe: !isActive) {
                                    if isActive {
                                        Button {
                                            rejectDeleteConversation(conv.id)
                                        } label: {
                                            Label("使用中", systemImage: "nosign")
                                        }
                                        .tint(.gray)
                                    } else {
                                        Button(role: .destructive) {
                                            deleteConversation(conv)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("历史对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { activeSheet = nil }
                }
            }
        }
    }

    @ViewBuilder
    private func historyRow(_ conv: Conversation) -> some View {
        let isActive = chatViewModel?.conversation?.id == conv.id

        Button {
            loadConversation(conv)
            activeSheet = nil
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conv.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(conv.updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(conv.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Image(systemName: "message")
                        .font(.caption2)
                    Text("\(conv.roundCount) 轮对话")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(
            isActive ? Color.blue.opacity(0.08) : Color.clear
        )
    }

    // MARK: - Actions

    private func startNewConversation() {
        chatViewModel?.stopAll()
        chatViewModel = nil
        let vm = ChatViewModel(metaGlassesService: metaGlassesService)
        vm.modelContext = modelContext
        vm.toolCallService.modelContext = modelContext
        vm.chatMode = hasBluetoothAudioDevice() ? .voice : .text
        if let latest = conversations.first, latest.messages.isEmpty {
            vm.loadConversation(latest)
        } else {
            vm.createNewConversation()
        }
        chatViewModel = vm
    }

    private func loadConversation(_ conv: Conversation) {
        chatViewModel?.stopAll()
        chatViewModel = nil
        let vm = ChatViewModel(metaGlassesService: metaGlassesService)
        vm.modelContext = modelContext
        vm.toolCallService.modelContext = modelContext
        vm.chatMode = hasBluetoothAudioDevice() ? .voice : .text
        vm.loadConversation(conv)
        chatViewModel = vm
    }

    private func deleteConversation(_ conv: Conversation) {
        modelContext.delete(conv)
        try? modelContext.save()
    }

    private func rejectDeleteConversation(_ id: UUID) {
        shakingId = id
        shakePhase = 0
        withAnimation(.linear(duration: 0.4)) {
            shakePhase = 3
        }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            shakingId = nil
            shakePhase = 0
        }
    }

    private func hasBluetoothAudioDevice() -> Bool {
        let route = AVAudioSession.sharedInstance().currentRoute
        let bluetoothPorts: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
        return route.outputs.contains { bluetoothPorts.contains($0.portType) }
            || route.inputs.contains { bluetoothPorts.contains($0.portType) }
    }

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
            print("[HearView] audio session config failed: \(error)")
        }
    }

    private func requestPermissions() async {
        let speechService = SpeechRecognitionService()
        _ = await speechService.requestAuthorization()

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            AVAudioApplication.requestRecordPermission { _ in
                c.resume()
            }
        }
    }
}
