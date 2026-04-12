import SwiftUI
import Charts
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

/// 侧栏「模式 / 曲线 / 控制」打开的 .inp 章节详情。
public enum InpSectionDetailKind: String, Identifiable, CaseIterable {
    case patterns
    case curves
    case controls

    public var id: String { rawValue }

    public var windowTitle: String {
        switch self {
        case .patterns: return "模式 [PATTERNS]"
        case .curves: return "曲线 [CURVES]"
        case .controls: return "控制 [CONTROLS]"
        }
    }

    /// 标题栏分段控件上的短标签（与 `windowTitle` 区分：窗口使用统一标题，由分段切换章节）。
    public var toolbarSegmentLabel: String {
        switch self {
        case .patterns: return "模式"
        case .curves: return "曲线"
        case .controls: return "控制"
        }
    }

    /// .inp 中节名（不含括号）。
    var sectionHeader: String {
        switch self {
        case .patterns: return "PATTERNS"
        case .curves: return "CURVES"
        case .controls: return "CONTROLS"
        }
    }
}

/// 从完整 .inp 文本中提取某一 `[SECTION]` 至下一 `[` 节之间的正文（保留换行）。
public enum InpSectionTextExtractor {
    public static func sectionBody(header: String, inpText: String) -> String {
        guard !inpText.isEmpty else { return "" }
        let lines = inpText.components(separatedBy: .newlines)
        let target = header.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["), let closeIdx = trimmed.firstIndex(of: "]") else {
                i += 1
                continue
            }
            let inner = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeIdx])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            if inner == target {
                var out: [String] = []
                i += 1
                while i < lines.count {
                    let nextLine = lines[i]
                    let t2 = nextLine.trimmingCharacters(in: .whitespaces)
                    if t2.hasPrefix("[") && t2.contains("]") { break }
                    out.append(nextLine)
                    i += 1
                }
                return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            i += 1
        }
        return ""
    }
}

/// 展示从当前工程 .inp 中解析出的章节原文或结构化视图。
struct InpSectionDetailView: View {
    let kind: InpSectionDetailKind
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch kind {
            case .patterns:
                patternsBody
            case .curves:
                curvesBody
            case .controls:
                controlsBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var patternsBody: some View {
        if let inp = appState.inpTextForSectionDetail() {
            let bodyText = InpSectionTextExtractor.sectionBody(header: kind.sectionHeader, inpText: inp)
            InpPatternsSectionDetailView(sectionBody: bodyText)
        } else {
            Text("无法读取 .inp 原文（请先打开文件或确保已保存路径）。")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        }
    }

    @ViewBuilder
    private var curvesBody: some View {
        if let inp = appState.inpTextForSectionDetail() {
            let bodyText = InpSectionTextExtractor.sectionBody(header: kind.sectionHeader, inpText: inp)
            InpCurvesSectionDetailView(sectionBody: bodyText)
        } else {
            Text("无法读取 .inp 原文（请先打开文件或确保已保存路径）。")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        }
    }

    @ViewBuilder
    private var controlsBody: some View {
        if let inp = appState.inpTextForSectionDetail() {
            let bodyText = InpSectionTextExtractor.sectionBody(header: kind.sectionHeader, inpText: inp)
            InpControlsSectionDetailView(sectionBody: bodyText)
        } else {
            Text("无法读取 .inp 原文（请先打开文件或确保已保存路径）。")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        }
    }
}

// MARK: - 分段：数据与曲线 | 原文

private enum InpSectionDetailTab: String, CaseIterable {
    case data = "数据与曲线"
    case raw = "原文"
}

/// 「原文」Tab：整节可能极大（如多模式 × 1440 点）。整段 `SwiftUI.Text` 会触发一次性排版导致界面卡死，故用系统文本视图承载。
private struct InpSectionRawTextPanel: View {
    let text: String

    var body: some View {
        ReadonlyMonospaceScrollText(text: text)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if os(macOS)
private struct ReadonlyMonospaceScrollText: NSViewRepresentable {
    var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.labelColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }
}
#elseif os(iOS)
private struct ReadonlyMonospaceScrollText: UIViewRepresentable {
    var text: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.backgroundColor = .clear
        tv.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textColor = .label
        tv.textContainer.widthTracksTextView = true
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }
    }
}
#else
private struct ReadonlyMonospaceScrollText: View {
    var text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif

// MARK: - 模式

private struct InpPatternsSectionDetailView: View {
    let sectionBody: String

    @State private var selectedPatternID: String = ""
    @State private var detailTab: InpSectionDetailTab = .data

    private var parsed: [InpPatternParser.ParsedPattern] {
        InpPatternParser.parse(sectionBody: sectionBody)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $detailTab) {
                ForEach(InpSectionDetailTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 8)

            switch detailTab {
            case .data:
                dataSplit
            case .raw:
                InpSectionRawTextPanel(text: rawDisplay)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { syncSelection() }
        .onChange(of: sectionBody) { _ in syncSelection() }
    }

    private var rawDisplay: String {
        if sectionBody.isEmpty {
            return "（PATTERNS 节在文件中无内容或不存在）"
        }
        return sectionBody
    }

    private func syncSelection() {
        let list = parsed
        if list.isEmpty {
            selectedPatternID = ""
            return
        }
        if !list.contains(where: { $0.id == selectedPatternID }) {
            selectedPatternID = list[0].id
        }
    }

    @ViewBuilder
    private var dataSplit: some View {
        let list = parsed
        if list.isEmpty {
            Text(sectionBody.isEmpty ? "（PATTERNS 节在文件中无内容或不存在）" : "未能从当前节解析出模式行。")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        } else {
            NavigationSplitView {
                List(selection: $selectedPatternID) {
                    Section {
                        ForEach(list) { p in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.id)
                                    .font(.body.weight(.medium))
                                Text(p.kind.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .tag(p.id)
                        }
                    } header: {
                        Text("模式")
                    }
                }
                .frame(minWidth: 200, idealWidth: 240)
            } detail: {
                Group {
                    if let p = list.first(where: { $0.id == selectedPatternID }) {
                        ScrollView {
                            PatternDetailPanel(p: p)
                                .padding(12)
                        }
                    } else {
                        InpSectionSplitPlaceholder(
                            systemImage: "waveform.path",
                            message: "请在左侧选择模式名称"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 曲线

private struct InpCurvesSectionDetailView: View {
    let sectionBody: String

    @State private var selectedCurveID: String = ""
    @State private var detailTab: InpSectionDetailTab = .data

    private var parsed: [InpCurveParser.ParsedCurve] {
        InpCurveParser.parse(sectionBody: sectionBody)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $detailTab) {
                ForEach(InpSectionDetailTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 8)

            switch detailTab {
            case .data:
                dataSplit
            case .raw:
                InpSectionRawTextPanel(text: rawDisplay)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { syncSelection() }
        .onChange(of: sectionBody) { _ in syncSelection() }
    }

    private var rawDisplay: String {
        if sectionBody.isEmpty {
            return "（CURVES 节在文件中无内容或不存在）"
        }
        return sectionBody
    }

    private func syncSelection() {
        let list = parsed
        if list.isEmpty {
            selectedCurveID = ""
            return
        }
        if !list.contains(where: { $0.id == selectedCurveID }) {
            selectedCurveID = list[0].id
        }
    }

    @ViewBuilder
    private var dataSplit: some View {
        let list = parsed
        if list.isEmpty {
            Text(sectionBody.isEmpty ? "（CURVES 节在文件中无内容或不存在）" : "未能从当前节解析出曲线行。")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        } else {
            NavigationSplitView {
                List(selection: $selectedCurveID) {
                    Section {
                        ForEach(list) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.id)
                                    .font(.body.weight(.medium))
                                Text(curveSubtitle(c))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .tag(c.id)
                        }
                    } header: {
                        Text("曲线")
                    }
                }
                .frame(minWidth: 200, idealWidth: 240)
            } detail: {
                Group {
                    if let c = list.first(where: { $0.id == selectedCurveID }) {
                        ScrollView {
                            CurveDetailPanel(c: c)
                                .padding(12)
                        }
                    } else {
                        InpSectionSplitPlaceholder(
                            systemImage: "chart.xyaxis.line",
                            message: "请在左侧选择曲线名称"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func curveSubtitle(_ c: InpCurveParser.ParsedCurve) -> String {
        var parts: [String] = []
        if let t = c.typeKeyword {
            parts.append(t)
        }
        if c.hasPoints {
            parts.append("\(c.points.count) 个点")
        }
        return parts.isEmpty ? "（仅类型声明）" : parts.joined(separator: " · ")
    }
}

// MARK: - 控制（每条一行，无命名 ID）

private struct InpControlsSectionDetailView: View {
    let sectionBody: String

    @State private var selectedRowIndex: Int = 0
    @State private var detailTab: InpSectionDetailTab = .data

    private var rows: [InpControlLineRow] {
        InpControlLineRow.parse(sectionBody: sectionBody)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $detailTab) {
                ForEach(InpSectionDetailTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 8)

            switch detailTab {
            case .data:
                dataSplit
            case .raw:
                InpSectionRawTextPanel(text: rawDisplay)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { syncSelection() }
        .onChange(of: sectionBody) { _ in syncSelection() }
    }

    private var rawDisplay: String {
        if sectionBody.isEmpty {
            return "（CONTROLS 节在文件中无内容或不存在）"
        }
        return sectionBody
    }

    private func syncSelection() {
        let r = rows
        if r.isEmpty {
            selectedRowIndex = 0
            return
        }
        if !r.contains(where: { $0.index == selectedRowIndex }) {
            selectedRowIndex = r[0].index
        }
    }

    @ViewBuilder
    private var dataSplit: some View {
        let r = rows
        if r.isEmpty {
            Text(sectionBody.isEmpty ? "（CONTROLS 节在文件中无内容或不存在）" : "本节无有效控制行。")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        } else {
            NavigationSplitView {
                List(selection: $selectedRowIndex) {
                    Section {
                        ForEach(r) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("控制 \(row.displayNumber)")
                                    .font(.body.weight(.medium))
                                Text(row.line)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            .tag(row.index)
                        }
                    } header: {
                        Text("简单控制")
                    }
                }
                .frame(minWidth: 200, idealWidth: 260)
            } detail: {
                Group {
                    if let row = r.first(where: { $0.index == selectedRowIndex }) {
                        ScrollView {
                            ControlDetailPanel(line: row.line)
                                .padding(12)
                        }
                    } else {
                        InpSectionSplitPlaceholder(
                            systemImage: "slider.horizontal.3",
                            message: "请在左侧选择一条控制"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct InpControlLineRow: Identifiable {
    let index: Int
    let line: String

    var id: Int { index }

    var displayNumber: Int { index + 1 }

    static func parse(sectionBody: String) -> [InpControlLineRow] {
        var out: [InpControlLineRow] = []
        var i = 0
        for raw in sectionBody.split(whereSeparator: \.isNewline) {
            let line = stripComment(String(raw)).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            out.append(InpControlLineRow(index: i, line: line))
            i += 1
        }
        return out
    }

    private static func stripComment(_ line: String) -> String {
        if let r = line.range(of: ";") {
            return String(line[..<r.lowerBound])
        }
        return line
    }
}

// MARK: - 模式 / 曲线图轴：整齐刻度（与主窗口时序图策略一致）

private enum InpDetailChartAxisHelpers {
    private static func niceStep(approximate: Double) -> Double {
        guard approximate.isFinite, approximate > 0 else { return 1 }
        let exp = floor(log10(approximate))
        let f = approximate / pow(10, exp)
        let nf: Double
        if f <= 1 { nf = 1 }
        else if f <= 2 { nf = 2 }
        else if f <= 2.5 { nf = 2.5 }
        else if f <= 5 { nf = 5 }
        else { nf = 10 }
        return nf * pow(10, exp)
    }

    /// 在 `domain` 内生成约 `maxTicks` 条等间隔的整齐刻度。
    static func axisTickValues(domain: ClosedRange<Double>, maxTicks: Int = 8) -> [Double] {
        let lo = domain.lowerBound
        let hi = domain.upperBound
        let span = hi - lo
        guard span > 0, span.isFinite else {
            return lo.isFinite ? [lo] : [0, 1]
        }
        let cap = max(2, maxTicks)
        var step = niceStep(approximate: span / Double(max(1, cap - 1)))
        if step <= 0 { step = span }
        for _ in 0..<10 {
            var t = floor(lo / step) * step
            while t < lo - 1e-12 * max(abs(step), 1) {
                t += step
            }
            var ticks: [Double] = []
            while t <= hi + 1e-9 * max(abs(step), 1) {
                ticks.append(t)
                t += step
                if ticks.count > 64 { break }
            }
            if ticks.count <= max(cap + 1, 3) { return ticks }
            step *= 2
        }
        return [lo, hi]
    }

    /// 模式「乘子」曲线 Y 轴：从下界 **0** 起，上界为数据最大值加少量顶边距，便于读数。
    static func patternFactorYDomainFromZero(factors: [Double]) -> ClosedRange<Double> {
        let fyHi = factors.max() ?? 1
        let span = max(fyHi, 1e-9)
        let yPadTop = max(span * 0.06, 0.01)
        let hi = fyHi + yPadTop
        return 0...max(hi, 0.01)
    }
}

/// 模式曲线图：在绘图区底层绘制 X 轴（底边水平线）与 Y 轴（左侧竖线）。
private struct PatternChartXYSpinesModifier: ViewModifier {
    let axisColor: Color

    func body(content: Content) -> some View {
        content.chartPlotStyle { plot in
            plot.background {
                ZStack(alignment: .bottomLeading) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(axisColor)
                            .frame(height: 2.25)
                    }
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(axisColor)
                            .frame(width: 2.25)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

// MARK: - 模式详情（右栏）

private struct PatternDetailPanel: View {
    let p: InpPatternParser.ParsedPattern
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    /// 与主窗口 `ResultTimeSeriesChartContent` 一致：绘图区底边（X 轴）与左侧（Y 轴）脊线颜色。
    private var patternAxisLineColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.42)
            : Color.black.opacity(0.36)
    }

    /// `[TIMES] Duration`（秒）；无工程或未设时为 0。
    private var simulationDurationSeconds: Int {
        guard let proj = appState.project,
              let d = try? proj.getTimeParam(param: .duration),
              d > 0
        else { return 0 }
        return d
    }

    private static func fixedPatternTimeX(
        _ pt: InpPatternParser.ParsedPattern.FixedChartPoint,
        useHours: Bool
    ) -> Double {
        guard let ts = pt.timeSeconds else { return Double(pt.periodIndex) }
        return useHours ? Double(ts) / 3600.0 : ts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("类型") {
                Text(p.kind.rawValue)
            }
            if let sec = p.fixedIntervalSeconds {
                LabeledContent("时间步长") {
                    Text("\(sec) 秒（\(formatSecondsShort(sec))）")
                }
            }

            if p.hasSeries {
                switch p.kind {
                case .fixed:
                    fixedTable(p)
                    patternChartFixed(p)
                case .variable:
                    variableTable(p)
                    patternChartVariable(p)
                }
            } else {
                Text("（尚无乘子数据：仅有 FIXED/VARIABLE 声明行时可继续在其他行补充数据。）")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fixedTable(_ p: InpPatternParser.ParsedPattern) -> some View {
        let pts = p.fixedChartPoints
        return Table(pts) {
            TableColumn("时段") { row in
                Text("\(row.periodIndex)")
            }
            TableColumn("时间 (s)") { row in
                if let t = row.timeSeconds {
                    Text(String(format: "%.0f", t))
                } else {
                    Text("—")
                }
            }
            TableColumn("乘子") { row in
                Text(formatDouble(row.factor))
            }
        }
        .frame(minHeight: min(CGFloat(pts.count) * 28 + 36, 220))
    }

    private func variableTable(_ p: InpPatternParser.ParsedPattern) -> some View {
        let pts = p.variableChartPoints
        return Table(pts) {
            TableColumn("时间") { row in
                Text(formatSecondsShort(row.timeSeconds))
            }
            TableColumn("时间 (h)") { row in
                Text(String(format: "%.4f", row.timeHours))
            }
            TableColumn("乘子") { row in
                Text(formatDouble(row.factor))
            }
        }
        .frame(minHeight: min(CGFloat(pts.count) * 28 + 36, 220))
    }

    private func patternChartFixed(_ p: InpPatternParser.ParsedPattern) -> some View {
        let pts = p.fixedChartPoints
        let dur = simulationDurationSeconds
        let factors = pts.map(\.factor)
        let yDomain = InpDetailChartAxisHelpers.patternFactorYDomainFromZero(factors: factors)
        let yTicks = InpDetailChartAxisHelpers.axisTickValues(domain: yDomain, maxTicks: 6)

        return VStack(alignment: .leading, spacing: 6) {
            Text("曲线")
                .font(.headline)
            if pts.first?.timeSeconds != nil {
                fixedPatternTimeAxisChart(
                    pts: pts,
                    dur: dur,
                    yDomain: yDomain,
                    yTicks: yTicks
                )
            } else {
                fixedPatternPeriodAxisChart(pts: pts, yDomain: yDomain, yTicks: yTicks)
            }
        }
    }

    /// 固定模式且已知时间步长：横轴 0…模拟总时长（与 INP Duration 一致），适度刻度；Y 轴在左侧。
    private func fixedPatternTimeAxisChart(
        pts: [InpPatternParser.ParsedPattern.FixedChartPoint],
        dur: Int,
        yDomain: ClosedRange<Double>,
        yTicks: [Double]
    ) -> some View {
        let dataMaxSec = pts.compactMap(\.timeSeconds).max() ?? 0
        let useHours = dur >= 3600 || dataMaxSec >= 3600
        let xLabel = useHours ? "时间 (h)" : "时间 (s)"
        let xMax: Double = {
            if useHours {
                let durH = dur > 0 ? Double(dur) / 3600.0 : 0
                let dmH = Double(dataMaxSec) / 3600.0
                return dur > 0 ? max(durH, dmH) : max(dmH, 1e-9)
            }
            let dm = Double(dataMaxSec)
            return dur > 0 ? max(Double(dur), dm) : max(dm, 1)
        }()
        let xDomain = 0.0...max(xMax, 1e-9)
        let xTicks = InpDetailChartAxisHelpers.axisTickValues(domain: xDomain, maxTicks: 8)
        return Chart {
            ForEach(pts) { pt in
                LineMark(
                    x: .value(xLabel, Self.fixedPatternTimeX(pt, useHours: useHours)),
                    y: .value("乘子", pt.factor)
                )
                .interpolationMethod(.linear)
                PointMark(
                    x: .value(xLabel, Self.fixedPatternTimeX(pt, useHours: useHours)),
                    y: .value("乘子", pt.factor)
                )
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: xTicks) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisTick(length: 4)
                AxisValueLabel().font(.system(size: 9, weight: .medium, design: .rounded))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yTicks) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisTick(length: 4)
                AxisValueLabel().font(.system(size: 9, weight: .medium, design: .rounded))
            }
        }
        .chartXAxisLabel(xLabel, alignment: .center)
        .chartYAxisLabel("乘子", alignment: .leading)
        .modifier(PatternChartXYSpinesModifier(axisColor: patternAxisLineColor))
        .frame(height: 240)
        .padding(.vertical, 4)
    }

    /// 固定模式无时间步长：横轴为时段序号（无法映射到总时长）。
    private func fixedPatternPeriodAxisChart(
        pts: [InpPatternParser.ParsedPattern.FixedChartPoint],
        yDomain: ClosedRange<Double>,
        yTicks: [Double]
    ) -> some View {
        let n = pts.count
        let xHi = Double(max(n, 1))
        let xDomain: ClosedRange<Double> = 0...xHi
        let xTicks = InpDetailChartAxisHelpers.axisTickValues(domain: xDomain, maxTicks: min(8, max(2, n + 1)))
        return Chart {
            ForEach(pts) { pt in
                LineMark(
                    x: .value("时段序号", Double(pt.periodIndex)),
                    y: .value("乘子", pt.factor)
                )
                .interpolationMethod(.linear)
                PointMark(
                    x: .value("时段序号", Double(pt.periodIndex)),
                    y: .value("乘子", pt.factor)
                )
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: xTicks) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisTick(length: 4)
                AxisValueLabel().font(.system(size: 9, weight: .medium, design: .rounded))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yTicks) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisTick(length: 4)
                AxisValueLabel().font(.system(size: 9, weight: .medium, design: .rounded))
            }
        }
        .chartXAxisLabel("时段序号", alignment: .center)
        .chartYAxisLabel("乘子", alignment: .leading)
        .modifier(PatternChartXYSpinesModifier(axisColor: patternAxisLineColor))
        .frame(height: 240)
        .padding(.vertical, 4)
    }

    private func patternChartVariable(_ p: InpPatternParser.ParsedPattern) -> some View {
        let pts = p.variableChartPoints
        let dur = simulationDurationSeconds
        let dataMaxH = pts.map(\.timeHours).max() ?? 0
        let durH = dur > 0 ? Double(dur) / 3600.0 : 0
        let xMax = dur > 0 ? max(durH, dataMaxH) : max(dataMaxH, 1e-9)
        let xDomain = 0.0...max(xMax, 1e-9)
        let xTicks = InpDetailChartAxisHelpers.axisTickValues(domain: xDomain, maxTicks: 8)
        let factors = pts.map(\.factor)
        let yDomain = InpDetailChartAxisHelpers.patternFactorYDomainFromZero(factors: factors)
        let yTicks = InpDetailChartAxisHelpers.axisTickValues(domain: yDomain, maxTicks: 6)

        return VStack(alignment: .leading, spacing: 6) {
            Text("曲线")
                .font(.headline)
            Chart {
                ForEach(pts) { pt in
                    LineMark(
                        x: .value("时间 (h)", pt.timeHours),
                        y: .value("乘子", pt.factor)
                    )
                    .interpolationMethod(.linear)
                    PointMark(
                        x: .value("时间 (h)", pt.timeHours),
                        y: .value("乘子", pt.factor)
                    )
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: xTicks) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisTick(length: 4)
                    AxisValueLabel().font(.system(size: 9, weight: .medium, design: .rounded))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: yTicks) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisTick(length: 4)
                    AxisValueLabel().font(.system(size: 9, weight: .medium, design: .rounded))
                }
            }
            .chartXAxisLabel("时间 (h)", alignment: .center)
            .chartYAxisLabel("乘子", alignment: .leading)
            .modifier(PatternChartXYSpinesModifier(axisColor: patternAxisLineColor))
            .frame(height: 240)
            .padding(.vertical, 4)
        }
    }

    private func formatDouble(_ x: Double) -> String {
        String(format: "%.6g", x)
    }

    private func formatSecondsShort(_ s: Int) -> String {
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return String(format: "%d:%02d:%02d", h, m, sec)
    }
}

// MARK: - 曲线详情（右栏）

private struct CurveDetailPanel: View {
    let c: InpCurveParser.ParsedCurve

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let t = c.typeKeyword {
                LabeledContent("类型") {
                    Text(t)
                }
            } else {
                LabeledContent("类型") {
                    Text("（首行即为数据点，未单独声明 PUMP 等）")
                        .foregroundStyle(.secondary)
                }
            }

            if c.hasPoints {
                curveTable(c)
                curveChart(c)
            } else {
                Text("（尚无 (X,Y) 数据点；可在类型行之后追加数据行。）")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func curveTable(_ c: InpCurveParser.ParsedCurve) -> some View {
        let pts = c.chartPoints
        return Table(pts) {
            TableColumn("X") { row in
                Text(formatDouble(row.x))
            }
            TableColumn("Y") { row in
                Text(formatDouble(row.y))
            }
        }
        .frame(minHeight: min(CGFloat(pts.count) * 28 + 36, 220))
    }

    private func curveChart(_ c: InpCurveParser.ParsedCurve) -> some View {
        let pts = c.chartPoints
        return VStack(alignment: .leading, spacing: 6) {
            Text("曲线")
                .font(.headline)
            Chart {
                ForEach(pts) { pt in
                    LineMark(
                        x: .value("X", pt.x),
                        y: .value("Y", pt.y)
                    )
                    .interpolationMethod(.linear)
                    PointMark(
                        x: .value("X", pt.x),
                        y: .value("Y", pt.y)
                    )
                }
            }
            .chartXAxisLabel("X", alignment: .center)
            .chartYAxisLabel("Y", alignment: .center)
            .frame(height: 240)
            .padding(.vertical, 4)
        }
    }

    private func formatDouble(_ x: Double) -> String {
        String(format: "%.6g", x)
    }
}

// MARK: - 控制详情（右栏：无连续曲线，展示结构化字段 + 原文）

private struct ControlDetailPanel: View {
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("简单控制为单条规则，无连续采样曲线；以下为该条规则的原文与拆分字段。")
                .font(.callout)
                .foregroundStyle(.secondary)

            LabeledContent("原文") {
                Text(line)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }

            let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if !tokens.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("词元")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(tokens.enumerated()), id: \.offset) { i, tok in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)")
                                    .frame(width: 28, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                    .font(.caption.monospacedDigit())
                                Text(tok)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct InpSectionSplitPlaceholder: View {
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
