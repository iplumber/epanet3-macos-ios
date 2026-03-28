/* 从 .inp 的 [OPTION] / [OPTIONS] 解析 Flow Units，用于属性面板显示单位标签。
 * EPANET 3 使用 [OPTION]，EPANET 2 常用 [OPTIONS]；支持 FLOW_UNITS GPM、Flow Units GPM、UNITS GPM 等写法。 */
import Foundation

struct InpOptionsParser {
    /// US Customary flow units → 长度/管径/压力/水头等为 ft, in, psi；否则按 SI（m, mm 等）
    private static let usFlowUnits: Set<String> = ["CFS", "GPM", "MGD", "IMGD", "AFD"]
    /// 合法的 flow unit 关键字，用于识别 “UNITS GPM” 中的值
    private static let flowUnitValues: Set<String> = ["CFS", "GPM", "MGD", "IMGD", "AFD", "LPS", "LPM", "MLD", "CMH", "CMD"]

    /// 与 `EPANET3/Core/options.cpp` 中 `flowUnitsWords[]` 顺序一致（设置界面、切换单位时写入 .inp 的合法值）。
    static let epanetFlowUnitsOrdered: [(code: String, menuLabel: String)] = [
        ("CFS", "CFS · 立方英尺/秒"),
        ("GPM", "GPM · 美制加仑/分钟"),
        ("MGD", "MGD · 百万美制加仑/日"),
        ("IMGD", "IMGD · 百万英制加仑/日"),
        ("AFD", "AFD · 英亩·英尺/日"),
        ("LPS", "LPS · 升/秒"),
        ("LPM", "LPM · 升/分钟"),
        ("MLD", "MLD · 百万升/日"),
        ("CMH", "CMH · 立方米/小时"),
        ("CMD", "CMD · 立方米/日"),
    ]

    /// 是否为 EPANET 支持的 Flow Units 关键字。
    static func isValidFlowUnitCode(_ code: String) -> Bool {
        let u = code.uppercased().trimmingCharacters(in: .whitespaces)
        return flowUnitValues.contains(u)
    }

    /// 流量类数值在界面上的简短单位后缀（画布标注等若需显示单位时可复用；属性面板当前不显示单位）。
    static func flowUnitDisplaySuffix(code: String?) -> String {
        let u = (code ?? "GPM").uppercased().trimmingCharacters(in: .whitespaces)
        switch u {
        case "CMH": return "m³/h"
        case "CMD": return "m³/d"
        case "LPS": return "L/s"
        case "LPM": return "L/min"
        case "MLD": return "ML/d"
        default: return u.isEmpty ? "GPM" : u
        }
    }

    /// 解析 path 指向的 .inp 的 [OPTION]/[OPTIONS]，返回 Flow Units 关键字（如 "GPM", "LPS"）；无法解析时返回 nil。
    static func parseFlowUnits(path: String) -> String? {
        guard let content = try? InpFileTextReader.contentsOfFile(path: path) else { return nil }
        return parseFlowUnits(content: content)
    }

    /// 从已读入的 .inp 全文解析 Flow Units（与 `parseFlowUnits(path:)` 一致，避免重复磁盘读）。
    static func parseFlowUnits(content: String) -> String? {
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

    /// 一次读入 .inp 后在 `[OPTIONS]` 段内解析的常用项（避免设置页对同一文件连读多遍）。
    struct InpOptionsHints: Equatable {
        var headloss: String?
        var viscosity: Double?
        var diffusivity: Double?
        var quality: String?
    }

    /// 整文件只读一次，扫描 `[OPTION(S)]` 中的 HEADLOSS / VISCOSITY / DIFFUSIVITY / QUALITY。
    static func parseOptionsHints(path: String) -> InpOptionsHints? {
        guard let content = try? InpFileTextReader.contentsOfFile(path: path) else { return nil }
        return parseOptionsHints(content: content)
    }

    static func parseOptionsHints(content: String) -> InpOptionsHints {
        var hints = InpOptionsHints()
        let lines = content.components(separatedBy: .newlines)
        var inOptions = false
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") {
                let upper = line.uppercased()
                inOptions = upper.starts(with: "[OPTION")
                continue
            }
            guard inOptions else { continue }
            let tokens = line.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
            guard tokens.count >= 2 else { continue }
            let key = tokens[0].uppercased()
            switch key {
            case "HEADLOSS":
                hints.headloss = tokens[1].uppercased()
            case "VISCOSITY":
                hints.viscosity = Double(tokens[1])
            case "DIFFUSIVITY":
                hints.diffusivity = Double(tokens[1])
            case "QUALITY":
                hints.quality = tokens[1].uppercased()
            default:
                break
            }
        }
        return hints
    }

    /// 从 .inp [OPTIONS] 解析水头损失公式；返回 "H-W", "D-W", "C-M" 之一，或 nil。
    static func parseHeadloss(path: String) -> String? {
        parseOptionsHints(path: path)?.headloss
    }

    /// 从 .inp [OPTIONS] 解析需水量模型；返回 "DDA", "PDA", "FIXED" 等，或 nil。
    static func parseDemandModel(path: String) -> String? {
        return parseStringOption(path: path, keys: ["DEMAND_MODEL", "DEMANDMODEL"])
    }

    /// 从 .inp [OPTIONS] 解析水质类型；返回 "NONE", "CHEMICAL", "AGE", "TRACE" 等，或 nil。
    static func parseQualityType(path: String) -> String? {
        parseOptionsHints(path: path)?.quality
    }

    /// 从 .inp [OPTIONS] 解析粘度系数，默认 1.0。
    static func parseViscosity(path: String) -> Double? {
        parseOptionsHints(path: path)?.viscosity
    }

    /// 从 .inp [OPTIONS] 解析扩散系数，默认 1.0。
    static func parseDiffusivity(path: String) -> Double? {
        parseOptionsHints(path: path)?.diffusivity
    }

    private static func parseStringOption(path: String, keys: [String]) -> String? {
        guard let content = try? InpFileTextReader.contentsOfFile(path: path) else { return nil }
        let lines = content.components(separatedBy: .newlines)
        var inOptions = false
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") {
                let upper = line.uppercased()
                inOptions = upper.starts(with: "[OPTION")
                continue
            }
            if inOptions {
                let tokens = line.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
                guard tokens.count >= 2 else { continue }
                let key = tokens[0].uppercased()
                if keys.contains(key) {
                    return tokens[1].uppercased()
                }
            }
        }
        return nil
    }

    private static func parseDoubleOption(path: String, keys: [String]) -> Double? {
        guard let content = try? InpFileTextReader.contentsOfFile(path: path) else { return nil }
        let lines = content.components(separatedBy: .newlines)
        var inOptions = false
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") {
                let upper = line.uppercased()
                inOptions = upper.starts(with: "[OPTION")
                continue
            }
            if inOptions {
                let tokens = line.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
                guard tokens.count >= 2 else { continue }
                let key = tokens[0].uppercased()
                if keys.contains(key) {
                    return Double(tokens[1])
                }
            }
        }
        return nil
    }
}
