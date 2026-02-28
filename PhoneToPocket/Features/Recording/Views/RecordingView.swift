import SwiftUI

struct RecordingView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = RecordingViewModel()
    @State private var showCompletion = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                teleprompterSection
                cameraSection
                Spacer(minLength: 4)
                controlsSection
                recordBar.padding(.bottom, 26)
            }

        }
        .overlay {
            if showCompletion { savedToast }
        }
        .task { await viewModel.setup(lines: appState.scriptLines) }
        .onDisappear { viewModel.cleanup() }
        .onChange(of: viewModel.speechService.recognizedText) {
            viewModel.updateSpeechMatch()
        }
        .alert("错误", isPresented: $viewModel.showError) {
            Button("确定") {}
        } message: { Text(viewModel.errorText) }
    }

    // MARK: - Teleprompter

    @ViewBuilder
    private var teleprompterSection: some View {
        if !viewModel.scriptLines.isEmpty {
            TeleprompterOverlayView(
                lines: viewModel.scriptLines,
                currentLineIndex: viewModel.currentLine,
                currentCharIndex: viewModel.currentCharInLine,
                onSwipeUp: { viewModel.advanceLine() },
                onSwipeDown: { viewModel.retreatLine() }
            )
            .padding(.top, 4).padding(.bottom, 4)
        }
    }

    // MARK: - Camera

    @ViewBuilder
    private var cameraSection: some View {
        #if os(iOS)
        Group {
            if viewModel.isConfigured {
                CameraPreviewView(session: viewModel.cameraService.captureSession)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 12)
                    .aspectRatio(viewModel.selectedAspectRatio.previewAspectRatio, contentMode: .fit)
                    .animation(.smooth(duration: 0.4), value: viewModel.selectedAspectRatio)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.04))
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .padding(.horizontal, 12)
                    .overlay { ProgressView().tint(.white) }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    if value.translation.height < -15 {
                        viewModel.advanceLine()
                    } else if value.translation.height > 15 {
                        viewModel.retreatLine()
                    }
                }
        )
        #endif
    }

    // MARK: - Controls

    @ViewBuilder
    private var controlsSection: some View {
        VStack(spacing: 12) {
            AspectRatioPickerView(
                selectedRatio: $viewModel.selectedAspectRatio,
                onChanged: { viewModel.applyCameraSettings() }
            )

            CameraControlsView(
                microphoneMode: $viewModel.microphoneMode,
                isCenterStageOn: $viewModel.isCenterStageOn,
                selectedFrameRate: $viewModel.selectedFrameRate,
                supportedFrameRates: viewModel.cameraService.allSupportedFrameRates(),
                isCenterStageAvailable: viewModel.isCenterStageAvailable,
                onToggleCenterStage: { viewModel.toggleCenterStage() },
                onFrameRateChanged: { viewModel.changeFrameRate($0) }
            )
        }
        .padding(.bottom, 8)
    }

    // MARK: - Record Bar

    @ViewBuilder
    private var recordBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 44) {
                Button {
                    viewModel.cleanup()
                    appState.navigateTo(.scriptInput)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2).foregroundStyle(.white.opacity(0.65))
                        .frame(width: 50, height: 50)
                }

                Button {
                    if viewModel.cameraService.isRecording {
                        Task {
                            await viewModel.stopRecording()
                            withAnimation(.spring(duration: 0.5)) { showCompletion = true }
                        }
                    } else { viewModel.startRecording() }
                } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 72, height: 72)
                        if viewModel.cameraService.isRecording {
                            RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 28, height: 28)
                        } else {
                            Circle().fill(.red).frame(width: 60, height: 60)
                        }
                    }
                    .animation(.spring(duration: 0.25), value: viewModel.cameraService.isRecording)
                }

                Button { viewModel.openSystemPhotos() } label: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.12))
                        .frame(width: 50, height: 50)
                        .overlay {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title3).foregroundStyle(.white.opacity(0.65))
                        }
                }
            }

            if viewModel.cameraService.isRecording {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 7, height: 7)
                    Text(viewModel.formattedDuration)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Saved Toast

    @ViewBuilder
    private var savedToast: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("已保存到相册")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Button {
                viewModel.openSystemPhotos()
            } label: {
                Text("查看")
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .transition(.scale(scale: 0.9).combined(with: .opacity))
        .onAppear {
            viewModel.resetForNextRecording()
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeOut(duration: 0.3)) { showCompletion = false }
            }
        }
    }
}
