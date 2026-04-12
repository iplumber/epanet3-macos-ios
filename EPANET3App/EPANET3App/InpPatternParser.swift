import Foundation

/// 与 `patternparser.cpp` 中 `PatternParser` 行为一致的 `[PATTERNS]` 解析（用于界面展示，非引擎校验）。
public enum InpPatternParser {

    public enum PatternKind: String {
        case fixed = "固定 (FIXED)"
        case variable = "变量 (VARIABLE)"
    }

    /// 单条模式的展示模型。
    public struct ParsedPattern: Identifiable {
        public let id: String
        public let kind: PatternKind
        /// 仅 FIXED：时间步长（秒），与 `FIXED` 行第三项一致；未写则为 nil。
        public let fixedIntervalSeconds: Int?
        /// FIXED：各时段乘子。
        public let fixedFactors: [Double]
        /// VARIABLE：(时间秒, 乘子)。
        public let variablePairs: [(timeSeconds: Int, factor: Double)]

        public var hasSeries: Bool {
            switch kind {
            case .fixed: return !fixedFactors.isEmpty
            case .variable: return !variablePairs.isEmpty
            }
        }
    }

    /// 从 `[PATTERNS]` 节正文解析；空节返回空数组。
    public static func parse(sectionBody: String) -> [ParsedPattern] {
        let lines = sectionBody.split(whereSeparator: \.isNewline).map(String.init)
        var orderedIds: [String] = []
        var accumulators: [String: PatternAccumulator] = [:]

        for raw in lines {
            let line = stripComment(raw)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let tokens = splitTokens(trimmed)
            guard let id = tokens.first, tokens.count >= 2 else { continue }
            if accumulators[id] == nil {
                orderedIds.append(id)
                accumulators[id] = PatternAccumulator()
            }
            parseLineTokens(tokens, into: &accumulators[id]!)
        }

        return orderedIds.compactMap { pid -> ParsedPattern? in
            guard let acc = accumulators[pid], let k = acc.kind else { return nil }
            return ParsedPattern(
                id: pid,
                kind: k,
                fixedIntervalSeconds: acc.fixedIntervalSeconds,
                fixedFactors: acc.fixedFactors,
                variablePairs: acc.variablePairs
            )
        }
    }

    // MARK: - Private

    private struct PatternAccumulator {
        var kind: PatternKind?
        var fixedIntervalSeconds: Int?
        var fixedFactors: [Double] = []
        var variablePairs: [(Int, Double)] = []
    }

    private static func stripComment(_ line: String) -> String {
        if let r = line.range(of: ";") {
            return String(line[..<r.lowerBound])
        }
        return line
    }

    private static func splitTokens(_ line: String) -> [String] {
        line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func parseLineTokens(_ tokens: [String], into acc: inout PatternAccumulator) {
        guard tokens.count >= 2 else { return }
        if acc.kind == nil {
            let t1 = tokens[1].uppercased()
            if t1 == "VARIABLE" {
                acc.kind = .variable
                return
            }
            if t1 == "FIXED" {
                acc.kind = .fixed
                if tokens.count >= 3, let sec = parseFixedIntervalToken(tokens[2]) {
                    acc.fixedIntervalSeconds = sec
                }
                return
            }
            acc.kind = .fixed
            for i in 1..<tokens.count {
                if let v = parseDouble(tokens[i]) { acc.fixedFactors.append(v) }
            }
            return
        }

        if acc.kind == .fixed {
            for i in 1..<tokens.count {
                if let v = parseDouble(tokens[i]) { acc.fixedFactors.append(v) }
            }
        } else {
            var i = 1
            while i + 1 < tokens.count {
                if let secs = parsePatternTimeToken(tokens[i]), let f = parseDouble(tokens[i + 1]) {
                    acc.variablePairs.append((secs, f))
                }
                i += 2
            }
        }
    }

    /// 与 `Utilities::getSeconds(str, "")` 一致：无冒号为十进制小时→秒。
    private static func parseFixedIntervalToken(_ token: String) -> Int? {
        if token.contains(":") { return parseClockTimeToSeconds(token) }
        guard let t = parseDouble(token), t.isFinite else { return nil }
        return Int((3600.0 * t).rounded())
    }

    /// 变量模式时间：冒号为 h:m(:s)；否则十进制小时→秒。
    private static func parsePatternTimeToken(_ token: String) -> Int? {
        if token.contains(":") { return parseClockTimeToSeconds(token) }
        guard let t = parseDouble(token), t.isFinite else { return nil }
        return Int((3600.0 * t).rounded())
    }

    private static func parseClockTimeToSeconds(_ token: String) -> Int? {
        let parts = token.split(separator: ":").map { String($0) }
        if parts.count == 2 {
            guard let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            return h * 3600 + m * 60
        }
        if parts.count == 3 {
            guard let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]) else { return nil }
            return h * 3600 + m * 60 + s
        }
        return nil
    }

    private static func parseDouble(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        return Double(t)
    }
}

// MARK: - Chart / table helpers

extension InpPatternParser.ParsedPattern {

    /// 固定模式：横轴为时段序号 1…n；若已知步长则附带等效时间（秒）。
    public struct FixedChartPoint: Identifiable {
        public var id: Int { periodIndex }
        public let periodIndex: Int
        public let timeSeconds: Double?
        public let factor: Double
    }

    /// 变量模式：横轴为时间（小时）。
    public struct VariableChartPoint: Identifiable {
        public let id: Int
        public let timeSeconds: Int
        public let timeHours: Double
        public let factor: Double
    }

    public var fixedChartPoints: [FixedChartPoint] {
        guard kind == .fixed else { return [] }
        let n = fixedFactors.count
        let step = fixedIntervalSeconds
        return (0..<n).map { i in
            let period = i + 1
            let tSec: Double? = step.map { Double(i * $0) }
            return FixedChartPoint(periodIndex: period, timeSeconds: tSec, factor: fixedFactors[i])
        }
    }

    public var variableChartPoints: [VariableChartPoint] {
        guard kind == .variable else { return [] }
        return variablePairs.enumerated().map { i, pair in
            VariableChartPoint(
                id: i,
                timeSeconds: pair.timeSeconds,
                timeHours: Double(pair.timeSeconds) / 3600.0,
                factor: pair.factor
            )
        }
    }
}
