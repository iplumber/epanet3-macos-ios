import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers

/// 侧栏右键「导入监测时序数据」：选文件 → 左侧设备列表 + 右侧 ZOH 对齐预览表格 → 确认后导入。
struct ScadaMonitoringTimeSeriesImportSheet: View {
    @ObservedObject var appState: AppState
    let kind: ScadaDeviceKind

    // MARK: - State

    @State private var fileURL: URL?
    @State private var parsedRows: [ScadaTimeSeriesRow] = []
    @State private var filteredRows: [ScadaTimeSeriesRow] = []
    @State private var deviceList: [DeviceEntry] = []
    @State private var selectedDeviceId: String?
    @State private var fileMedianStepSeconds: Int?
    @State private var parseError: String?
    @State private var headPreview: String = ""

    private var kindLabel: String { kind == .pressure ? "压力" : "流量" }

    private var inpHydraulicStepSeconds: Int? {
        guard let p = appState.project else { return nil }
        return max(1, (try? p.getTimeParam(param: .hydStep)) ?? 3600)
    }

    private var inpDurationSeconds: Int? {
        guard let p = appState.project else { return nil }
        let d = (try? p.getTimeParam(param: .duration)) ?? 0
        return d > 0 ? d : nil
    }

    // MARK: - Derived preview

    private var inpTimePoints: [Int] {
        if let ts = appState.timeSeriesResults, !ts.timePoints.isEmpty {
            return ts.timePoints
        }
        guard let dur = inpDurationSeconds, let step = inpHydraulicStepSeconds else { return [] }
        return ScadaMonitoringAlignment.discreteSimulationTimePoints(durationSeconds: dur, hydraulicStepSeconds: step)
    }

    private var previewTableRows: [PreviewRow] {
        guard let devId = selectedDeviceId else { return [] }
        let devRows = filteredRows.filter { $0.scadaID == devId }
        guard !devRows.isEmpty else { return [] }

        let calendar = Calendar.current
        guard let minDate = devRows.map(\.time).min() else { return [] }
        let dayStart = calendar.startOfDay(for: minDate)

        let catalog = appState.scadaDeviceCatalog
        let dev: ScadaDeviceRow? = switch kind {
        case .pressure: catalog?.pressureByDeviceId[devId]
        case .flow:     catalog?.flowByDeviceId[devId]
        }

        var samples: [(Int, Double)] = []
        for r in devRows {
            let sec = Int(r.time.timeIntervalSince(dayStart).rounded())
            let raw = r.value
            let cal = dev?.calibratedValue(raw) ?? raw
            samples.append((sec, cal))
        }
        let deduped = ScadaMonitoringAlignment.dedupeSameSecondSorted(samples)
        let inpPts = inpTimePoints
        let resampled = ScadaMonitoringAlignment.zohResampleToSimulationSeconds(targetSeconds: inpPts, samples: deduped)

        var result: [PreviewRow] = []
        result.reserveCapacity(inpPts.count)
        for i in 0..<inpPts.count {
            let matchIdx = deduped.lastIndex { $0.0 <= inpPts[i] }
            let srcTime: Int? = matchIdx != nil ? deduped[matchIdx!].0 : nil
            let val = i < resampled.count ? resampled[i] : .nan
            result.append(PreviewRow(
                seq: i + 1,
                inpTimeSec: inpPts[i],
                srcTimeSec: srcTime,
                value: val
            ))
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            mainContent
            Divider()
            footerBar
        }
        .frame(width: 820, height: 620)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: kind == .pressure ? "gauge.with.dots.needle.33percent" : "drop.fill")
                    .foregroundStyle(kind == .pressure ? .blue : .cyan)
                Text("导入监测时序数据")
                    .font(.system(size: 13, weight: .semibold))
                Text("（\(kindLabel)）")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("关闭") {
                appState.scadaMonitoringTimeSeriesImportPresentation = nil
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            fileSelectRow
            stepInfoBox

            if let err = parseError {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            if fileURL != nil && !deviceList.isEmpty {
                HSplitView {
                    deviceSidebar
                        .frame(minWidth: 160, idealWidth: 190, maxWidth: 240)
                    previewTable
                        .frame(minWidth: 400)
                }
                .frame(maxHeight: .infinity)
            } else if fileURL != nil && deviceList.isEmpty && parseError == nil {
                Text("文件中没有与「\(kindLabel)」匹配的设备数据。")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Spacer()
                    Text("请选择监测时序 CSV / TXT 文件")
                        .font(.callout).foregroundStyle(.tertiary)
                    Text("表头格式：scadaType, scadaID, time, value")
                        .font(.caption2).foregroundStyle(.quaternary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
    }

    // MARK: - File select

    private var fileSelectRow: some View {
        HStack(alignment: .center) {
            Text(fileURL?.lastPathComponent ?? "未选择文件")
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(fileURL == nil ? .secondary : .primary)
            Button("选择文件…") { chooseFile() }
        }
    }

    // MARK: - Step info

    private var stepInfoBox: some View {
        GroupBox {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("INP 水力步长")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let s = inpHydraulicStepSeconds {
                        Text(Self.formatStep(seconds: s))
                            .font(.caption.monospacedDigit()).fontWeight(.medium)
                    } else {
                        Text("—").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("INP 总时长")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let d = inpDurationSeconds {
                        Text(Self.formatDuration(seconds: d))
                            .font(.caption.monospacedDigit()).fontWeight(.medium)
                    } else {
                        Text("—").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("文件推断步长（中位数）")
                        .font(.caption2).foregroundStyle(.secondary)
                    if fileURL == nil {
                        Text("选择文件后计算").font(.caption).foregroundStyle(.secondary)
                    } else if let s = fileMedianStepSeconds {
                        Text(Self.formatStep(seconds: s))
                            .font(.caption.monospacedDigit()).fontWeight(.medium)
                    } else {
                        Text("无法推断").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(6)
        }
    }

    // MARK: - Left sidebar: device list

    private var deviceSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("设备列表（\(deviceList.count)）")
                .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 6) {
                Text("序号")
                    .multilineTextAlignment(.center)
                    .frame(width: 32, alignment: .center)
                Text("ID / 名称")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.leading, 4)
            List(selection: $selectedDeviceId) {
                ForEach(Array(deviceList.enumerated()), id: \.element.id) { idx, entry in
                    HStack(alignment: .center, spacing: 6) {
                        Text("\(idx + 1)")
                            .multilineTextAlignment(.center)
                            .frame(width: 32, alignment: .center)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.id)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                            if !entry.name.isEmpty && entry.name != entry.id {
                                Text(entry.name)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Text("\(entry.rowCount) 行")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 1)
                    .tag(entry.id)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
        }
    }

    // MARK: - Right: preview table

    private var previewTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let devId = selectedDeviceId {
                let devEntry = deviceList.first { $0.id == devId }
                HStack(spacing: 8) {
                    Text("设备 \(devId)")
                        .font(.caption).fontWeight(.medium)
                    if let name = devEntry?.name, !name.isEmpty, name != devId {
                        Text(name).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("ZOH 对齐预览（\(previewTableRows.count) 行）")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                Text("← 选择左侧设备查看对齐预览")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            if selectedDeviceId != nil {
                tableContent
            } else {
                Color.clear
            }
        }
    }

    private var tableContent: some View {
        let rows = previewTableRows
        return VStack(spacing: 0) {
            tableHeader
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows, id: \.seq) { row in
                        tableRow(row)
                        if row.seq < rows.count {
                            Divider().padding(.leading, 4)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 40, alignment: .trailing)
            Divider().frame(height: 14)
            Text("INP 时刻")
                .frame(width: 90, alignment: .center)
            Divider().frame(height: 14)
            Text("数据时刻")
                .frame(width: 90, alignment: .center)
            Divider().frame(height: 14)
            Text("\(kindLabel)值")
                .frame(minWidth: 80, alignment: .trailing)
            Spacer()
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(Color.secondary.opacity(0.06))
    }

    private func tableRow(_ row: PreviewRow) -> some View {
        let isZoh = row.srcTimeSec != nil && row.srcTimeSec! != row.inpTimeSec
        return HStack(spacing: 0) {
            Text("\(row.seq)")
                .frame(width: 40, alignment: .trailing)
                .foregroundStyle(.secondary)
            Divider().frame(height: 14).opacity(0.3)
            Text(Self.formatTimeHHMMSS(seconds: row.inpTimeSec))
                .frame(width: 90, alignment: .center)
            Divider().frame(height: 14).opacity(0.3)
            if let st = row.srcTimeSec {
                Text(Self.formatTimeHHMMSS(seconds: st))
                    .frame(width: 90, alignment: .center)
                    .foregroundStyle(isZoh ? .orange : .primary)
            } else {
                Text("—")
                    .frame(width: 90, alignment: .center)
                    .foregroundStyle(.tertiary)
            }
            Divider().frame(height: 14).opacity(0.3)
            if row.value.isNaN {
                Text("NaN")
                    .frame(minWidth: 80, alignment: .trailing)
                    .foregroundStyle(.tertiary)
            } else {
                Text(String(format: "%.4f", row.value))
                    .frame(minWidth: 80, alignment: .trailing)
            }
            Spacer()
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Text("确认后按仿真时间轴做零阶保持对齐（ZOH）")
                .font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Button("取消") {
                appState.scadaMonitoringTimeSeriesImportPresentation = nil
            }
            .keyboardShortcut(.cancelAction)
            Button("确认导入") {
                guard let url = fileURL else { return }
                parseError = nil
                appState.commitScadaMonitoringTimeSeriesImport(fileURL: url, kind: kind)
                if let msg = appState.errorMessage {
                    parseError = msg
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(fileURL == nil)
        }
        .padding(16)
    }

    // MARK: - File picking

    private func chooseFile() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.commaSeparatedText, .plainText]
        if let csv = UTType(filenameExtension: "csv") { types.append(csv) }
        if let txt = UTType(filenameExtension: "txt") { types.append(txt) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "选择监测时序 CSV / TXT"
        panel.message = "表头：scadaType, scadaID, time, value"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileURL = url
        parseError = nil
        fileMedianStepSeconds = nil
        deviceList = []
        selectedDeviceId = nil
        filteredRows = []
        parsedRows = []
        headPreview = ""

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            headPreview = try ScadaCSVImporter.previewMonitoringFileHead(url: url, maxLines: 12)
            let rows = try ScadaCSVImporter.loadTimeSeries(url: url)
            parsedRows = rows
            let filtered = rows.filter { row in
                switch kind {
                case .pressure: return ScadaCSVImporter.scadaRowMatchesPressureImport(row.scadaType)
                case .flow: return ScadaCSVImporter.scadaRowMatchesFlowImport(row.scadaType)
                }
            }
            filteredRows = filtered
            fileMedianStepSeconds = ScadaCSVImporter.inferMedianTimeStepSeconds(from: filtered)

            var idOrder: [String] = []
            var countById: [String: Int] = [:]
            for r in filtered {
                countById[r.scadaID, default: 0] += 1
                if countById[r.scadaID] == 1 { idOrder.append(r.scadaID) }
            }

            let catalog = appState.scadaDeviceCatalog
            deviceList = idOrder.map { devId in
                let devRow: ScadaDeviceRow? = switch kind {
                case .pressure: catalog?.pressureByDeviceId[devId]
                case .flow:     catalog?.flowByDeviceId[devId]
                }
                return DeviceEntry(
                    id: devId,
                    name: devRow?.name ?? "",
                    rowCount: countById[devId] ?? 0
                )
            }

            if filtered.isEmpty {
                parseError = "文件中没有与「\(kindLabel)」匹配的 scadaType 行。"
            } else {
                selectedDeviceId = idOrder.first
            }
        } catch {
            parseError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private static func formatStep(seconds s: Int) -> String {
        if s >= 3600, s % 3600 == 0 { return "\(s / 3600) h" }
        if s >= 60, s % 60 == 0 { return "\(s / 60) min（\(s) s）" }
        return "\(s) s"
    }

    private static func formatDuration(seconds d: Int) -> String {
        if d >= 3600, d % 3600 == 0 { return "\(d / 3600) h" }
        if d >= 60, d % 60 == 0 { return "\(d / 60) min" }
        return "\(d) s"
    }

    static func formatTimeHHMMSS(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if s == 0 {
            return String(format: "%d:%02d", h, m)
        }
        return String(format: "%d:%02d:%02d", h, m, s)
    }
}

// MARK: - Models

private struct DeviceEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let rowCount: Int
}

private struct PreviewRow {
    let seq: Int
    let inpTimeSec: Int
    let srcTimeSec: Int?
    let value: Float
}

#endif
