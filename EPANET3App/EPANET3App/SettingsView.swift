import SwiftUI
import EPANET3Bridge

public struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var toolbarTab: SettingsToolbarTab = .hydraulic

    public init() {}

    public var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            SettingsLightTopToolbar(selection: $toolbarTab)
            Group {
                switch toolbarTab {
                case .units:
                    SettingsUnitsPane(appState: appState)
                case .hydraulic:
                    SettingsHydraulicPane(appState: appState)
                case .simulation:
                    SettingsSimulationPane(appState: appState)
                case .display:
                    SettingsDisplayPane()
                case .general:
                    SettingsGeneralPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DesignColors.lightBg)
        .frame(minWidth: 720, minHeight: 480)
        .preferredColorScheme(.light)
        #else
        EmptyView()
        #endif
    }
}

#if os(macOS)

// MARK: - 顶部工具栏 Tab 枚举

private enum SettingsToolbarTab: Int, CaseIterable, Identifiable {
    case units, hydraulic, simulation, display, general

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .units: return "单位"
        case .hydraulic: return "水力"
        case .simulation: return "计算"
        case .display: return "显示"
        case .general: return "通用"
        }
    }

    var symbolName: String {
        switch self {
        case .units: return "square.grid.2x2"
        case .hydraulic: return "point.topleft.down.curvedto.point.bottomright.up"
        case .simulation: return "clock"
        case .display: return "display"
        case .general: return "gearshape"
        }
    }

    var accentBackground: Color {
        switch self {
        case .units: return DesignColors.lightAccent.opacity(0.12)
        case .hydraulic: return DesignColors.lightSuccess.opacity(0.12)
        case .simulation: return DesignColors.lightWarn.opacity(0.12)
        case .display: return kPurple.opacity(0.1)
        case .general: return DesignColors.lightDanger.opacity(0.1)
        }
    }

    var accentForeground: Color {
        switch self {
        case .units: return DesignColors.lightAccent
        case .hydraulic: return DesignColors.lightSuccess
        case .simulation: return DesignColors.lightWarn
        case .display: return kPurple
        case .general: return DesignColors.lightDanger
        }
    }
}

private let kPurple = Color(red: 109 / 255, green: 40 / 255, blue: 217 / 255)

// MARK: - 顶部图标工具栏

private struct SettingsLightTopToolbar: View {
    @Binding var selection: SettingsToolbarTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SettingsToolbarTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(tab == selection ? tab.accentBackground : Color.clear)
                                .frame(width: 28, height: 28)
                            Image(systemName: tab.symbolName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(tab == selection ? tab.accentForeground : DesignColors.lightText3)
                        }
                        Text(tab.title)
                            .font(.system(size: 11))
                            .foregroundColor(tab == selection ? DesignColors.lightAccent : DesignColors.lightText3)
                            .fontWeight(tab == selection ? .medium : .regular)
                    }
                    .frame(minWidth: 72)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(tab == selection ? DesignColors.lightAccent.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 250 / 255, green: 249 / 255, blue: 245 / 255),
                    Color(red: 242 / 255, green: 241 / 255, blue: 235 / 255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignColors.lightBorder).frame(height: 1)
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - ① 单位页
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct SettingsUnitsPane: View {
    @ObservedObject var appState: AppState
    @State private var flowUnitsChoice = "GPM"
    @State private var message: String?
    @State private var isError = false

    private var isUS: Bool {
        InpOptionsParser.isUSCustomary(flowUnits: flowUnitsChoice)
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    paneTitle("单位与流量")

                    sectionLabel("流量单位")
                    SettingsFormRow(label: "Flow Units", subtitle: "切换后将重载当前 .inp") {
                        Picker("", selection: $flowUnitsChoice) {
                            Text("GPM").tag("GPM")
                            Text("LPS").tag("LPS")
                            Text("MLD").tag("MLD")
                            Text("CMH").tag("CMH")
                            Text("CFS").tag("CFS")
                            Text("MGD").tag("MGD")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 320)
                    }
                    SettingsFormRow(label: "应用", subtitle: nil) {
                        Button("应用 Flow Units 切换（重载）") { switchFlowUnits() }
                            .buttonStyle(SettingsPrimaryButtonStyle())
                    }

                    sectionLabel("派生单位（只读，随 Flow Units 自动变化）")
                    unitInfoRow("单位制", isUS ? "US Customary" : "SI (国际单位)")
                    unitInfoRow("压力单位", isUS ? "psi" : "m（水头）")
                    unitInfoRow("长度单位", isUS ? "ft" : "m")
                    unitInfoRow("管径单位", isUS ? "in" : "mm")
                    unitInfoRow("流速单位", isUS ? "ft/s" : "m/s")
                    unitInfoRow("水头/高程单位", isUS ? "ft" : "m")
                    unitInfoRow("粗糙度单位", "随摩阻公式（H-W: C 系数；D-W: mm/ft；C-M: 无量纲）")

                    if let message {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundColor(isError ? DesignColors.lightDanger : DesignColors.lightSuccess)
                            .padding(.top, 16)
                            .padding(.horizontal, 28)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .background(DesignColors.lightSurface)

            if appState.project == nil { noProjectOverlay() }
        }
        .onAppear { syncFromAppState() }
        .onChange(of: appState.inpFlowUnits) { _ in syncFromAppState() }
    }

    private func syncFromAppState() {
        let fu = appState.inpFlowUnits?.uppercased() ?? "GPM"
        if ["GPM", "LPS", "MLD", "CMH", "CFS", "MGD"].contains(fu) {
            flowUnitsChoice = fu
        }
    }

    private func switchFlowUnits() {
        appState.switchFlowUnitsReload(targetFlowUnits: flowUnitsChoice)
        if let err = appState.errorMessage, err.contains("切换 Flow Units 失败") {
            message = err; isError = true
        } else {
            message = "Flow Units 已切换为 \(flowUnitsChoice)（重载完成）。"
            isError = false
        }
    }

    private func unitInfoRow(_ label: String, _ value: String) -> some View {
        SettingsFormRow(label: label, subtitle: nil) {
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(DesignColors.lightText2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DesignColors.lightSurface2)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(DesignColors.lightBorder, lineWidth: 1))
                .cornerRadius(4)
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - ② 水力页
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private enum HydraulicSection: String, CaseIterable {
    case convergence = "收敛控制"
    case demand = "需水量模型"
    case fluid = "流体属性"
}

private struct SettingsHydraulicPane: View {
    @ObservedObject var appState: AppState
    @State private var section: HydraulicSection = .convergence

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            settingsSidebar(
                sections: [
                    SidebarGroup(title: "水力参数", items: [
                        SidebarItem(id: HydraulicSection.convergence.rawValue,
                                    label: "收敛控制", dotColor: DesignColors.lightSuccess,
                                    isActive: section == .convergence),
                        SidebarItem(id: HydraulicSection.demand.rawValue,
                                    label: "需水量模型", dotColor: DesignColors.lightSuccess,
                                    isActive: section == .demand),
                        SidebarItem(id: HydraulicSection.fluid.rawValue,
                                    label: "流体属性", dotColor: DesignColors.lightSuccess,
                                    isActive: section == .fluid),
                    ])
                ],
                onSelect: { id in
                    if let s = HydraulicSection(rawValue: id) { section = s }
                }
            )
            HydraulicContentView(appState: appState, section: section)
        }
    }
}

private struct HydraulicContentView: View {
    @ObservedObject var appState: AppState
    let section: HydraulicSection

    @State private var accuracyText = ""
    @State private var hydTolText = ""
    @State private var trialsText = ""
    @State private var demandMultText = ""
    @State private var minPressureText = ""
    @State private var maxPressureText = ""
    @State private var pressExponText = ""
    @State private var emitExponText = ""
    @State private var qualTolText = ""
    @State private var message: String?
    @State private var isError = false
    @State private var parsedHeadloss: String = "—"

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        paneTitle("水力参数")
                        switch section {
                        case .convergence:
                            convergenceSection
                        case .demand:
                            demandSection
                        case .fluid:
                            fluidSection
                        }
                        if let message {
                            messageLabel(message, isError: isError)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                }
                .background(DesignColors.lightSurface)

                if appState.project == nil { noProjectOverlay() }
            }

            settingsBottomBar {
                Button("刷新参数") { loadValues() }
                    .buttonStyle(SettingsSecondaryButtonStyle())
                Button("保存参数") { saveValues() }
                    .buttonStyle(SettingsPrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadValues() }
    }

    // MARK: 收敛控制

    private var convergenceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("摩阻公式")
            SettingsFormRow(label: "水头损失计算公式", subtitle: "影响管道粗糙度输入单位及含义") {
                Text(parsedHeadloss)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(DesignColors.lightText2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DesignColors.lightSurface2)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignColors.lightBorder, lineWidth: 1))
                    .cornerRadius(6)
            }

            sectionLabel("收敛控制")
            SettingsFormRow(label: "流量收敛精度", subtitle: "各管段流量残差上限 (ACCURACY)") {
                SettingsTextField(text: $accuracyText)
            }
            SettingsFormRow(label: "水头收敛精度", subtitle: "各节点水头残差上限 (HEAD_TOLERANCE)") {
                SettingsTextField(text: $hydTolText)
            }
            SettingsFormRow(label: "最大迭代次数", subtitle: "超限视为不收敛 (MAX_TRIALS)") {
                SettingsTextField(text: $trialsText)
            }
        }
    }

    // MARK: 需水量模型

    private var demandSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("需水量模型")
            SettingsFormRow(label: "需水乘数", subtitle: "全局需水量倍率 (DEMAND_MULTIPLIER)") {
                SettingsTextField(text: $demandMultText)
            }
            SettingsFormRow(label: "最小服务压力 (PDA)", subtitle: "低于此值需水量为 0 (MINIMUM_PRESSURE)") {
                HStack(spacing: 6) {
                    SettingsTextField(text: $minPressureText)
                    unitTag("m")
                }
            }
            SettingsFormRow(label: "设计服务压力 (PDA)", subtitle: "高于此值需水量完全满足 (SERVICE_PRESSURE)") {
                HStack(spacing: 6) {
                    SettingsTextField(text: $maxPressureText)
                    unitTag("m")
                }
            }
            SettingsFormRow(label: "压力指数 (PDA)", subtitle: "PDA 计算指数 (PRESSURE_EXPONENT)") {
                SettingsTextField(text: $pressExponText)
            }
            paneNote("PDA 模式下启用压力驱动需水量分配，适用于供水不足场景分析。最小/设计服务压力参数仅在 PDA 模式下生效。")
        }
    }

    // MARK: 流体属性

    private var fluidSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("流体与发射")
            SettingsFormRow(label: "发射器指数", subtitle: "发射器流量公式指数 (EMITTER_EXPONENT)") {
                SettingsTextField(text: $emitExponText)
            }
            SettingsFormRow(label: "水质容差", subtitle: "水质求解收敛容差 (QUAL_TOLERANCE)") {
                SettingsTextField(text: $qualTolText)
            }
            paneNote("动力粘度修正系数和扩散系数需在 .inp 文件 [OPTIONS] 中直接设置（VISCOSITY / DIFFUSIVITY），引擎接口暂未开放运行时修改。")
        }
    }

    private func loadValues() {
        guard let project = appState.project else { return }
        do {
            accuracyText = formatDouble(try project.getOption(param: .accuracy))
            hydTolText = formatDouble(try project.getOption(param: .hydTol))
            trialsText = "\(Int(try project.getOption(param: .trials)))"
            demandMultText = formatDouble(try project.getOption(param: .demandMult))
            minPressureText = formatDouble(try project.getOption(param: .minPressure))
            maxPressureText = formatDouble(try project.getOption(param: .maxPressure))
            pressExponText = formatDouble(try project.getOption(param: .pressExpon))
            emitExponText = formatDouble(try project.getOption(param: .emitExpon))
            qualTolText = formatDouble(try project.getOption(param: .qualTol))
            message = nil; isError = false
        } catch {
            message = "读取水力参数失败: \(error)"; isError = true
        }
        if let path = appState.filePath {
            let hl = InpOptionsParser.parseHeadloss(path: path)
            switch hl {
            case "H-W": parsedHeadloss = "Hazen-Williams"
            case "D-W": parsedHeadloss = "Darcy-Weisbach"
            case "C-M": parsedHeadloss = "Chezy-Manning"
            default: parsedHeadloss = hl ?? "Hazen-Williams"
            }
        }
    }

    private func saveValues() {
        guard let project = appState.project,
              let accuracy = Double(accuracyText),
              let hydTol = Double(hydTolText),
              let trials = Int(trialsText),
              let demandMult = Double(demandMultText),
              let minP = Double(minPressureText),
              let maxP = Double(maxPressureText),
              let pressExp = Double(pressExponText),
              let emitExp = Double(emitExponText),
              let qualTol = Double(qualTolText) else {
            message = "保存失败: 请填写合法数字。"; isError = true
            return
        }
        appState.applyProjectMutation(sceneLabel: "更新水力参数") { _ in
            try project.setOption(param: .accuracy, value: accuracy)
            try project.setOption(param: .hydTol, value: hydTol)
            try project.setOption(param: .trials, value: Double(trials))
            try project.setOption(param: .demandMult, value: demandMult)
            try project.setOption(param: .minPressure, value: minP)
            try project.setOption(param: .maxPressure, value: maxP)
            try project.setOption(param: .pressExpon, value: pressExp)
            try project.setOption(param: .emitExpon, value: emitExp)
            try project.setOption(param: .qualTol, value: qualTol)
        }
        if let err = appState.errorMessage, err.contains("更新水力参数失败") {
            message = err; isError = true
        } else {
            loadValues()
            message = "水力参数已保存。"; isError = false
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - ③ 计算页
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private enum SimulationSection: String, CaseIterable {
    case timeSteps = "时间步长"
    case quality = "水质参数"
}

private struct SettingsSimulationPane: View {
    @ObservedObject var appState: AppState
    @State private var section: SimulationSection = .timeSteps

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            settingsSidebar(
                sections: [
                    SidebarGroup(title: "模拟设置", items: [
                        SidebarItem(id: SimulationSection.timeSteps.rawValue,
                                    label: "模拟时长与步长", dotColor: DesignColors.lightWarn,
                                    isActive: section == .timeSteps),
                    ]),
                    SidebarGroup(title: "水质", items: [
                        SidebarItem(id: SimulationSection.quality.rawValue,
                                    label: "水质参数", dotColor: DesignColors.lightAccent,
                                    isActive: section == .quality),
                    ]),
                ],
                onSelect: { id in
                    if let s = SimulationSection(rawValue: id) { section = s }
                }
            )
            SimulationContentView(appState: appState, section: section)
        }
    }
}

private struct SimulationContentView: View {
    @ObservedObject var appState: AppState
    let section: SimulationSection

    @State private var durationH = ""
    @State private var hydStepH = ""
    @State private var qualStepMin = ""
    @State private var reportStepH = ""
    @State private var reportStartH = ""
    @State private var patternStepH = ""
    @State private var patternStartH = ""
    @State private var ruleStepH = ""
    @State private var qualTolText = ""
    @State private var parsedQuality = "—"
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        paneTitle("计算参数")
                        switch section {
                        case .timeSteps:
                            timeStepsSection
                        case .quality:
                            qualitySection
                        }
                        if let message {
                            messageLabel(message, isError: isError)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                }
                .background(DesignColors.lightSurface)

                if appState.project == nil { noProjectOverlay() }
            }

            settingsBottomBar {
                Button("刷新参数") { loadValues() }
                    .buttonStyle(SettingsSecondaryButtonStyle())
                Button("保存参数") { saveValues() }
                    .buttonStyle(SettingsPrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadValues() }
    }

    private var timeStepsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("模拟时长")
            SettingsFormRow(label: "模拟总时长", subtitle: "TOTAL_DURATION，0 = 稳态") {
                HStack(spacing: 6) { SettingsTextField(text: $durationH); unitTag("h") }
            }
            SettingsFormRow(label: "水力计算步长", subtitle: "HYD_STEP") {
                HStack(spacing: 6) { SettingsTextField(text: $hydStepH); unitTag("h") }
            }
            SettingsFormRow(label: "水质计算步长", subtitle: "QUAL_STEP") {
                HStack(spacing: 6) { SettingsTextField(text: $qualStepMin); unitTag("min") }
            }
            SettingsFormRow(label: "报告输出步长", subtitle: "REPORT_STEP") {
                HStack(spacing: 6) { SettingsTextField(text: $reportStepH); unitTag("h") }
            }
            SettingsFormRow(label: "报告起始时间", subtitle: "跳过初始预热期 (REPORT_START)") {
                HStack(spacing: 6) { SettingsTextField(text: $reportStartH); unitTag("h") }
            }

            sectionLabel("模式与规则")
            SettingsFormRow(label: "模式步长", subtitle: "PATTERN_STEP") {
                HStack(spacing: 6) { SettingsTextField(text: $patternStepH); unitTag("h") }
            }
            SettingsFormRow(label: "模式起始时间", subtitle: "PATTERN_START") {
                HStack(spacing: 6) { SettingsTextField(text: $patternStartH); unitTag("h") }
            }
            SettingsFormRow(label: "规则步长", subtitle: "RULE_STEP") {
                HStack(spacing: 6) { SettingsTextField(text: $ruleStepH); unitTag("h") }
            }
            paneNote("当模拟总时长为 0 时为稳态模式（单次平衡计算），以上时间参数不生效。设为 > 0 的值启用时变扩展周期（EPS）模拟。")
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("水质模拟")
            SettingsFormRow(label: "水质分析类型", subtitle: "从 .inp [OPTIONS] QUALITY 解析") {
                Text(parsedQuality)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(DesignColors.lightText2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DesignColors.lightSurface2)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignColors.lightBorder, lineWidth: 1))
                    .cornerRadius(6)
            }
            SettingsFormRow(label: "水质容差", subtitle: "QUAL_TOLERANCE") {
                SettingsTextField(text: $qualTolText)
            }
            paneNote("水质分析类型（无/氯消毒/水龄/示踪剂）需在 .inp 文件 [OPTIONS] 中直接设置 QUALITY 参数，引擎接口暂未开放运行时修改。总体衰减系数（BULK_COEFF）和管壁反应系数同理。")
        }
    }

    private func loadValues() {
        guard let project = appState.project else { return }
        do {
            let dur = try project.getTimeParam(param: .duration)
            let hyd = try project.getTimeParam(param: .hydStep)
            let qual = try project.getTimeParam(param: .qualStep)
            let rep = try project.getTimeParam(param: .reportStep)
            let repStart = try project.getTimeParam(param: .reportStart)
            let pat = try project.getTimeParam(param: .patternStep)
            let patStart = try project.getTimeParam(param: .patternStart)
            let rule = try project.getTimeParam(param: .ruleStep)

            durationH = secToH(dur)
            hydStepH = secToH(hyd)
            qualStepMin = secToMin(qual)
            reportStepH = secToH(rep)
            reportStartH = secToH(repStart)
            patternStepH = secToH(pat)
            patternStartH = secToH(patStart)
            ruleStepH = secToH(rule)

            qualTolText = formatDouble(try project.getOption(param: .qualTol))
            message = nil; isError = false
        } catch {
            message = "读取计算参数失败: \(error)"; isError = true
        }
        if let path = appState.filePath {
            let q = InpOptionsParser.parseQualityType(path: path)
            switch q {
            case "NONE", nil: parsedQuality = "无（仅水力）"
            case "CHEMICAL": parsedQuality = "化学物质"
            case "AGE": parsedQuality = "水龄"
            case "TRACE": parsedQuality = "示踪剂"
            default: parsedQuality = q ?? "无"
            }
        }
    }

    private func saveValues() {
        guard let project = appState.project else {
            message = "保存失败: 无项目。"; isError = true; return
        }
        guard let durSec = hToSec(durationH),
              let hydSec = hToSec(hydStepH),
              let qualSec = minToSec(qualStepMin),
              let repSec = hToSec(reportStepH),
              let repStartSec = hToSec(reportStartH),
              let patSec = hToSec(patternStepH),
              let patStartSec = hToSec(patternStartH),
              let ruleSec = hToSec(ruleStepH),
              let qualTol = Double(qualTolText) else {
            message = "保存失败: 请填写合法数字。"; isError = true
            return
        }
        appState.applyProjectMutation(sceneLabel: "更新计算参数") { _ in
            try project.setTimeParam(param: .duration, value: durSec)
            try project.setTimeParam(param: .hydStep, value: hydSec)
            try project.setTimeParam(param: .qualStep, value: qualSec)
            try project.setTimeParam(param: .reportStep, value: repSec)
            try project.setTimeParam(param: .reportStart, value: repStartSec)
            try project.setTimeParam(param: .patternStep, value: patSec)
            try project.setTimeParam(param: .patternStart, value: patStartSec)
            try project.setTimeParam(param: .ruleStep, value: ruleSec)
            try project.setOption(param: .qualTol, value: qualTol)
        }
        if let err = appState.errorMessage, err.contains("更新计算参数失败") {
            message = err; isError = true
        } else {
            loadValues()
            message = "计算参数已保存。"; isError = false
        }
    }

    private func secToH(_ sec: Int) -> String {
        let h = Double(sec) / 3600.0
        if h == Double(Int(h)) { return "\(Int(h))" }
        return String(format: "%.2f", h)
    }
    private func secToMin(_ sec: Int) -> String {
        let m = Double(sec) / 60.0
        if m == Double(Int(m)) { return "\(Int(m))" }
        return String(format: "%.2f", m)
    }
    private func hToSec(_ text: String) -> Int? {
        guard let h = Double(text) else { return nil }
        return Int(h * 3600)
    }
    private func minToSec(_ text: String) -> Int? {
        guard let m = Double(text) else { return nil }
        return Int(m * 60)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - ④ 显示页
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private enum DisplaySection: String, CaseIterable {
    case colorSize = "颜色 / 尺寸"
    case legend = "图例色带"
    case label = "标注设置"
}

private struct SettingsDisplayPane: View {
    @State private var section: DisplaySection = .colorSize

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            settingsSidebar(
                sections: [
                    SidebarGroup(title: "对象样式", items: [
                        SidebarItem(id: DisplaySection.colorSize.rawValue,
                                    label: "颜色 / 尺寸", dotColor: kPurple,
                                    isActive: section == .colorSize),
                        SidebarItem(id: DisplaySection.label.rawValue,
                                    label: "标注设置", dotColor: kPurple,
                                    isActive: section == .label),
                    ]),
                    SidebarGroup(title: "图例", items: [
                        SidebarItem(id: DisplaySection.legend.rawValue,
                                    label: "结果色带", dotColor: DesignColors.lightAccent,
                                    isActive: section == .legend),
                    ]),
                ],
                onSelect: { id in
                    if let s = DisplaySection(rawValue: id) { section = s }
                }
            )
            DisplayContentView(section: section)
        }
    }
}

private struct DisplayContentView: View {
    let section: DisplaySection

    @AppStorage("settings.display.nodeSize") private var nodeSize = 6
    @AppStorage("settings.display.lineWidth") private var lineWidth = 2
    @AppStorage("settings.display.proportionalWidth") private var proportionalWidth = false
    @AppStorage("settings.display.legendSegments") private var legendSegments = 5
    @AppStorage("settings.display.legendRangeAuto") private var legendRangeAuto = true
    @AppStorage("settings.display.legendScheme") private var legendScheme = 0
    @AppStorage("settings.display.labelFontSize") private var labelFontSize = 10
    @AppStorage("settings.display.labelShowID") private var labelShowID = true
    @AppStorage("settings.display.labelShowPressure") private var labelShowPressure = false
    @AppStorage("settings.display.labelShowDemand") private var labelShowDemand = false
    @AppStorage("settings.display.labelShowElevation") private var labelShowElevation = false

    private let legendSchemes = ["蓝 → 绿 → 黄 → 红", "灰度", "蓝 → 红", "绿 → 红"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                paneTitle("显示设置")
                switch section {
                case .colorSize:
                    colorSizeSection
                case .legend:
                    legendSection
                case .label:
                    labelSection
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .background(DesignColors.lightSurface)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var colorSizeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("节点颜色（默认）")
            SettingsFormRow(label: "节点默认颜色", subtitle: "Junction · Tank · Reservoir") {
                HStack(spacing: 8) {
                    colorDot("J", .blue)
                    colorDot("T", .green)
                    colorDot("R", .purple)
                }
            }
            SettingsFormRow(label: "管段默认颜色", subtitle: "Pipe · Valve · Pump") {
                HStack(spacing: 8) {
                    colorDot("P", .gray)
                    colorDot("V", .orange)
                    colorDot("Pm", .red)
                }
            }

            sectionLabel("尺寸")
            SettingsFormRow(label: "节点显示尺寸", subtitle: "画布像素，跟随缩放比例") {
                HStack(spacing: 6) {
                    stepperView(value: $nodeSize, range: 1...20)
                    unitTag("px")
                }
            }
            SettingsFormRow(label: "管段线宽", subtitle: nil) {
                HStack(spacing: 6) {
                    stepperView(value: $lineWidth, range: 1...8)
                    unitTag("px")
                }
            }
            SettingsFormRow(label: "按管径比例显示线宽", subtitle: "管径越大，管段越粗") {
                Toggle("", isOn: $proportionalWidth)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }

    private var legendSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("图例色带")
            SettingsFormRow(label: "预设配色方案", subtitle: nil) {
                Picker("", selection: $legendScheme) {
                    ForEach(0..<legendSchemes.count, id: \.self) { i in
                        Text(legendSchemes[i]).tag(i)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            SettingsFormRow(label: "分段数", subtitle: nil) {
                stepperView(value: $legendSegments, range: 3...10)
            }
            SettingsFormRow(label: "值域范围", subtitle: "自动取结果最小/最大值") {
                Picker("", selection: $legendRangeAuto) {
                    Text("自动").tag(true)
                    Text("手动").tag(false)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
        }
    }

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("标注设置")
            SettingsFormRow(label: "标注字号", subtitle: "8 – 18 pt") {
                HStack(spacing: 6) {
                    stepperView(value: $labelFontSize, range: 8...18)
                    unitTag("pt")
                }
            }

            sectionLabel("标注内容（多选）")
            SettingsFormRow(label: "显示 ID", subtitle: nil) {
                Toggle("", isOn: $labelShowID).toggleStyle(.switch).labelsHidden()
            }
            SettingsFormRow(label: "显示压力", subtitle: nil) {
                Toggle("", isOn: $labelShowPressure).toggleStyle(.switch).labelsHidden()
            }
            SettingsFormRow(label: "显示需水量", subtitle: nil) {
                Toggle("", isOn: $labelShowDemand).toggleStyle(.switch).labelsHidden()
            }
            SettingsFormRow(label: "显示高程", subtitle: nil) {
                Toggle("", isOn: $labelShowElevation).toggleStyle(.switch).labelsHidden()
            }
            paneNote("标注仅在缩放 > 50% 时自动显示。")
        }
    }

    private func colorDot(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(DesignColors.lightText3)
            RoundedRectangle(cornerRadius: 5)
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(DesignColors.lightBorder, lineWidth: 1))
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - ⑤ 通用页
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct SettingsGeneralPane: View {
    @AppStorage("settings.general.theme") private var theme = "system"
    @AppStorage("settings.general.autoSave") private var autoSave = true
    @AppStorage("settings.general.autoSaveInterval") private var autoSaveInterval = 5
    @AppStorage("settings.general.defaultTemplate") private var defaultTemplate = "空白"
    @AppStorage("settings.general.recentFileCount") private var recentFileCount = 10
    @State private var showResetConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                paneTitle("通用设置")

                sectionLabel("外观")
                SettingsFormRow(label: "外观主题", subtitle: nil) {
                    Picker("", selection: $theme) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                sectionLabel("自动保存")
                SettingsFormRow(label: "自动保存", subtitle: nil) {
                    Toggle("", isOn: $autoSave).toggleStyle(.switch).labelsHidden()
                }
                SettingsFormRow(label: "保存间隔", subtitle: nil) {
                    Picker("", selection: $autoSaveInterval) {
                        Text("1 min").tag(1)
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    .disabled(!autoSave)
                    .opacity(autoSave ? 1 : 0.4)
                }

                sectionLabel("项目")
                SettingsFormRow(label: "新建项目默认模板", subtitle: nil) {
                    Picker("", selection: $defaultTemplate) {
                        Text("空白").tag("空白")
                        Text("SI 标准").tag("SI 标准")
                        Text("US 标准").tag("US 标准")
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                SettingsFormRow(label: "最近文件数量", subtitle: nil) {
                    stepperView(value: $recentFileCount, range: 5...20)
                }

                sectionLabel("重置")
                SettingsFormRow(label: "恢复出厂默认设置", subtitle: "重置全部显示与通用设置为默认值，不影响已保存的 .inp 文件") {
                    Button("重置所有设置…") { showResetConfirm = true }
                        .buttonStyle(SettingsDangerButtonStyle())
                        .alert("确认重置", isPresented: $showResetConfirm) {
                            Button("取消", role: .cancel) {}
                            Button("重置", role: .destructive) { resetAllSettings() }
                        } message: {
                            Text("将恢复所有显示与通用设置为默认值。此操作不可撤销。")
                        }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .background(DesignColors.lightSurface)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resetAllSettings() {
        let keysToRemove = [
            "settings.display.nodeSize", "settings.display.lineWidth",
            "settings.display.proportionalWidth", "settings.display.legendSegments",
            "settings.display.legendRangeAuto", "settings.display.legendScheme",
            "settings.display.labelFontSize", "settings.display.labelShowID",
            "settings.display.labelShowPressure", "settings.display.labelShowDemand",
            "settings.display.labelShowElevation",
            "settings.general.theme", "settings.general.autoSave",
            "settings.general.autoSaveInterval", "settings.general.defaultTemplate",
            "settings.general.recentFileCount",
        ]
        for key in keysToRemove {
            UserDefaults.standard.removeObject(forKey: key)
        }
        theme = "system"
        autoSave = true
        autoSaveInterval = 5
        defaultTemplate = "空白"
        recentFileCount = 10
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 通用侧边栏
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct SidebarItem: Identifiable {
    let id: String
    let label: String
    let dotColor: Color
    let isActive: Bool
}

private struct SidebarGroup: Identifiable {
    let title: String
    let items: [SidebarItem]
    var id: String { title }
}

private func settingsSidebar(
    sections: [SidebarGroup],
    onSelect: @escaping (String) -> Void
) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        ForEach(sections) { group in
            Text(group.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DesignColors.lightText3)
                .tracking(0.6)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(group.items) { item in
                Button { onSelect(item.id) } label: {
                    HStack(spacing: 9) {
                        Circle().fill(item.dotColor).frame(width: 8, height: 8)
                        Text(item.label)
                            .font(.system(size: 13))
                            .foregroundColor(item.isActive ? DesignColors.lightText : DesignColors.lightText2)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(item.isActive ? DesignColors.lightAccent.opacity(0.08) : Color.clear)
                    .overlay(alignment: .leading) {
                        if item.isActive {
                            Rectangle().fill(DesignColors.lightAccent).frame(width: 2.5)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        Spacer(minLength: 0)
    }
    .frame(width: 180, alignment: .leading)
    .background(DesignColors.lightSurface)
    .overlay(alignment: .trailing) {
        Rectangle().fill(DesignColors.lightBorder).frame(width: 1)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 共享 UI 组件
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private func paneTitle(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 18, weight: .medium))
        .foregroundColor(DesignColors.lightText)
        .padding(.bottom, 20)
}

private func sectionLabel(_ text: String) -> some View {
    VStack(spacing: 0) {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(DesignColors.lightText3)
            .tracking(0.5)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DesignColors.lightBorder).frame(height: 1)
            }
    }
    .padding(.bottom, 10)
    .padding(.top, 8)
}

private func unitTag(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(DesignColors.lightText3)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(DesignColors.lightSurface2)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(DesignColors.lightBorder, lineWidth: 1))
        .cornerRadius(4)
}

private func paneNote(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11))
        .foregroundColor(DesignColors.lightText3)
        .lineSpacing(4)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignColors.lightSurface2)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(DesignColors.lightBorder, lineWidth: 1))
        .cornerRadius(7)
        .padding(.top, 10)
}

private func messageLabel(_ text: String, isError: Bool) -> some View {
    Text(text)
        .font(.system(size: 13))
        .foregroundColor(isError ? DesignColors.lightDanger : DesignColors.lightSuccess)
        .padding(.top, 16)
        .padding(.horizontal, 4)
}

private func formatDouble(_ value: Double) -> String {
    if value == Double(Int(value)) { return "\(Int(value))" }
    let s = String(format: "%.8f", value)
    var trimmed = s
    while trimmed.hasSuffix("0") && !trimmed.hasSuffix(".0") { trimmed = String(trimmed.dropLast()) }
    if trimmed.hasSuffix(".") { trimmed += "0" }
    return trimmed
}

private struct SettingsFormRow<Content: View>: View {
    let label: String
    var subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(DesignColors.lightText)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(DesignColors.lightText3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignColors.lightSurface2.opacity(0.85)).frame(height: 0.5)
        }
    }
}

private struct SettingsTextField: View {
    @Binding var text: String

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minWidth: 100, alignment: .trailing)
            .background(DesignColors.lightSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DesignColors.lightBorder, lineWidth: 1)
            )
    }
}

private func stepperView(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
    HStack(spacing: 0) {
        Button { if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1 } } label: {
            Text("−").frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .background(DesignColors.lightSurface2)

        Rectangle().fill(DesignColors.lightBorder).frame(width: 1, height: 26)

        Text("\(value.wrappedValue)")
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(DesignColors.lightText)
            .frame(minWidth: 44, alignment: .center)
            .frame(height: 26)
            .background(DesignColors.lightSurface)

        Rectangle().fill(DesignColors.lightBorder).frame(width: 1, height: 26)

        Button { if value.wrappedValue < range.upperBound { value.wrappedValue += 1 } } label: {
            Text("+").frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .background(DesignColors.lightSurface2)
    }
    .overlay(
        RoundedRectangle(cornerRadius: 6)
            .stroke(DesignColors.lightBorder, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 6))
}

private func settingsBottomBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    HStack {
        Spacer()
        content()
    }
    .padding(.horizontal, 20)
    .frame(height: 44)
    .background(
        LinearGradient(
            colors: [
                Color(red: 240 / 255, green: 239 / 255, blue: 233 / 255),
                Color(red: 233 / 255, green: 232 / 255, blue: 225 / 255)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    )
    .overlay(alignment: .top) {
        Rectangle().fill(DesignColors.lightBorder).frame(height: 1)
    }
}

private func noProjectOverlay() -> some View {
    VStack(spacing: 8) {
        Text("请先打开 .inp 文件")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(DesignColors.lightText2)
        Text("需要已加载的管网项目才能查看和修改引擎参数。")
            .font(.system(size: 12))
            .foregroundColor(DesignColors.lightText3)
            .multilineTextAlignment(.center)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DesignColors.lightSurface.opacity(0.92))
}

// MARK: - 按钮样式

private struct SettingsPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? DesignColors.lightAccent2 : DesignColors.lightAccent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DesignColors.lightAccent2, lineWidth: 1)
            )
            .shadow(color: DesignColors.lightAccent.opacity(0.25), radius: 2, y: 1)
    }
}

private struct SettingsSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundColor(DesignColors.lightText2)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? DesignColors.lightSurface2 : DesignColors.lightSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DesignColors.lightBorder, lineWidth: 1)
            )
    }
}

private struct SettingsDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundColor(DesignColors.lightDanger)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DesignColors.lightDanger.opacity(configuration.isPressed ? 0.14 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DesignColors.lightDanger.opacity(0.25), lineWidth: 1)
            )
    }
}

#endif
