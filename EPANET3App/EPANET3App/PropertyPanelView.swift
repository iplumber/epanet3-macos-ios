import SwiftUI
import EPANET3Bridge
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 与 Flow Units 联动的属性单位标签：GPM/CFS/MGD/IMGD/AFD → 美制；LPS/LPM/MLD/CMH/CMD → 公制。
/// 美制/公制由 inp 的 Flow Units 决定；未解析到时与引擎默认一致按 GPM（美制）。
private struct PropertyUnits {
    let flowUnit: String
    let flowUnitDisplay: String
    let isUS: Bool
    let elevation: String
    let head: String
    let pressure: String
    let velocity: String
    let length: String
    let diameter: String

    init(flowUnits: String?) {
        let u = (flowUnits ?? "GPM").uppercased().trimmingCharacters(in: .whitespaces)
        flowUnit = u.isEmpty ? "GPM" : u
        isUS = InpOptionsParser.isUSCustomary(flowUnits: flowUnit)
        flowUnitDisplay = Self.flowUnitDisplayName(flowUnit)
        if isUS {
            elevation = "高程 (ft)"
            head = "水头 (ft)"
            pressure = "压力 (psi)"
            velocity = "流速 (ft/s)"
            length = "长度 (ft)"
            diameter = "管径 (in)"
        } else {
            elevation = "高程 (m)"
            head = "水头 (m)"
            pressure = "压力 (m)"
            velocity = "流速 (m/s)"
            length = "长度 (m)"
            diameter = "管径 (mm)"
        }
    }

    /// 需水量/管段流量的显示单位：公制 CMH→m³/h，CMD→m³/d 等；美制保持 GPM 等。
    private static func flowUnitDisplayName(_ unit: String) -> String {
        switch unit.uppercased() {
        case "CMH": return "m³/h"
        case "CMD": return "m³/d"
        case "LPS": return "L/s"
        case "LPM": return "L/min"
        case "MLD": return "ML/d"
        default: return unit.uppercased()
        }
    }
}

struct PropertyPanelView: View {
    @ObservedObject var appState: AppState
    let selectedNodeIndex: Int?
    let selectedLinkIndex: Int?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("属性")
                    .font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            if appState.project != nil {
                Text("单位: \(units.flowUnitDisplay) (\(units.isUS ? "美制" : "公制"))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
            if let proj = appState.project {
                SimulationSettingsSection(appState: appState, project: proj, units: units)
                Divider().padding(.vertical, 6)
            }
            if appState.project != nil, appState.editorMode == .add {
                AddToolsSection(appState: appState, units: units)
                Divider().padding(.vertical, 6)
            }
            if appState.project != nil, appState.editorMode == .delete {
                DeleteToolsSection(appState: appState)
                Divider().padding(.vertical, 6)
            }
            if let proj = appState.project {
                if let i = selectedNodeIndex, i >= 0 {
                    NodeEditorSection(appState: appState, project: proj, nodeIndex: i, units: units)
                    Divider().padding(.vertical, 6)
                    PropertyTableView(rows: nodeRows(project: proj, nodeIndex: i))
                } else if let i = selectedLinkIndex, i >= 0 {
                    LinkEditorSection(appState: appState, project: proj, linkIndex: i, units: units)
                    Divider().padding(.vertical, 6)
                    PropertyTableView(rows: linkRows(project: proj, linkIndex: i))
                } else {
                    Text("未选中对象")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    PropertyTableView(rows: [])
                }
            } else {
                Text("仅显示模式，无属性数据")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            Spacer(minLength: 0)
        }
        .background(platformWindowBackgroundColor)
        .overlay(Rectangle().frame(width: 1).foregroundColor(.secondary.opacity(0.3)), alignment: .leading)
    }

    private var units: PropertyUnits {
        PropertyUnits(flowUnits: appState.inpFlowUnits)
    }
    private var platformWindowBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }

    private func nodeRows(project: EpanetProject, nodeIndex: Int) -> [(String, String)] {
        var rows: [(String, String)] = []
        let u = units
        do {
            rows.append(("ID", try project.getNodeId(index: nodeIndex)))
            rows.append((u.elevation, String(format: "%.2f", try project.getNodeValue(nodeIndex: nodeIndex, param: .elevation))))
            rows.append((u.head, String(format: "%.2f", try project.getNodeValue(nodeIndex: nodeIndex, param: .head))))
            rows.append((u.pressure, String(format: "%.2f", try project.getNodeValue(nodeIndex: nodeIndex, param: .pressure))))
            rows.append(("需水量 (\(u.flowUnitDisplay))", String(format: "%.4f", try project.getNodeValue(nodeIndex: nodeIndex, param: .actualdemand))))
        } catch {}
        return rows
    }

    private func linkRows(project: EpanetProject, linkIndex: Int) -> [(String, String)] {
        var rows: [(String, String)] = []
        let u = units
        do {
            rows.append(("ID", try project.getLinkId(index: linkIndex)))
            let (n1, n2) = try project.getLinkNodes(linkIndex: linkIndex)
            rows.append(("节点", "\(n1 + 1) → \(n2 + 1)"))
            rows.append(("流量 (\(u.flowUnitDisplay))", String(format: "%.4f", try project.getLinkValue(linkIndex: linkIndex, param: .flow))))
            rows.append((u.velocity, String(format: "%.4f", try project.getLinkValue(linkIndex: linkIndex, param: .velocity))))
            rows.append((u.length, String(format: "%.2f", try project.getLinkValue(linkIndex: linkIndex, param: .length))))
            rows.append((u.diameter, String(format: "%.2f", try project.getLinkValue(linkIndex: linkIndex, param: .diameter))))
        } catch {}
        return rows
    }
}

private struct SimulationSettingsSection: View {
    @ObservedObject var appState: AppState
    let project: EpanetProject
    let units: PropertyUnits

    @State private var trialsText = ""
    @State private var accuracyText = ""
    @State private var demandMultText = ""
    @State private var durationText = ""
    @State private var hydStepText = ""
    @State private var reportStepText = ""
    @State private var flowUnitsChoice = "GPM"
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("计算参数")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
            Text("流量单位: \(units.flowUnitDisplay)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("Flow Units（重载切换）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Flow Units", selection: $flowUnitsChoice) {
                    Text("GPM").tag("GPM")
                    Text("LPS").tag("LPS")
                }
                .pickerStyle(.segmented)
                Button("应用 Flow Units 切换（重载）") { switchFlowUnits() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 6) {
                TextField("最大迭代次数 (TRIALS)", text: $trialsText)
                    .textFieldStyle(.roundedBorder)
                TextField("收敛精度 (ACCURACY)", text: $accuracyText)
                    .textFieldStyle(.roundedBorder)
                TextField("需水乘数 (DEMAND MULT)", text: $demandMultText)
                    .textFieldStyle(.roundedBorder)
                TextField("计算时长秒 (DURATION)", text: $durationText)
                    .textFieldStyle(.roundedBorder)
                TextField("水力步长秒 (HYD STEP)", text: $hydStepText)
                    .textFieldStyle(.roundedBorder)
                TextField("报告步长秒 (REPORT STEP)", text: $reportStepText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 12)

            HStack {
                Button("刷新参数") { loadValues() }
                    .buttonStyle(.bordered)
                Button("保存参数") { saveValues() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(isError ? .red : .green)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 6)
        .onAppear { loadValues() }
    }

    private func loadValues() {
        do {
            let trials = Int(try project.getOption(param: .trials))
            let accuracy = try project.getOption(param: .accuracy)
            let demandMult = try project.getOption(param: .demandMult)
            let duration = try project.getTimeParam(param: .duration)
            let hydStep = try project.getTimeParam(param: .hydStep)
            let reportStep = try project.getTimeParam(param: .reportStep)

            trialsText = "\(trials)"
            accuracyText = String(format: "%.8f", accuracy)
            demandMultText = String(format: "%.6f", demandMult)
            durationText = "\(duration)"
            hydStepText = "\(hydStep)"
            reportStepText = "\(reportStep)"
            flowUnitsChoice = (appState.inpFlowUnits?.uppercased() == "LPS") ? "LPS" : "GPM"
            message = nil
            isError = false
        } catch {
            message = "读取计算参数失败: \(error)"
            isError = true
        }
    }

    private func switchFlowUnits() {
        appState.switchFlowUnitsReload(targetFlowUnits: flowUnitsChoice)
        if let err = appState.errorMessage, err.contains("切换 Flow Units 失败") {
            message = err
            isError = true
        } else {
            loadValues()
            message = "Flow Units 已切换为 \(flowUnitsChoice)（重载完成）。"
            isError = false
        }
    }

    private func saveValues() {
        guard let trials = Int(trialsText),
              let accuracy = Double(accuracyText),
              let demandMult = Double(demandMultText),
              let duration = Int(durationText),
              let hydStep = Int(hydStepText),
              let reportStep = Int(reportStepText) else {
            message = "保存失败: 请填写合法数字。"
            isError = true
            return
        }

        appState.updateSimulationSettings(
            trials: trials,
            accuracy: accuracy,
            demandMultiplier: demandMult,
            duration: duration,
            hydraulicStep: hydStep,
            reportStep: reportStep
        )

        if let err = appState.errorMessage, err.contains("更新计算参数失败") {
            message = err
            isError = true
        } else {
            loadValues()
            message = "计算参数已保存。"
            isError = false
        }
    }
}

private struct AddToolsSection: View {
    @ObservedObject var appState: AppState
    let units: PropertyUnits

    @State private var nodeID = ""
    @State private var nodeElevation = ""
    @State private var nodeDemand = ""
    @State private var nodeX = ""
    @State private var nodeY = ""

    @State private var linkID = ""
    @State private var fromNodeID = ""
    @State private var toNodeID = ""
    @State private var linkLength = ""
    @State private var linkDiameter = ""
    @State private var linkRoughness = ""

    @State private var message: String?
    @State private var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("添加对象")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("新增节点（Junction）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("节点 ID", text: $nodeID).textFieldStyle(.roundedBorder)
                TextField(units.elevation, text: $nodeElevation).textFieldStyle(.roundedBorder)
                TextField("基础需水量 (\(units.flowUnitDisplay))", text: $nodeDemand).textFieldStyle(.roundedBorder)
                TextField("X 坐标", text: $nodeX).textFieldStyle(.roundedBorder)
                TextField("Y 坐标", text: $nodeY).textFieldStyle(.roundedBorder)
                Button("新增节点") { addNode() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("新增管段（Pipe）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("管段 ID", text: $linkID).textFieldStyle(.roundedBorder)
                TextField("起点节点 ID", text: $fromNodeID).textFieldStyle(.roundedBorder)
                TextField("终点节点 ID", text: $toNodeID).textFieldStyle(.roundedBorder)
                TextField(units.length, text: $linkLength).textFieldStyle(.roundedBorder)
                TextField(units.diameter, text: $linkDiameter).textFieldStyle(.roundedBorder)
                TextField("糙率", text: $linkRoughness).textFieldStyle(.roundedBorder)
                Button("新增管段") { addLink() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(isError ? .red : .green)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 6)
    }

    private func addNode() {
        guard !nodeID.trimmingCharacters(in: .whitespaces).isEmpty,
              let elev = Double(nodeElevation),
              let demand = Double(nodeDemand),
              let x = Double(nodeX),
              let y = Double(nodeY) else {
            message = "新增节点失败: 请填写完整且合法的数字。"
            isError = true
            return
        }
        appState.addJunction(nodeID: nodeID, elevation: elev, baseDemand: demand, xCoord: x, yCoord: y)
        if let err = appState.errorMessage, err.contains("新增节点失败") {
            message = err
            isError = true
        } else {
            message = "节点已新增。"
            isError = false
        }
    }

    private func addLink() {
        guard !linkID.trimmingCharacters(in: .whitespaces).isEmpty,
              !fromNodeID.trimmingCharacters(in: .whitespaces).isEmpty,
              !toNodeID.trimmingCharacters(in: .whitespaces).isEmpty,
              let length = Double(linkLength),
              let diameter = Double(linkDiameter),
              let roughness = Double(linkRoughness) else {
            message = "新增管段失败: 请填写完整且合法的数字。"
            isError = true
            return
        }
        appState.addPipe(
            linkID: linkID,
            fromNodeID: fromNodeID,
            toNodeID: toNodeID,
            length: length,
            diameter: diameter,
            roughness: roughness
        )
        if let err = appState.errorMessage, err.contains("新增管段失败") {
            message = err
            isError = true
        } else {
            message = "管段已新增。"
            isError = false
        }
    }
}

private struct DeleteToolsSection: View {
    @ObservedObject var appState: AppState
    @State private var deleteNodeID = ""
    @State private var deleteLinkID = ""
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("删除对象")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
            Text("支持删除已选中对象，或按 ID 直接删除。")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
            Button("删除当前选中对象") {
                appState.deleteSelectedObject()
                if let err = appState.errorMessage, err.contains("删除") {
                    message = err
                    isError = true
                } else {
                    message = "对象已删除。"
                    isError = false
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("按 ID 删除（无需先选中）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("节点 ID", text: $deleteNodeID)
                    .textFieldStyle(.roundedBorder)
                Button("按节点 ID 删除") {
                    appState.deleteNodeByID(deleteNodeID)
                    if let err = appState.errorMessage, err.contains("删除节点失败") {
                        message = err
                        isError = true
                    } else {
                        message = "节点已删除。"
                        isError = false
                    }
                }
                .buttonStyle(.bordered)

                TextField("管段 ID", text: $deleteLinkID)
                    .textFieldStyle(.roundedBorder)
                Button("按管段 ID 删除") {
                    appState.deleteLinkByID(deleteLinkID)
                    if let err = appState.errorMessage, err.contains("删除管段失败") {
                        message = err
                        isError = true
                    } else {
                        message = "管段已删除。"
                        isError = false
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(isError ? .red : .green)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct NodeEditorSection: View {
    @ObservedObject var appState: AppState
    let project: EpanetProject
    let nodeIndex: Int
    let units: PropertyUnits

    @State private var elevationText = ""
    @State private var baseDemandText = ""
    @State private var xCoordText = ""
    @State private var yCoordText = ""
    @State private var formMessage: String?
    @State private var formMessageIsError = false

    private var nodeID: String {
        (try? project.getNodeId(index: nodeIndex)) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("编辑节点")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
            Text("ID: \(nodeID)")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 6) {
                TextField(units.elevation, text: $elevationText)
                    .textFieldStyle(.roundedBorder)
                TextField("基础需水量 (\(units.flowUnitDisplay))", text: $baseDemandText)
                    .textFieldStyle(.roundedBorder)
                TextField("X 坐标", text: $xCoordText)
                    .textFieldStyle(.roundedBorder)
                TextField("Y 坐标", text: $yCoordText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 12)

            Text("坐标支持负值与小数，不做正值约束。")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)

            HStack {
                Button("刷新") { loadValues() }
                    .buttonStyle(.bordered)
                Button("保存节点属性") { saveValues() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)

            if let formMessage {
                Text(formMessage)
                    .font(.caption)
                    .foregroundColor(formMessageIsError ? .red : .green)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 6)
        .onAppear { loadValues() }
        .onChange(of: nodeIndex) { _ in loadValues() }
    }

    private func loadValues() {
        do {
            let elevation = try project.getNodeValue(nodeIndex: nodeIndex, param: .elevation)
            let baseDemand = try project.getNodeValue(nodeIndex: nodeIndex, param: .basedemand)
            let x = try project.getNodeValue(nodeIndex: nodeIndex, param: .xcoord)
            let y = try project.getNodeValue(nodeIndex: nodeIndex, param: .ycoord)
            elevationText = String(format: "%.4f", elevation)
            baseDemandText = String(format: "%.4f", baseDemand)
            xCoordText = String(format: "%.4f", x)
            yCoordText = String(format: "%.4f", y)
            formMessage = nil
            formMessageIsError = false
        } catch {
            formMessage = "读取节点属性失败: \(error)"
            formMessageIsError = true
        }
    }

    private func saveValues() {
        guard let elevation = Double(elevationText),
              let baseDemand = Double(baseDemandText),
              let xCoord = Double(xCoordText),
              let yCoord = Double(yCoordText) else {
            formMessage = "请输入有效数字后再保存。"
            formMessageIsError = true
            return
        }
        guard !nodeID.isEmpty else {
            formMessage = "节点 ID 为空，无法保存。"
            formMessageIsError = true
            return
        }
        appState.updateNodeCoreProperties(
            nodeID: nodeID,
            elevation: elevation,
            baseDemand: baseDemand,
            xCoord: xCoord,
            yCoord: yCoord
        )
        if let err = appState.errorMessage, err.contains("更新节点属性失败") {
            formMessage = err
            formMessageIsError = true
        } else {
            loadValues() // 自动回填最新值
            formMessage = "节点属性已保存。"
            formMessageIsError = false
        }
    }
}

private struct LinkEditorSection: View {
    @ObservedObject var appState: AppState
    let project: EpanetProject
    let linkIndex: Int
    let units: PropertyUnits

    @State private var lengthText = ""
    @State private var diameterText = ""
    @State private var roughnessText = ""
    @State private var formMessage: String?
    @State private var formMessageIsError = false

    private var linkID: String {
        (try? project.getLinkId(index: linkIndex)) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("编辑管段")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
            Text("ID: \(linkID)")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 6) {
                TextField(units.length, text: $lengthText)
                    .textFieldStyle(.roundedBorder)
                TextField(units.diameter, text: $diameterText)
                    .textFieldStyle(.roundedBorder)
                TextField("糙率", text: $roughnessText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 12)

            HStack {
                Button("刷新") { loadValues() }
                    .buttonStyle(.bordered)
                Button("保存管段属性") { saveValues() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)

            if let formMessage {
                Text(formMessage)
                    .font(.caption)
                    .foregroundColor(formMessageIsError ? .red : .green)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 6)
        .onAppear { loadValues() }
        .onChange(of: linkIndex) { _ in loadValues() }
    }

    private func loadValues() {
        do {
            let length = try project.getLinkValue(linkIndex: linkIndex, param: .length)
            let diameter = try project.getLinkValue(linkIndex: linkIndex, param: .diameter)
            let roughness = try project.getLinkValue(linkIndex: linkIndex, param: .roughness)
            lengthText = String(format: "%.4f", length)
            diameterText = String(format: "%.4f", diameter)
            roughnessText = String(format: "%.4f", roughness)
            formMessage = nil
            formMessageIsError = false
        } catch {
            formMessage = "读取管段属性失败: \(error)"
            formMessageIsError = true
        }
    }

    private func saveValues() {
        guard let length = Double(lengthText),
              let diameter = Double(diameterText),
              let roughness = Double(roughnessText) else {
            formMessage = "请输入有效数字后再保存。"
            formMessageIsError = true
            return
        }
        guard !linkID.isEmpty else {
            formMessage = "管段 ID 为空，无法保存。"
            formMessageIsError = true
            return
        }
        appState.updateLinkCoreProperties(linkID: linkID, length: length, diameter: diameter, roughness: roughness)
        if let err = appState.errorMessage, err.contains("更新管段属性失败") {
            formMessage = err
            formMessageIsError = true
        } else {
            loadValues() // 自动回填最新值
            formMessage = "管段属性已保存。"
            formMessageIsError = false
        }
    }
}

private struct PropertyTableView: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, pair in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(pair.0)
                        .foregroundColor(.secondary)
                        .frame(width: 72, alignment: .leading)
                    Text(pair.1)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                if idx < rows.count - 1 {
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
        .padding(.top, 4)
    }
}
