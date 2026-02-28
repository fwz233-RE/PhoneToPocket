import SwiftUI

struct TeleprompterOverlayView: View {
    let lines: [String]
    let currentLineIndex: Int
    let currentCharIndex: Int
    var onSwipeUp: () -> Void
    var onSwipeDown: () -> Void

    private var progress: Double {
        guard lines.count > 1 else { return 1 }
        return Double(currentLineIndex) / Double(lines.count - 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            lineView(at: currentLineIndex - 1)
            currentHighlightedLine
                .id(currentLineIndex)
                .transition(.push(from: .bottom))
            lineView(at: currentLineIndex + 1)
        }
        .padding(.leading, 16).padding(.trailing, 40)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            progressIndicator
                .padding(.vertical, 14)
                .padding(.trailing, 10)
        }
        .background(
            .ultraThinMaterial.opacity(0.6),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .padding(.horizontal, 48)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    if value.translation.height < -15 {
                        onSwipeUp()
                    } else if value.translation.height > 15 {
                        onSwipeDown()
                    }
                }
        )
        .animation(.smooth(duration: 0.3), value: currentLineIndex)
    }

    // MARK: - Current Line

    @ViewBuilder
    private var currentHighlightedLine: some View {
        if currentLineIndex >= 0, currentLineIndex < lines.count {
            let line = lines[currentLineIndex]
            let read = min(max(currentCharIndex + 1, 0), line.count)
            HStack(spacing: 0) {
                Text(String(line.prefix(read))).foregroundStyle(.white)
                Text(String(line.dropFirst(read))).foregroundStyle(.white.opacity(0.5))
            }
            .font(.body.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Adjacent Line

    @ViewBuilder
    private func lineView(at index: Int) -> some View {
        if index >= 0, index < lines.count {
            Text(lines[index])
                .font(.body.weight(.medium))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Color.clear.frame(height: 22)
        }
    }

    // MARK: - Progress Indicator (overlay, does not affect layout height)

    @ViewBuilder
    private var progressIndicator: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white.opacity(0.12))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white.opacity(0.5))
                        .frame(height: max(2, geo.size.height * progress))
                }
            }
            .frame(width: 3)

            Text("\(Int(progress * 100))%")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(width: 28)
    }
}
