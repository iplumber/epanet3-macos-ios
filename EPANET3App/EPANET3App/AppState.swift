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

/// 管网模型统计（节点分型、管段分型、Pipe 总长）；用于底部状态栏详情。
public struct ModelNetworkStatistics: Equatable {
    public var junctions: Int
    public var tanks: Int
    public var reservoirs: Int
    public var pipes: Int
    public var valves: Int
    public var pumps: Int
    public var totalPipeLength: Double
    public var lengthUnitLabel: String
    public var isPlanarLengthApproximation: Bool
}

enum EditorMode: String {
    case browse
    case add
    case edit
    case delete
    case result
}

/// 编辑菜单中的画布绘制命令：点类在空白处单击放置；管段/阀门/水泵为连续折线（每段终点作下一段起点，Esc 结束）。
public enum CanvasPlacementTool: String, CaseIterable {
    case junction
    /// 水塔：有容积的 Tank 节点（画布凹角方块）
    case tankTower
    /// 水库：EPANET Reservoir（定压边界，`[RESERVOIR]`；画布梯形）
    case tankPool
    case pipe
    case valve
    case pump
}

enum ResultOverlayMode: String, CaseIterable {
    case none
    case pressure
    case flow
}

// MARK: - Time-series result storage

/// Per-hydraulic-timestep results collected during `runCalculation()`.
/// Arrays are indexed `[stepIndex][objectIndex]`.
public struct TimeSeriesResultStore {
    public var timePoints: [Int] = []
    public var nodePressure: [[Float]] = []
    public var nodeHead: [[Float]] = []
    public var nodeDemand: [[Float]] = []
    public var tankLevel: [[Float]] = []
    public var linkFlow: [[Float]] = []
    public var linkVelocity: [[Float]] = []
    public var linkHeadloss: [[Float]] = []
    public var linkStatus: [[Float]] = []

    /// Snapshot current solver state for all nodes/links and append one time row.
    public mutating func recordStep(time: Int, project: EpanetProject) {
        guard let nc = try? project.nodeCount(),
              let lc = try? project.linkCount() else { return }
        timePoints.append(time)

        var pres = [Float](); pres.reserveCapacity(nc)
        var head = [Float](); head.reserveCapacity(nc)
        var dem  = [Float](); dem.reserveCapacity(nc)
        var tlvl = [Float](); tlvl.reserveCapacity(nc)
        for i in 0..<nc {
            pres.append(Float((try? project.getNodeValue(nodeIndex: i, param: .pressure)) ?? 0))
            head.append(Float((try? project.getNodeValue(nodeIndex: i, param: .head)) ?? 0))
            dem.append(Float((try? project.getNodeValue(nodeIndex: i, param: .actualdemand)) ?? 0))
            let isTank = (try? project.getNodeType(index: i)) == .tank
            tlvl.append(isTank ? Float((try? project.getNodeValue(nodeIndex: i, param: .tanklevel)) ?? .nan) : .nan)
        }
        nodePressure.append(pres)
        nodeHead.append(head)
        nodeDemand.append(dem)
        tankLevel.append(tlvl)

        var fl  = [Float](); fl.reserveCapacity(lc)
        var vel = [Float](); vel.reserveCapacity(lc)
        var hl  = [Float](); hl.reserveCapacity(lc)
        var st  = [Float](); st.reserveCapacity(lc)
        for i in 0..<lc {
            fl.append(Float((try? project.getLinkValue(linkIndex: i, param: .flow)) ?? 0))
            vel.append(Float((try? project.getLinkValue(linkIndex: i, param: .velocity)) ?? 0))
            hl.append(Float((try? project.getLinkValue(linkIndex: i, param: .headloss)) ?? 0))
            st.append(Float((try? project.getLinkValue(linkIndex: i, param: .status)) ?? 0))
        }
        linkFlow.append(fl)
        linkVelocity.append(vel)
        linkHeadloss.append(hl)
        linkStatus.append(st)
    }

    public var stepCount: Int { timePoints.count }

    /// Extract time-series for a single node parameter.
    public func nodeTimeSeries(nodeIndex: Int, param: NodeChartParam) -> [Float]? {
        let src: [[Float]]
        switch param {
        case .pressure: src = nodePressure
        case .head: src = nodeHead
        case .demand: src = nodeDemand
        case .tankLevel: src = tankLevel
        }
        guard !src.isEmpty, nodeIndex >= 0, nodeIndex < (src.first?.count ?? 0) else { return nil }
        return src.map { $0[nodeIndex] }
    }

    /// Extract time-series for a single link parameter.
    public func linkTimeSeries(linkIndex: Int, param: LinkChartParam) -> [Float]? {
        let src: [[Float]]
        switch param {
        case .flow: src = linkFlow
        case .velocity: src = linkVelocity
        case .headloss: src = linkHeadloss
        case .status: src = linkStatus
        }
        guard !src.isEmpty, linkIndex >= 0, linkIndex < (src.first?.count ?? 0) else { return nil }
        return src.map { $0[linkIndex] }
    }

    /// 与工具栏时间轴当前时刻（秒）最接近的水力行下标。
    public func rowIndexNearest(toPlayheadSeconds playhead: Double) -> Int? {
        guard !timePoints.isEmpty else { return nil }
        let target = Int(playhead.rounded())
        var bestIdx = 0
        var bestDist = Int.max
        for (i, tp) in timePoints.enumerated() {
            let d = abs(tp - target)
            if d < bestDist { bestDist = d; bestIdx = i }
        }
        return bestIdx
    }
}

public enum NodeChartParam: String, CaseIterable, Identifiable {
    case pressure = "压力"
    case head = "水头"
    case demand = "需水量"
    case tankLevel = "水位"
    public var id: String { rawValue }
}

public enum LinkChartParam: String, CaseIterable, Identifiable {
    case flow = "流量"
    case velocity = "流速"
    case headloss = "水头损失"
    case status = "状态"
    public var id: String { rawValue }
}

/// 底部时序图 Y 轴槽位：Y1 为左侧，Y2 为右侧（双轴时）。
public enum ChartAxisSlot: Int, CaseIterable, Identifiable, Codable {
    case y1 = 1
    case y2 = 2
    public var id: Int { rawValue }
    /// 与属性面板中间列标签一致。
    public var shortLabel: String { self == .y1 ? "Y1" : "Y2" }
}

/// 用户在属性面板为底部图选择的曲线及其轴（按添加顺序排列）。
public struct ChartPanelCurve: Identifiable, Equatable {
    public let id: UUID
    public var paramKey: String
    public var axis: ChartAxisSlot
    public init(id: UUID = UUID(), paramKey: String, axis: ChartAxisSlot) {
        self.id = id
        self.paramKey = paramKey
        self.axis = axis
    }
}

@MainActor
public final class AppState: ObservableObject {
    private enum StorageKeys {
        static let recentFiles = "epanet3.recentFiles"
    }

    @Published var scene: NetworkScene?
    /// 画布 Metal 顶点缓存失效计数：几何或拓扑每次替换时递增（仅平移/缩放不改此项）。
    @Published private(set) var sceneGeometryRevision: UInt64 = 0
    /// 压力/流量标量数组更新时递增，用于仅刷新标量 GPU 缓冲而不重建几何。
    @Published private(set) var resultScalarRevision: UInt64 = 0
    @Published var project: EpanetProject?
    @Published var filePath: String?
    @Published var errorMessage: String?
    @Published var isLoading = false
    /// 最近一次运行计算的结果；nil 表示尚未运行或已清除。
    @Published var runResult: RunResult?
    @Published public var isRunning = false
    /// 最近一次**成功**计算完成时的仿真总时长（秒），来自 `TOTAL_DURATION`；仅当 `> 0` 时工具栏显示时间轴。
    @Published var lastCompletedSimulationDurationSeconds: Int?
    /// 最近一次成功计算完成时的水力时间步长（秒），来自 `HYDRAULIC TIMESTEP`；时间轴滑块按该步长离散取值。
    @Published var lastCompletedSimulationHydraulicStepSeconds: Int?
    /// 工具栏时间轴滑块当前位置（秒，0…总时长）；用于浏览时刻，后续可对接该时刻的水力/水质结果。
    @Published var simulationTimelinePlayheadSeconds: Double = 0
    /// 最近一次成功完成「读入 .inp + 构建画布场景」的墙钟耗时（秒）；新建空白、重新加载时更新。
    @Published var lastLoadAndRenderElapsedSeconds: TimeInterval?
    /// 最近一次成功计算的逐水力步结果，供底部图表面板使用；nil 表示无可用时序数据。
    @Published public var timeSeriesResults: TimeSeriesResultStore?
    /// 底部时序图：用户在「计算结果」中选择的曲线及 Y1/Y2；切换选中对象时清空。
    @Published public var chartPanelCurves: [ChartPanelCurve] = []
    /// 从当前 .inp 的 [OPTIONS] 解析的 Flow Units（如 "GPM", "LPS"），用于属性面板单位标签；nil 表示未解析或非 project 模式。
    @Published var inpFlowUnits: String?
    /// 打开/保存/重载 .inp 时从全文快照解析的 `[OPTIONS]` 摘要；设置页只读此项，避免每次打开设置再读盘。
    @Published var cachedInpOptionsHints: InpOptionsParser.InpOptionsHints?
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
    /// 框选/多选：画布节点索引集合（与 `selectedNodeIndex` 同时维护；单选时仅含一个）。
    @Published var selectedNodeIndices: Set<Int> = []
    /// 框选/多选：画布管段索引集合。
    @Published var selectedLinkIndices: Set<Int> = []
    /// macOS：拓扑框选拖拽预览矩形（视图坐标，nil 表示未拖拽）。
    @Published var marqueeRectInView: CGRect?
    /// C1：属性面板可见状态由 AppState 统一管理。
    @Published var isPropertyPanelVisible = false
    /// 最近一次错误定位到的节点索引（用于 UI 自动选中）。
    @Published var errorFocusNodeIndex: Int?
    /// 最近一次错误定位到的管段索引（用于 UI 自动选中）。
    @Published var errorFocusLinkIndex: Int?
    /// D2: 请求画布聚焦到当前选中对象的触发器。
    @Published var focusSelectionToken: Int = 0
    /// 打开 .inp、`newFile`、`newProject` 时递增；`ContentView` 做一次全貌适配并重设投影锚点（编辑触发的场景刷新不递增）。
    @Published private(set) var canvasViewportFitResetNonce: UInt64 = 0
    /// D4：结果上图模式（无/压力/流量）。
    @Published var resultOverlayMode: ResultOverlayMode = .none
    /// D4：节点压力结果（按节点索引）。
    @Published var nodePressureValues: [Float] = []
    /// 节点水头（按节点索引）；与压力、流量同为当前时间轴时刻或引擎快照。
    @Published var nodeHeadValues: [Float] = []
    /// D4：管段流量结果（按管段索引）。
    @Published var linkFlowValues: [Float] = []
    /// 管段流速（按管段索引）；与流量同为当前时间轴时刻或引擎快照。
    @Published var linkVelocityValues: [Float] = []
    /// 启动页最近打开文件列表（按时间倒序）。
    @Published var recentFiles: [RecentFileItem] = []

    /// 编辑菜单「允许编辑管网拓扑」：关闭时禁止新增/删除命令与画布放置；新建/打开文件时默认关（不跨文档记忆）。
    @Published public var isTopologyEditingEnabled: Bool = false {
        didSet {
            if isTopologyEditingEnabled {
                setEditorMode(.add)
            } else {
                _ = cancelCanvasPlacementIfActive()
                if editorMode == .add || editorMode == .delete {
                    setEditorMode(.browse)
                }
            }
        }
    }

    /// 是否可在画布上进行拓扑编辑（与 `ensureProjectForCanvasTopologyEditing` 一致）：已有引擎工程，或未命名空白画布（首次绘制会懒建 `project`）；仅显示模式（有磁盘路径但无 `project`）不可。
    public var canEditTopologyOnCanvas: Bool {
        guard scene != nil else { return false }
        if project != nil { return true }
        return filePath == nil
    }

    /// 是否可运行水力求解（与工具栏「运行计算」及菜单快捷键一致）：需已加载工程且存在已保存的 .inp 路径。
    public var canRunHydraulicSolver: Bool {
        guard project != nil, let p = filePath, !p.isEmpty else { return false }
        return true
    }

    /// 当前画布绘制命令；nil 表示未在绘制流程中。
    @Published var activeCanvasPlacementTool: CanvasPlacementTool?
    /// 画布顶部提示，如「指定第二点…」。
    @Published var canvasPlacementStatusHint: String?
    /// 线类命令已选起点节点 ID（稳定，避免刷新后索引变化）。
    private var placementLinkFirstNodeID: String?

    #if os(macOS)
    /// 打开设置窗口后若为非 nil，切换到对应顶层标签（与设置页 `SettingsToolbarTab.rawValue` 一致：0=单位…）；由 `SettingsView` 消费后清零。
    @Published public var settingsPendingToolbarTab: Int?
    /// 打开设置「显示」页后若为非 nil，切换到对应左侧子项（与 `DisplaySection.rawValue` 一致，如「标注设置」）；由 `SettingsDisplayPane` 消费后清零。
    @Published public var settingsPendingDisplaySection: String?
    /// Mac 宿主（`EPANET3MacApp`）注入，供界面打开设置窗口而不依赖 `SettingsWindowController`。
    public var macOpenSettingsHandler: ((_ initialTab: Int?) -> Void)?
    /// 打开设置；`initialTab` 为 `SettingsToolbarTab` 的 rawValue，`nil` 表示不改变当前子页。
    public func openMacSettings(initialTab: Int? = nil) {
        macOpenSettingsHandler?(initialTab)
    }
    /// 打开设置并定位到「显示 → 标注设置」（与侧栏「标注设置」一致）。
    public func openMacSettingsDisplayLabelSection() {
        settingsPendingDisplaySection = "标注设置"
        // `SettingsToolbarTab.display`（units=0, hydraulic=1, simulation=2, display=3, general=4）
        openMacSettings(initialTab: 3)
    }
    /// 当前文件的 security-scoped URL，用于保持读写权限。
    private var securityScopedFileURL: URL?
    /// 递增时由 `ContentView` 收起右侧属性面板（如新建空白画布后默认不展开）。
    @Published public var macDismissRightSidebarNonce: UInt64 = 0
    #endif

    /// 打开 .inp 时解码后的全文快照；用于「保存」时按原结构写回，避免 ProjectWriter 重写导致丢章节/改顺序。
    private var inpSourceSnapshot: String?
    /// 属性面板等写入后待同步到 .inp 的字段级修改；文件菜单「保存」只应用这些补丁，不整文件重写数据行。
    private var inpPendingSaveDelta = InpSaveDelta()

    public init() {
        loadRecentFilesFromStorage()
    }

    /// 替换画布几何并 bump 版本，供 Metal 层判断何时重建顶点缓冲。
    func replaceRenderingScene(_ newValue: NetworkScene?) {
        scene = newValue
        sceneGeometryRevision &+= 1
    }

    func setEditorMode(_ mode: EditorMode) {
        editorMode = mode
        switch mode {
        case .browse:
            selectedNodeIndex = nil
            selectedLinkIndex = nil
            selectedNodeID = nil
            selectedLinkID = nil
            selectedNodeIndices = []
            selectedLinkIndices = []
            isPropertyPanelVisible = false
        case .add, .delete:
            selectedNodeIndex = nil
            selectedLinkIndex = nil
            selectedNodeID = nil
            selectedLinkID = nil
            selectedNodeIndices = []
            selectedLinkIndices = []
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
        let selectionChanged = nodeIndex != selectedNodeIndex || linkIndex != selectedLinkIndex
        if selectionChanged {
            chartPanelCurves.removeAll()
        }
        selectedNodeIndex = nodeIndex
        selectedLinkIndex = linkIndex
        selectedNodeIndices = []
        selectedLinkIndices = []
        if let i = nodeIndex { selectedNodeIndices = [i] }
        if let i = linkIndex { selectedLinkIndices = [i] }
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
        if selectionChanged, nodeIndex != nil || linkIndex != nil {
            seedDefaultChartPanelCurvesIfPossible()
        }
    }

    /// 选中节点/管段且存在时序数据时：节点默认 Y1=水头、Y2=压力；管段默认 Y1=流量、Y2=流速（泵/阀无流速时为 Y2=状态）。
    private func seedDefaultChartPanelCurvesIfPossible() {
        let keys = chartableResultParamKeysForCurrentSelection()
        if let ni = selectedNodeIndex, ni >= 0 {
            let headKey = NodeChartParam.head.rawValue
            let pressureKey = NodeChartParam.pressure.rawValue
            guard keys.contains(headKey), keys.contains(pressureKey) else { return }
            chartPanelCurves = [
                ChartPanelCurve(paramKey: headKey, axis: .y1),
                ChartPanelCurve(paramKey: pressureKey, axis: .y2),
            ]
            return
        }
        if let li = selectedLinkIndex, li >= 0, let proj = project {
            let flowKey = LinkChartParam.flow.rawValue
            let velocityKey = LinkChartParam.velocity.rawValue
            let statusKey = LinkChartParam.status.rawValue
            let lt = (try? proj.getLinkType(index: li)) ?? .pipe
            switch lt {
            case .pipe, .cvpipe:
                guard keys.contains(flowKey), keys.contains(velocityKey) else { return }
                chartPanelCurves = [
                    ChartPanelCurve(paramKey: flowKey, axis: .y1),
                    ChartPanelCurve(paramKey: velocityKey, axis: .y2),
                ]
            default:
                guard keys.contains(flowKey), keys.contains(statusKey) else { return }
                chartPanelCurves = [
                    ChartPanelCurve(paramKey: flowKey, axis: .y1),
                    ChartPanelCurve(paramKey: statusKey, axis: .y2),
                ]
            }
        }
    }

    func clearSelection(closePanel: Bool = true) {
        chartPanelCurves.removeAll()
        selectedNodeIndex = nil
        selectedLinkIndex = nil
        selectedNodeID = nil
        selectedLinkID = nil
        selectedNodeIndices = []
        selectedLinkIndices = []
        if editorMode == .edit {
            editorMode = .browse
        }
        if closePanel { isPropertyPanelVisible = false }
    }

    /// 在属性面板切换某条「计算结果」是否进入底部时序图；第 1 条默认 Y1，第 2 条起默认 Y2。
    public func toggleChartPanelParam(_ paramKey: String) {
        if let i = chartPanelCurves.firstIndex(where: { $0.paramKey == paramKey }) {
            chartPanelCurves.remove(at: i)
            return
        }
        let n = chartPanelCurves.count
        let axis: ChartAxisSlot = (n == 0) ? .y1 : .y2
        chartPanelCurves.append(ChartPanelCurve(paramKey: paramKey, axis: axis))
    }

    public func setChartPanelAxis(paramKey: String, axis: ChartAxisSlot) {
        guard let i = chartPanelCurves.firstIndex(where: { $0.paramKey == paramKey }) else { return }
        chartPanelCurves[i].axis = axis
    }

    /// 当前单选对象下，底部时序图可绑定的字段名（与 `NodeChartParam` / `LinkChartParam` 的 `rawValue` 一致）。
    public func chartableResultParamKeysForCurrentSelection() -> Set<String> {
        guard let store = timeSeriesResults, store.stepCount >= 1,
              let proj = project else { return [] }
        if let ni = selectedNodeIndex, ni >= 0 {
            let nt = (try? proj.getNodeType(index: ni)) ?? .junction
            let params: [NodeChartParam]
            switch nt {
            case .tank: params = [.tankLevel, .pressure, .head]
            case .reservoir: params = [.head, .pressure, .demand]
            case .junction: params = [.pressure, .head, .demand]
            }
            return Set(params.compactMap { p -> String? in
                guard let vals = store.nodeTimeSeries(nodeIndex: ni, param: p) else { return nil }
                if p == .tankLevel && vals.allSatisfy({ $0.isNaN }) { return nil }
                return p.rawValue
            })
        }
        if let li = selectedLinkIndex, li >= 0 {
            let lt = (try? proj.getLinkType(index: li)) ?? .pipe
            let params: [LinkChartParam]
            switch lt {
            case .pump, .prv, .psv, .pbv, .fcv, .tcv, .gpv:
                params = [.flow, .status]
            case .pipe, .cvpipe:
                params = [.flow, .velocity, .headloss]
            }
            return Set(params.compactMap { p in
                guard store.linkTimeSeries(linkIndex: li, param: p) != nil else { return nil }
                return p.rawValue
            })
        }
        return []
    }

    /// 框选结束：从左往右 `crossingMode == true` 为相交选择，从右往左为仅完全包含。
    func applyMarqueeSelection(coordinator: MetalNetworkCoordinator, viewRect: CGRect, viewSize: CGSize, crossingMode: Bool) {
        marqueeRectInView = nil
        guard let sceneRect = coordinator.sceneBoundingRectFromViewRect(viewRect, viewSize: viewSize) else { return }
        let mode: MetalNetworkCoordinator.MarqueeSelectionMode = crossingMode ? .crossing : .window
        let (nodes, links) = coordinator.indicesInMarquee(sceneRect: sceneRect, viewSize: viewSize, mode: mode)
        setMarqueeSelection(nodes: nodes, links: links)
    }

    func setMarqueeSelection(nodes: Set<Int>, links: Set<Int>, openPanel: Bool = true) {
        selectedNodeIndices = nodes
        selectedLinkIndices = links
        let total = nodes.count + links.count
        if total == 0 {
            clearSelection(closePanel: openPanel)
            return
        }
        if total > 1 {
            chartPanelCurves.removeAll()
        }
        if total == 1 {
            if let n = nodes.first {
                setSelection(nodeIndex: n, linkIndex: nil, openPanel: openPanel)
            } else if let l = links.first {
                setSelection(nodeIndex: nil, linkIndex: l, openPanel: openPanel)
            }
            return
        }
        selectedNodeIndex = nil
        selectedLinkIndex = nil
        selectedNodeID = nil
        selectedLinkID = nil
        if editorMode != .add && editorMode != .delete {
            editorMode = .edit
        }
        if openPanel { isPropertyPanelVisible = true }
    }

    func requestFocusOnSelection() {
        focusSelectionToken &+= 1
    }

    /// 拓扑绘制/编辑中：`ContentView` 不随几何变化做 scale 比例补偿与 clamp；回浏览/结果时再 `resyncCanvasIntrinsicBaselineNoRatio`。
    public var freezesCanvasViewportWhileEditingTopology: Bool {
        if activeCanvasPlacementTool != nil { return true }
        switch editorMode {
        case .browse, .result: return false
        case .add, .delete, .edit: break
        }
        #if os(macOS)
        return isTopologyEditingEnabled
        #else
        return true
        #endif
    }

    func bumpCanvasViewportFitReset() {
        canvasViewportFitResetNonce &+= 1
    }

    /// C2：当 project 重新加载后，用稳定 ID 重新解析索引，避免对象增删后的索引漂移。
    func syncSelectionIndicesFromIDs() {
        guard let p = project else {
            selectedNodeIndex = nil
            selectedLinkIndex = nil
            selectedNodeIndices = []
            selectedLinkIndices = []
            return
        }
        if let nodeID = selectedNodeID {
            selectedNodeIndex = try? p.getNodeIndex(id: nodeID)
            selectedLinkIndex = nil
            if let i = selectedNodeIndex {
                selectedNodeIndices = [i]
                selectedLinkIndices = []
            } else {
                selectedNodeIndices = []
                selectedLinkIndices = []
            }
            return
        }
        if let linkID = selectedLinkID {
            selectedLinkIndex = try? p.getLinkIndex(id: linkID)
            selectedNodeIndex = nil
            if let i = selectedLinkIndex {
                selectedLinkIndices = [i]
                selectedNodeIndices = []
            } else {
                selectedNodeIndices = []
                selectedLinkIndices = []
            }
            return
        }
        selectedNodeIndex = nil
        selectedLinkIndex = nil
        selectedNodeIndices = []
        selectedLinkIndices = []
    }

    /// C3：从当前 project 重建画布场景，并按稳定 ID 恢复选中对象。
    func refreshSceneFromProject(
        preserveSelection: Bool = true,
        sceneLabel: String = "场景刷新"
    ) {
        guard let p = project else {
            replaceRenderingScene(nil)
            clearSelection()
            return
        }

        let previousNodeID = selectedNodeID
        let previousLinkID = selectedLinkID
        let previousPanelVisible = isPropertyPanelVisible
        let previousNodeIDs: Set<String> = Set(selectedNodeIndices.compactMap { try? p.getNodeId(index: $0) })
        let previousLinkIDs: Set<String> = Set(selectedLinkIndices.compactMap { try? p.getLinkId(index: $0) })
        let multiSelect = selectedNodeIndices.count + selectedLinkIndices.count > 1

        do {
            replaceRenderingScene(try Self.buildScene(from: p))
            if preserveSelection {
                if multiSelect {
                    selectedNodeIndices = Set(previousNodeIDs.compactMap { try? p.getNodeIndex(id: $0) })
                    selectedLinkIndices = Set(previousLinkIDs.compactMap { try? p.getLinkIndex(id: $0) })
                    selectedNodeIndex = nil
                    selectedLinkIndex = nil
                    selectedNodeID = nil
                    selectedLinkID = nil
                    isPropertyPanelVisible = previousPanelVisible && (!selectedNodeIndices.isEmpty || !selectedLinkIndices.isEmpty)
                } else {
                    selectedNodeID = previousNodeID
                    selectedLinkID = previousLinkID
                    syncSelectionIndicesFromIDs()
                    isPropertyPanelVisible = previousPanelVisible && ((selectedNodeIndex != nil) || (selectedLinkIndex != nil))
                }
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
        }
    }

    /// 新增水库（`[RESERVOIR]` 定压节点）：水头默认 100，可随后在属性面板修改。
    func addReservoir(nodeID: String, totalHead: Double, xCoord: Double, yCoord: Double, sceneLabel: String = "新增水库") {
        applyProjectMutation(sceneLabel: sceneLabel) { p in
            _ = try p.createNode(id: nodeID, type: .reservoir)
            let nodeIndex = try p.getNodeIndex(id: nodeID)
            // 引擎里水库定压水位存在 `elev`（与 .inp 的 [RESERVOIR] 一致）；`EN_HEAD` 未对全节点开放。
            try p.setNodeValue(nodeIndex: nodeIndex, param: .elevation, value: totalHead)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .xcoord, value: xCoord)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .ycoord, value: yCoord)
            selectedNodeID = nodeID
            selectedLinkID = nil
            editorMode = .edit
            isPropertyPanelVisible = true
        }
        if errorMessage == nil {
            invalidateInpSourceSnapshot()
        }
    }

    /// 新增水塔 / 有容积圆柱罐（`[TANK]`）：默认直径与液位范围可在属性面板调整。
    func addTank(
        nodeID: String,
        xCoord: Double,
        yCoord: Double,
        bottomElevation: Double = 0,
        diameter: Double = 50,
        minLevel: Double = 0,
        maxLevel: Double = 20,
        initialLevel: Double = 10
    ) {
        applyProjectMutation(sceneLabel: "新增水塔") { p in
            _ = try p.createNode(id: nodeID, type: .tank)
            let nodeIndex = try p.getNodeIndex(id: nodeID)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .elevation, value: bottomElevation)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .tankdiam, value: diameter)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .minlevel, value: minLevel)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .maxlevel, value: maxLevel)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .tanklevel, value: initialLevel)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .xcoord, value: xCoord)
            try p.setNodeValue(nodeIndex: nodeIndex, param: .ycoord, value: yCoord)
            selectedNodeID = nodeID
            selectedLinkID = nil
            editorMode = .edit
            isPropertyPanelVisible = true
        }
        if errorMessage == nil {
            invalidateInpSourceSnapshot()
        }
    }

    /// 新增阀门（节流阀 TCV）；开度等可在属性面板修改。
    func addThrottleValve(
        linkID: String,
        fromNodeID: String,
        toNodeID: String,
        length: Double,
        diameter: Double,
        roughness: Double,
        initialSetting: Double = 0
    ) {
        applyProjectMutation(sceneLabel: "新增阀门") { p in
            let fromIndex = try p.getNodeIndex(id: fromNodeID)
            let toIndex = try p.getNodeIndex(id: toNodeID)
            _ = try p.createLink(id: linkID, type: .tcv, fromNodeIndex: fromIndex, toNodeIndex: toIndex)
            let linkIndex = try p.getLinkIndex(id: linkID)
            try p.setLinkValue(linkIndex: linkIndex, param: .length, value: length)
            try p.setLinkValue(linkIndex: linkIndex, param: .diameter, value: diameter)
            try p.setLinkValue(linkIndex: linkIndex, param: .roughness, value: roughness)
            try p.setLinkValue(linkIndex: linkIndex, param: .initsetting, value: initialSetting)
            selectedLinkID = linkID
            selectedNodeID = nil
            editorMode = .edit
            isPropertyPanelVisible = true
        }
        if errorMessage == nil {
            invalidateInpSourceSnapshot()
        }
    }

    /// 新增水泵；若引擎要求曲线或额外参数，失败时见 `errorMessage`。
    func addPumpLink(
        linkID: String,
        fromNodeID: String,
        toNodeID: String,
        length: Double,
        initialSetting: Double = 40
    ) {
        applyProjectMutation(sceneLabel: "新增水泵") { p in
            let fromIndex = try p.getNodeIndex(id: fromNodeID)
            let toIndex = try p.getNodeIndex(id: toNodeID)
            _ = try p.createLink(id: linkID, type: .pump, fromNodeIndex: fromIndex, toNodeIndex: toIndex)
            let linkIndex = try p.getLinkIndex(id: linkID)
            try p.setLinkValue(linkIndex: linkIndex, param: .length, value: length)
            try p.setLinkValue(linkIndex: linkIndex, param: .diameter, value: 1)
            try p.setLinkValue(linkIndex: linkIndex, param: .roughness, value: 0)
            try p.setLinkValue(linkIndex: linkIndex, param: .initsetting, value: initialSetting)
            selectedLinkID = linkID
            selectedNodeID = nil
            editorMode = .edit
            isPropertyPanelVisible = true
        }
        if errorMessage == nil {
            invalidateInpSourceSnapshot()
        }
    }

    // MARK: - 画布绘制命令（编辑菜单 / CAD 式交互）

    public func beginCanvasPlacement(_ tool: CanvasPlacementTool) {
        guard isTopologyEditingEnabled else { return }
        activeCanvasPlacementTool = tool
        placementLinkFirstNodeID = nil
        setEditorMode(.add)
        switch tool {
        case .junction:
            canvasPlacementStatusHint = "单击画布放置节点（Esc 退出命令）"
        case .tankTower:
            canvasPlacementStatusHint = "单击画布放置水塔（Esc 退出命令）"
        case .tankPool:
            canvasPlacementStatusHint = "单击画布放置水库（Esc 退出命令）"
        case .pipe:
            canvasPlacementStatusHint = "连续绘管：单击第一点（空白处自动建节点；Esc 或右键结束链）"
        case .valve:
            canvasPlacementStatusHint = "连续绘阀：单击第一点（空白处自动建节点；Esc 或右键结束链）"
        case .pump:
            canvasPlacementStatusHint = "连续绘泵：单击第一点（空白处自动建节点；Esc 或右键结束链）"
        }
    }

    /// 线类连续绘制：右键结束当前折线链（清除「待连下一点」的起点）；仍保持放置命令。无悬起点时返回 false（不拦右键菜单）。
    @discardableResult
    public func endContinuousLinkPlacementChainIfActive() -> Bool {
        guard let t = activeCanvasPlacementTool else { return false }
        switch t {
        case .pipe, .valve, .pump:
            guard placementLinkFirstNodeID != nil else { return false }
            placementLinkFirstNodeID = nil
            switch t {
            case .pipe:
                canvasPlacementStatusHint = "连续绘管：单击第一点（空白处自动建节点；Esc 或右键结束链）"
            case .valve:
                canvasPlacementStatusHint = "连续绘阀：单击第一点（空白处自动建节点；Esc 或右键结束链）"
            case .pump:
                canvasPlacementStatusHint = "连续绘泵：单击第一点（空白处自动建节点；Esc 或右键结束链）"
            default:
                break
            }
            return true
        default:
            return false
        }
    }

    /// 退出当前绘制命令；若曾激活则返回 true（用于 Esc 优先消费）。
    @discardableResult
    public func cancelCanvasPlacementIfActive() -> Bool {
        guard activeCanvasPlacementTool != nil else { return false }
        activeCanvasPlacementTool = nil
        placementLinkFirstNodeID = nil
        canvasPlacementStatusHint = nil
        return true
    }

    /// 未命名画布（`newFile`）仅有 `NetworkScene`、`project` 为 nil；拓扑绘制首次点击时创建内存 EPANET 工程。
    /// 已关联磁盘路径但引擎未加载的仅显示模型不自动建工程，避免与画布脱节。
    private func ensureProjectForCanvasTopologyEditing() -> Bool {
        if project != nil { return true }
        guard scene != nil else {
            errorMessage = "绘制失败: 无可编辑画布。"
            return false
        }
        if filePath != nil {
            errorMessage = "绘制失败: 当前为仅显示模式或模型未在引擎中加载，无法编辑拓扑。请打开可由本应用完整加载的 .inp 文件。"
            return false
        }
        project = EpanetProject()
        return true
    }

    /// 主键单击：返回 true 表示由绘制命令消费（不触发画布平移/空白清选）。
    @discardableResult
    public func handleCanvasPlacementClick(
        coordinator: MetalNetworkCoordinator,
        viewPoint: CGPoint,
        viewSize: CGSize
    ) -> Bool {
        guard isTopologyEditingEnabled else { return false }
        guard let tool = activeCanvasPlacementTool else { return false }
        guard ensureProjectForCanvasTopologyEditing() else { return true }
        guard let p = project else { return true }

        switch tool {
        case .junction, .tankTower, .tankPool:
            guard let (sx, sy) = coordinator.viewToScene(viewPoint: viewPoint, viewSize: viewSize) else { return true }
            let x = Double(sx), y = Double(sy)
            switch tool {
            case .junction:
                addJunction(
                    nodeID: allocateNodeID(project: p, prefix: "J"),
                    elevation: 0,
                    baseDemand: 0,
                    xCoord: x,
                    yCoord: y
                )
            case .tankTower:
                addTank(
                    nodeID: allocateNodeID(project: p, prefix: "T"),
                    xCoord: x,
                    yCoord: y,
                    bottomElevation: 25,
                    diameter: 40,
                    minLevel: 0,
                    maxLevel: 15,
                    initialLevel: 8
                )
            case .tankPool:
                addReservoir(
                    nodeID: allocateNodeID(project: p, prefix: "R"),
                    totalHead: 100,
                    xCoord: x,
                    yCoord: y,
                    sceneLabel: "新增水库"
                )
            default:
                break
            }
            return true

        case .pipe, .valve, .pump:
            guard let nodeID = ensureNodeIDForLinkEndpoint(
                coordinator: coordinator,
                viewPoint: viewPoint,
                viewSize: viewSize
            ) else { return true }
            if let first = placementLinkFirstNodeID {
                if first == nodeID {
                    return true
                }
                guard let p2 = project else { return true }
                let len = (try? linkLengthPlanar(project: p2, fromNodeID: first, toNodeID: nodeID)) ?? 100
                switch tool {
                case .pipe:
                    addPipe(
                        linkID: allocateLinkID(project: p2, prefix: "P"),
                        fromNodeID: first,
                        toNodeID: nodeID,
                        length: len,
                        diameter: 10,
                        roughness: 100
                    )
                case .valve:
                    addThrottleValve(
                        linkID: allocateLinkID(project: p2, prefix: "V"),
                        fromNodeID: first,
                        toNodeID: nodeID,
                        length: len,
                        diameter: 10,
                        roughness: 100
                    )
                case .pump:
                    addPumpLink(
                        linkID: allocateLinkID(project: p2, prefix: "M"),
                        fromNodeID: first,
                        toNodeID: nodeID,
                        length: len
                    )
                default:
                    break
                }
                if errorMessage == nil {
                    placementLinkFirstNodeID = nodeID
                    switch tool {
                    case .pipe, .valve, .pump:
                        canvasPlacementStatusHint = "单击下一点连线（空白处自动建节点；Esc 或右键结束链）"
                    default:
                        break
                    }
                }
                return true
            }
            placementLinkFirstNodeID = nodeID
            canvasPlacementStatusHint = "单击下一点连线（空白处自动建节点；Esc 或右键结束链）"
            return true
        }
    }

    private func allocateNodeID(project p: EpanetProject, prefix: String) -> String {
        for i in 1..<100_000 {
            let id = "\(prefix)\(i)"
            if (try? p.getNodeIndex(id: id)) == nil { return id }
        }
        return "\(prefix)_\(UUID().uuidString.prefix(8))"
    }

    private func allocateLinkID(project p: EpanetProject, prefix: String) -> String {
        for i in 1..<100_000 {
            let id = "\(prefix)\(i)"
            if (try? p.getLinkIndex(id: id)) == nil { return id }
        }
        return "\(prefix)_\(UUID().uuidString.prefix(8))"
    }

    private func linkLengthPlanar(project p: EpanetProject, fromNodeID: String, toNodeID: String) throws -> Double {
        let i1 = try p.getNodeIndex(id: fromNodeID)
        let i2 = try p.getNodeIndex(id: toNodeID)
        let (x1, y1) = try p.getNodeCoords(nodeIndex: i1)
        let (x2, y2) = try p.getNodeCoords(nodeIndex: i2)
        let dx = x2 - x1, dy = y2 - y1
        let d = (dx * dx + dy * dy).squareRoot()
        return max(0.01, d)
    }

    /// 与某节点相连的管段 ID（`Network::deleteElement(NODE)` 要求先删这些管段）。
    private func linkIdsConnectedToNode(project p: EpanetProject, nodeIndex: Int) throws -> [String] {
        let lc = try p.linkCount()
        var ids: [String] = []
        for i in 0..<lc {
            let (n1, n2) = try p.getLinkNodes(linkIndex: i)
            if n1 == nodeIndex || n2 == nodeIndex {
                ids.append(try p.getLinkId(index: i))
            }
        }
        return ids
    }

    /// 先删除所有与该节点相连的管段，再删节点。
    private func deleteNodeRemovingIncidentLinks(project p: EpanetProject, nodeID: String) throws {
        let nodeIndex = try p.getNodeIndex(id: nodeID)
        for lid in try linkIdsConnectedToNode(project: p, nodeIndex: nodeIndex) {
            try p.deleteLink(id: lid)
        }
        try p.deleteNode(id: nodeID)
    }

    /// 线类命令端点：命中节点则用该节点；否则在点击处新建 Junction。失败返回 nil。
    private func ensureNodeIDForLinkEndpoint(
        coordinator: MetalNetworkCoordinator,
        viewPoint: CGPoint,
        viewSize: CGSize
    ) -> String? {
        guard let p = project else { return nil }
        let (nodeIdx, _) = coordinator.hitTest(viewPoint: viewPoint, viewSize: viewSize)
        if let n = nodeIdx, let id = try? p.getNodeId(index: n) {
            return id
        }
        guard let (sx, sy) = coordinator.viewToScene(viewPoint: viewPoint, viewSize: viewSize) else { return nil }
        let id = allocateNodeID(project: p, prefix: "J")
        addJunction(nodeID: id, elevation: 0, baseDemand: 0, xCoord: Double(sx), yCoord: Double(sy))
        return errorMessage == nil ? id : nil
    }

    /// D2：删除当前选中对象（优先节点，其次管段）；支持多选批量删除。
    public func deleteSelectedObject() {
        guard isTopologyEditingEnabled else {
            errorMessage = "删除失败: 请先在「编辑」菜单中开启「允许编辑管网拓扑」。"
            return
        }
        if let p = project, selectedNodeIndices.count + selectedLinkIndices.count > 1 {
            let linkIDs = selectedLinkIndices.compactMap { try? p.getLinkId(index: $0) }
            let nodeIDs = selectedNodeIndices.compactMap { try? p.getNodeId(index: $0) }
            applyProjectMutation(sceneLabel: "批量删除") { proj in
                for id in linkIDs {
                    try? proj.deleteLink(id: id)
                }
                for id in nodeIDs {
                    try deleteNodeRemovingIncidentLinks(project: proj, nodeID: id)
                }
                selectedNodeID = nil
                selectedLinkID = nil
                selectedNodeIndex = nil
                selectedLinkIndex = nil
                selectedNodeIndices = []
                selectedLinkIndices = []
                editorMode = .delete
                isPropertyPanelVisible = true
            }
            if errorMessage == nil { invalidateInpSourceSnapshot() }
            return
        }
        if let nodeID = selectedNodeID {
            applyProjectMutation(sceneLabel: "删除节点及连接管段") { p in
                try deleteNodeRemovingIncidentLinks(project: p, nodeID: nodeID)
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

    /// D3 第二版：通过重载式策略切换 Flow Units（与 EPANET `FlowUnits` 枚举 / .inp UNITS 关键字一致）。
    func switchFlowUnitsReload(targetFlowUnits: String) {
        let target = targetFlowUnits.uppercased().trimmingCharacters(in: .whitespaces)
        guard InpOptionsParser.isValidFlowUnitCode(target) else {
            errorMessage = "切换 Flow Units 失败: 无效单位 \(target)（EPANET 支持 CFS/GPM/MGD/IMGD/AFD/LPS/LPM/MLD/CMH/CMD）。"
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
            inpFlowUnits = InpOptionsParser.parseFlowUnits(content: rewritten) ?? target
            inpSourceSnapshot = rewritten
            cachedInpOptionsHints = InpOptionsParser.parseOptionsHints(content: rewritten)
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
        applyProjectMutation(sceneLabel: "删除节点及连接管段") { p in
            let incident = try linkIdsConnectedToNode(project: p, nodeIndex: try p.getNodeIndex(id: nodeID))
            try deleteNodeRemovingIncidentLinks(project: p, nodeID: nodeID)
            if selectedNodeID == nodeID {
                selectedNodeID = nil
                selectedNodeIndex = nil
            }
            if let sl = selectedLinkID, incident.contains(sl) {
                selectedLinkID = nil
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
        replaceRenderingScene(nil)
        filePath = nil
        errorMessage = nil
        runResult = nil
        lastCompletedSimulationDurationSeconds = nil
        lastCompletedSimulationHydraulicStepSeconds = nil
        simulationTimelinePlayheadSeconds = 0
        timeSeriesResults = nil
        chartPanelCurves.removeAll()
        inpFlowUnits = nil
        cachedInpOptionsHints = nil
        editorMode = .browse
        selectedNodeIndex = nil
        selectedLinkIndex = nil
        selectedNodeID = nil
        selectedLinkID = nil
        selectedNodeIndices = []
        selectedLinkIndices = []
        isPropertyPanelVisible = false
        errorFocusNodeIndex = nil
        errorFocusLinkIndex = nil
        resultOverlayMode = .none
        nodePressureValues = []
        nodeHeadValues = []
        linkFlowValues = []
        linkVelocityValues = []
        inpSourceSnapshot = nil
        inpPendingSaveDelta.clear()
        activeCanvasPlacementTool = nil
        placementLinkFirstNodeID = nil
        canvasPlacementStatusHint = nil
        isTopologyEditingEnabled = false
        lastLoadAndRenderElapsedSeconds = nil
        bumpCanvasViewportFitReset()
    }

    /// 新建空白画布：先只建 `NetworkScene`（零节点零管段）；首次在画布上做拓扑编辑时会懒创建内存 `EpanetProject`。保存/计算仍需指定路径或另存为 .inp。
    public func newFile() {
        #if os(macOS)
        stopSecurityScopedAccess()
        #endif
        project = nil
        replaceRenderingScene(NetworkScene(nodes: [], links: []))
        filePath = nil
        errorMessage = nil
        runResult = nil
        lastCompletedSimulationDurationSeconds = nil
        lastCompletedSimulationHydraulicStepSeconds = nil
        simulationTimelinePlayheadSeconds = 0
        timeSeriesResults = nil
        chartPanelCurves.removeAll()
        inpFlowUnits = nil
        cachedInpOptionsHints = nil
        editorMode = .browse
        selectedNodeIndex = nil
        selectedLinkIndex = nil
        selectedNodeID = nil
        selectedLinkID = nil
        selectedNodeIndices = []
        selectedLinkIndices = []
        isPropertyPanelVisible = false
        errorFocusNodeIndex = nil
        errorFocusLinkIndex = nil
        resultOverlayMode = .none
        nodePressureValues = []
        nodeHeadValues = []
        linkFlowValues = []
        linkVelocityValues = []
        inpSourceSnapshot = nil
        inpPendingSaveDelta.clear()
        isLoading = false
        activeCanvasPlacementTool = nil
        placementLinkFirstNodeID = nil
        canvasPlacementStatusHint = nil
        isTopologyEditingEnabled = false
        lastLoadAndRenderElapsedSeconds = nil
        bumpCanvasViewportFitReset()
        #if os(macOS)
        macDismissRightSidebarNonce &+= 1
        #endif
    }

    /// 增删节点/管段或改写全局计算参数后，快照与磁盘结构不再一致，需退回完整重写或下次保存前重新加载。
    private func invalidateInpSourceSnapshot() {
        inpSourceSnapshot = nil
        inpPendingSaveDelta.clear()
    }

    /// 将当前 project（引擎内存状态）通过 ProjectWriter 序列化到磁盘，再从写出的文件回读快照供后续增量补丁使用。
    private func writeProjectToPath(_ path: String) throws {
        guard let p = project else {
            throw NSError(domain: "AppState", code: 1, userInfo: [NSLocalizedDescriptionKey: "无项目"])
        }
        let sectionDigits = inpSourceSnapshot.map { InpNumericFormat.maxFractionDigitsPerSection(content: $0) } ?? [:]
        let defaultDigits = max(4, sectionDigits.values.max() ?? 0)
        try p.configureNoriaInpExport(
            version: NoriaAppInfo.marketingVersionString,
            sectionFractionDigits: sectionDigits,
            defaultFractionDigits: defaultDigits
        )
        try p.save(path: path)
        inpSourceSnapshot = try? InpFileTextReader.contentsOfFile(path: path)
        inpPendingSaveDelta.clear()
        syncCachedOptionsFromSnapshot()
    }

    private func syncCachedOptionsFromSnapshot() {
        if let snap = inpSourceSnapshot {
            cachedInpOptionsHints = InpOptionsParser.parseOptionsHints(content: snap)
        } else {
            cachedInpOptionsHints = nil
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
        cachedInpOptionsHints = nil
        inpPendingSaveDelta.clear()
        lastLoadAndRenderElapsedSeconds = nil
        let pathCopy = path
        let prefetchedFileData: Data? = try? Data(contentsOf: URL(fileURLWithPath: pathCopy))
        Task.detached(priority: .userInitiated) {
            let loadWallClockStart = CFAbsoluteTimeGetCurrent()
            let inpSnapshot: String? = if let d = prefetchedFileData {
                InpFileTextReader.decodeInpData(d)
            } else {
                try? InpFileTextReader.contentsOfFile(path: pathCopy)
            }
            let optionsHintsForLoad = inpSnapshot.map { InpOptionsParser.parseOptionsHints(content: $0) }
            var loadedProject: EpanetProject?
            do {
                let proj = EpanetProject()
                loadedProject = proj
                try proj.load(path: pathCopy)
                let nodeCount = try proj.nodeCount()
                let linkCount = try proj.linkCount()
                let flowUnits = inpSnapshot.flatMap { InpOptionsParser.parseFlowUnits(content: $0) }
                    ?? InpOptionsParser.parseFlowUnits(path: pathCopy)
                await MainActor.run { [weak self] in
                    self?.project = proj
                    self?.filePath = pathCopy
                    self?.errorMessage = nil
                    self?.runResult = nil
                    self?.lastCompletedSimulationDurationSeconds = nil
                    self?.lastCompletedSimulationHydraulicStepSeconds = nil
                    self?.simulationTimelinePlayheadSeconds = 0
                    self?.timeSeriesResults = nil
                    self?.chartPanelCurves.removeAll()
                    self?.inpFlowUnits = flowUnits
                    self?.cachedInpOptionsHints = optionsHintsForLoad
                    self?.inpSourceSnapshot = inpSnapshot
                    self?.editorMode = .browse
                    self?.selectedNodeIndex = nil
                    self?.selectedLinkIndex = nil
                    self?.selectedNodeID = nil
                    self?.selectedLinkID = nil
                    self?.selectedNodeIndices = []
                    self?.selectedLinkIndices = []
                    self?.isPropertyPanelVisible = false
                    self?.errorFocusNodeIndex = nil
                    self?.errorFocusLinkIndex = nil
                    self?.resultOverlayMode = .none
                    self?.nodePressureValues = []
                    self?.nodeHeadValues = []
                    self?.linkFlowValues = []
                    self?.linkVelocityValues = []
                    self?.refreshSceneFromProject(preserveSelection: false, sceneLabel: "加载 .inp")
                    self?.recordRecentFile(path: pathCopy, nodeCount: nodeCount, linkCount: linkCount)
                    self?.lastLoadAndRenderElapsedSeconds = CFAbsoluteTimeGetCurrent() - loadWallClockStart
                    self?.isLoading = false
                    self?.activeCanvasPlacementTool = nil
                    self?.placementLinkFirstNodeID = nil
                    self?.canvasPlacementStatusHint = nil
                    self?.isTopologyEditingEnabled = false
                    self?.bumpCanvasViewportFitReset()
                }
            } catch EpanetError.apiError(200) {
                do {
                    let scene: NetworkScene
                    let contentForOptions: String?
                    if let d = prefetchedFileData {
                        let decoded = InpFileTextReader.decodeInpData(d)
                        contentForOptions = decoded
                        scene = try InpDisplayParser.parse(content: decoded)
                    } else {
                        contentForOptions = try? InpFileTextReader.contentsOfFile(path: pathCopy)
                        scene = try InpDisplayParser.parse(path: pathCopy)
                    }
                    let dispHints = contentForOptions.map { InpOptionsParser.parseOptionsHints(content: $0) }
                    let dispFlow = contentForOptions.flatMap { InpOptionsParser.parseFlowUnits(content: $0) }
                        ?? InpOptionsParser.parseFlowUnits(path: pathCopy)
                    await MainActor.run { [weak self] in
                        self?.project = nil
                        self?.replaceRenderingScene(scene)
                        self?.filePath = pathCopy
                        self?.errorMessage = "仅显示模式（不可计算）"
                        self?.runResult = nil
                        self?.lastCompletedSimulationDurationSeconds = nil
                        self?.lastCompletedSimulationHydraulicStepSeconds = nil
                        self?.simulationTimelinePlayheadSeconds = 0
                        self?.timeSeriesResults = nil
                        self?.chartPanelCurves.removeAll()
                        self?.inpFlowUnits = dispFlow
                        self?.cachedInpOptionsHints = dispHints
                        self?.editorMode = .browse
                        self?.selectedNodeIndex = nil
                        self?.selectedLinkIndex = nil
                        self?.selectedNodeID = nil
                        self?.selectedLinkID = nil
                        self?.selectedNodeIndices = []
                        self?.selectedLinkIndices = []
                        self?.isPropertyPanelVisible = false
                        self?.errorFocusNodeIndex = nil
                        self?.errorFocusLinkIndex = nil
                        self?.resultOverlayMode = .none
                        self?.nodePressureValues = []
                        self?.nodeHeadValues = []
                        self?.linkFlowValues = []
                        self?.linkVelocityValues = []
                        self?.recordRecentFile(path: pathCopy, nodeCount: scene.nodes.count, linkCount: scene.links.count)
                        self?.lastLoadAndRenderElapsedSeconds = CFAbsoluteTimeGetCurrent() - loadWallClockStart
                        self?.isLoading = false
                        self?.activeCanvasPlacementTool = nil
                        self?.placementLinkFirstNodeID = nil
                        self?.canvasPlacementStatusHint = nil
                        self?.isTopologyEditingEnabled = false
                        self?.bumpCanvasViewportFitReset()
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.errorMessage = "加载失败（仅显示解析）: \(error)"
                        self?.replaceRenderingScene(nil)
                        self?.project = nil
                        self?.filePath = nil
                        self?.inpFlowUnits = nil
                        self?.cachedInpOptionsHints = nil
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
                    self?.replaceRenderingScene(nil)
                    self?.project = nil
                    self?.filePath = nil
                    self?.inpFlowUnits = nil
                    self?.cachedInpOptionsHints = nil
                    self?.inpSourceSnapshot = nil
                    self?.errorFocusNodeIndex = focus.nodeIndex
                    self?.errorFocusLinkIndex = focus.linkIndex
                    self?.isLoading = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = "加载失败: \(error)"
                    self?.replaceRenderingScene(nil)
                    self?.project = nil
                    self?.filePath = nil
                    self?.inpFlowUnits = nil
                    self?.cachedInpOptionsHints = nil
                    self?.inpSourceSnapshot = nil
                    self?.errorFocusNodeIndex = nil
                    self?.errorFocusLinkIndex = nil
                    self?.isLoading = false
                }
            }
        }
    }

    /// 使用当前打开的 .inp 在内存中的 project 上执行水力求解，结果保留在 project 中，属性面板的压力/水头/流量/流速会正确显示。
    public func runCalculation() {
        guard let path = filePath, !path.isEmpty else { return }
        isRunning = true
        runResult = nil
        lastCompletedSimulationDurationSeconds = nil
        lastCompletedSimulationHydraulicStepSeconds = nil
        simulationTimelinePlayheadSeconds = 0
        timeSeriesResults = nil
        chartPanelCurves.removeAll()
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
                var tsStore = TimeSeriesResultStore()
                var t: Int32 = 0
                var dt: Int32 = 0
                // 与 epanet3.cpp EN_runEpanet 一致：以 advance 返回的步长判断，不可用 runSolver 的 t（首轮 t 为 0 会误退出）。
                repeat {
                    try proj.runSolver(time: &t)
                    tsStore.recordStep(time: Int(t), project: proj)
                    dt = 0
                    try proj.advanceSolver(dt: &dt)
                } while dt > 0
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                let simDurationSec = (try? proj.getTimeParam(param: .duration)) ?? 0
                let hydStepSec = max(1, (try? proj.getTimeParam(param: .hydStep)) ?? 3600)
                let collectedTS: TimeSeriesResultStore? = tsStore.stepCount > 0 ? tsStore : nil
                await MainActor.run { [weak self] in
                    self?.project = proj
                    self?.timeSeriesResults = collectedTS
                    let snap = try? InpFileTextReader.contentsOfFile(path: inpPath)
                    self?.inpSourceSnapshot = snap
                    self?.cachedInpOptionsHints = snap.map { InpOptionsParser.parseOptionsHints(content: $0) }
                    self?.inpPendingSaveDelta.clear()
                    self?.selectedNodeID = previousSelection.0
                    self?.selectedLinkID = previousSelection.1
                    self?.isPropertyPanelVisible = previousSelection.2
                    self?.lastCompletedSimulationDurationSeconds = simDurationSec > 0 ? simDurationSec : nil
                    self?.lastCompletedSimulationHydraulicStepSeconds = simDurationSec > 0 ? hydStepSec : nil
                    self?.simulationTimelinePlayheadSeconds = 0
                    self?.runResult = .success(elapsed: elapsed)
                    self?.editorMode = .result
                    self?.errorFocusNodeIndex = nil
                    self?.errorFocusLinkIndex = nil
                    self?.refreshSceneFromProject(preserveSelection: true, sceneLabel: "计算完成后刷新")
                    self?.applyResultScalarsForCurrentPlayhead()
                    self?.seedDefaultChartPanelCurvesIfPossible()
                    self?.isRunning = false
                }
            } catch let error as EpanetError {
                let message = Self.formatLocalizedEpanetError(error, scene: "运行失败（求解器）")
                let focus = Self.resolveErrorFocus(error, project: loadedProject)
                await MainActor.run { [weak self] in
                    self?.lastCompletedSimulationDurationSeconds = nil
                    self?.lastCompletedSimulationHydraulicStepSeconds = nil
                    self?.simulationTimelinePlayheadSeconds = 0
                    self?.timeSeriesResults = nil
                    self?.chartPanelCurves.removeAll()
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
                    self?.lastCompletedSimulationDurationSeconds = nil
                    self?.lastCompletedSimulationHydraulicStepSeconds = nil
                    self?.simulationTimelinePlayheadSeconds = 0
                    self?.timeSeriesResults = nil
                    self?.chartPanelCurves.removeAll()
                    self?.runResult = .failure(message: String(describing: error))
                    self?.errorFocusNodeIndex = nil
                    self?.errorFocusLinkIndex = nil
                    self?.isRunning = false
                }
            }
        }
    }

    /// 与工具栏 `SimulationDurationTimelineBar` 一致：0, Δt, 2Δt, …，末段不足一步则补总时长。
    private static func discreteSimulationTimePoints(duration: Int, step: Int) -> [Int] {
        guard duration > 0 else { return [0] }
        let s = max(1, step)
        var pts: [Int] = []
        var t = 0
        while true {
            pts.append(t)
            if t >= duration { break }
            let next = t + s
            if next >= duration {
                if pts.last != duration { pts.append(duration) }
                break
            }
            t = next
        }
        return pts
    }

    private static func nearestDiscreteTimeIndex(seconds: Double, points: [Int]) -> Int {
        guard !points.isEmpty else { return 0 }
        let s = Int(seconds.rounded())
        var bestIdx = 0
        var bestDist = Int.max
        for (i, p) in points.enumerated() {
            let d = abs(p - s)
            if d < bestDist { bestDist = d; bestIdx = i }
        }
        return bestIdx
    }

    /// 按水力时间步离散点，将时间轴游标前移/后移若干档（与滑块一致）；键盘左右方向键各对应 −1 / +1。
    public func stepSimulationTimelinePlayheadDiscreteSteps(_ delta: Int) {
        guard delta != 0,
              let duration = lastCompletedSimulationDurationSeconds, duration > 0,
              !isRunning,
              let r = runResult, case .success = r else { return }
        let hydStep = max(1, lastCompletedSimulationHydraulicStepSeconds ?? 3600)
        let points = Self.discreteSimulationTimePoints(duration: duration, step: hydStep)
        guard !points.isEmpty else { return }
        let idx = Self.nearestDiscreteTimeIndex(seconds: simulationTimelinePlayheadSeconds, points: points)
        let newIdx = min(max(0, idx + delta), points.count - 1)
        simulationTimelinePlayheadSeconds = Double(points[newIdx])
    }

    /// 按当前时间轴游标从 `timeSeriesResults` 取该时刻的压力/水头/流量/流速；无时序时回退为引擎当前快照。
    func applyResultScalarsForCurrentPlayhead() {
        guard let ts = timeSeriesResults, ts.stepCount > 0,
              let row = ts.rowIndexNearest(toPlayheadSeconds: simulationTimelinePlayheadSeconds),
              row < ts.nodePressure.count,
              row < ts.nodeHead.count,
              row < ts.linkFlow.count,
              row < ts.linkVelocity.count else {
            refreshResultData()
            return
        }
        nodePressureValues = ts.nodePressure[row]
        nodeHeadValues = ts.nodeHead[row]
        linkFlowValues = ts.linkFlow[row]
        linkVelocityValues = ts.linkVelocity[row]
        resultScalarRevision &+= 1
    }

    /// 属性面板「计算结果」：有 `timeSeriesResults` 时取与当前 `simulationTimelinePlayheadSeconds` 最接近的水力行；无时序时返回 `nil`（用 `project` 快照）。
    func resultScalarForPropertyPanel(nodeIndex: Int, param: NodeChartParam) -> Double? {
        guard let ts = timeSeriesResults, ts.stepCount > 0,
              let row = ts.rowIndexNearest(toPlayheadSeconds: simulationTimelinePlayheadSeconds) else { return nil }
        switch param {
        case .pressure:
            guard row < ts.nodePressure.count, nodeIndex >= 0, nodeIndex < ts.nodePressure[row].count else { return nil }
            return Double(ts.nodePressure[row][nodeIndex])
        case .head:
            guard row < ts.nodeHead.count, nodeIndex >= 0, nodeIndex < ts.nodeHead[row].count else { return nil }
            return Double(ts.nodeHead[row][nodeIndex])
        case .demand:
            guard row < ts.nodeDemand.count, nodeIndex >= 0, nodeIndex < ts.nodeDemand[row].count else { return nil }
            return Double(ts.nodeDemand[row][nodeIndex])
        case .tankLevel:
            guard row < ts.tankLevel.count, nodeIndex >= 0, nodeIndex < ts.tankLevel[row].count else { return nil }
            let v = ts.tankLevel[row][nodeIndex]
            guard v.isFinite else { return nil }
            return Double(v)
        }
    }

    /// 属性面板「计算结果」（管段）：有逐水力步时序时与 `resultScalarForPropertyPanel(nodeIndex:param:)` 同理。
    func resultScalarForPropertyPanel(linkIndex: Int, param: LinkChartParam) -> Double? {
        guard let ts = timeSeriesResults, ts.stepCount > 0,
              let row = ts.rowIndexNearest(toPlayheadSeconds: simulationTimelinePlayheadSeconds) else { return nil }
        switch param {
        case .flow:
            guard row < ts.linkFlow.count, linkIndex >= 0, linkIndex < ts.linkFlow[row].count else { return nil }
            return Double(ts.linkFlow[row][linkIndex])
        case .velocity:
            guard row < ts.linkVelocity.count, linkIndex >= 0, linkIndex < ts.linkVelocity[row].count else { return nil }
            return Double(ts.linkVelocity[row][linkIndex])
        case .headloss:
            guard row < ts.linkHeadloss.count, linkIndex >= 0, linkIndex < ts.linkHeadloss[row].count else { return nil }
            return Double(ts.linkHeadloss[row][linkIndex])
        case .status:
            guard row < ts.linkStatus.count, linkIndex >= 0, linkIndex < ts.linkStatus[row].count else { return nil }
            return Double(ts.linkStatus[row][linkIndex])
        }
    }

    /// D4：刷新用于上图展示的结果数组（压力/流量）。
    func refreshResultData() {
        guard let p = project else {
            nodePressureValues = []
            nodeHeadValues = []
            linkFlowValues = []
            linkVelocityValues = []
            resultScalarRevision &+= 1
            return
        }
        do {
            let nodeCount = try p.nodeCount()
            let linkCount = try p.linkCount()
            var nodeValues: [Float] = []
            nodeValues.reserveCapacity(nodeCount)
            var headValues: [Float] = []
            headValues.reserveCapacity(nodeCount)
            for i in 0..<nodeCount {
                let v = try p.getNodeValue(nodeIndex: i, param: .pressure)
                nodeValues.append(Float(v))
                let h = try p.getNodeValue(nodeIndex: i, param: .head)
                headValues.append(Float(h))
            }
            var linkValues: [Float] = []
            linkValues.reserveCapacity(linkCount)
            var velValues: [Float] = []
            velValues.reserveCapacity(linkCount)
            for i in 0..<linkCount {
                let v = try p.getLinkValue(linkIndex: i, param: .flow)
                linkValues.append(Float(v))
                let vel = try p.getLinkValue(linkIndex: i, param: .velocity)
                velValues.append(Float(vel))
            }
            nodePressureValues = nodeValues
            nodeHeadValues = headValues
            linkFlowValues = linkValues
            linkVelocityValues = velValues
            resultScalarRevision &+= 1
        } catch {
            // 保持上次可用结果，避免 UI 抖动；同时给出错误提示。
            errorMessage = "刷新结果数据失败: \(error)"
        }
    }

    func setResultOverlayMode(_ mode: ResultOverlayMode) {
        if resultOverlayMode != mode {
            resultScalarRevision &+= 1
        }
        resultOverlayMode = mode
        if mode != .none && nodePressureValues.isEmpty && linkFlowValues.isEmpty {
            applyResultScalarsForCurrentPlayhead()
        }
    }

    private static nonisolated func buildScene(from proj: EpanetProject) throws -> NetworkScene {
        let nodeCount = try proj.nodeCount()
        let linkCount = try proj.linkCount()

        var nodes: [NodeVertex] = []
        for i in 0..<nodeCount {
            let (x, y) = try proj.getNodeCoords(nodeIndex: i)
            if x > -1e19 && y > -1e19 {
                let nt = try proj.getNodeType(index: i)
                let kind: UInt8
                switch nt {
                case .junction: kind = 0
                case .reservoir: kind = 1
                case .tank: kind = 2
                }
                nodes.append(NodeVertex(x: Float(x), y: Float(y), nodeIndex: i, kind: kind))
            }
        }

        var links: [LinkVertex] = []
        for i in 0..<linkCount {
            let (n1, n2) = try proj.getLinkNodes(linkIndex: i)
            guard n1 >= 0, n2 >= 0, n1 < nodeCount, n2 < nodeCount else { continue }
            let (x1, y1) = try proj.getNodeCoords(nodeIndex: n1)
            let (x2, y2) = try proj.getNodeCoords(nodeIndex: n2)
            if x1 > -1e19, y1 > -1e19, x2 > -1e19, y2 > -1e19 {
                let lt = try proj.getLinkType(index: i)
                let kind: UInt8
                switch lt {
                case .pipe, .cvpipe: kind = 0
                case .pump: kind = 1
                default: kind = 2
                }
                links.append(LinkVertex(x1: Float(x1), y1: Float(y1), x2: Float(x2), y2: Float(y2), linkIndex: i, kind: kind))
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

    /// 当前画布所依据的模型统计（有 `project` 时用引擎管段 LENGTH 求和；仅显示模式用 `NetworkScene` 平面几何近似）。
    public func modelNetworkStatistics() -> ModelNetworkStatistics? {
        guard let scene else { return nil }
        if let p = project {
            return try? Self.statisticsFromProject(p, flowUnits: inpFlowUnits)
        }
        return Self.statisticsFromSceneOnly(scene)
    }

    private static func statisticsFromProject(_ p: EpanetProject, flowUnits: String?) throws -> ModelNetworkStatistics {
        var junctions = 0, tanks = 0, reservoirs = 0
        let nodeCount = try p.nodeCount()
        for i in 0..<nodeCount {
            switch try p.getNodeType(index: i) {
            case .junction: junctions += 1
            case .tank: tanks += 1
            case .reservoir: reservoirs += 1
            }
        }
        var pipes = 0, valves = 0, pumps = 0
        var lenSum = 0.0
        let linkCount = try p.linkCount()
        for i in 0..<linkCount {
            let lt = try p.getLinkType(index: i)
            switch lt {
            case .pipe, .cvpipe:
                pipes += 1
                lenSum += try p.getLinkValue(linkIndex: i, param: .length)
            case .pump: pumps += 1
            default: valves += 1
            }
        }
        let us = InpOptionsParser.isUSCustomary(flowUnits: flowUnits)
        return ModelNetworkStatistics(
            junctions: junctions,
            tanks: tanks,
            reservoirs: reservoirs,
            pipes: pipes,
            valves: valves,
            pumps: pumps,
            totalPipeLength: lenSum,
            lengthUnitLabel: us ? "ft" : "m",
            isPlanarLengthApproximation: false
        )
    }

    private static func statisticsFromSceneOnly(_ s: NetworkScene) -> ModelNetworkStatistics {
        var junctions = 0, tanks = 0, reservoirs = 0
        for n in s.nodes {
            switch n.kind {
            case 0: junctions += 1
            case 1: reservoirs += 1
            case 2: tanks += 1
            default: junctions += 1
            }
        }
        var pipes = 0, valves = 0, pumps = 0
        var planar = 0.0
        for l in s.links {
            switch l.kind {
            case 0:
                pipes += 1
                let dx = Double(l.x2 - l.x1)
                let dy = Double(l.y2 - l.y1)
                planar += (dx * dx + dy * dy).squareRoot()
            case 1: pumps += 1
            case 2: valves += 1
            default: pipes += 1
            }
        }
        return ModelNetworkStatistics(
            junctions: junctions,
            tanks: tanks,
            reservoirs: reservoirs,
            pipes: pipes,
            valves: valves,
            pumps: pumps,
            totalPipeLength: planar,
            lengthUnitLabel: "画布单位",
            isPlanarLengthApproximation: true
        )
    }
}
