import Foundation

/// Scans a source `.inp` to infer maximum fractional digits per `[SECTION]` for export formatting.
enum InpNumericFormat {
    static func maxFractionDigitsPerSection(content: String) -> [String: Int] {
        var maxBySection: [String: Int] = [:]
        var section = ""
        for rawLine in content.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("["), let end = trimmed.firstIndex(of: "]") {
                section = String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
                    .trimmingCharacters(in: .whitespaces)
                    .uppercased()
                continue
            }
            if trimmed.hasPrefix(";") { continue }
            if section == "TITLE" || section == "END" || section.isEmpty { continue }

            var line = String(rawLine)
            if let semi = line.firstIndex(of: ";") {
                line = String(line[..<semi])
            }
            let tokens = line.split { $0.isWhitespace || $0 == "\t" }.map(String.init)
            for tok in tokens {
                let t = tok.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { continue }
                if t.count >= 2, t.first == "\"", t.last == "\"" { continue }
                if t.contains(":") { continue }
                guard let frac = fractionalDigitCount(forNumericToken: t) else { continue }
                let prev = maxBySection[section] ?? 0
                if frac > prev { maxBySection[section] = frac }
            }
        }
        return maxBySection
    }

    private static func fractionalDigitCount(forNumericToken tok: String) -> Int? {
        var t = tok
        if let eRange = t.range(of: #"[eE][+-]?\d+"#, options: .regularExpression) {
            t = String(t[..<eRange.lowerBound])
        }
        t = t.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        guard Double(t) != nil else { return nil }

        guard let dot = t.firstIndex(of: ".") else { return 0 }
        let afterDot = t[t.index(after: dot)...]
        var count = 0
        for ch in afterDot {
            if ch.isNumber { count += 1 } else { break }
        }
        return count
    }
}
