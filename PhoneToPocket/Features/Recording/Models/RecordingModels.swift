import Foundation
import CoreGraphics

enum AspectRatioCategory: String, CaseIterable, Identifiable {
    case landscape = "横屏"
    case portrait = "竖屏"
    case fullGate = "片门全开"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .landscape: return "rectangle.landscape.rotate"
        case .portrait: return "rectangle.portrait"
        case .fullGate: return "camera.aperture"
        }
    }
}

enum AspectRatio: String, CaseIterable, Identifiable {
    case landscape16x9 = "16:9"
    case landscape4x3 = "4:3"
    case portrait9x16 = "9:16"
    case portrait3x4 = "3:4"
    case fullGate = "Full"

    var id: String { rawValue }

    var category: AspectRatioCategory {
        switch self {
        case .landscape16x9, .landscape4x3: return .landscape
        case .portrait9x16, .portrait3x4: return .portrait
        case .fullGate: return .fullGate
        }
    }

    /// Aspect ratio of the sensor format to search for (always landscape, width/height).
    var sensorRatio: CGFloat {
        switch self {
        case .landscape16x9, .portrait9x16: return 16.0 / 9.0
        case .landscape4x3, .portrait3x4:   return 4.0 / 3.0
        case .fullGate:                      return 0
        }
    }

    /// Aspect ratio for the SwiftUI preview clipping.
    /// iPhone 17 front camera has a 1:1 square sensor, so fullGate is 1:1.
    var previewAspectRatio: CGFloat {
        switch self {
        case .landscape16x9: return 16.0 / 9.0
        case .landscape4x3:  return 4.0 / 3.0
        case .portrait9x16:  return 9.0 / 16.0
        case .portrait3x4:   return 3.0 / 4.0
        case .fullGate:      return 1.0
        }
    }

    static func ratios(for cat: AspectRatioCategory) -> [AspectRatio] {
        switch cat {
        case .landscape: return [.landscape16x9, .landscape4x3]
        case .portrait:  return [.portrait9x16, .portrait3x4]
        case .fullGate:  return [.fullGate]
        }
    }
}

enum MicrophoneMode: String, CaseIterable, Identifiable {
    case standard = "标准"
    case voiceIsolation = "语音突显"
    case wideSpectrum = "宽谱"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .standard: return "mic"
        case .voiceIsolation: return "person.wave.2"
        case .wideSpectrum: return "waveform"
        }
    }
}

enum FrameRate: Int, CaseIterable, Identifiable, Hashable {
    case fps24 = 24
    case fps25 = 25
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }
    var label: String { "\(rawValue)" }
}

