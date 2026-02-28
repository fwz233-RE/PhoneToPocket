import Foundation

/// 逐行独立匹配的提词器文案追踪服务。
///
/// 核心设计：
/// - 每一行的拼音独立存储，匹配在行内完成，误差不跨行传导
/// - 换行检测依赖下一行**前缀**是否出现在近期语音中（前缀锚定）
/// - 行内容错窗口严格限定在当前行，即"补偿发生在行内"
/// - 行号和行内位置只进不退
@Observable
final class FuzzyMatchService {

    // MARK: - Public State

    private(set) var currentLineIndex: Int = 0
    private(set) var currentCharInLine: Int = 0

    // MARK: - Per-Line Data

    private struct LinePinyin {
        let pinyin: [String]
    }

    private var lines: [LinePinyin] = []

    // MARK: - Tuning Constants

    /// 用于匹配的语音尾部长度（字符级拼音 token 数量）
    private let tailSize = 25
    /// 用于前缀检测的"最近"语音长度
    private let recentSize = 12
    /// 触发换行所需的最少前缀匹配数
    private let prefixMinMatch = 3
    /// 向前检查多少行的前缀
    private let lookahead = 3
    /// 行内每次搜索的最大前探窗口（容错字数）
    private let inLineWindow = 3
    /// 行内推进所需的最低匹配 token 数
    private let minMatchCount = 2
    /// 模糊拼音比较的 Levenshtein 距离阈值（占最长串比例）
    private let fuzzyThreshold = 0.35

    // MARK: - Configuration

    func configure(lines: [String]) {
        self.lines = lines.map { line in
            LinePinyin(pinyin: line.map { char in
                let s = String(char)
                let p = s.toPinyin.trimmingCharacters(in: .whitespacesAndNewlines)
                return p.isEmpty ? s.lowercased() : p
            })
        }
        reset()
    }

    // MARK: - Recognition Update

    func updateWithRecognizedText(_ text: String) {
        guard !lines.isEmpty, !text.isEmpty else { return }

        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return }

        let tail = Array(tokens.suffix(tailSize))

        // Phase 1 — 前缀锚定换行检测
        //   取最近一段语音，检查后续各行的前缀是否出现其中
        if let nextLine = detectLineJump(tail: tail) {
            currentLineIndex = nextLine
            currentCharInLine = 0
        }

        // Phase 2 — 行内推进
        //   在当前行内顺序匹配 tail token，推进已读位置
        //   容错窗口 (inLineWindow) 严格限定在本行，不影响其他行
        let progress = matchLineProgress(
            tail: tail,
            lineIndex: currentLineIndex,
            fromChar: currentCharInLine
        )
        if progress > currentCharInLine {
            currentCharInLine = progress
        }
    }

    func jumpToLine(_ lineIndex: Int) {
        guard !lines.isEmpty else { return }
        currentLineIndex = max(0, min(lineIndex, lines.count - 1))
        currentCharInLine = 0
    }

    func reset() {
        currentLineIndex = 0
        currentCharInLine = 0
    }

    // MARK: - Tokenization

    private func tokenize(_ text: String) -> [String] {
        text.compactMap { char -> String? in
            let s = String(char)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let p = s.toPinyin.trimmingCharacters(in: .whitespacesAndNewlines)
            return p.isEmpty ? s.lowercased() : p
        }
    }

    // MARK: - Line Jump Detection

    /// 取 tail 的最近 `recentSize` 个 token，逐行检查后续行的前缀是否作为
    /// 子序列出现。命中即判定用户已开始读该行，从最近的行开始检查以避免跳过行。
    private func detectLineJump(tail: [String]) -> Int? {
        let maxLine = min(currentLineIndex + lookahead, lines.count - 1)
        guard currentLineIndex < maxLine else { return nil }

        let recent = Array(tail.suffix(min(tail.count, recentSize)))

        for lineIdx in (currentLineIndex + 1)...maxLine {
            let linePy = lines[lineIdx].pinyin
            let prefixLen = min(prefixMinMatch, linePy.count)
            guard prefixLen >= 2 else { continue }

            let prefix = Array(linePy.prefix(prefixLen))
            if containsSequential(source: recent, pattern: prefix) {
                return lineIdx
            }
        }

        return nil
    }

    /// 判断 `pattern` 是否作为顺序子序列出现在 `source` 中。
    /// 为防止偶然命中，每个起始位置最多扫描 pattern.count * 2 个元素。
    private func containsSequential(source: [String], pattern: [String]) -> Bool {
        let spread = pattern.count * 2

        for start in 0..<source.count {
            var patIdx = 0
            var srcIdx = start

            while patIdx < pattern.count,
                  srcIdx < source.count,
                  srcIdx - start < spread {
                if fuzzyEqual(source[srcIdx], pattern[patIdx]) {
                    patIdx += 1
                }
                srcIdx += 1
            }

            if patIdx >= pattern.count { return true }
        }

        return false
    }

    // MARK: - Within-Line Matching

    /// 从 `fromChar` 开始，在行内顺序匹配 tail token。
    ///
    /// 每个 token 最多向前探 `inLineWindow` 个字符位置，超出则跳过该 token。
    /// 这样单次识别错误最多浪费 1 个窗口宽度的行内位置，不会扩散到其他行。
    /// 需要至少 `minMatchCount` 次命中才认为推进有效，防止单个偶然匹配拉跑位置。
    private func matchLineProgress(tail: [String], lineIndex: Int, fromChar: Int) -> Int {
        guard lineIndex < lines.count else { return fromChar }
        let linePy = lines[lineIndex].pinyin
        guard !linePy.isEmpty, fromChar < linePy.count else { return fromChar }

        var linePos = fromChar
        var best = fromChar
        var matchCount = 0

        for token in tail {
            guard linePos < linePy.count else { break }

            let windowEnd = min(linePos + inLineWindow, linePy.count)
            for check in linePos..<windowEnd {
                if fuzzyEqual(token, linePy[check]) {
                    linePos = check + 1
                    best = check
                    matchCount += 1
                    break
                }
            }
        }

        return matchCount >= minMatchCount ? best : fromChar
    }

    // MARK: - Fuzzy Pinyin Comparison

    private func fuzzyEqual(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a.count <= 1, b.count <= 1 { return false }
        let maxLen = max(a.count, b.count)
        return Double(levenshtein(a, b)) / Double(maxLen) < fuzzyThreshold
    }

    private func levenshtein(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1), b = Array(s2)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = curr
        }
        return prev[n]
    }
}
