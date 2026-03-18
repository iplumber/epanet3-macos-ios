import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import UniformTypeIdentifiers
import EPANET3Bridge
import EPANET3Renderer

/// 最近一次运行计算的结果，供界面与后续查询展示。
enum RunResult: Equatable {
    case success(elapsed: TimeInterval)
    case failure(message: String)
}

enum EditorMode: String {
    case browse
    case add
    case edit
    case delete
    case result
}

enum ResultOverlayMode: String, CaseIterable {
    case none
    case pressure
    case flow
}

@MainActor
public final class AppState: ObservableObject {
    @Published var scene: NetworkScene?
    @Published var project: EpanetProject?
    @Published var filePath: String?
    @Published var errorMessage: String?
    @Published var isLoading = false
    /// 最近一次运行计算的结果；nil 表示尚未运行或已清除。
    @Published var runResult: RunResult?
    @Published var isRunning = false
    /// 从当前 .inp 的 [OPTIONS] 解析的 Flow Units（如 "GPM", "LPS"），用于属性面板单位标签；nil 表示未解析或非 project 模式。
    @Published var inpFlowUnits: String?
    /// iOS：为 true 时弹出文件选择（.fileImporter）
    @Published var showFileImporter = false
    /// C1：统一编辑状态机当前模式。
    @Published var editorMode: EditorMode = .browse
    /// C1：画布当前选中节点索引（后续 C2 会扩展到稳定标识）。
    @Published var selectedNodeIndex: Int?
    /// C1：画布当前选中管段索引（后续 C2 会扩展到稳定标识）。
    @Published var selectedLinkIndex: Int?
    /// C2：当前选中节点稳定标识（ID）。
    @Published var selectedNodeID: String?
    /// C2：当前选中管段稳定标识（ID）。
    @Published var selectedLinkID: String?
    /// C1：属性面板可见状态由 AppState 统一管理。
    @Published var isPropertyPanelVisible = false
    /// 最近一次错误定位到的节点索引（用于 UI 自动选中）。
    @Published var errorFocusNodeIndex: Int?
    /// 最近一次错误定位到的管段索引（用于 UI 自动选中）。
    @Published var errorFocusLinkIndex: Int?
    /// D2: 请求画布聚焦到当前选中对象的触发器。
    @Published var focusSelectionToken: Int = 0
    /// D4：结果上图模式（无/压力/流量）。
    @Published var resultOverlayMode: ResultOverlayMode = .none
    /// D4：节点压力结果（按节点索引）。
    @Published var nodePressureValues: [Float] = []
    /// D4：管段流量结果（按管段索引）。
    @Published var linkFlowValues: [Float] = []

    public init() {}

    func setEditorMode(_ mode: EditorMode) {
        editorMode = mode
        switch mode {
        case .browse:
            selectedNodeIndex = nil
            selectedLinkIndex = nil
            selectedNodeID = nil
            selectedLinkID = nil
            isPropertyPanelVisible = false
        case .add, .delete:
            selectedNodeIndex = nil
            selectedLinkIndex = nil
            selectedNodeID = nil
            selectedLinkID = nil
            // D2: 添加/删除模式下打开工具面板。
            isPropertyPanelVisible = true
        case .edit:
            // edit 模式需要选中对象，若无选中则仅切换模式。
            break
        case .result:
            // 结果模式下保留当前选中对象，便于对照查看。
            break
        }
    }

    func setSelection(nodeIndex: Int?, linkIndex: Int?, openPanel: Bool = true) {
        selectedNodeIndex = nodeIndex
        selectedLinkIndex = linkIndex
        selectedNodeID = nil
        selectedLinkID = nil
        if let p = project {
            if let i = nodeIndex {
                selectedNodeID = try? p.getNodeId(index: i)
            } else if let i = linkIndex {
                selectedLinkID = try? p.getLinkId(index: i)
            }
        }
        if nodeIndex != nil || linkIndex != nil {
            if editorMode != .add && editorMode != .delete {
                editorMode = .edit
            }
            if openPanel { isPropertyPanelVisible = true }
        } else if editorMode == .edit {
            editorMode = .browse
            if openPanel { isPropertyPanelVisible = false }
        }
    }

    func clearSelection(closePanel: Bool = true) {
        selectedNodeIndex = nil
        selectedLinkIndex = nil
        selectedNodeID = nil
        selectedLinkID = nil
        if editorMode == .edit {
            editorMode = .browse
        }
        if closePanel { isPropertyPanelVisible = false }
    }

    func requestFocusOnSelection() {
        focusSelectionToken &+= 1
    }

    /// C2：当 project 重新加载后，用稳定 ID 重新解析索引，避免对象增删后的索引漂移。
    func syncSelectionIndicesFromIDs() {
        guard let p = project else {
            selectedNodeIndex = nil
            selectedLinkIndex = nil
            return
        }
        if let nodeID = selectedNodeID {
            selectedNodeIndex = try? p.getNodeIndex(id: nodeID)
            selectedLinkIndex = nil
            return
        }
        if let linkID = selectedLinkID {
            selectedLinkIndex = try? p.getLinkIndex(id: linkID)
            selectedNodeIndex = nil
            return
        }
        selectedNodeIndex = nil
        selectedLinkIndex = nil
    }

    /// C3：从当前 project 重建画布场景，并按稳定 ID 恢复选中对象。
    func refreshSceneFromProject(
        preserveSelection: Bool = true,
        sceneLabel: String = "场景刷新"
    ) {
        guard let p = project else {
            scene = nil
            clearSelection()
            return
        }

        let previousNodeID = selectedNodeID
        let previousLinkID = selectedLinkID
        let previousPanelVisible = isPropertyPanelVisible

        do {
            scene = try Self.buildScene(from: p)
            if preserveSelection {
                selectedNodeID = previousNodeID
                selectedLinkID = previousLinkID
                syncSelectionIndicesFromIDs()
                isPropertyPanelVisible = previousPanelVisible && ((selectedNodeIndex != nil) || (selectedLinkIndex != nil))
            } else {
                clearSelection()
            }
        } catch let error as EpanetError {
            errorMessage = Self.formatLocalizedEpanetError(error, scene: "\(sceneLabel)失败")
            let focus = Self.resolveErrorFocus(error, project: p)
            errorFocusNodeIndex = focus.nodeIndex
            errorFocusLinkIndex = focus.linkIndex
            if focus.nodeIndex != nil || focus.linkIndex != nil {
                setSelection(nodeIndex: focus.nodeIndex, linkIndex: focus.linkIndex, openPanel: true)
            }
        } catch {
            errorMessage = "\(sceneLabel)失败: \(error)"
        }
    }

    /// C3：统一模型变更入口；执行变更后自动刷新 scene 并恢复选中。
    func applyProjectMutation(
        sceneLabel: String = "模型更新",
        mutation: (EpanetProject) throws -> Void
    ) {
        guard let p = project else {
            errorMessage = "\(sceneLabel)失败: EPANET 项目未创建"
            return
        }
        do {
            try mutation(p)
            errorMessage = nil
            refreshSceneFromProject(preserveSelection: true, sceneLabel: sceneLabel)
        } catch let error as EpanetError {
            errorMessage = Self.formatLocalizedEpanetError(error, scene: "\(sceneLabel)失败")
            let focus = Self.resolveErrorFocus(error, project: p)
            errorFocusNodeIndex = focus.nodeIndex
            errorFocusLinkIndex = focus.linkIndex
            if focus.nodeIndex != nil || focus.linkIndex != nil {
                setSelection(nodeIndex: focus.nodeIndex, linkIndex: focus.linkIndex, openPanel: true)
            }
        } catch {
            errorMessage = "\(sceneLabel)失败: \(error)"
        }
    }

    /// D1：更新节点核心属性（第二版：高程、基础需水量、X/Y 坐标）。
    func updateNodeCoreProperties(
        nodeID: String,
        elevation: Double,
        baseDemand: Double,
        xCoord: Double,
        yCoord: Double
    ) {
        applyProjectMutation(sceneLabel: "更新节点属性") { p in
            let nodeIndex = try p.getNodeIndex(id: nodeID)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .elevation, value: elevation)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .basedemand, value: baseDemand)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .xcoord, value: xCoord)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .ycoord, value: yCoord)
            selectedNodeID = nodeID
            selectedLinkID = nil
        }
    }

    /// D1：更新管段核心属性（首批：长度、管径、糙率）。
    func updateLinkCoreProperties(linkID: String, length: Double, diameter: Double, roughness: Double) {
        applyProjectMutation(sceneLabel: "更新管段属性") { p in
            let linkIndex = try p.getLinkIndex(id: linkID)
            try p.setLinkValue(linkIndex: linkIndex, param: .length, value: length)
            try p.setLinkValue(linkIndex: linkIndex, param: .diameter, value: diameter)
            try p.setLinkValue(linkIndex: linkIndex, param: .roughness, value: roughness)
            selectedLinkID = linkID
            selectedNodeID = nil
        }
    }

    /// D2：新增节点（Junction）并设置核心属性。
    func addJunction(nodeID: String, elevation: Double, baseDemand: Double, xCoord: Double, yCoord: Double) {
        applyProjectMutation(sceneLabel: "新增节点") { p in
            _ = try p.createNode(id: nodeID, type: .junction)
            let nodeIndex = try p.getNodeIndex(id: nodeID)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .elevation, value: elevation)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .basedemand, value: baseDemand)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .xcoord, value: xCoord)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .ycoord, value: yCoord)
            selectedNodeID = nodeID
            selectedLinkID = nil
            editorMode = .edit
            isPropertyPanelVisible = true
        }
        if errorMessage == nil {
            requestFocusOnSelection()
        }
    }

    /// D2：新增管段（Pipe）并设置核心属性。
    func addPipe(
        linkID: String,
        fromNodeID: String,
        toNodeID: String,
        length: Double,
        diameter: Double,
        roughness: Double
    ) {
        applyProjectMutation(sceneLabel: "新增管段") { p in
            let fromIndex = try p.getNodeIndex(id: fromNodeID)
            let toIndex = try p.getNodeIndex(id: toNodeID)
            _ = try p.createLink(id: linkID, type: .pipe, fromNodeIndex: fromIndex, toNodeIndex: toIndex)
            let linkIndex = try p.getLinkIndex(id: linkID)
            try p.setLinkValue(linkIndex: linkIndex, param: .length, value: length)
            try p.setLinkValue(linkIndex: linkIndex, param: .diameter, value: diameter)
            try p.setLinkValue(linkIndex: linkIndex, param: .roughness, value: roughness)
            selectedLinkID = linkID
            selectedNodeID = nil
            editorMode = .edit
            isPropertyPanelVisible = true
        }
        if errorMessage == nil {
            requestFocusOnSelection()
        }
    }

    /// D2：删除当前选中对象（优先节点，其次管段）。
    func deleteSelectedObject() {
        if let nodeID = selectedNodeID {
            applyProjectMutation(sceneLabel: "删除节点") { p in
                try p.deleteNode(id: nodeID)
                selectedNodeID = nil
                selectedLinkID = nil
                selectedNodeIndex = nil
                selectedLinkIndex = nil
                editorMode = .delete
                isPropertyPanelVisible = true
            }
            return
        }
        if let linkID = selectedLinkID {
            applyProjectMutation(sceneLabel: "删除管段") { p in
                try p.deleteLink(id: linkID)
                selectedNodeID = nil
                selectedLinkID = nil
                selectedNodeIndex = nil
                selectedLinkIndex = nil
                editorMode = .delete
                isPropertyPanelVisible = true
            }
            return
        }
        errorMessage = "删除失败: 当前没有选中节点或管段。"
    }

    /// D3：更新计算参数（第一版）。
    func updateSimulationSettings(
        trials: Int,
        accuracy: Double,
        demandMultiplier: Double,
        duration: Int,
        hydraulicStep: Int,
        reportStep: Int
    ) {
        applyProjectMutation(sceneLabel: "更新计算参数") { p in
            try p.setOption(param: .trials, value: Double(trials))
            try p.setOption(param: .accuracy, value: accuracy)
            try p.setOption(param: .demandMult, value: demandMultiplier)
            try p.setTimeParam(param: .duration, value: duration)
            try p.setTimeParam(param: .hydStep, value: hydraulicStep)
            try p.setTimeParam(param: .reportStep, value: reportStep)
        }
    }

    /// D3 第二版：通过重载式策略切换 Flow Units（当前最小支持 GPM/LPS）。
    func switchFlowUnitsReload(targetFlowUnits: String) {
        let target = targetFlowUnits.uppercased().trimmingCharacters(in: .whitespaces)
        guard target == "GPM" || target == "LPS" else {
            errorMessage = "切换 Flow Units 失败: 当前仅支持 GPM 或 LPS。"
            return
        }
        guard let currentPath = filePath, !currentPath.isEmpty else {
            errorMessage = "切换 Flow Units 失败: 当前没有可重载的 .inp 文件路径。"
            return
        }

        if inpFlowUnits?.uppercased() == target {
            errorMessage = "Flow Units 已是 \(target)。"
            return
        }

        let previousSelection = (selectedNodeID, selectedLinkID, isPropertyPanelVisible)
        do {
            let input = try String(contentsOfFile: currentPath, encoding: .utf8)
            let rewritten = Self.rewriteFlowUnitsInInp(input, targetFlowUnits: target)
            let base = URL(fileURLWithPath: currentPath).deletingPathExtension().lastPathComponent
            let suffix = String(UUID().uuidString.prefix(8))
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(base)_units_\(target)_\(suffix).inp")
            try rewritten.write(to: tempURL, atomically: true, encoding: .utf8)

            let proj = EpanetProject()
            try proj.load(path: tempURL.path)

            project = proj
            filePath = tempURL.path
            inpFlowUnits = InpOptionsParser.parseFlowUnits(path: tempURL.path) ?? target
            selectedNodeID = previousSelection.0
            selectedLinkID = previousSelection.1
            isPropertyPanelVisible = previousSelection.2
            refreshSceneFromProject(preserveSelection: true, sceneLabel: "切换 Flow Units")
            errorMessage = "已切换 Flow Units 为 \(target)（已重载临时副本）。"
        } catch let error as EpanetError {
            errorMessage = Self.formatLocalizedEpanetError(error, scene: "切换 Flow Units 失败")
        } catch {
            errorMessage = "切换 Flow Units 失败: \(error)"
        }
    }

    /// D2 第二版：按节点 ID 直接删除。
    func deleteNodeByID(_ nodeID: String) {
        guard !nodeID.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "删除节点失败: 节点 ID 不能为空。"
            return
        }
        applyProjectMutation(sceneLabel: "删除节点") { p in
            try p.deleteNode(id: nodeID)
            if selectedNodeID == nodeID {
                selectedNodeID = nil
                selectedNodeIndex = nil
            }
            if selectedLinkID == nil {
                selectedLinkIndex = nil
            }
            editorMode = .delete
            isPropertyPanelVisible = true
        }
    }

    /// D2 第二版：按管段 ID 直接删除。
    func deleteLinkByID(_ linkID: String) {
        guard !linkID.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "删除管段失败: 管段 ID 不能为空。"
            return
        }
        applyProjectMutation(sceneLabel: "删除管段") { p in
            try p.deleteLink(id: linkID)
            if selectedLinkID == linkID {
                selectedLinkID = nil
                selectedLinkIndex = nil
            }
            if selectedNodeID == nil {
                selectedNodeIndex = nil
            }
            editorMode = .delete
            isPropertyPanelVisible = true
        }
    }

    private static nonisolated func formatLocalizedEpanetError(_ error: EpanetError, scene: String) -> String {
        switch error {
        case .apiContext(let code, let context):
            let detail = EpanetProject.describeError(code: code)
            var object = "未知对象"
            if let t = context.objectType { object = t }
            if let id = context.objectID {
                object += "(ID=\(id))"
            } else if let index = context.objectIndex {
                object += "(索引=\(index))"
            }
            let param = context.parameter.map { "，参数=\($0)" } ?? ""
            return "\(scene): [\(code)] \(detail)；接口=\(context.api)，对象=\(object)\(param)"
        case .apiError(let code):
            let detail = EpanetProject.describeError(code: code)
            return "\(scene): [\(code)] \(detail)"
        case .projectNotCreated:
            return "\(scene): EPANET 项目未创建"
        }
    }

    private static nonisolated func resolveErrorFocus(
        _ error: EpanetError,
        project: EpanetProject?
    ) -> (nodeIndex: Int?, linkIndex: Int?) {
        guard case .apiContext(_, let context) = error else { return (nil, nil) }
        if context.objectType == "节点" {
            if let i = context.objectIndex { return (i, nil) }
            if let id = context.objectID, let p = project, let i = try? p.getNodeIndex(id: id) {
                return (i, nil)
            }
            return (nil, nil)
        }
        if context.objectType == "管段" {
            if let i = context.objectIndex { return (nil, i) }
            if let id = context.objectID, let p = project, let i = try? p.getLinkIndex(id: id) {
                return (nil, i)
            }
            return (nil, nil)
        }
        return (nil, nil)
    }

    public func openFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "inp") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "选择 .inp 管网文件"
        panel.message = "仅支持 .inp 格式"
        if panel.runModal() == .OK, let url = panel.url {
            load(path: url.path)
        }
        NSCursor.arrow.set()
        #else
        showFileImporter = true
        #endif
    }

    /// 从已选 URL 加载（iOS 在 fileImporter 回调中调用，需先 startAccessingSecurityScopedResource）
    public func openFileFromURL(_ url: URL) {
        load(path: url.path)
    }

    func load(path: String) {
        isLoading = true
        errorMessage = nil
        Task.detached(priority: .userInitiated) {
            var loadedProject: EpanetProject?
            do {
                let proj = EpanetProject()
                loadedProject = proj
                try proj.load(path: path)
                let scene = try Self.buildScene(from: proj)
                let flowUnits = InpOptionsParser.parseFlowUnits(path: path)
                await MainActor.run { [weak self] in
                    self?.project = proj
                    self?.scene = scene
                    self?.filePath = path
                    self?.errorMessage = nil
                    self?.inpFlowUnits = flowUnits
                    self?.editorMode = .browse
                    self?.selectedNodeIndex = nil
                    self?.selectedLinkIndex = nil
                    self?.selectedNodeID = nil
                    self?.selectedLinkID = nil
                    self?.isPropertyPanelVisible = false
                    self?.errorFocusNodeIndex = nil
                    self?.errorFocusLinkIndex = nil
                    self?.resultOverlayMode = .none
                    self?.nodePressureValues = []
                    self?.linkFlowValues = []
                    self?.refreshSceneFromProject(preserveSelection: false, sceneLabel: "加载 .inp")
                    self?.isLoading = false
                }
            } catch EpanetError.apiError(200) {
                do {
                    let scene = try InpDisplayParser.parse(path: path)
                    await MainActor.run { [weak self] in
                        self?.project = nil
                        self?.scene = scene
                        self?.filePath = path
                        self?.errorMessage = "仅显示模式（不可计算）"
                        self?.inpFlowUnits = InpOptionsParser.parseFlowUnits(path: path)
                        self?.editorMode = .browse
                        self?.selectedNodeIndex = nil
                        self?.selectedLinkIndex = nil
                        self?.selectedNodeID = nil
                        self?.selectedLinkID = nil
                        self?.isPropertyPanelVisible = false
                        self?.errorFocusNodeIndex = nil
                        self?.errorFocusLinkIndex = nil
                        self?.resultOverlayMode = .none
                        self?.nodePressureValues = []
                        self?.linkFlowValues = []
                        self?.isLoading = false
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.errorMessage = "加载失败（仅显示解析）: \(error)"
                        self?.scene = nil
                        self?.project = nil
                        self?.filePath = nil
                        self?.inpFlowUnits = nil
                        self?.errorFocusNodeIndex = nil
                        self?.errorFocusLinkIndex = nil
                        self?.isLoading = false
                    }
                }
            } catch let error as EpanetError {
                let message = Self.formatLocalizedEpanetError(error, scene: "加载失败（加载 .inp）")
                let focus = Self.resolveErrorFocus(error, project: loadedProject)
                await MainActor.run { [weak self] in
                    self?.errorMessage = message
                    self?.scene = nil
                    self?.project = nil
                    self?.filePath = nil
                    self?.inpFlowUnits = nil
                    self?.errorFocusNodeIndex = focus.nodeIndex
                    self?.errorFocusLinkIndex = focus.linkIndex
                    self?.isLoading = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = "加载失败: \(error)"
                    self?.scene = nil
                    self?.project = nil
                    self?.filePath = nil
                    self?.inpFlowUnits = nil
                    self?.errorFocusNodeIndex = nil
                    self?.errorFocusLinkIndex = nil
                    self?.isLoading = false
                }
            }
        }
    }

    /// 使用当前打开的 .inp 在内存中的 project 上执行水力求解，结果保留在 project 中，属性面板的压力/水头/流量/流速会正确显示。
    func runCalculation() {
        guard let path = filePath, !path.isEmpty else { return }
        isRunning = true
        runResult = nil
        let inpPath = path
        let previousSelection = (selectedNodeID, selectedLinkID, isPropertyPanelVisible)

        Task.detached(priority: .userInitiated) {
            let start = CFAbsoluteTimeGetCurrent()
            var loadedProject: EpanetProject?
            do {
                let proj = EpanetProject()
                loadedProject = proj
                try proj.load(path: inpPath)
                try proj.initSolver(initFlows: false)
                var t: Int32 = 0
                repeat {
                    try proj.runSolver(time: &t)
                    var dt: Int32 = 0
                    try proj.advanceSolver(dt: &dt)
                } while t > 0
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                await MainActor.run { [weak self] in
                    self?.project = proj
                    self?.selectedNodeID = previousSelection.0
                    self?.selectedLinkID = previousSelection.1
                    self?.isPropertyPanelVisible = previousSelection.2
                    self?.runResult = .success(elapsed: elapsed)
                    self?.editorMode = .result
                    self?.errorFocusNodeIndex = nil
                    self?.errorFocusLinkIndex = nil
                    self?.refreshSceneFromProject(preserveSelection: true, sceneLabel: "计算完成后刷新")
                    self?.refreshResultData()
                    self?.isRunning = false
                }
            } catch let error as EpanetError {
                let message = Self.formatLocalizedEpanetError(error, scene: "运行失败（求解器）")
                let focus = Self.resolveErrorFocus(error, project: loadedProject)
                await MainActor.run { [weak self] in
                    self?.runResult = .failure(message: message)
                    self?.editorMode = .result
                    self?.errorFocusNodeIndex = focus.nodeIndex
                    self?.errorFocusLinkIndex = focus.linkIndex
                    if focus.nodeIndex != nil || focus.linkIndex != nil {
                        self?.setSelection(nodeIndex: focus.nodeIndex, linkIndex: focus.linkIndex, openPanel: true)
                    }
                    self?.isRunning = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.runResult = .failure(message: String(describing: error))
                    self?.errorFocusNodeIndex = nil
                    self?.errorFocusLinkIndex = nil
                    self?.isRunning = false
                }
            }
        }
    }

    /// D4：刷新用于上图展示的结果数组（压力/流量）。
    func refreshResultData() {
        guard let p = project else {
            nodePressureValues = []
            linkFlowValues = []
            return
        }
        do {
            let nodeCount = try p.nodeCount()
            let linkCount = try p.linkCount()
            var nodeValues: [Float] = []
            nodeValues.reserveCapacity(nodeCount)
            for i in 0..<nodeCount {
                let v = try p.getNodeValue(nodeIndex: i, param: .pressure)
                nodeValues.append(Float(v))
            }
            var linkValues: [Float] = []
            linkValues.reserveCapacity(linkCount)
            for i in 0..<linkCount {
                let v = try p.getLinkValue(linkIndex: i, param: .flow)
                linkValues.append(Float(v))
            }
            nodePressureValues = nodeValues
            linkFlowValues = linkValues
        } catch {
            // 保持上次可用结果，避免 UI 抖动；同时给出错误提示。
            errorMessage = "刷新结果数据失败: \(error)"
        }
    }

    func setResultOverlayMode(_ mode: ResultOverlayMode) {
        resultOverlayMode = mode
        if mode != .none && nodePressureValues.isEmpty && linkFlowValues.isEmpty {
            refreshResultData()
        }
    }

    private static nonisolated func buildScene(from proj: EpanetProject) throws -> NetworkScene {
        let nodeCount = try proj.nodeCount()
        let linkCount = try proj.linkCount()

        var nodes: [NodeVertex] = []
        for i in 0..<nodeCount {
            let (x, y) = try proj.getNodeCoords(nodeIndex: i)
            if x > -1e19 && y > -1e19 {
                nodes.append(NodeVertex(x: Float(x), y: Float(y), nodeIndex: i))
            }
        }

        var links: [LinkVertex] = []
        for i in 0..<linkCount {
            let (n1, n2) = try proj.getLinkNodes(linkIndex: i)
            guard n1 >= 0, n2 >= 0, n1 < nodeCount, n2 < nodeCount else { continue }
            let (x1, y1) = try proj.getNodeCoords(nodeIndex: n1)
            let (x2, y2) = try proj.getNodeCoords(nodeIndex: n2)
            if x1 > -1e19, y1 > -1e19, x2 > -1e19, y2 > -1e19 {
                links.append(LinkVertex(x1: Float(x1), y1: Float(y1), x2: Float(x2), y2: Float(y2), linkIndex: i))
            }
        }

        if nodes.isEmpty && links.isEmpty {
            throw EpanetError.apiError(-1)
        }

        if nodes.isEmpty {
            nodes = [NodeVertex(x: 0, y: 0, nodeIndex: 0)]
        }

        return NetworkScene(nodes: nodes, links: links)
    }

    private static nonisolated func rewriteFlowUnitsInInp(
        _ content: String,
        targetFlowUnits: String
    ) -> String {
        var lines = content.components(separatedBy: .newlines)
        var optionsStart: Int?
        var optionsEnd: Int?

        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                let upper = trimmed.uppercased()
                if optionsStart == nil && upper.starts(with: "[OPTION") {
                    optionsStart = i
                } else if optionsStart != nil {
                    optionsEnd = i
                    break
                }
            }
        }

        if optionsStart == nil {
            if !lines.isEmpty, !lines.last!.isEmpty {
                lines.append("")
            }
            lines.append("[OPTIONS]")
            lines.append("  UNITS \(targetFlowUnits)")
            return lines.joined(separator: "\n")
        }

        let start = optionsStart!
        let end = optionsEnd ?? lines.count
        var replaced = false
        if start + 1 < end {
            for i in (start + 1)..<end {
                let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix(";") { continue }
                if isFlowUnitsLine(trimmed.uppercased()) {
                    lines[i] = "  UNITS \(targetFlowUnits)"
                    replaced = true
                    break
                }
            }
        }
        if !replaced {
            lines.insert("  UNITS \(targetFlowUnits)", at: min(start + 1, lines.count))
        }
        return lines.joined(separator: "\n")
    }

    private static nonisolated func isFlowUnitsLine(_ upperTrimmedLine: String) -> Bool {
        if upperTrimmedLine.starts(with: "UNITS ") { return true }
        if upperTrimmedLine.starts(with: "FLOW_UNITS") { return true }
        if upperTrimmedLine.starts(with: "FLOWUNITS") { return true }
        if upperTrimmedLine.starts(with: "FLOW UNITS") { return true }
        return false
    }
}
