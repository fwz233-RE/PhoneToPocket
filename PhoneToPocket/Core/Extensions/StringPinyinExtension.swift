import Foundation

extension String {
    var toPinyin: String {
        let mutable = NSMutableString(string: self) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return (mutable as String).lowercased()
    }

    var pinyinTokens: [String] {
        toPinyin.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }

    func characterPinyinArray() -> [String] {
        map { char in
            String(char).toPinyin.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
