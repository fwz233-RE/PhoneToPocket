import SwiftUI

struct TeleprompterOverlayView: View {
    let lines: [String]
    let currentLineIndex: Int
    let currentCharIndex: Int
    var onSwipeUp: () -> Void
    var onSwipeDown: () -> Void

    @State private var animatedLineIndex: Int = 0

    private let lineHeight: CGFloat = 22
    private let lineSpacing: CGFloat = 6
    private var rowStep: CGFloat { lineHeight + lineSpacing }

    private var progress: Double {
        guard lines.count > 1 else { return 1 }
        return Double(currentLineIndex) / Double(lines.count - 1)
    }

    private var visibleHeight: CGFloat {
        lineHeight * 3 + lineSpacing * 2
    }

    var body: some View {
        scrollingLines
            .padding(.leading, 8).padding(.trailing, 40)
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
    }

    // MARK: - Scrolling Lines

    private var scrollingLines: some View {
        VStack(spacing: lineSpacing) {
            Color.clear.frame(height: lineHeight)

            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(spacing: 1) {
                    lineNumber(at: index)
                    lineContent(at: index, line: line)
                }
                .frame(height: lineHeight)
            }

            Color.clear.frame(height: lineHeight)
        }
        .offset(y: -CGFloat(animatedLineIndex) * rowStep)
        .frame(height: visibleHeight, alignment: .top)
        .clipped()
        .onAppear { animatedLineIndex = currentLineIndex }
        .onChange(of: currentLineIndex) { _, newValue in
            withAnimation(.smooth(duration: 0.35)) {
                animatedLineIndex = newValue
            }
        }
    }

    // MARK: - Line Content

    private func lineContent(at index: Int, line: String) -> some View {
        let isCurrent = index == currentLineIndex
        let read = isCurrent ? min(max(currentCharIndex + 1, 0), line.count) : 0

        return HStack(spacing: 0) {
            Text(String(line.prefix(read)))
                .foregroundStyle(isCurrent ? .white : .white.opacity(0.45))
            Text(String(line.dropFirst(read)))
                .foregroundStyle(isCurrent ? .white.opacity(0.5) : .white.opacity(0.45))
        }
        .font(.body.weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Line Number

    private func lineNumber(at index: Int) -> some View {
        Text("\(index + 1)")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(index == currentLineIndex ? .white.opacity(0.7) : .white.opacity(0.3))
            .frame(width: 14, alignment: .leading)
    }

    // MARK: - Progress Indicator

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
