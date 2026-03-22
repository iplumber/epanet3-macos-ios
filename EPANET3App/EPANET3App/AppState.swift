import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import UniformTypeIdentifiers
import EPANET3Bridge
import EPANET3Renderer

struct RecentFileItem: Codable, Identifiable, Equatable {
    var path: String
    var displayName: String
    var lastOpenedAt: Date
    var nodeCount: Int?
    var linkCount: Int?

    var id: String { path }
}

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
    private enum StorageKeys {
        static let recentFiles = "epanet3.recentFiles"
    }

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
    /// 启动页最近打开文件列表（按时间倒序）。
    @Published var recentFiles: [RecentFileItem] = []

    #if os(macOS)
    /// 当前文件的 security-scoped URL，用于保持读写权限。
    private var securityScopedFileURL: URL?
    #endif

    /// 打开 .inp 时解码后的全文快照；用于「保存」时按原结构写回，避免 ProjectWriter 重写导致丢章节/改顺序。
    private var inpSourceSnapshot: String?
    /// 属性面板等写入后待同步到 .inp 的字段级修改；文件菜单「保存」只应用这些补丁，不整文件重写数据行。
    private var inpPendingSaveDelta = InpSaveDelta()

    public init() {
        loadRecentFilesFromStorage()
    }

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

    /// D1：更新节点核心属性（第二版：高程、基础需水量、X/Y 坐标）。`changedFields` 决定写引擎与待落盘 .inp 的字段子集。
    func updateNodeCoreProperties(
        nodeID: String,
        elevation: Double,
        baseDemand: Double,
        xCoord: Double,
        yCoord: Double,
        changedFields: Set<InpNodePatchField>
    ) {
        guard !changedFields.isEmpty else { return }
        applyProjectMutation(sceneLabel: "更新节点属性") { p in
            let nodeIndex = try p.getNodeIndex(id: nodeID)
            if changedFields.contains(.elevation) {
                try p.setNodeValue(nodeIndex: nodeIndex, param: .elevation, value: elevation)
            }
            if changedFields.contains(.baseDemand) {
                try p.setNodeValue(nodeIndex: nodeIndex, param: .basedemand, value: baseDemand)
            }
            if changedFields.contains(.xCoord) {
                try p.setNodeValue(nodeIndex: nodeIndex, param: .xcoord, value: xCoord)
            }
            if changedFields.contains(.yCoord) {
                try p.setNodeValue(nodeIndex: nodeIndex, param: .ycoord, value: yCoord)
            }
            selectedNodeID = nodeID
            selectedLinkID = nil
        }
        if errorMessage == nil {
            inpPendingSaveDelta.record(
                nodeID: nodeID,
                fields: changedFields,
                baseDemandForFile: changedFields.contains(.baseDemand) ? baseDemand : nil
            )
        }
    }

    /// D1：更新管段核心属性（首批：长度、管径、糙率）。`changedFields` 决定写引擎与待落盘 .inp 的字段子集。
    func updateLinkCoreProperties(
        linkID: String,
        length: Double,
        diameter: Double,
        roughness: Double,
        changedFields: Set<InpLinkPatchField>
    ) {
        guard !changedFields.isEmpty else { return }
        applyProjectMutation(sceneLabel: "更新管段属性") { p in
            let linkIndex = try p.getLinkIndex(id: linkID)
            if changedFields.contains(.length) {
                try p.setLinkValue(linkIndex: linkIndex, param: .length, value: length)
            }
            if changedFields.contains(.diameter) {
                try p.setLinkValue(linkIndex: linkIndex, param: .diameter, value: diameter)
            }
            if changedFields.contains(.roughness) {
                try p.setLinkValue(linkIndex: linkIndex, param: .roughness, value: roughness)
            }
            selectedLinkID = linkID
            selectedNodeID = nil
        }
        if errorMessage == nil {
            inpPendingSaveDelta.record(linkID: linkID, fields: changedFields)
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
            invalidateInpSourceSnapshot()
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
            invalidateInpSourceSnapshot()
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
            if errorMessage == nil { invalidateInpSourceSnapshot() }
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
            if errorMessage == nil { invalidateInpSourceSnapshot() }
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
        if errorMessage == nil {
            invalidateInpSourceSnapshot()
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
            inpSourceSnapshot = rewritten
            inpPendingSaveDelta.clear()
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
        if errorMessage == nil { invalidateInpSourceSnapshot() }
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
        if errorMessage == nil { invalidateInpSourceSnapshot() }
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
            stopSecurityScopedAccess()
            _ = url.startAccessingSecurityScopedResource()
            securityScopedFileURL = url
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

    func openRecentFile(_ item: RecentFileItem) {
        let cleanPath = item.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPath.isEmpty else {
            recentFiles.removeAll { $0.path == item.path }
            saveRecentFilesToStorage()
            errorMessage = "无效的路径记录，已从近期打开中移除。"
            return
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: cleanPath, isDirectory: &isDirectory)
        guard exists, !isDirectory.boolValue else {
            recentFiles.removeAll { $0.path.trimmingCharacters(in: .whitespacesAndNewlines) == cleanPath }
            saveRecentFilesToStorage()
            let name = URL(fileURLWithPath: cleanPath).lastPathComponent
            errorMessage = "文件不存在或已移动，已从近期打开中移除：\(name)"
            return
        }
        load(path: cleanPath)
    }

    /// 新建：清空当前项目，回到空白状态。
    public func newProject() {
        #if os(macOS)
        stopSecurityScopedAccess()
        #endif
        project = nil
        scene = nil
        filePath = nil
        errorMessage = nil
        runResult = nil
        inpFlowUnits = nil
        editorMode = .browse
        selectedNodeIndex = nil
        selectedLinkIndex = nil
        selectedNodeID = nil
        selectedLinkID = nil
        isPropertyPanelVisible = false
        errorFocusNodeIndex = nil
        errorFocusLinkIndex = nil
        resultOverlayMode = .none
        nodePressureValues = []
        linkFlowValues = []
        inpSourceSnapshot = nil
        inpPendingSaveDelta.clear()
    }

    /// 增删节点/管段或改写全局计算参数后，快照与磁盘结构不再一致，需退回完整重写或下次保存前重新加载。
    private func invalidateInpSourceSnapshot() {
        inpSourceSnapshot = nil
        inpPendingSaveDelta.clear()
    }

    /// 将当前 project 写入路径：若有快照则仅应用待写增量补丁；无待写项则跳过磁盘写入。无快照时用 ProjectWriter 全量保存。
    private func writeProjectToPath(_ path: String) throws {
        guard let p = project else {
            throw NSError(domain: "AppState", code: 1, userInfo: [NSLocalizedDescriptionKey: "无项目"])
        }
        if let snap = inpSourceSnapshot {
            if inpPendingSaveDelta.isEmpty {
                return
            }
            let merged = InpPreservingSaver.applyPatches(original: snap, project: p, delta: inpPendingSaveDelta)
            try merged.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            inpSourceSnapshot = merged
            inpPendingSaveDelta.clear()
        } else {
            try p.save(path: path)
            inpSourceSnapshot = try? InpFileTextReader.contentsOfFile(path: path)
            inpPendingSaveDelta.clear()
        }
    }

    /// 保存：若有当前路径则保存到该路径，否则执行另存为。
    public func saveFile() {
        guard project != nil else {
            errorMessage = "保存失败: 当前没有打开的项目。"
            return
        }
        if let path = filePath, !path.isEmpty {
            do {
                try writeProjectToPath(path)
                errorMessage = nil
            } catch let error as EpanetError {
                errorMessage = Self.formatLocalizedEpanetError(error, scene: "保存失败")
            } catch {
                errorMessage = "保存失败: \(error)"
            }
        } else {
            saveAsFile()
        }
    }

    /// 另存为：弹出保存对话框，保存到用户选择的路径。
    public func saveAsFile() {
        #if os(macOS)
        guard project != nil else {
            errorMessage = "另存为失败: 当前没有打开的项目。"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "inp") ?? .plainText]
        panel.title = "另存为 .inp 文件"
        panel.message = "仅支持 .inp 格式"
        if let current = filePath, !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: current).deletingLastPathComponent()
            panel.nameFieldStringValue = URL(fileURLWithPath: current).lastPathComponent
        }
        if panel.runModal() == .OK, let url = panel.url {
            stopSecurityScopedAccess()
            _ = url.startAccessingSecurityScopedResource()
            securityScopedFileURL = url
            do {
                try writeProjectToPath(url.path)
                filePath = url.path
                errorMessage = nil
            } catch let error as EpanetError {
                errorMessage = Self.formatLocalizedEpanetError(error, scene: "另存为失败")
            } catch {
                errorMessage = "另存为失败: \(error)"
            }
        }
        NSCursor.arrow.set()
        #else
        errorMessage = "另存为: iOS 暂不支持，请使用打开功能选择保存位置。"
        #endif
    }

    /// 关闭：清空当前项目，回到空白状态。
    public func closeFile() {
        newProject()
    }

    func load(path: String) {
        isLoading = true
        errorMessage = nil
        inpSourceSnapshot = nil
        inpPendingSaveDelta.clear()
        let pathCopy = path
        let prefetchedFileData: Data? = try? Data(contentsOf: URL(fileURLWithPath: pathCopy))
        Task.detached(priority: .userInitiated) {
            let inpSnapshot: String? = if let d = prefetchedFileData {
                InpFileTextReader.decodeInpData(d)
            } else {
                try? InpFileTextReader.contentsOfFile(path: pathCopy)
            }
            var loadedProject: EpanetProject?
            do {
                let proj = EpanetProject()
                loadedProject = proj
                try proj.load(path: pathCopy)
                let scene = try Self.buildScene(from: proj)
                let nodeCount = try proj.nodeCount()
                let linkCount = try proj.linkCount()
                let flowUnits = InpOptionsParser.parseFlowUnits(path: pathCopy)
                await MainActor.run { [weak self] in
                    self?.project = proj
                    self?.scene = scene
                    self?.filePath = pathCopy
                    self?.errorMessage = nil
                    self?.inpFlowUnits = flowUnits
                    self?.inpSourceSnapshot = inpSnapshot
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
                    self?.recordRecentFile(path: pathCopy, nodeCount: nodeCount, linkCount: linkCount)
                    self?.isLoading = false
                }
            } catch EpanetError.apiError(200) {
                do {
                    let scene: NetworkScene
                    if let d = prefetchedFileData {
                        scene = try InpDisplayParser.parse(content: InpFileTextReader.decodeInpData(d))
                    } else {
                        scene = try InpDisplayParser.parse(path: pathCopy)
                    }
                    await MainActor.run { [weak self] in
                        self?.project = nil
                        self?.scene = scene
                        self?.filePath = pathCopy
                        self?.errorMessage = "仅显示模式（不可计算）"
                        self?.inpFlowUnits = InpOptionsParser.parseFlowUnits(path: pathCopy)
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
                        self?.recordRecentFile(path: pathCopy, nodeCount: scene.nodes.count, linkCount: scene.links.count)
                        self?.isLoading = false
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.errorMessage = "加载失败（仅显示解析）: \(error)"
                        self?.scene = nil
                        self?.project = nil
                        self?.filePath = nil
                        self?.inpFlowUnits = nil
                        self?.inpSourceSnapshot = nil
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
                    self?.inpSourceSnapshot = nil
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
                    self?.inpSourceSnapshot = nil
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
                    self?.inpSourceSnapshot = try? InpFileTextReader.contentsOfFile(path: inpPath)
                    self?.inpPendingSaveDelta.clear()
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

    #if os(macOS)
    private func stopSecurityScopedAccess() {
        if let url = securityScopedFileURL {
            url.stopAccessingSecurityScopedResource()
            securityScopedFileURL = nil
        }
    }
    #endif

    private func loadRecentFilesFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: StorageKeys.recentFiles) else {
            recentFiles = []
            return
        }
        do {
            let decoded = try JSONDecoder().decode([RecentFileItem].self, from: data)
            recentFiles = decoded.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
        } catch {
            recentFiles = []
        }
    }

    private func saveRecentFilesToStorage() {
        do {
            let data = try JSONEncoder().encode(recentFiles)
            UserDefaults.standard.set(data, forKey: StorageKeys.recentFiles)
        } catch {
            // 最近文件保存失败不阻断主流程。
        }
    }

    private func recordRecentFile(path: String, nodeCount: Int?, linkCount: Int?) {
        let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPath.isEmpty else { return }

        let item = RecentFileItem(
            path: cleanPath,
            displayName: URL(fileURLWithPath: cleanPath).lastPathComponent,
            lastOpenedAt: Date(),
            nodeCount: nodeCount,
            linkCount: linkCount
        )

        recentFiles.removeAll { $0.path == cleanPath }
        recentFiles.insert(item, at: 0)
        if recentFiles.count > 12 {
            recentFiles = Array(recentFiles.prefix(12))
        }
        saveRecentFilesToStorage()
    }
}
