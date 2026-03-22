import SwiftUI
import EPANET3Bridge
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 属性面板数值编辑后防抖再提交引擎，避免每个按键都触发求解/刷新。
private enum PropertyInspectorAutosave {
    static let fieldCommitDebounceNs: UInt64 = 450_000_000
}

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
    @Environment(\.colorScheme) var colorScheme
    private enum InspectorTab: String {
        case properties = "属性"
        case styles = "样式"
    }

    @ObservedObject var appState: AppState
    let selectedNodeIndex: Int?
    let selectedLinkIndex: Int?
    let onClose: () -> Void
    @State private var activeTab: InspectorTab = .properties

    private var surface: Color { colorScheme == .dark ? DesignColors.darkSurface : DesignColors.lightSurface }
    private var surface2: Color { colorScheme == .dark ? DesignColors.darkSurface2 : DesignColors.lightSurface2 }
    private var border: Color { colorScheme == .dark ? DesignColors.darkBorder : DesignColors.lightBorder }
    private var text2: Color { colorScheme == .dark ? DesignColors.darkText2 : DesignColors.lightText2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    objectTypeLabel
                    objectIDText
                    Spacer(minLength: 8)
                }
                HStack(spacing: 2) {
                    tabButton(.properties)
                    tabButton(.styles)
                }
                .padding(2)
                .background(surface2, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
            }
            .padding(.horizontal, DesignSizes.inspectorPaddingH)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background(surface)
            .overlay(Rectangle().frame(height: 1).foregroundColor(border), alignment: .bottom)

            ScrollView {
                switch activeTab {
                case .properties:
                    propertiesTab
                case .styles:
                    stylesTab
                }
            }
            Spacer(minLength: 0)
        }
        .background(surface)
        .overlay(Rectangle().frame(width: 1).foregroundColor(border), alignment: .leading)
    }

    private var units: PropertyUnits {
        PropertyUnits(flowUnits: appState.inpFlowUnits)
    }

    private var objectTypeLabel: some View {
        let accentColor = colorScheme == .dark ? DesignColors.darkAccent : DesignColors.lightAccent
        let (label, tint): (String, Color) = {
            if selectedNodeIndex != nil { return ("节点 Junction", accentColor) }
            if selectedLinkIndex != nil { return ("管段 Pipe", Color.orange) }
            return ("未选中", text2)
        }()
        return HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label).font(DesignFonts.fieldName).fontWeight(.medium).foregroundColor(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private var objectIDText: some View {
        let id: String = {
            guard let proj = appState.project else { return "—" }
            if let i = selectedNodeIndex { return (try? proj.getNodeId(index: i)) ?? "—" }
            if let i = selectedLinkIndex { return (try? proj.getLinkId(index: i)) ?? "—" }
            return "—"
        }()
        return Text(id)
            .font(DesignFonts.fieldValue)
            .foregroundColor(text2)
    }

    private func tabButton(_ tab: InspectorTab) -> some View {
        Button { activeTab = tab } label: {
            Text(tab.rawValue)
                .font(DesignFonts.tabLabel)
                .foregroundColor(activeTab == tab ? (colorScheme == .dark ? DesignColors.darkText : DesignColors.lightText) : text2)
                .frame(maxWidth: .infinity)
                .frame(height: DesignSizes.tabHeight)
        }
        .buttonStyle(.plain)
        .background(activeTab == tab ? surface : .clear, in: RoundedRectangle(cornerRadius: DesignSizes.tabCornerRadius))
        .overlay(activeTab == tab ? RoundedRectangle(cornerRadius: DesignSizes.tabCornerRadius).stroke(Color.black.opacity(0.06), lineWidth: 1) : nil)
    }

    @ViewBuilder
    private var propertiesTab: some View {
        if let proj = appState.project {
            if appState.editorMode == .add {
                AddToolsSection(appState: appState, units: units)
                Divider().padding(.vertical, 6)
            }
            if appState.editorMode == .delete {
                DeleteToolsSection(appState: appState)
                Divider().padding(.vertical, 6)
            }
            if let i = selectedNodeIndex, i >= 0 {
                NodeBasicInfoSection(appState: appState, project: proj, nodeIndex: i, units: units)
            } else if let i = selectedLinkIndex, i >= 0 {
                LinkBasicInfoSection(appState: appState, project: proj, linkIndex: i, units: units)
            } else {
                Text("未选中对象")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }

            Divider().padding(.vertical, 6)

            if case .success(let elapsed) = appState.runResult {
                HStack(spacing: 8) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("最近计算成功 · \(String(format: "%.2f", elapsed)) 秒")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            } else if case .failure(let message) = appState.runResult {
                Text("最近计算失败：\(message)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            } else {
                Text("尚未运行计算")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }
            if let i = selectedNodeIndex, i >= 0 {
                PropertyFieldGroup(label: "计算结果", rows: nodeResultRows(project: proj, nodeIndex: i))
            } else if let i = selectedLinkIndex, i >= 0 {
                PropertyFieldGroup(label: "计算结果", rows: linkResultRows(project: proj, linkIndex: i))
            } else {
                Text("选择对象后显示结果项")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        } else {
            Text("仅显示模式，无属性数据")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }

    private var stylesTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("样式设置")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.top, 8)
            Text("当前版本为设计稿一致性实现，样式项先提供基础控制入口。")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
            Group {
                HStack { Text("节点大小"); Spacer(); Text("默认").foregroundColor(.secondary) }
                HStack { Text("管线宽度"); Spacer(); Text("默认").foregroundColor(.secondary) }
                HStack { Text("标注显示"); Spacer(); Text("开启").foregroundColor(.secondary) }
                HStack { Text("主题"); Spacer(); Text("浅色").foregroundColor(.secondary) }
            }
            .font(.caption)
            .padding(.horizontal, 12)
        }
    }

    private func nodeResultRows(project: EpanetProject, nodeIndex: Int) -> [(String, String)] {
        var rows: [(String, String)] = []
        let u = units
        do {
            rows.append((u.head, String(format: "%.2f", try project.getNodeValue(nodeIndex: nodeIndex, param: .head))))
            rows.append((u.pressure, String(format: "%.2f", try project.getNodeValue(nodeIndex: nodeIndex, param: .pressure))))
            rows.append(("需水量 (\(u.flowUnitDisplay))", String(format: "%.4f", try project.getNodeValue(nodeIndex: nodeIndex, param: .actualdemand))))
        } catch {}
        return rows
    }

    private func linkResultRows(project: EpanetProject, linkIndex: Int) -> [(String, String)] {
        var rows: [(String, String)] = []
        let u = units
        do {
            rows.append(("流量 (\(u.flowUnitDisplay))", String(format: "%.4f", try project.getLinkValue(linkIndex: linkIndex, param: .flow))))
            rows.append((u.velocity, String(format: "%.4f", try project.getLinkValue(linkIndex: linkIndex, param: .velocity))))
            rows.append(("水头损失", String(format: "%.4f", try project.getLinkValue(linkIndex: linkIndex, param: .headloss))))
        } catch {}
        return rows
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

private struct NodeBasicInfoSection: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var appState: AppState
    let project: EpanetProject
    let nodeIndex: Int
    let units: PropertyUnits

    @State private var elevationText = ""
    @State private var baseDemandText = ""
    @State private var xCoordText = ""
    @State private var yCoordText = ""
    /// 上次从引擎加载或防抖提交成功后的文本，用于判断用户是否只改了部分字段。
    @State private var committedElevationText = ""
    @State private var committedBaseDemandText = ""
    @State private var committedXCoordText = ""
    @State private var committedYCoordText = ""
    @State private var formMessage: String?
    @State private var formMessageIsError = false
    @State private var nodeCommitTask: Task<Void, Never>?

    private var nodeID: String {
        (try? project.getNodeId(index: nodeIndex)) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("基本信息")
                .font(DesignFonts.fieldLabel)
                .foregroundColor(colorScheme == .dark ? DesignColors.darkText3 : DesignColors.lightText3)
                .textCase(.uppercase)
                .padding(.horizontal, DesignSizes.inspectorPaddingH)

            PropertyFieldRow(label: "ID", value: nodeID)
            PropertyFieldRow(label: units.elevation, value: $elevationText)
            PropertyFieldRow(label: "X 坐标", value: $xCoordText)
            PropertyFieldRow(label: "Y 坐标", value: $yCoordText)
            PropertyFieldRow(label: "基本需水量 (\(units.flowUnitDisplay))", value: $baseDemandText)

            HStack(spacing: 8) {
                Button("刷新") { loadValues() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, DesignSizes.inspectorPaddingH)
            .padding(.top, 4)

            if let formMessage {
                Text(formMessage)
                    .font(.caption)
                    .foregroundColor(formMessageIsError ? .red : .green)
                    .padding(.horizontal, DesignSizes.inspectorPaddingH)
            }
        }
        .padding(.bottom, DesignSizes.fieldGroupMarginBottom)
        .onAppear { loadValues() }
        .onChange(of: nodeIndex) { _ in loadValues() }
        .onChange(of: elevationText) { _ in scheduleNodeFieldCommit() }
        .onChange(of: baseDemandText) { _ in scheduleNodeFieldCommit() }
        .onChange(of: xCoordText) { _ in scheduleNodeFieldCommit() }
        .onChange(of: yCoordText) { _ in scheduleNodeFieldCommit() }
    }

    private func loadValues() {
        nodeCommitTask?.cancel()
        nodeCommitTask = nil
        do {
            let elevation = try project.getNodeValue(nodeIndex: nodeIndex, param: .elevation)
            let baseDemand = try project.getNodeValue(nodeIndex: nodeIndex, param: .basedemand)
            let x = try project.getNodeValue(nodeIndex: nodeIndex, param: .xcoord)
            let y = try project.getNodeValue(nodeIndex: nodeIndex, param: .ycoord)
            elevationText = String(format: "%.4f", elevation)
            baseDemandText = String(format: "%.4f", baseDemand)
            xCoordText = String(format: "%.4f", x)
            yCoordText = String(format: "%.4f", y)
            committedElevationText = elevationText
            committedBaseDemandText = baseDemandText
            committedXCoordText = xCoordText
            committedYCoordText = yCoordText
            formMessage = nil
            formMessageIsError = false
        } catch {
            formMessage = "读取节点属性失败: \(error)"
            formMessageIsError = true
        }
    }

    private func scheduleNodeFieldCommit() {
        nodeCommitTask?.cancel()
        let capturedIndex = nodeIndex
        nodeCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: PropertyInspectorAutosave.fieldCommitDebounceNs)
            guard !Task.isCancelled else { return }
            commitNodeFieldsIfNeeded(expectedNodeIndex: capturedIndex)
        }
    }

    private func commitNodeFieldsIfNeeded(expectedNodeIndex: Int) {
        guard expectedNodeIndex == nodeIndex else { return }
        guard !nodeID.isEmpty else { return }
        let t = { (s: String) -> String in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let elevation = Double(t(elevationText)),
              let baseDemand = Double(t(baseDemandText)),
              let xCoord = Double(t(xCoordText)),
              let yCoord = Double(t(yCoordText)) else {
            return
        }
        var changed: Set<InpNodePatchField> = []
        if elevationText != committedElevationText { changed.insert(.elevation) }
        if baseDemandText != committedBaseDemandText { changed.insert(.baseDemand) }
        if xCoordText != committedXCoordText { changed.insert(.xCoord) }
        if yCoordText != committedYCoordText { changed.insert(.yCoord) }
        guard !changed.isEmpty else { return }

        appState.updateNodeCoreProperties(
            nodeID: nodeID,
            elevation: elevation,
            baseDemand: baseDemand,
            xCoord: xCoord,
            yCoord: yCoord,
            changedFields: changed
        )
        if let err = appState.errorMessage, err.contains("更新节点属性失败") {
            formMessage = err
            formMessageIsError = true
            return
        }
        formMessage = nil
        formMessageIsError = false
        committedElevationText = elevationText
        committedBaseDemandText = baseDemandText
        committedXCoordText = xCoordText
        committedYCoordText = yCoordText
    }
}

private struct LinkBasicInfoSection: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var appState: AppState
    let project: EpanetProject
    let linkIndex: Int
    let units: PropertyUnits

    @State private var lengthText = ""
    @State private var diameterText = ""
    @State private var roughnessText = ""
    @State private var committedLengthText = ""
    @State private var committedDiameterText = ""
    @State private var committedRoughnessText = ""
    @State private var formMessage: String?
    @State private var formMessageIsError = false
    @State private var linkCommitTask: Task<Void, Never>?

    private var linkID: String {
        (try? project.getLinkId(index: linkIndex)) ?? ""
    }
    private var nodesText: String {
        guard let (n1, n2) = try? project.getLinkNodes(linkIndex: linkIndex) else { return "—" }
        return "\(n1 + 1) → \(n2 + 1)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("基本信息")
                .font(DesignFonts.fieldLabel)
                .foregroundColor(colorScheme == .dark ? DesignColors.darkText3 : DesignColors.lightText3)
                .textCase(.uppercase)
                .padding(.horizontal, DesignSizes.inspectorPaddingH)

            PropertyFieldRow(label: "ID", value: linkID)
            PropertyFieldRow(label: "节点", value: nodesText)
            PropertyFieldRow(label: units.length, value: $lengthText)
            PropertyFieldRow(label: units.diameter, value: $diameterText)
            PropertyFieldRow(label: "糙率", value: $roughnessText)

            HStack(spacing: 8) {
                Button("刷新") { loadValues() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, DesignSizes.inspectorPaddingH)
            .padding(.top, 4)

            if let formMessage {
                Text(formMessage)
                    .font(.caption)
                    .foregroundColor(formMessageIsError ? .red : .green)
                    .padding(.horizontal, DesignSizes.inspectorPaddingH)
            }
        }
        .padding(.bottom, DesignSizes.fieldGroupMarginBottom)
        .onAppear { loadValues() }
        .onChange(of: linkIndex) { _ in loadValues() }
        .onChange(of: lengthText) { _ in scheduleLinkFieldCommit() }
        .onChange(of: diameterText) { _ in scheduleLinkFieldCommit() }
        .onChange(of: roughnessText) { _ in scheduleLinkFieldCommit() }
    }

    private func loadValues() {
        linkCommitTask?.cancel()
        linkCommitTask = nil
        do {
            let length = try project.getLinkValue(linkIndex: linkIndex, param: .length)
            let diameter = try project.getLinkValue(linkIndex: linkIndex, param: .diameter)
            let roughness = try project.getLinkValue(linkIndex: linkIndex, param: .roughness)
            lengthText = String(format: "%.4f", length)
            diameterText = String(format: "%.4f", diameter)
            roughnessText = String(format: "%.4f", roughness)
            committedLengthText = lengthText
            committedDiameterText = diameterText
            committedRoughnessText = roughnessText
            formMessage = nil
            formMessageIsError = false
        } catch {
            formMessage = "读取管段属性失败: \(error)"
            formMessageIsError = true
        }
    }

    private func scheduleLinkFieldCommit() {
        linkCommitTask?.cancel()
        let capturedIndex = linkIndex
        linkCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: PropertyInspectorAutosave.fieldCommitDebounceNs)
            guard !Task.isCancelled else { return }
            commitLinkFieldsIfNeeded(expectedLinkIndex: capturedIndex)
        }
    }

    private func commitLinkFieldsIfNeeded(expectedLinkIndex: Int) {
        guard expectedLinkIndex == linkIndex else { return }
        guard !linkID.isEmpty else { return }
        let t = { (s: String) -> String in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let length = Double(t(lengthText)),
              let diameter = Double(t(diameterText)),
              let roughness = Double(t(roughnessText)) else {
            return
        }
        var changed: Set<InpLinkPatchField> = []
        if lengthText != committedLengthText { changed.insert(.length) }
        if diameterText != committedDiameterText { changed.insert(.diameter) }
        if roughnessText != committedRoughnessText { changed.insert(.roughness) }
        guard !changed.isEmpty else { return }

        appState.updateLinkCoreProperties(
            linkID: linkID,
            length: length,
            diameter: diameter,
            roughness: roughness,
            changedFields: changed
        )
        if let err = appState.errorMessage, err.contains("更新管段属性失败") {
            formMessage = err
            formMessageIsError = true
            return
        }
        formMessage = nil
        formMessageIsError = false
        committedLengthText = lengthText
        committedDiameterText = diameterText
        committedRoughnessText = roughnessText
    }
}

private struct PropertyFieldRow: View {
    @Environment(\.colorScheme) var colorScheme
    let label: String
    @Binding var value: String
    let readOnly: Bool

    init(label: String, value: String) {
        self.label = label
        self._value = .constant(value)
        self.readOnly = true
    }
    init(label: String, value: Binding<String>) {
        self.label = label
        self._value = value
        self.readOnly = false
    }

    private var surface2: Color { colorScheme == .dark ? DesignColors.darkSurface2 : DesignColors.lightSurface2 }
    private var border: Color { colorScheme == .dark ? DesignColors.darkBorder : DesignColors.lightBorder }
    private var text2: Color { colorScheme == .dark ? DesignColors.darkText2 : DesignColors.lightText2 }
    private var text: Color { colorScheme == .dark ? DesignColors.darkText : DesignColors.lightText }
    private var accent: Color { colorScheme == .dark ? DesignColors.darkAccent : DesignColors.lightAccent }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(DesignFonts.fieldName)
                .foregroundColor(text2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if readOnly {
                Text(value)
                    .font(DesignFonts.fieldValue)
                    .foregroundColor(text)
                    .frame(minWidth: DesignSizes.fieldValMinWidth, alignment: .trailing)
                    .padding(.horizontal, DesignSizes.fieldValPaddingH)
                    .padding(.vertical, DesignSizes.fieldValPaddingV)
                    .background(surface2, in: RoundedRectangle(cornerRadius: DesignSizes.fieldValCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: DesignSizes.fieldValCornerRadius).stroke(border, lineWidth: 1))
            } else {
                TextField("", text: $value)
                    .font(DesignFonts.fieldValue)
                    .foregroundColor(accent)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: DesignSizes.fieldValMinWidth)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, DesignSizes.fieldValPaddingH)
                    .padding(.vertical, DesignSizes.fieldValPaddingV)
                    .background(accent.opacity(colorScheme == .dark ? 0.15 : 0.05), in: RoundedRectangle(cornerRadius: DesignSizes.fieldValCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: DesignSizes.fieldValCornerRadius).stroke(accent, lineWidth: 1))
            }
        }
        .padding(.horizontal, DesignSizes.inspectorPaddingH)
    }
}

private struct PropertyFieldGroup: View {
    @Environment(\.colorScheme) var colorScheme
    let label: String
    let rows: [(String, String)]

    private var surface2: Color { colorScheme == .dark ? DesignColors.darkSurface2 : DesignColors.lightSurface2 }
    private var border: Color { colorScheme == .dark ? DesignColors.darkBorder : DesignColors.lightBorder }
    private var text2: Color { colorScheme == .dark ? DesignColors.darkText2 : DesignColors.lightText2 }
    private var text3: Color { colorScheme == .dark ? DesignColors.darkText3 : DesignColors.lightText3 }
    private var text: Color { colorScheme == .dark ? DesignColors.darkText : DesignColors.lightText }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSizes.fieldRowMarginBottom) {
            Text(label)
                .font(DesignFonts.fieldLabel)
                .foregroundColor(text3)
                .textCase(.uppercase)
                .padding(.bottom, 6)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, pair in
                HStack(alignment: .center, spacing: 8) {
                    Text(pair.0)
                        .font(DesignFonts.fieldName)
                        .foregroundColor(text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(pair.1)
                        .font(DesignFonts.fieldValue)
                        .foregroundColor(text)
                        .frame(minWidth: DesignSizes.fieldValMinWidth, alignment: .trailing)
                        .padding(.horizontal, DesignSizes.fieldValPaddingH)
                        .padding(.vertical, DesignSizes.fieldValPaddingV)
                        .background(surface2, in: RoundedRectangle(cornerRadius: DesignSizes.fieldValCornerRadius))
                        .overlay(RoundedRectangle(cornerRadius: DesignSizes.fieldValCornerRadius).stroke(border, lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, DesignSizes.inspectorPaddingH)
        .padding(.bottom, DesignSizes.fieldGroupMarginBottom)
    }
}
