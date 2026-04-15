import CoreFoundation
import Foundation

// MARK: - 设备与时序（CSV）

/// 设备 CSV 来源：流量表 `MODEL` 为**管段**侧 ID；压力表 `MODEL` 为**节点**侧 ID。与 EPANET 的对应关系由 `ScadaMappingConfiguration` 配置，不做拓扑推断。
enum ScadaDeviceKind: String, Codable, Sendable, Identifiable {
    case flow
    case pressure
    var id: String { rawValue }
}

/// 画布选中态：与管网节点/管段选中互斥，由 `AppState` 持有。
struct ScadaDeviceSelection: Equatable, Sendable {
    var kind: ScadaDeviceKind
    var deviceId: String
}

struct ScadaDeviceRow: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var x: Double?
    var y: Double?
    /// 流量表：外部管段 ID；压力表：外部节点 ID。
    var model: String
    var convAdd: Double
    var convMul: Double
    var compareTitle: String
    var compareOName: String
    var diameter: String
    var elevation: String
    var kind: ScadaDeviceKind

    /// 时序实测值换算：`value * convMul + convAdd`（与平台约定一致时再用于和仿真对比）。
    func calibratedValue(_ raw: Double) -> Double {
        raw * convMul + convAdd
    }
}

struct ScadaTimeSeriesRow: Equatable, Sendable {
    /// 如 `流量计`、`压力计`
    var scadaType: String
    var scadaID: String
    var time: Date
    var value: Double
}

struct ScadaDeviceCatalog: Sendable {
    /// `ID` → 记录
    var flowByDeviceId: [String: ScadaDeviceRow]
    var pressureByDeviceId: [String: ScadaDeviceRow]

    func device(for scadaID: String, typeHint: String?) -> ScadaDeviceRow? {
        if let t = typeHint {
            if t.contains("流量") { return flowByDeviceId[scadaID] }
            if t.contains("压力") { return pressureByDeviceId[scadaID] }
        }
        return flowByDeviceId[scadaID] ?? pressureByDeviceId[scadaID]
    }
}

// MARK: - 映射配置（JSON）

/// 与 INP 同目录的 `*.scada-mapping.json`：将设备表中的 `MODEL` 映射到当前工程 EPANET 对象 ID 字符串。
struct ScadaMappingConfiguration: Codable, Equatable, Sendable {
    /// 键：流量设备 CSV 的 `MODEL`（管段侧 ID）；值：EPANET 管段 ID（`[Pipes]` 等中的 ID）。
    var epanetLinkIdByFlowModelId: [String: String] = [:]
    /// 键：压力设备 CSV 的 `MODEL`（节点侧 ID）；值：EPANET 节点 ID。
    var epanetNodeIdByPressureModelId: [String: String] = [:]
    /// 可选：与 `.inp` **同目录**下的流量设备表文件名（仅文件名，不含路径）。
    var flowDeviceCSVFileName: String?
    /// 可选：与 `.inp` 同目录下的压力设备表文件名。
    var pressureDeviceCSVFileName: String?

    static let fileExtension = "scada-mapping.json"

    static func defaultURL(forInpURL inpURL: URL) -> URL {
        inpURL.deletingPathExtension().appendingPathExtension(Self.fileExtension)
    }

    static func load(from url: URL) throws -> ScadaMappingConfiguration {
        let data = try Data(contentsOf: url)
        let dec = JSONDecoder()
        return try dec.decode(ScadaMappingConfiguration.self, from: data)
    }

    func save(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(self)
        try data.write(to: url, options: [.atomic])
    }

    func resolvedEpanetLinkId(forFlowModel model: String) -> String? {
        let k = Self.normalizeKey(model)
        if let v = epanetLinkIdByFlowModelId[k] { return v }
        if let v = epanetLinkIdByFlowModelId[k.uppercased()] { return v }
        return epanetLinkIdByFlowModelId.first { Self.normalizeKey($0.key).caseInsensitiveCompare(k) == .orderedSame }?.value
    }

    func resolvedEpanetNodeId(forPressureModel model: String) -> String? {
        let k = Self.normalizeKey(model)
        if let v = epanetNodeIdByPressureModelId[k] { return v }
        if let v = epanetNodeIdByPressureModelId[k.uppercased()] { return v }
        return epanetNodeIdByPressureModelId.first { Self.normalizeKey($0.key).caseInsensitiveCompare(k) == .orderedSame }?.value
    }

    private static func normalizeKey(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ScadaDeviceRow {
    /// 使用映射表解析 EPANET 管段 ID（仅 `kind == .flow` 有意义）。
    func resolvedEpanetLinkId(mapping: ScadaMappingConfiguration) -> String? {
        guard kind == .flow else { return nil }
        return mapping.resolvedEpanetLinkId(forFlowModel: model)
    }

    /// 使用映射表解析 EPANET 节点 ID（仅 `kind == .pressure` 有意义）。
    func resolvedEpanetNodeId(mapping: ScadaMappingConfiguration) -> String? {
        guard kind == .pressure else { return nil }
        return mapping.resolvedEpanetNodeId(forPressureModel: model)
    }

    /// 与 `resolvedEpanetNodeId` 相同，但若 MODEL 键未命中，再用**设备 ID** 查映射（侧车中常把键写成与 ID 一致）。
    func resolvedEpanetNodeIdWithIdFallback(mapping: ScadaMappingConfiguration) -> String? {
        guard kind == .pressure else { return nil }
        if let m = resolvedEpanetNodeId(mapping: mapping) { return m }
        return mapping.resolvedEpanetNodeId(forPressureModel: id)
    }

    /// 与 `resolvedEpanetLinkId` 相同，但若 MODEL 键未命中，再用设备 ID 查映射。
    func resolvedEpanetLinkIdWithIdFallback(mapping: ScadaMappingConfiguration) -> String? {
        guard kind == .flow else { return nil }
        if let m = resolvedEpanetLinkId(mapping: mapping) { return m }
        return mapping.resolvedEpanetLinkId(forFlowModel: id)
    }
}

// MARK: - CSV 解析

enum ScadaImportError: Error, LocalizedError {
    case cannotRead(URL)
    case invalidDeviceHeader(row: String)
    case invalidTimeSeriesHeader(row: String)
    case invalidDeviceRow(lineNumber: Int, reason: String)
    case invalidTimeSeriesRow(lineNumber: Int, reason: String)

    var errorDescription: String? {
        switch self {
        case .cannotRead(let u): return "无法读取文件：\(u.path)"
        case .invalidDeviceHeader(let row): return "设备表表头不符：\(row)"
        case .invalidTimeSeriesHeader(let row): return "时序表表头不符：\(row)"
        case .invalidDeviceRow(let n, let r): return "设备表第 \(n) 行：\(r)"
        case .invalidTimeSeriesRow(let n, let r): return "时序表第 \(n) 行：\(r)"
        }
    }
}

private let expectedDeviceHeader = "ID,NAME,X,Y,MODEL,CONV_ADD,CONV_MUL,COMPARE_TITLE,COMPARE_ONAME,DIAMETER,ELEVATION"
private let expectedTimeSeriesHeader = "scadaType,scadaID,time,value"

enum ScadaCSVImporter {
    /// 时序 `scadaType` 是否与「压力」侧导入匹配（中文或英文）。
    static func scadaRowMatchesPressureImport(_ scadaType: String) -> Bool {
        let t = scadaType.lowercased()
        return scadaType.contains("压力") || t.contains("pressure")
    }
    /// 时序 `scadaType` 是否与「流量」侧导入匹配。
    static func scadaRowMatchesFlowImport(_ scadaType: String) -> Bool {
        let t = scadaType.lowercased()
        return scadaType.contains("流量") || t.contains("flow") || t.contains("meter")
    }

    static func loadDeviceCatalog(flowDeviceURL: URL, pressureDeviceURL: URL) throws -> ScadaDeviceCatalog {
        try loadDeviceCatalogFromOptionalFiles(flowDeviceURL: flowDeviceURL, pressureDeviceURL: pressureDeviceURL)
    }

    /// 从流量表、压力表中**任意存在的一侧或两侧**构建设备目录（便于只配置一种设备表时仍能加载 MODEL）。
    static func loadDeviceCatalogFromOptionalFiles(flowDeviceURL: URL?, pressureDeviceURL: URL?) throws -> ScadaDeviceCatalog {
        var fd: [String: ScadaDeviceRow] = [:]
        var pd: [String: ScadaDeviceRow] = [:]
        if let u = flowDeviceURL {
            for r in try loadDeviceRows(url: u, kind: .flow) { fd[r.id] = r }
        }
        if let u = pressureDeviceURL {
            for r in try loadDeviceRows(url: u, kind: .pressure) { pd[r.id] = r }
        }
        return ScadaDeviceCatalog(flowByDeviceId: fd, pressureByDeviceId: pd)
    }

    static func loadDeviceRows(url: URL, kind: ScadaDeviceKind) throws -> [ScadaDeviceRow] {
        let text = try readText(url)
        var lines = splitLines(text)
        guard !lines.isEmpty else { return [] }
        let header = lines.removeFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizeHeaderLine(header) == normalizeHeaderLine(expectedDeviceHeader) else {
            throw ScadaImportError.invalidDeviceHeader(row: header)
        }
        var out: [ScadaDeviceRow] = []
        out.reserveCapacity(lines.count)
        var lineNumber = 2
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                lineNumber += 1
                continue
            }
            let fields = parseCSVLine(trimmed)
            guard fields.count >= 11 else {
                throw ScadaImportError.invalidDeviceRow(lineNumber: lineNumber, reason: "列数不足 (\(fields.count))")
            }
            let id = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                throw ScadaImportError.invalidDeviceRow(lineNumber: lineNumber, reason: "ID 为空")
            }
            let convAdd = Double(fields[5]) ?? 0
            let convMul = Double(fields[6]) ?? 1
            out.append(
                ScadaDeviceRow(
                    id: id,
                    name: fields[1],
                    x: Double(fields[2]),
                    y: Double(fields[3]),
                    model: fields[4].trimmingCharacters(in: .whitespacesAndNewlines),
                    convAdd: convAdd,
                    convMul: convMul,
                    compareTitle: fields[7],
                    compareOName: fields[8],
                    diameter: fields[9],
                    elevation: fields[10],
                    kind: kind
                )
            )
            lineNumber += 1
        }
        return out
    }

    static func loadTimeSeries(url: URL) throws -> [ScadaTimeSeriesRow] {
        let text = try readText(url)
        var lines = splitLines(text)
        guard !lines.isEmpty else { return [] }
        let header = lines.removeFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizeHeaderLine(header) == normalizeHeaderLine(expectedTimeSeriesHeader) else {
            throw ScadaImportError.invalidTimeSeriesHeader(row: header)
        }
        var out: [ScadaTimeSeriesRow] = []
        var lineNumber = 2
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                lineNumber += 1
                continue
            }
            let fields = parseCSVLine(trimmed)
            guard fields.count >= 4 else {
                throw ScadaImportError.invalidTimeSeriesRow(lineNumber: lineNumber, reason: "列数不足")
            }
            let timeStr = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let t = parseMonitoringTimeString(timeStr) else {
                throw ScadaImportError.invalidTimeSeriesRow(lineNumber: lineNumber, reason: "无法解析时间：\(fields[2])")
            }
            guard let v = Double(fields[3]) else {
                throw ScadaImportError.invalidTimeSeriesRow(lineNumber: lineNumber, reason: "无法解析数值：\(fields[3])")
            }
            out.append(
                ScadaTimeSeriesRow(
                    scadaType: fields[0],
                    scadaID: fields[1].trimmingCharacters(in: .whitespacesAndNewlines),
                    time: t,
                    value: v
                )
            )
            lineNumber += 1
        }
        return out
    }

    /// 监测 CSV/TXT 前几行文本（表头与样例行），用于导入前预览。
    static func previewMonitoringFileHead(url: URL, maxLines: Int = 12) throws -> String {
        let s = try readText(url)
        let lines = s.split(whereSeparator: \.isNewline).map(String.init)
        return lines.prefix(maxLines).joined(separator: "\n")
    }

    /// 从时序行推断文件中采样间隔（秒）：对**全局唯一时刻**升序后取相邻间隔的中位数；时刻少于 2 个则返回 `nil`。
    static func inferMedianTimeStepSeconds(from rows: [ScadaTimeSeriesRow]) -> Int? {
        let uniqueSeconds = Set(rows.map { Int($0.time.timeIntervalSince1970.rounded()) })
        let sorted = uniqueSeconds.sorted()
        guard sorted.count >= 2 else { return nil }
        var deltas: [Int] = []
        deltas.reserveCapacity(sorted.count - 1)
        for i in 1..<sorted.count {
            let d = sorted[i] - sorted[i - 1]
            if d > 0 { deltas.append(d) }
        }
        guard !deltas.isEmpty else { return nil }
        let ds = deltas.sorted()
        return ds[ds.count / 2]
    }

    /// 先读二进制再解码：支持 UTF-8、带 BOM 的 UTF-8/UTF-16，以及简体中文 CSV 常见的 GB18030 / GBK（Excel 等导出常非 UTF-8）。
    private static func readText(_ url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ScadaImportError.cannotRead(url)
        }
        if data.isEmpty { return "" }
        if let s = decodeTextData(data) {
            return s
        }
        throw ScadaImportError.cannotRead(url)
    }

    /// 依次尝试多种编码，全部失败则返回 `nil`。
    private static func decodeTextData(_ data: Data) -> String? {
        // UTF-8 BOM
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            if let s = String(data: data.dropFirst(3), encoding: .utf8) { return s }
        }
        if let s = String(data: data, encoding: .utf8) { return s }

        // UTF-16 BOM
        if data.count >= 2 {
            if data[0] == 0xFF, data[1] == 0xFE, let s = String(data: data, encoding: .utf16LittleEndian) { return s }
            if data[0] == 0xFE, data[1] == 0xFF, let s = String(data: data, encoding: .utf16BigEndian) { return s }
        }

        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        )
        if let s = String(data: data, encoding: gb18030) { return s }

        let gbk = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GBK_95.rawValue))
        )
        if let s = String(data: data, encoding: gbk) { return s }

        return nil
    }

    private static func splitLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map(String.init)
    }

    private static func normalizeHeaderLine(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{feff}", with: "")
    }

    private static func timeSeriesDateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }

    /// 解析监测时序 `time` 列：支持 `yyyy-MM-dd HH:mm:ss`、ISO8601 等。
    static func parseMonitoringTimeString(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if let d = timeSeriesDateFormatter().date(from: s) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let f2 = DateFormatter()
        f2.locale = Locale(identifier: "en_US_POSIX")
        f2.timeZone = .current
        f2.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return f2.date(from: s)
    }

    /// 简单 CSV 行解析：支持双引号包裹字段。
    static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        current.reserveCapacity(line.count)
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
                continue
            }
            if ch == ",", !inQuotes {
                result.append(current)
                current = ""
                continue
            }
            current.append(ch)
        }
        result.append(current)
        return result
    }
}
