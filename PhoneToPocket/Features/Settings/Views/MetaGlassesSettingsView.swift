import SwiftUI

struct MetaGlassesSettingsView: View {
    var metaService: MetaGlassesService

    var body: some View {
        @Bindable var service = metaService

        List {
            Section("连接状态") {
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(metaService.connectionState.rawValue)
                }

                if let error = metaService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if metaService.isConnected {
                    Button("断开连接", role: .destructive) {
                        metaService.disconnect()
                    }
                } else {
                    Button("扫描并连接") {
                        metaService.startRegistration()
                    }
                    .disabled(metaService.connectionState == .scanning || metaService.connectionState == .connecting)
                }
            }

            Section("视频流画质") {
                Picker("画质", selection: $service.streamQuality) {
                    ForEach(MetaStreamQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                .pickerStyle(.segmented)

                Text("所有画质均以 24fps 传输")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("需要 Meta AI 眼镜（如 Ray-Ban Meta）配合使用。确保眼镜已开启且蓝牙已打开。首次连接需要通过 Meta AI 应用完成配对。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Meta 眼镜")
    }

    private var statusColor: Color {
        switch metaService.connectionState {
        case .disconnected: return .red
        case .scanning, .connecting: return .orange
        case .connected: return .green
        case .streaming: return .blue
        }
    }
}
