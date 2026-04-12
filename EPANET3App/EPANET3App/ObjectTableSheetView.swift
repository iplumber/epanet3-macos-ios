import SwiftUI
import EPANET3Bridge

/// 与「显示」菜单及图层右键「打开表格」对应的对象表类型。
public enum ObjectTableKind: String, Identifiable, CaseIterable {
    case junction
    case tank
    case reservoir
    case pipe
    case valve
    case pump

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .junction: return "节点"
        case .tank: return "水塔"
        case .reservoir: return "水库"
        case .pipe: return "管段"
        case .valve: return "阀门"
        case .pump: return "水泵"
        }
    }

    var isNodeKind: Bool {
        switch self {
        case .junction, .tank, .reservoir: return true
        default: return false
        }
    }
}

/// 对象数据表（macOS 独立窗口中展示，非模态）。线类使用自绘「宽表」以支持十余列以上。
///
/// 行数据缓存在 `@State`，仅在文件/几何/结果/类型变化时从引擎重建，排序仅在排序参数或源数据变化时执行。
/// 避免 `@EnvironmentObject` 的任意 `@Published` 变化导致万级行表格反复从引擎读取+排序。
struct ObjectTableSheetView: View {
    let kind: ObjectTableKind
    @EnvironmentObject var appState: AppState

    @State private var nodeSortColumn: NodeWideColumn = .index
    @State private var nodeSortAscending = true
    @State private var linkSortColumn: LinkWideColumn = .index
    @State private var linkSortAscending = true

    @State private var cachedNodeRows: [NodeTableRow] = []
    @State private var cachedLinkRows: [LinkTableRow] = []
    @State private var sortedNodeRows: [NodeTableRow] = []
    @State private var sortedLinkRows: [LinkTableRow] = []
    @State private var playheadDebounceTask: Task<Void, Never>?

    private struct DataRebuildTrigger: Equatable {
        let filePath: String?
        let geometryRevision: UInt64
        let resultRevision: UInt64
        let kind: ObjectTableKind
    }

    private var dataRebuildTrigger: DataRebuildTrigger {
        DataRebuildTrigger(
            filePath: appState.filePath,
            geometryRevision: appState.sceneGeometryRevision,
            resultRevision: appState.resultScalarRevision,
            kind: kind
        )
    }

    var body: some View {
        #if os(macOS)
        tableContent
        #else
        NavigationStack {
            tableContent
        }
        .frame(minWidth: 520, minHeight: 380)
        #endif
    }

    @ViewBuilder
    private var tableContent: some View {
        Group {
            if appState.project == nil {
                tableEmptyPlaceholder(title: "无工程", subtitle: "请先打开 .inp 文件", systemImage: "doc")
            } else if kind.isNodeKind {
                nodeTableBody
            } else {
                linkTableBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #if os(macOS)
        .navigationTitle("")
        #else
        .navigationTitle(kind.title)
        #endif
        .task(id: dataRebuildTrigger) {
            rebuildRows()
        }
        .onChange(of: kind) { _ in
            nodeSortColumn = .index
            nodeSortAscending = true
            linkSortColumn = .index
            linkSortAscending = true
        }
        .onChange(of: nodeSortColumn) { _ in resortNodeRows() }
        .onChange(of: nodeSortAscending) { _ in resortNodeRows() }
        .onChange(of: linkSortColumn) { _ in resortLinkRows() }
        .onChange(of: linkSortAscending) { _ in resortLinkRows() }
        .onChange(of: appState.simulationTimelinePlayheadSeconds) { _ in
            guard appState.timeSeriesResults != nil else { return }
            playheadDebounceTask?.cancel()
            playheadDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                rebuildRows()
            }
        }
        .onDisappear {
            playheadDebounceTask?.cancel()
        }
    }

    @ViewBuilder
    private var nodeTableBody: some View {
        if sortedNodeRows.isEmpty {
            tableEmptyPlaceholder(title: "无数据", subtitle: "当前模型中没有此类对象", systemImage: "circle.dashed")
        } else {
            WideScrollTableView(
                columns: NodeWideColumn.nodeTableColumns(),
                rows: sortedNodeRows,
                sortColumnId: "node.\(nodeSortColumn.rawValue)",
                sortAscending: nodeSortAscending,
                onHeaderTap: { columnId in
                    NodeWideColumn.cycleSort(
                        tappedColumnId: columnId,
                        currentColumn: &nodeSortColumn,
                        ascending: &nodeSortAscending
                    )
                },
                onCellCommit: { row, columnId, text in
                    appState.commitObjectTableNodeCell(row: row, columnId: columnId, text: text)
                }
            )
        }
    }

    @ViewBuilder
    private var linkTableBody: some View {
        if sortedLinkRows.isEmpty {
            tableEmptyPlaceholder(title: "无数据", subtitle: "当前模型中没有此类对象", systemImage: "line.diagonal")
        } else {
            WideScrollTableView(
                columns: LinkWideColumn.linkTableColumns(headlossHint: appState.cachedInpOptionsHints?.headloss),
                rows: sortedLinkRows,
                sortColumnId: "link.\(linkSortColumn.rawValue)",
                sortAscending: linkSortAscending,
                onHeaderTap: { columnId in
                    LinkWideColumn.cycleSort(
                        tappedColumnId: columnId,
                        currentColumn: &linkSortColumn,
                        ascending: &linkSortAscending
                    )
                },
                onCellCommit: { row, columnId, text in
                    appState.commitObjectTableLinkCell(row: row, columnId: columnId, text: text)
                }
            )
        }
    }

    // MARK: - 行数据缓存与排序

    private func rebuildRows() {
        guard let project = appState.project else {
            cachedNodeRows = []
            cachedLinkRows = []
            sortedNodeRows = []
            sortedLinkRows = []
            return
        }
        if kind.isNodeKind {
            cachedNodeRows = ObjectTableRows.nodeRows(project: project, kind: kind, appState: appState)
            cachedLinkRows = []
            sortedLinkRows = []
            resortNodeRows()
        } else {
            cachedLinkRows = ObjectTableRows.linkRows(project: project, kind: kind, appState: appState)
            cachedNodeRows = []
            sortedNodeRows = []
            resortLinkRows()
        }
    }

    private func resortNodeRows() {
        guard !cachedNodeRows.isEmpty else {
            sortedNodeRows = []
            return
        }
        sortedNodeRows = NodeWideColumn.sortRows(cachedNodeRows, column: nodeSortColumn, ascending: nodeSortAscending)
    }

    private func resortLinkRows() {
        guard !cachedLinkRows.isEmpty else {
            sortedLinkRows = []
            return
        }
        sortedLinkRows = LinkWideColumn.sortRows(cachedLinkRows, column: linkSortColumn, ascending: linkSortAscending)
    }

    private func tableEmptyPlaceholder(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#if os(macOS)
/// 单窗口内切换对象表类型：分段控件放在窗口标题栏中部（`ToolbarItem(placement: .principal)`）。
struct ObjectTableTabsView: View {
    @EnvironmentObject var appState: AppState

    private var availableKinds: [ObjectTableKind] {
        guard let p = appState.project else { return [] }
        return ObjectTableKind.allCases.filter { ObjectTableRows.kindHasAnyObjects(project: p, kind: $0) }
    }

    private var effectiveKind: ObjectTableKind {
        let avail = availableKinds
        guard let s = appState.objectTableSheetKind, avail.contains(s) else {
            return avail.first ?? .junction
        }
        return s
    }

    private var selectionBinding: Binding<ObjectTableKind> {
        Binding(
            get: { effectiveKind },
            set: { appState.objectTableSheetKind = $0 }
        )
    }

    var body: some View {
        Group {
            if appState.project == nil {
                ObjectTableSheetView(kind: .junction)
            } else if availableKinds.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("无列表对象")
                        .font(.headline)
                    Text("当前模型中无节点、管段等可列表对象")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NavigationStack {
                    ObjectTableSheetView(kind: effectiveKind)
                        .toolbar {
                            if availableKinds.count > 1 {
                                ToolbarItem(placement: .principal) {
                                    Picker("", selection: selectionBinding) {
                                        ForEach(availableKinds, id: \.self) { k in
                                            Text(k.title).tag(k)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .controlSize(.small)
                                    .labelsHidden()
                                    .frame(maxWidth: 720)
                                    .accessibilityLabel("对象类型")
                                }
                            }
                        }
                }
            }
        }
        .frame(minWidth: 880, minHeight: 380)
        .onAppear { reconcileSelectionToAvailableKinds() }
        .onChange(of: appState.sceneGeometryRevision) { _ in
            reconcileSelectionToAvailableKinds()
        }
        .onChange(of: appState.filePath) { _ in
            reconcileSelectionToAvailableKinds()
        }
    }

    private func reconcileSelectionToAvailableKinds() {
        let avail = availableKinds
        guard !avail.isEmpty else { return }
        if let s = appState.objectTableSheetKind, avail.contains(s) { return }
        appState.objectTableSheetKind = avail.first
    }
}
#endif
