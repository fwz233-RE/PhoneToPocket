import SwiftUI

struct CameraControlsView: View {
    @Binding var microphoneMode: MicrophoneMode
    @Binding var isCenterStageOn: Bool
    @Binding var selectedFrameRate: FrameRate
    var supportedFrameRates: [FrameRate]
    var isCenterStageAvailable: Bool
    var onToggleCenterStage: () -> Void
    var onFrameRateChanged: (FrameRate) -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Mic mode
            Menu {
                ForEach(MicrophoneMode.allCases) { mode in
                    Button {
                        withAnimation { microphoneMode = mode }
                    } label: {
                        Label(mode.rawValue, systemImage: mode.icon)
                    }
                }
            } label: {
                pill(icon: microphoneMode.icon,
                     label: microphoneMode.rawValue,
                     active: microphoneMode != .standard)
            }

            // Center Stage
            Button(action: onToggleCenterStage) {
                pill(icon: "person.crop.rectangle",
                     label: "人像居中",
                     active: isCenterStageOn)
            }
            .disabled(!isCenterStageAvailable)
            .opacity(isCenterStageAvailable ? 1 : 0.3)

            // Frame rate — use Picker to avoid Menu crash on some devices
            if supportedFrameRates.count > 1 {
                Menu {
                    ForEach(supportedFrameRates) { fps in
                        Button {
                            onFrameRateChanged(fps)
                        } label: {
                            HStack {
                                Text("\(fps.label) fps")
                                if fps == selectedFrameRate {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    pill(icon: "speedometer",
                         label: "\(selectedFrameRate.label)fps",
                         active: selectedFrameRate != .fps60)
                }
            } else {
                pill(icon: "speedometer",
                     label: "\(selectedFrameRate.label)fps",
                     active: false)
            }
        }
    }

    @ViewBuilder
    private func pill(icon: String, label: String, active: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .frame(width: 40, height: 40)
                .background(Circle().fill(active ? .white : .white.opacity(0.12)))
                .foregroundStyle(active ? .black : .white)

            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
        }
        .animation(.easeInOut(duration: 0.2), value: active)
    }
}
