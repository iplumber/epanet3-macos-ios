import Foundation

/// 与 `curveparser.cpp` 中 `CurveParser::parseCurveData` 行为一致的 `[CURVES]` 解析（用于界面展示）。
public enum InpCurveParser {

    public struct ParsedCurve: Identifiable {
        public let id: String
        /// 第二列为 `PUMP` / `EFFICIENCY` / `VOLUME` / `HEADLOSS` 之一时记录；否则为 nil。
        public let typeKeyword: String?
        public let points: [(x: Double, y: Double)]

        public var hasPoints: Bool { !points.isEmpty }
    }

    private static let typeKeywords: Set<String> = ["PUMP", "EFFICIENCY", "VOLUME", "HEADLOSS"]

    public static func parse(sectionBody: String) -> [ParsedCurve] {
        let lines = sectionBody.split(whereSeparator: \.isNewline).map(String.init)
        var orderedIds: [String] = []
        var accumulators: [String: CurveAccumulator] = [:]

        for raw in lines {
            let line = stripComment(raw)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let tokens = splitTokens(trimmed)
            guard let id = tokens.first, tokens.count >= 2 else { continue }
            if accumulators[id] == nil {
                orderedIds.append(id)
                accumulators[id] = CurveAccumulator()
            }
            parseLineTokens(tokens, into: &accumulators[id]!)
        }

        return orderedIds.compactMap { cid -> ParsedCurve? in
            guard let acc = accumulators[cid] else { return nil }
            return ParsedCurve(id: cid, typeKeyword: acc.typeKeyword, points: acc.points)
        }
    }

    private struct CurveAccumulator {
        var typeKeyword: String?
        var points: [(Double, Double)] = []
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

    private static func parseLineTokens(_ tokens: [String], into acc: inout CurveAccumulator) {
        guard tokens.count >= 2 else { return }
        let t1 = tokens[1].uppercased()
        if typeKeywords.contains(t1) {
            acc.typeKeyword = t1
            return
        }
        var i = 1
        while i + 1 < tokens.count {
            if let x = Double(tokens[i]), let y = Double(tokens[i + 1]) {
                acc.points.append((x, y))
            }
            i += 2
        }
    }
}

extension InpCurveParser.ParsedCurve {

    public struct ChartPoint: Identifiable {
        public let id: Int
        public let x: Double
        public let y: Double
    }

    public var chartPoints: [ChartPoint] {
        points.enumerated().map { i, p in
            ChartPoint(id: i, x: p.x, y: p.y)
        }
    }
}
