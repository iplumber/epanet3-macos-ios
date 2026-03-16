/* 从 .inp 的 [OPTION] / [OPTIONS] 解析 Flow Units，用于属性面板显示单位标签。
 * EPANET 3 使用 [OPTION]，EPANET 2 常用 [OPTIONS]；支持 FLOW_UNITS GPM、Flow Units GPM、UNITS GPM 等写法。 */
import Foundation

struct InpOptionsParser {
    /// US Customary flow units → 长度/管径/压力/水头等为 ft, in, psi；否则按 SI（m, mm 等）
    private static let usFlowUnits: Set<String> = ["CFS", "GPM", "MGD", "IMGD", "AFD"]
    /// 合法的 flow unit 关键字，用于识别 “UNITS GPM” 中的值
    private static let flowUnitValues: Set<String> = ["CFS", "GPM", "MGD", "IMGD", "AFD", "LPS", "LPM", "MLD", "CMH", "CMD"]

    /// 解析 path 指向的 .inp 的 [OPTION]/[OPTIONS]，返回 Flow Units 关键字（如 "GPM", "LPS"）；无法解析时返回 nil。
    static func parseFlowUnits(path: String) -> String? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: .newlines)
        var inOptions = false
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") {
                let upper = line.uppercased().trimmingCharacters(in: .whitespaces)
                inOptions = upper.starts(with: "[OPTION")
                continue
            }
            if inOptions {
                if let v = parseFlowUnitsFromLine(line) { return v }
            }
        }
        return fallbackScanFlowUnits(content: content)
    }

    private static func parseFlowUnitsFromLine(_ line: String) -> String? {
        let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 2 {
            let key = parts[0].uppercased().replacingOccurrences(of: " ", with: "")
            if key == "FLOWUNITS" {
                let val = parts[1].trimmingCharacters(in: .whitespaces).uppercased()
                if flowUnitValues.contains(val) { return val }
            }
        }
        let tokens = line.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
        if tokens.isEmpty { return nil }
        let t0 = tokens[0].uppercased()
        if t0 == "FLOW_UNITS" || t0 == "FLOWUNITS" {
            if tokens.count >= 2 {
                let val = tokens[1].uppercased()
                if flowUnitValues.contains(val) { return val }
            }
            return nil
        }
        if tokens.count >= 2 && t0 == "FLOW" && tokens[1].uppercased() == "UNITS" {
            if tokens.count >= 3 {
                let val = (tokens.last ?? tokens[2]).uppercased()
                if flowUnitValues.contains(val) { return val }
            }
            return nil
        }
        if t0 == "UNITS" && tokens.count >= 2 {
            let val = tokens[1].uppercased()
            if flowUnitValues.contains(val) { return val }
        }
        return nil
    }

    private static func fallbackScanFlowUnits(content: String) -> String? {
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            let upper = line.uppercased()
            guard upper.contains("FLOW") || upper.contains("UNITS") else { continue }
            let tokens = line.split(whereSeparator: { $0.isWhitespace }).map { String($0).uppercased() }
            for t in tokens {
                if flowUnitValues.contains(t) { return t }
            }
        }
        return nil
    }

    /// 若 Flow Units 为美制（GPM/CFS/MGD/IMGD/AFD），返回 true；否则为 SI 或未知时返回 false。
    static func isUSCustomary(flowUnits: String?) -> Bool {
        guard let u = flowUnits?.uppercased().trimmingCharacters(in: .whitespaces), !u.isEmpty else { return false }
        return Self.usFlowUnits.contains(u)
    }
}
