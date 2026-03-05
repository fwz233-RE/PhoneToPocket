import Foundation

enum ChatMode: String, CaseIterable, Identifiable, Codable {
    case visual = "视觉聊天"
    case voice = "语音聊天"
    case text = "打字聊天"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .visual: return "eye.fill"
        case .voice: return "waveform"
        case .text: return "keyboard"
        }
    }

    var usesVoiceInput: Bool { self == .visual || self == .voice }
    var usesTTS: Bool { self == .visual || self == .voice }
    var usesMetaVideoStream: Bool { self == .visual }
}
