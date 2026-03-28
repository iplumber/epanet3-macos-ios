import SwiftUI
import EPANET3Bridge

private let kPurple = Color(red: 109 / 255, green: 40 / 255, blue: 217 / 255)

// MARK: - 顶部工具栏 Tab 枚举（rawValue 与 `AppState.settingsPendingToolbarTab` 一致）

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
        .frame(minWidth: 720, minHeight: 640)
        .preferredColorScheme(.light)
        .onAppear { consumeSettingsPendingTab() }
        .onChange(of: appState.settingsPendingToolbarTab) { _ in consumeSettingsPendingTab() }
        #else
        EmptyView()
        #endif
    }

    #if os(macOS)
    private func consumeSettingsPendingTab() {
        guard let raw = appState.settingsPendingToolbarTab,
              let tab = SettingsToolbarTab(rawValue: raw) else { return }
        toolbarTab = tab
        appState.settingsPendingToolbarTab = nil
    }
    #endif
}

#if os(macOS)

/// 与 `epanet-settings-light.html` 对齐：`.field { min-width:80px }`、`.picker { min-width:120px }`
private enum SettingsPixelLayout {
    /// 所有数值/文本输入框统一宽度（pt，约等于稿 80px 在 1x 下的视觉比例）
    static let fieldWidth: CGFloat = 88
    static let pickerMinWidth: CGFloat = 120
    static let segmentedExtraPadding: CGFloat = 8
    /// 计算参数页：单位菜单（h / min / sec）与 H:mm 共用列宽 **70 pt**
    static let simulationTrailingWidth: CGFloat = 70
    /// 与左侧 `SettingsTextField` 对齐：13pt 单行约 16pt 行高 + 上下 `padding(.vertical, 5)` 各 5 → **约 26 pt**；右侧 Picker/H:mm 与此同高
    static let simulationControlHeight: CGFloat = 26
}

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
    /// 由 .inp 解析一次写入，避免 `body` 每次重算都整文件读 HEADLOSS。
    @State private var headlossCodeFromInp = "H-W"

    @AppStorage("settings.detail.pressureUnit") private var pressureUnit = "m"
    @AppStorage("settings.detail.lengthSystem") private var lengthSystem = "SI" // SI | US
    @AppStorage("settings.detail.velocityUnit") private var velocityUnit = "m/s"
    @AppStorage("settings.detail.headElevUnit") private var headElevUnit = "m"

    private var isUS: Bool {
        InpOptionsParser.isUSCustomary(flowUnits: flowUnitsChoice) || lengthSystem == "US"
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    paneTitle("单位与流量")

                    sectionLabel("单位 UNITS")
                    SettingsFormRow(label: "流量单位", subtitle: "与 EPANET [OPTIONS] Flow Units 关键字一致；下拉里为各代码对应中文释义，应用后重载 .inp") {
                        Picker("", selection: $flowUnitsChoice) {
                            ForEach(InpOptionsParser.epanetFlowUnitsOrdered, id: \.code) { item in
                                Text(item.menuLabel).tag(item.code)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: SettingsPixelLayout.pickerMinWidth)
                    }
                    SettingsFormRow(label: "应用流量单位", subtitle: nil) {
                        Button("应用并重载") { switchFlowUnits() }
                            .buttonStyle(SettingsPrimaryButtonStyle())
                    }

                    SettingsFormRow(label: "压力单位", subtitle: "m（水头）· kPa · psi · bar；影响节点压力显示与阈值判断") {
                        Picker("", selection: $pressureUnit) {
                            Text("m").tag("m")
                            Text("kPa").tag("kPa")
                            Text("psi").tag("psi")
                            Text("bar").tag("bar")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: SettingsPixelLayout.pickerMinWidth)
                    }

                    SettingsFormRow(label: "长度 / 管径单位", subtitle: "m / mm（SI）· ft / in（US）；SI/US 联动") {
                        Picker("", selection: $lengthSystem) {
                            Text("SI（m / mm）").tag("SI")
                            Text("US（ft / in）").tag("US")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(minWidth: SettingsPixelLayout.pickerMinWidth + 40)
                    }

                    SettingsFormRow(label: "流速单位", subtitle: "m/s · ft/s；切换 SI/US 时自动联动") {
                        Picker("", selection: $velocityUnit) {
                            Text("m/s").tag("m/s")
                            Text("ft/s").tag("ft/s")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: SettingsPixelLayout.pickerMinWidth)
                    }

                    SettingsFormRow(label: "水头 / 高程单位", subtitle: "节点高程、水头损失显示") {
                        Picker("", selection: $headElevUnit) {
                            Text("m").tag("m")
                            Text("ft").tag("ft")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: SettingsPixelLayout.pickerMinWidth)
                    }

                    SettingsFormRow(label: "粗糙度单位", subtitle: "只读（随摩阻公式）；H-W：C 系数；D-W：mm；C-M：无量纲") {
                        settingsReadonlyValue(roughnessUnitHint)
                    }

                    sectionLabel("派生预览（随流量单位 / SI·US）")
                    unitInfoRow("单位制", isUS ? "US Customary" : "SI")
                    unitInfoRow("压力显示", pressureUnit)
                    unitInfoRow("长度", isUS ? "ft" : "m")
                    unitInfoRow("管径", isUS ? "in" : "mm")
                    unitInfoRow("流速", isUS ? "ft/s" : "m/s")
                    unitInfoRow("水头/高程", headElevUnit)

                    paneNote("压力/长度等选项当前保存在本机偏好中，用于界面展示规划；写入 .inp 的仍由 Flow Units 重载与引擎选项控制。")

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
        .onAppear {
            syncFromAppState()
            refreshHeadlossCodeFromInp()
        }
        .onChange(of: appState.inpFlowUnits) { _ in syncFromAppState() }
        .onChange(of: appState.cachedInpOptionsHints) { _ in refreshHeadlossCodeFromInp() }
        .onChange(of: lengthSystem) { new in
            if new == "US" {
                velocityUnit = "ft/s"
                headElevUnit = "ft"
            } else {
                velocityUnit = "m/s"
                headElevUnit = "m"
            }
        }
    }

    private var roughnessUnitHint: String {
        guard appState.filePath != nil else { return "—（打开项目后随公式）" }
        switch headlossCodeFromInp.uppercased() {
        case "D-W": return isUS ? "ft（相对管径）" : "mm"
        case "C-M": return "无量纲"
        default: return "C 系数（无量纲）"
        }
    }

    private func refreshHeadlossCodeFromInp() {
        if let hl = appState.cachedInpOptionsHints?.headloss?.uppercased() {
            headlossCodeFromInp = hl
        } else {
            headlossCodeFromInp = "H-W"
        }
    }

    private func syncFromAppState() {
        let fu = appState.inpFlowUnits?.uppercased() ?? "GPM"
        if InpOptionsParser.isValidFlowUnitCode(fu) {
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
            settingsReadonlyValue(value)
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
    @State private var trialsCount = 40
    @State private var demandMultText = ""
    @State private var minPressureText = ""
    @State private var maxPressureText = ""
    @State private var pressExponText = ""
    @State private var emitExponText = ""
    @State private var message: String?
    @State private var isError = false
    @State private var parsedHeadloss: String = "—"
    @State private var headlossCode: String = "H-W"

    @AppStorage("settings.detail.relativeConvergence") private var relativeConvergence = false
    @AppStorage("settings.detail.viscosity") private var viscosityText = "1.0"
    @AppStorage("settings.detail.diffusivity") private var diffusivityText = "1.0"
    @AppStorage("settings.detail.usePDA") private var usePDA = false
    @AppStorage("settings.detail.imbalanceStrategy") private var imbalanceStrategy = "warn"
    @AppStorage("settings.detail.checkValveVelocity") private var checkValveVelocity = "0.01"

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
            SettingsFormRow(label: "水头损失计算公式", subtitle: "Hazen-Williams · Darcy-Weisbach · Chezy-Manning（由 .inp 解析，只读）") {
                headlossSegmentedReadonly
            }
            SettingsFormRow(label: "粗糙度单位（当前公式）", subtitle: "切换公式后请重新核对管道属性") {
                settingsReadonlyValue(roughnessUnitForHeadloss)
            }

            sectionLabel("收敛控制")
            SettingsFormRow(label: "流量收敛精度", subtitle: "0.0001 – 0.1，各管段流量残差上限 (ACCURACY)") {
                HStack(spacing: 8) {
                    SettingsTextField(text: $accuracyText)
                    unitTag(flowUnitTag)
                }
            }
            SettingsFormRow(label: "水头收敛精度", subtitle: "0.0001 – 0.1 m，各节点水头残差上限 (HEAD_TOLERANCE)") {
                HStack(spacing: 8) {
                    SettingsTextField(text: $hydTolText)
                    unitTag("m")
                }
            }
            SettingsFormRow(label: "最大迭代次数", subtitle: "10 – 200，超限视为不收敛 (MAX_TRIALS)") {
                HStack(spacing: 8) {
                    stepperView(value: Binding(
                        get: { trialsCount },
                        set: { trialsCount = min(200, max(10, $0)) }
                    ), range: 10...200)
                }
            }
            SettingsFormRow(label: "相对收敛判据", subtitle: "以相对误差代替绝对误差（EPANET 3.0 规划项，偏好存本机）") {
                Toggle("", isOn: $relativeConvergence)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            SettingsFormRow(label: "不平衡处理策略", subtitle: "迭代不收敛时的行为（偏好存本机，引擎接口后续对接）") {
                Picker("", selection: $imbalanceStrategy) {
                    Text("继续迭代").tag("continue")
                    Text("停止报错").tag("stop")
                    Text("警告后继续").tag("warn")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: SettingsPixelLayout.pickerMinWidth)
            }
            SettingsFormRow(label: "检查截止流速", subtitle: "止回阀判断阈值 m/s（偏好存本机）") {
                HStack(spacing: 8) {
                    SettingsTextField(text: $checkValveVelocity)
                    unitTag("m/s")
                }
            }
        }
    }

    private var headlossSegmentedReadonly: some View {
        HStack(spacing: 1) {
            ForEach([("H-W", "H-W"), ("D-W", "D-W"), ("C-M", "C-M")], id: \.0) { code, short in
                Text(short)
                    .font(.system(size: 12, weight: headlossCode == code ? .medium : .regular))
                    .foregroundColor(headlossCode == code ? DesignColors.lightText : DesignColors.lightText3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(headlossCode == code ? DesignColors.lightSurface : Color.clear)
                            .shadow(color: headlossCode == code ? Color.black.opacity(0.08) : .clear, radius: 2, y: 1)
                    )
            }
        }
        .padding(2)
        .background(DesignColors.lightSurface2)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(DesignColors.lightBorder, lineWidth: 1))
        .cornerRadius(7)
        .allowsHitTesting(false)
        .accessibilityLabel("摩阻公式 \(parsedHeadloss)")
    }

    private var roughnessUnitForHeadloss: String {
        switch headlossCode {
        case "D-W": return InpOptionsParser.isUSCustomary(flowUnits: appState.inpFlowUnits) ? "ft" : "mm"
        case "C-M": return "无量纲"
        default: return "C 系数"
        }
    }

    private var flowUnitTag: String {
        InpOptionsParser.flowUnitDisplaySuffix(code: appState.inpFlowUnits)
    }

    // MARK: 需水量模型

    private var demandSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("需水量模型")
            SettingsFormRow(label: "模拟模型", subtitle: "DDA：需水量驱动 · PDA：压力驱动") {
                Picker("", selection: $usePDA) {
                    Text("DDA").tag(false)
                    Text("PDA").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(minWidth: SettingsPixelLayout.pickerMinWidth + 24)
            }
            SettingsFormRow(label: "需水乘数", subtitle: "全局需水量倍率 (DEMAND_MULTIPLIER)") {
                SettingsTextField(text: $demandMultText)
            }
            subFormRow(usePDA, label: "最小服务压力（PDA）", subtitle: "低于此值需水量为 0 (MINIMUM_PRESSURE)") {
                HStack(spacing: 8) {
                    SettingsTextField(text: $minPressureText)
                    unitTag("m")
                }
            }
            subFormRow(usePDA, label: "设计服务压力（PDA）", subtitle: "高于此值需水量完全满足 (SERVICE_PRESSURE)") {
                HStack(spacing: 8) {
                    SettingsTextField(text: $maxPressureText)
                    unitTag("m")
                }
            }
            SettingsFormRow(label: "压力指数 (PDA)", subtitle: "PDA 计算指数 (PRESSURE_EXPONENT)") {
                SettingsTextField(text: $pressExponText)
            }
            .opacity(usePDA ? 1 : 0.35)
            .disabled(!usePDA)
            paneNote("PDA 模式下启用压力驱动需水量分配。最小/设计服务压力仅在 PDA 下生效；DDA 时上两项已禁用。")
        }
    }

    // MARK: 流体属性

    private var fluidSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("流体属性")
            SettingsFormRow(label: "动力粘度修正系数", subtitle: "相对值，1.0 = 20°C 清水；写入 .inp VISCOSITY 需手动（偏好先存本机）") {
                SettingsTextField(text: $viscosityText)
            }
            SettingsFormRow(label: "扩散系数", subtitle: "水质模拟中的扩散倍率；.inp DIFFUSIVITY（偏好 + 打开文件时同步）") {
                SettingsTextField(text: $diffusivityText)
            }
            sectionLabel("射流器")
            SettingsFormRow(label: "射流器指数", subtitle: "射流器流量公式指数 (EMITTER_EXPONENT)") {
                SettingsTextField(text: $emitExponText)
            }
            paneNote("水质容差 QUAL_TOLERANCE 在「计算 → 水质参数」中编辑。部分选项仍依赖 .inp 或后续引擎 API。")
        }
    }

    @ViewBuilder
    private func subFormRow<Content: View>(_ enabled: Bool, label: String, subtitle: String?, @ViewBuilder content: @escaping () -> Content) -> some View {
        SettingsFormRow(label: label, subtitle: subtitle) { content() }
            .padding(.leading, 16)
            .background(Color.black.opacity(enabled ? 0 : 0.02))
            .opacity(enabled ? 1 : 0.35)
            .disabled(!enabled)
    }

    private func loadValues() {
        guard let project = appState.project else { return }
        do {
            accuracyText = formatDouble(try project.getOption(param: .accuracy))
            hydTolText = formatDouble(try project.getOption(param: .hydTol))
            trialsCount = min(200, max(10, Int(try project.getOption(param: .trials))))
            demandMultText = formatDouble(try project.getOption(param: .demandMult))
            minPressureText = formatDouble(try project.getOption(param: .minPressure))
            maxPressureText = formatDouble(try project.getOption(param: .maxPressure))
            pressExponText = formatDouble(try project.getOption(param: .pressExpon))
            emitExponText = formatDouble(try project.getOption(param: .emitExpon))
            message = nil; isError = false
        } catch {
            message = "读取水力参数失败: \(error)"; isError = true
        }
        if let hints = appState.cachedInpOptionsHints {
            let hl = hints.headloss?.uppercased()
            headlossCode = hl ?? "H-W"
            switch headlossCode {
            case "D-W": parsedHeadloss = "Darcy-Weisbach"
            case "C-M": parsedHeadloss = "Chezy-Manning"
            default: parsedHeadloss = "Hazen-Williams"; headlossCode = "H-W"
            }
            if let v = hints.viscosity {
                viscosityText = formatDouble(v)
            }
            if let d = hints.diffusivity {
                diffusivityText = formatDouble(d)
            }
        }
    }

    private func saveValues() {
        guard let project = appState.project,
              let accuracy = Double(accuracyText),
              let hydTol = Double(hydTolText),
              let demandMult = Double(demandMultText),
              let minP = Double(minPressureText),
              let maxP = Double(maxPressureText),
              let pressExp = Double(pressExponText),
              let emitExp = Double(emitExponText) else {
            message = "保存失败: 请填写合法数字。"; isError = true
            return
        }
        appState.applyProjectMutation(sceneLabel: "更新水力参数") { _ in
            try project.setOption(param: .accuracy, value: accuracy)
            try project.setOption(param: .hydTol, value: hydTol)
            try project.setOption(param: .trials, value: Double(trialsCount))
            try project.setOption(param: .demandMult, value: demandMult)
            try project.setOption(param: .minPressure, value: minP)
            try project.setOption(param: .maxPressure, value: maxP)
            try project.setOption(param: .pressExpon, value: pressExp)
            try project.setOption(param: .emitExpon, value: emitExp)
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

/// 计算参数时间输入单位（与引擎秒整数互转）
private enum SimulationTimeUnit: String, CaseIterable, Identifiable {
    case hour = "h"
    case minute = "min"
    case second = "sec"
    var id: String { rawValue }
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

    /// 默认：总时长 → h；水质步长等步长 → min；报告/模式起始为固定 H:mm 输入（无单位菜单）
    @AppStorage("settings.sim.unit.duration") private var unitDuration = SimulationTimeUnit.hour.rawValue
    @AppStorage("settings.sim.unit.hydStep") private var unitHydStep = SimulationTimeUnit.minute.rawValue
    /// 新键名：避免沿用旧版默认 h 的偏好；缺省为 min
    @AppStorage("settings.sim.displayUnit.qualStep") private var unitQualStep = SimulationTimeUnit.minute.rawValue
    @AppStorage("settings.sim.unit.reportStep") private var unitReportStep = SimulationTimeUnit.minute.rawValue
    @AppStorage("settings.sim.unit.patternStep") private var unitPatternStep = SimulationTimeUnit.minute.rawValue
    @AppStorage("settings.sim.unit.ruleStep") private var unitRuleStep = SimulationTimeUnit.minute.rawValue

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
            SettingsFormRow(label: "模拟总时长", subtitle: "TOTAL_DURATION，0 = 稳态；右侧可选 h / min / sec，存盘为秒") {
                simulationParamValueRow(field: { SettingsTextField(text: $durationH) }) {
                    simulationTimeUnitPicker(binding: $unitDuration)
                }
            }
            SettingsFormRow(label: "水力计算步长", subtitle: "HYD_STEP；可选 h / min / sec") {
                simulationParamValueRow(field: { SettingsTextField(text: $hydStepH) }) {
                    simulationTimeUnitPicker(binding: $unitHydStep)
                }
            }
            SettingsFormRow(label: "水质计算步长", subtitle: "QUAL_STEP；默认单位 min，右侧可改 h / min / sec") {
                simulationParamValueRow(field: { SettingsTextField(text: $qualStepMin) }) {
                    simulationTimeUnitPicker(binding: $unitQualStep)
                }
            }
            SettingsFormRow(label: "报告输出步长", subtitle: "REPORT_STEP；可选 h / min / sec") {
                simulationParamValueRow(field: { SettingsTextField(text: $reportStepH) }) {
                    simulationTimeUnitPicker(binding: $unitReportStep)
                }
            }
            SettingsFormRow(label: "报告起始时间", subtitle: "REPORT_START，自模拟起算；时间格式 H:mm（默认 0:00），存盘为秒") {
                simulationParamValueRow(trailingAlignment: .center, field: { SettingsTextField(text: $reportStartH) }) {
                    simulationTrailingUnitTag("H:mm")
                }
            }

            sectionLabel("模式与规则")
            SettingsFormRow(label: "模式步长", subtitle: "PATTERN_STEP；可选 h / min / sec") {
                simulationParamValueRow(field: { SettingsTextField(text: $patternStepH) }) {
                    simulationTimeUnitPicker(binding: $unitPatternStep)
                }
            }
            SettingsFormRow(label: "模式起始时间", subtitle: "PATTERN_START，自模拟起算；时间格式 H:mm（默认 0:00），存盘为秒") {
                simulationParamValueRow(trailingAlignment: .center, field: { SettingsTextField(text: $patternStartH) }) {
                    simulationTrailingUnitTag("H:mm")
                }
            }
            SettingsFormRow(label: "规则步长", subtitle: "RULE_STEP；可选 h / min / sec") {
                simulationParamValueRow(field: { SettingsTextField(text: $ruleStepH) }) {
                    simulationTimeUnitPicker(binding: $unitRuleStep)
                }
            }
            paneNote("当模拟总时长为 0 时为稳态模式（单次平衡计算），以上时间参数不生效。设为 > 0 的值启用时变扩展周期（EPS）模拟。")
        }
        .onChange(of: unitDuration) { _ in loadValues() }
        .onChange(of: unitHydStep) { _ in loadValues() }
        .onChange(of: unitQualStep) { _ in loadValues() }
        .onChange(of: unitReportStep) { _ in loadValues() }
        .onChange(of: unitPatternStep) { _ in loadValues() }
        .onChange(of: unitRuleStep) { _ in loadValues() }
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
                simulationParamValueRow(field: { SettingsTextField(text: $qualTolText) }) {
                    Color.clear
                }
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

            durationH = secToDisplay(dur, unit: SimulationTimeUnit(rawValue: unitDuration) ?? .hour)
            hydStepH = secToDisplay(hyd, unit: SimulationTimeUnit(rawValue: unitHydStep) ?? .minute)
            qualStepMin = secToDisplay(qual, unit: SimulationTimeUnit(rawValue: unitQualStep) ?? .minute)
            reportStepH = secToDisplay(rep, unit: SimulationTimeUnit(rawValue: unitReportStep) ?? .minute)
            reportStartH = secToElapsedHM(repStart)
            patternStepH = secToDisplay(pat, unit: SimulationTimeUnit(rawValue: unitPatternStep) ?? .minute)
            patternStartH = secToElapsedHM(patStart)
            ruleStepH = secToDisplay(rule, unit: SimulationTimeUnit(rawValue: unitRuleStep) ?? .minute)

            qualTolText = formatDouble(try project.getOption(param: .qualTol))
            message = nil; isError = false
        } catch {
            message = "读取计算参数失败: \(error)"; isError = true
        }
        if let hints = appState.cachedInpOptionsHints {
            let q = hints.quality
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
        guard let durSec = displayToSec(durationH, unit: SimulationTimeUnit(rawValue: unitDuration) ?? .hour),
              let hydSec = displayToSec(hydStepH, unit: SimulationTimeUnit(rawValue: unitHydStep) ?? .minute),
              let qualSec = displayToSec(qualStepMin, unit: SimulationTimeUnit(rawValue: unitQualStep) ?? .minute),
              let repSec = displayToSec(reportStepH, unit: SimulationTimeUnit(rawValue: unitReportStep) ?? .minute),
              let repStartSec = elapsedHMToSec(reportStartH),
              let patSec = displayToSec(patternStepH, unit: SimulationTimeUnit(rawValue: unitPatternStep) ?? .minute),
              let patStartSec = elapsedHMToSec(patternStartH),
              let ruleSec = displayToSec(ruleStepH, unit: SimulationTimeUnit(rawValue: unitRuleStep) ?? .minute),
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

    /// 计算参数：左 `SettingsTextField`（固定宽）+ 右等宽列（单位菜单 / H:mm），保证各行文本框与右侧对齐。
    private func simulationParamValueRow<Field: View, Trail: View>(
        trailingAlignment: Alignment = .trailing,
        @ViewBuilder field: () -> Field,
        @ViewBuilder trailing: () -> Trail
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            field()
            trailing()
                .frame(height: SettingsPixelLayout.simulationControlHeight)
                .frame(width: SettingsPixelLayout.simulationTrailingWidth, alignment: trailingAlignment)
        }
    }

    @ViewBuilder
    private func simulationTimeUnitPicker(binding: Binding<String>) -> some View {
        Picker("", selection: binding) {
            ForEach(SimulationTimeUnit.allCases) { u in
                Text(u.rawValue).tag(u.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    /// 与单位列同尺寸（70×26 pt），样式同 `unitTag`，铺满列内以便与 Picker 对齐
    private func simulationTrailingUnitTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(DesignColors.lightText3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 4)
            .background(DesignColors.lightSurface2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(DesignColors.lightBorder, lineWidth: 1))
            .cornerRadius(4)
    }

    private func secToDisplay(_ sec: Int, unit: SimulationTimeUnit) -> String {
        switch unit {
        case .hour:
            let h = Double(sec) / 3600.0
            if h == Double(Int(h)) { return "\(Int(h))" }
            return String(format: "%.2f", h)
        case .minute:
            let m = Double(sec) / 60.0
            if m == Double(Int(m)) { return "\(Int(m))" }
            return String(format: "%.2f", m)
        case .second:
            return "\(sec)"
        }
    }

    private func displayToSec(_ text: String, unit: SimulationTimeUnit) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let v = Double(t) else { return nil }
        switch unit {
        case .hour: return Int((v * 3600.0).rounded())
        case .minute: return Int((v * 60.0).rounded())
        case .second: return Int(v.rounded())
        }
    }

    /// 报告/模式起始：秒 → `H:mm`，整分为止；若有非零秒则 `H:mm:ss`（0 秒为 `0:00`）。
    private func secToElapsedHM(_ sec: Int) -> String {
        let s = max(0, sec)
        let h = s / 3600
        let m = (s % 3600) / 60
        let r = s % 60
        if r == 0 {
            return "\(h):\(String(format: "%02d", m))"
        }
        return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", r))"
    }

    /// 解析 `H:mm` 或 `H:mm:ss`；无冒号时按整数秒（如 `0`）；非法返回 nil。
    private func elapsedHMToSec(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if !t.contains(":") {
            return Int(t)
        }
        let parts = t.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2,
              let hh = Int(parts[0]),
              let mm = Int(parts[1]) else { return nil }
        var total = hh * 3600 + mm * 60
        if parts.count >= 3, let ss = Int(parts[2]) {
            total += ss
        }
        return total
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
    @EnvironmentObject private var appState: AppState
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
        .onAppear { consumePendingDisplaySection() }
        .onChange(of: appState.settingsPendingDisplaySection) { _ in consumePendingDisplaySection() }
    }

    private func consumePendingDisplaySection() {
        guard let raw = appState.settingsPendingDisplaySection,
              let s = DisplaySection(rawValue: raw) else { return }
        section = s
        appState.settingsPendingDisplaySection = nil
    }
}

private struct DisplayContentView: View {
    let section: DisplaySection

    @AppStorage("settings.display.nodeSize") private var nodeSize = 6
    @AppStorage(DisplayCanvasNodeColor.junctionKey) private var nodeRGBJunction = DisplayCanvasNodeColor.defaultJunction
    @AppStorage(DisplayCanvasNodeColor.reservoirKey) private var nodeRGBReservoir = DisplayCanvasNodeColor.defaultReservoir
    @AppStorage(DisplayCanvasNodeColor.tankKey) private var nodeRGBTank = DisplayCanvasNodeColor.defaultTank
    @AppStorage("settings.display.lineWidth") private var lineWidth = 2
    @AppStorage(DisplayCanvasLinkColor.pipeKey) private var linkRGBPipe = DisplayCanvasLinkColor.defaultPipe
    @AppStorage(DisplayCanvasLinkColor.valveKey) private var linkRGBValve = DisplayCanvasLinkColor.defaultValve
    @AppStorage(DisplayCanvasLinkColor.pumpKey) private var linkRGBPump = DisplayCanvasLinkColor.defaultPump
    @AppStorage("settings.display.proportionalWidth") private var proportionalWidth = false
    @AppStorage("settings.display.legendSegments") private var legendSegments = 5
    @AppStorage("settings.display.legendRangeAuto") private var legendRangeAuto = true
    @AppStorage("settings.display.legendScheme") private var legendScheme = 0
    @AppStorage("settings.display.labelFontSize") private var labelFontSize = 10
    @AppStorage("settings.display.label.node.id") private var labelNodeShowId = true
    @AppStorage("settings.display.label.node.elevation") private var labelNodeShowElevation = false
    @AppStorage("settings.display.label.node.baseDemand") private var labelNodeShowBaseDemand = false
    @AppStorage("settings.display.label.node.pressure") private var labelNodeShowPressure = false
    @AppStorage("settings.display.label.node.head") private var labelNodeShowHead = false
    @AppStorage("settings.display.label.link.id") private var labelLinkShowId = false
    @AppStorage("settings.display.label.link.diameter") private var labelLinkShowDiameter = false
    @AppStorage("settings.display.label.link.length") private var labelLinkShowLength = false
    @AppStorage("settings.display.label.link.flow") private var labelLinkShowFlow = false
    @AppStorage("settings.display.label.link.velocity") private var labelLinkShowVelocity = false

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
        .onAppear { migrateLegacyDisplayLabelKeys() }
    }

    private var colorSizeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("节点颜色（默认）")
            SettingsFormRow(label: "节点默认颜色", subtitle: "Junction · 水塔 · 水库；画布实时应用") {
                HStack(spacing: 12) {
                    displayNodeColorPickerChip("J", pack: $nodeRGBJunction)
                    displayNodeColorPickerChip("T", pack: $nodeRGBTank)
                    displayNodeColorPickerChip("R", pack: $nodeRGBReservoir)
                }
            }
            SettingsFormRow(label: "管段默认颜色", subtitle: "Pipe · Valve · Pump；画布实时应用") {
                HStack(spacing: 12) {
                    displayNodeColorPickerChip("P", pack: $linkRGBPipe)
                    displayNodeColorPickerChip("V", pack: $linkRGBValve)
                    displayNodeColorPickerChip("Pm", pack: $linkRGBPump)
                }
            }

            sectionLabel("尺寸")
            SettingsFormRow(label: "节点尺寸", subtitle: "画布像素，跟随缩放比例；可点中间数字直接输入") {
                HStack(spacing: 6) {
                    settingsIntStepperField(value: $nodeSize, range: 1...20)
                    unitTag("px")
                }
            }
            SettingsFormRow(label: "管段线宽", subtitle: "屏幕像素厚度（与节点尺寸语义一致），缩放地图时线宽不随放大变粗；同时影响点选容差；可点中间数字直接输入") {
                HStack(spacing: 6) {
                    settingsIntStepperField(value: $lineWidth, range: 1...8)
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

            sectionLabel("节点标注（多选，自上而下多行）")
            SettingsFormRow(label: "节点 ID", subtitle: nil) {
                Toggle("", isOn: $labelNodeShowId).toggleStyle(.switch).labelsHidden()
            }
            SettingsFormRow(label: "高程", subtitle: nil) {
                Toggle("", isOn: $labelNodeShowElevation).toggleStyle(.switch).labelsHidden()
            }
            SettingsFormRow(label: "基本需水量", subtitle: "基准需水，与属性面板一致") {
                Toggle("", isOn: $labelNodeShowBaseDemand).toggleStyle(.switch).labelsHidden()
            }
            SettingsFormRow(label: "压力", subtitle: "计算后；无项目或未解算时显示 —") {
                Toggle("", isOn: $labelNodeShowPressure).toggleStyle(.switch).labelsHidden()
            }
            SettingsFormRow(label: "总水头", subtitle: "计算后；无项目或未解算时显示 —") {
                Toggle("", isOn: $labelNodeShowHead).toggleStyle(.switch).labelsHidden()
            }

            sectionLabel("管段标注（多选，同一行内以「 - 」连接）")
            SettingsFormRow(label: "管段 ID", subtitle: nil) {
                Toggle("", isOn: $labelLinkShowId).toggleStyle(.switch).labelsHidden()
            }
            SettingsFormRow(label: "管径", subtitle: nil) {
                Toggle("", isOn: $labelLinkShowDiameter).toggleStyle(.switch).labelsHidden()
            }
            SettingsFormRow(label: "管长", subtitle: nil) {
                Toggle("", isOn: $labelLinkShowLength).toggleStyle(.switch).labelsHidden()
            }
            SettingsFormRow(label: "流量", subtitle: "计算后") {
                Toggle("", isOn: $labelLinkShowFlow).toggleStyle(.switch).labelsHidden()
            }
            SettingsFormRow(label: "流速", subtitle: "计算后") {
                Toggle("", isOn: $labelLinkShowVelocity).toggleStyle(.switch).labelsHidden()
            }
            paneNote("标注仅在缩放 > 50% 时显示。超大模型在缩放不足时可能暂不绘管段/节点文字以保流畅。")
        }
    }

    private func displayNodeColorPickerChip(_ letter: String, pack: Binding<Int>) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(letter)
                .font(.system(size: 11))
                .foregroundColor(DesignColors.lightText3)
            ColorPicker("", selection: Binding(
                get: { Color(srgbRGB24: pack.wrappedValue) },
                set: { pack.wrappedValue = $0.toSRGBRGB24(fallback: pack.wrappedValue) }
            ), supportsOpacity: false)
            .labelsHidden()
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
            "settings.display.nodeSize",
            DisplayCanvasNodeColor.junctionKey,
            DisplayCanvasNodeColor.reservoirKey,
            DisplayCanvasNodeColor.tankKey,
            DisplayCanvasLinkColor.pipeKey,
            DisplayCanvasLinkColor.valveKey,
            DisplayCanvasLinkColor.pumpKey,
            "settings.display.lineWidth",
            "settings.display.proportionalWidth", "settings.display.legendSegments",
            "settings.display.legendRangeAuto", "settings.display.legendScheme",
            "settings.display.labelFontSize",
            "settings.display.labelsVisible",
            "settings.display.label.node.id", "settings.display.label.node.elevation",
            "settings.display.label.node.baseDemand", "settings.display.label.node.pressure", "settings.display.label.node.head",
            "settings.display.label.link.id", "settings.display.label.link.diameter", "settings.display.label.link.length",
            "settings.display.label.link.flow", "settings.display.label.link.velocity",
            "settings.display.labelShowID", "settings.display.labelShowPressure",
            "settings.display.labelShowDemand", "settings.display.labelShowElevation",
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
            .frame(width: SettingsPixelLayout.fieldWidth, alignment: .trailing)
            .background(DesignColors.lightSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DesignColors.lightBorder, lineWidth: 1)
            )
    }
}

/// 与 `.field` 同尺寸的只读展示（摩阻公式、解析结果等）
@ViewBuilder
private func settingsReadonlyValue(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 13, design: .monospaced))
        .foregroundColor(DesignColors.lightText2)
        .multilineTextAlignment(.trailing)
        .lineLimit(2)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(width: SettingsPixelLayout.fieldWidth, alignment: .trailing)
        .background(DesignColors.lightSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(DesignColors.lightBorder, lineWidth: 1)
        )
}

/// 从旧版 `labelShow*` 键迁移到 `settings.display.label.*`（仅当新键从未写入时）
private func migrateLegacyDisplayLabelKeys() {
    let d = UserDefaults.standard
    func copyBool(_ newKey: String, legacyKey: String) {
        guard d.object(forKey: newKey) == nil else { return }
        if let v = d.object(forKey: legacyKey) as? Bool {
            d.set(v, forKey: newKey)
        }
    }
    copyBool("settings.display.label.node.id", legacyKey: "settings.display.labelShowID")
    copyBool("settings.display.label.node.elevation", legacyKey: "settings.display.labelShowElevation")
    copyBool("settings.display.label.node.baseDemand", legacyKey: "settings.display.labelShowDemand")
    copyBool("settings.display.label.node.pressure", legacyKey: "settings.display.labelShowPressure")
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

/// 带 ± 的整数步进，中间为可编辑 `TextField`（合法范围内即时写回；失焦/回车钳制到范围）
private struct SettingsIntStepperField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    @State private var fieldText: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if value > range.lowerBound { value -= 1 }
            } label: {
                Text("−").frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .background(DesignColors.lightSurface2)

            Rectangle().fill(DesignColors.lightBorder).frame(width: 1, height: 26)

            TextField("", text: $fieldText)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(DesignColors.lightText)
                .focused($fieldFocused)
                .frame(minWidth: 44, maxWidth: 72)
                .frame(height: 26)
                .background(DesignColors.lightSurface)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif

            Rectangle().fill(DesignColors.lightBorder).frame(width: 1, height: 26)

            Button {
                if value < range.upperBound { value += 1 }
            } label: {
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
        .onAppear {
            fieldText = "\(value)"
        }
        .onChange(of: value) { newVal in
            if !fieldFocused {
                fieldText = "\(newVal)"
            }
        }
        .onChange(of: fieldText) { newText in
            let t = newText.trimmingCharacters(in: .whitespaces)
            guard let v = Int(t), range.contains(v) else { return }
            if v != value {
                value = v
            }
        }
        .onSubmit {
            commitClamp()
        }
        .onChange(of: fieldFocused) { focused in
            if !focused {
                commitClamp()
            }
        }
    }

    private func commitClamp() {
        let t = fieldText.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            fieldText = "\(value)"
            return
        }
        if let v = Int(t) {
            value = min(max(v, range.lowerBound), range.upperBound)
        }
        fieldText = "\(value)"
    }
}

private func settingsIntStepperField(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
    SettingsIntStepperField(value: value, range: range)
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
