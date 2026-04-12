import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

private func compareNumeric(_ x: Double, _ y: Double) -> ComparisonResult {
    if x < y { return .orderedAscending }
    if x > y { return .orderedDescending }
    return .orderedSame
}

private enum ObjectTableWideGridMetrics {
    /// 列间区域宽度（表头可拖动调整列宽；数据行与表头同一宽度以便竖线对齐）。
    static let columnGapWidth: CGFloat = 6
    /// 表头与单元格统一水平内边距；须先于 `frame(width:)` 使用，保证每列总宽恒为 `col.width`，列间竖线上下对齐。
    static let cellHPadding: CGFloat = 6
    /// 列间细实线线宽（pt）。
    static let columnRuleLineWidth: CGFloat = 0.5
    /// 表头列缝悬停 / 列宽拖动预览时竖线线宽（蓝色加粗）。
    static let headerDividerHighlightLineWidth: CGFloat = 2
    /// 行间水平分隔线高度（替代 `Divider()` 避免额外留白，竖线更易上下对齐）。
    static let rowSeparatorHeight: CGFloat = 1
    /// 数据行 / 表头单元格内容区最小高度（与 `minHeight: 22` 一致）。
    static let rowCellMinHeight: CGFloat = 22
    /// 行上下内边距（表头与数据行相同，保证行高一致）。
    static let rowVPadding: CGFloat = 5
    /// 单行总高度：上下内边距 + 内容区（与数据行 `minHeight` + `padding` 一致）。
    static var rowTotalHeight: CGFloat { rowCellMinHeight + 2 * rowVPadding }
}

/// 列间竖向细实线（占满 `columnGapWidth`，线条居中）。
/// - `fillsRowVertically`: 数据行内为 `true`，竖线随单元格行高延伸；表头须为 `false`，否则在 `VStack` 首行会纵向撑满剩余空间，表头异常变高。
/// - `isHighlighted`: 表头悬停或拖动该缝时为蓝色加粗。
private struct ObjectTableColumnVerticalDivider: View {
    var fillsRowVertically: Bool = true
    var isHighlighted: Bool = false

    private var lineColor: Color {
        isHighlighted ? Color.accentColor : Color.secondary.opacity(0.4)
    }

    private var lineWidth: CGFloat {
        isHighlighted
            ? ObjectTableWideGridMetrics.headerDividerHighlightLineWidth
            : ObjectTableWideGridMetrics.columnRuleLineWidth
    }

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: ObjectTableWideGridMetrics.columnGapWidth)
            .overlay {
                ObjectTableVerticalLineShape()
                    .stroke(lineColor, lineWidth: lineWidth)
            }
            .modifier(VerticalDividerHeightModifier(fillsRowVertically: fillsRowVertically))
    }
}

private struct VerticalDividerHeightModifier: ViewModifier {
    let fillsRowVertically: Bool

    func body(content: Content) -> some View {
        if fillsRowVertically {
            content.frame(maxHeight: .infinity)
        } else {
            content.frame(height: ObjectTableWideGridMetrics.rowCellMinHeight)
        }
    }
}

private struct ObjectTableVerticalLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let x = rect.midX
        p.move(to: CGPoint(x: x, y: rect.minY))
        p.addLine(to: CGPoint(x: x, y: rect.maxY))
        return p
    }
}

/// 数据单元格水平对齐：序号与 ID 居中，其余列右对齐；表头文字一律居中（与数据对齐方式独立）。
enum ObjectTableColumnCellAlignment {
    case center
    case trailing
}

/// 列宽拖动：记录分割线起点 x（行坐标），拖动中仅平移预览竖线，松手再写入 `columnWidthOverrides`。
private struct ColumnResizeSession {
    /// 与 `columnGapDragGesture(beforeColumnIndex:)` 一致，用于表头该缝高亮。
    var beforeColumnIndex: Int
    /// 右列左缘 x（与 `leftEdgeBeforeColumn(at: beforeColumnIndex)` 一致），拖动开始时记下。
    var anchorSplitX: CGFloat
}

/// 表头列拖动重排：仅用于预览与松手命中，拖动过程中不更新 `columnOrder`。
private struct ColumnReorderDragState {
    var columnId: String
    /// 该列左缘在表头 `HStack` 内的 x（与 `leftEdgeBeforeColumn` 一致）。
    var columnLeftEdge: CGFloat
    var columnWidth: CGFloat
    /// 手势起点在整行坐标中的 x，用于 `anchor + translation` 得到松手时指尖行坐标。
    var anchorRowX: CGFloat
}

// MARK: - 通用：横向滚动 + 表头与数据同步滚动（无 SwiftUI Table 列数上限）

/// 自绘宽表：外层横向 `ScrollView` 包裹「表头 + 纵向数据区」，列数可扩展至十余列以上。
struct WideScrollTableView<Row: Identifiable & ObjectTableRowIndexable>: View {
    struct Column: Identifiable {
        let id: String
        let title: String
        let width: CGFloat
        /// 拖窄时不得小于该宽度（按该列表头与典型单元格文本测算）。
        let minimumWidth: CGFloat
        let value: (Row) -> String
        /// 是否可点击单元格编辑（结果列、序号等可为 false）。
        let isEditable: (Row) -> Bool
        /// 数据区水平对齐（表头一律居中）。
        let cellContentAlignment: ObjectTableColumnCellAlignment
    }

    let columns: [Column]
    let rows: [Row]
    /// 当前排序列的 `Column.id`；nil 表示未选或未排序。
    let sortColumnId: String?
    let sortAscending: Bool
    let onHeaderTap: (String) -> Void
    /// 提交编辑：`columnId` 与 `Column.id` 一致。
    var onCellCommit: ((Row, String, String) -> Void)?

    init(
        columns: [Column],
        rows: [Row],
        sortColumnId: String?,
        sortAscending: Bool,
        onHeaderTap: @escaping (String) -> Void,
        onCellCommit: ((Row, String, String) -> Void)? = nil
    ) {
        self.columns = columns
        self.rows = rows
        self.sortColumnId = sortColumnId
        self.sortAscending = sortAscending
        self.onHeaderTap = onHeaderTap
        self.onCellCommit = onCellCommit
    }

    @State private var editingCellKey: String?
    @State private var editingText: String = ""
    #if os(iOS)
    @FocusState private var focusedCellKey: String?
    @State private var previousIOSFocusedCellKey: String?
    #endif

    /// 用户拖动表头分割线后的列宽；键为 `Column.id`。
    @State private var columnWidthOverrides: [String: CGFloat] = [:]
    /// 表头拖动调整列顺序；与 `columns` 中 `id` 对应，重排后仍用同一 `id` 的宽度覆盖。
    @State private var columnOrder: [String] = []
    /// 表头水平拖动与横向滚动区分：为 true 时禁用外层横向 ScrollView。
    @State private var headerReorderDragActive = false
    /// 超过阈值后记录被拖动的列 id；用于抬升样式，避免误触排序。
    @State private var headerDragColumnId: String?
    /// 列重排：拖动中不修改 `columnOrder`，仅记录几何与锚点；松手后一次 `moveColumnId`。
    @State private var columnReorderDrag: ColumnReorderDragState?
    /// 列重排水平平移（`GestureState`，松手自动归零）；用于浮动预览框，不写布局。
    @GestureState private var columnReorderTranslation: CGFloat = 0
    /// 列宽拖动水平平移（`GestureState`）；仅用于预览竖线，不写 `columnWidthOverrides`。
    @GestureState private var columnResizeDragTranslation: CGFloat = 0
    /// 列宽拖动会话（锚点）；与 `columnResizeDragTranslation` 共同决定预览线位置。
    @State private var columnResizeSession: ColumnResizeSession?
    /// 列宽拖动一开始即禁用横向滚动（避免 ScrollView 抢走水平拖动手势）。
    @State private var columnResizeActive = false
    /// 表头列缝悬停（macOS 指针），用于分割线变蓝；下标与 `beforeColumnIndex` 一致。
    @State private var headerDividerHoverBeforeIndex: Int?

    private var columnsById: [String: Column] {
        Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0) })
    }

    /// 当前列顺序（默认与 `columns` 一致，可经表头拖动重排）。
    private var orderedColumns: [Column] {
        let order = columnOrder.isEmpty ? columns.map(\.id) : columnOrder
        return order.compactMap { columnsById[$0] }
    }

    private func mergeColumnOrderWithColumns() {
        let newIds = columns.map(\.id)
        let newSet = Set(newIds)
        var merged = columnOrder.filter { newSet.contains($0) }
        for id in newIds where !merged.contains(id) {
            merged.append(id)
        }
        columnOrder = merged
    }

    /// 将列移动到 `toSlot`（与当前 `columnOrder` 中最终下标一致；先 remove 再 insert）。
    private func moveColumnId(_ id: String, toSlot: Int) {
        var o = columnOrder.isEmpty ? columns.map(\.id) : columnOrder
        guard let from = o.firstIndex(of: id) else { return }
        let to = min(max(toSlot, 0), o.count - 1)
        guard from != to else { return }
        o.remove(at: from)
        o.insert(id, at: to)
        columnOrder = o
    }

    /// 第 `index` 列左缘在表头行内的 x（含最左外侧竖线槽、其左侧列宽与列间空隙）。
    private func leftEdgeBeforeColumn(at index: Int) -> CGFloat {
        let gap = ObjectTableWideGridMetrics.columnGapWidth
        var x: CGFloat = gap
        for i in 0..<min(index, orderedColumns.count) {
            if i > 0 { x += gap }
            x += effectiveWidth(for: orderedColumns[i])
        }
        return x
    }

    /// 行坐标 x 映射为「插入到该列之前」的下标（0..<n）。
    private func insertIndexBeforeColumn(atRowX xFinger: CGFloat) -> Int {
        let cols = orderedColumns
        let n = cols.count
        guard n > 0 else { return 0 }
        let gap = ObjectTableWideGridMetrics.columnGapWidth
        var x: CGFloat = gap
        for i in 0..<n {
            let w = effectiveWidth(for: cols[i])
            let mid = x + w * 0.5
            if xFinger < mid {
                return i
            }
            x += w
            if i < n - 1 { x += gap }
        }
        return n - 1
    }

    /// 「插入到 insertBefore 之前」换算为 `remove` 之后 `insert` 的下标。
    private func moveDropSlot(fromIndex: Int, insertBefore: Int) -> Int {
        if fromIndex == insertBefore { return fromIndex }
        if fromIndex < insertBefore {
            return max(0, insertBefore - 1)
        }
        return insertBefore
    }

    /// 不含当前拖拽预览，仅来自持久化 overrides / 列默认宽。
    private func baseWidth(for col: Column) -> CGFloat {
        columnWidthOverrides[col.id] ?? col.width
    }

    /// 拖动列间分割线时左右两列宽度。若当前总宽等于两列最小值之和，仍可通过增大总宽来调宽（旧逻辑把 `rawL` 钳在 `[minL, total-minR]` 会退化为单点无法拖动）。
    private func pairWidthsAfterResize(L: Column, R: Column, translation: CGFloat) -> (CGFloat, CGFloat) {
        let bL = baseWidth(for: L)
        let bR = baseWidth(for: R)
        let minL = L.minimumWidth
        let minR = R.minimumWidth
        let total = bL + bR
        var newL = bL + translation
        newL = max(newL, minL)
        var newR = total - newL
        let expanded = newR < minR
        if expanded {
            newR = minR
            newL = max(minL, bL + translation)
        }
        let sL = snapColumnWidth(newL)
        let sR: CGFloat
        if expanded {
            sR = snapColumnWidth(newR)
        } else {
            sR = snapColumnWidth(max(minR, total - sL))
        }
        return (sL, sR)
    }

    private func effectiveWidth(for col: Column) -> CGFloat {
        baseWidth(for: col)
    }

    private var totalWidth: CGFloat {
        let gap = ObjectTableWideGridMetrics.columnGapWidth
        let cols = orderedColumns.reduce(0) { $0 + effectiveWidth(for: $1) }
        let innerGaps = CGFloat(max(0, orderedColumns.count - 1)) * gap
        let edgeGaps = 2 * gap
        return cols + innerGaps + edgeGaps
    }

    /// 对齐到整像素，避免最小宽度附近子像素来回与横向 ScrollView 抢手势时产生抖动。
    private func snapColumnWidth(_ w: CGFloat) -> CGFloat {
        w.rounded(.toNearestOrAwayFromZero)
    }

    /// 表头该列缝的分割线是否显示为蓝色（悬停或正在拖动列宽）。
    private func headerDividerSplitHighlighted(beforeColumnIndex idx: Int) -> Bool {
        if let s = columnResizeSession, s.beforeColumnIndex == idx { return true }
        if headerDividerHoverBeforeIndex == idx { return true }
        return false
    }

    /// 水平拖动重排：拖动中仅平移预览框，不修改 `columnOrder`；松手后按指尖行坐标一次落位。
    /// `minimumDistance: 0` 以便单击松手时仍能收到 `onEnded`，从而恢复表头排序（`onHeaderTap`）。
    private func headerColumnDragGesture(columnId: String) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($columnReorderTranslation) { value, state, _ in
                state = value.translation.width
            }
            .onChanged { value in
                let h = hypot(value.translation.width, value.translation.height)
                if h > 8 {
                    headerReorderDragActive = true
                    if headerDragColumnId == nil {
                        headerDragColumnId = columnId
                        guard let idx = orderedColumns.firstIndex(where: { $0.id == columnId }) else { return }
                        let col = orderedColumns[idx]
                        let left = leftEdgeBeforeColumn(at: idx)
                        let w = effectiveWidth(for: col)
                        let anchor = left + value.startLocation.x
                        columnReorderDrag = ColumnReorderDragState(
                            columnId: columnId,
                            columnLeftEdge: left,
                            columnWidth: w,
                            anchorRowX: anchor
                        )
                    }
                }
            }
            .onEnded { value in
                headerReorderDragActive = false
                let wasDraggingColumn = headerDragColumnId != nil
                let dragSnapshot = columnReorderDrag
                columnReorderDrag = nil
                headerDragColumnId = nil

                if let drag = dragSnapshot {
                    let xFinger = drag.anchorRowX + value.translation.width
                    let insertBefore = insertIndexBeforeColumn(atRowX: xFinger)
                    guard let from = orderedColumns.firstIndex(where: { $0.id == drag.columnId }) else { return }
                    let toSlot = moveDropSlot(fromIndex: from, insertBefore: insertBefore)
                    if from != toSlot {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            moveColumnId(drag.columnId, toSlot: toSlot)
                        }
                    }
                }

                let h = hypot(value.translation.width, value.translation.height)
                if !wasDraggingColumn, h < 8 {
                    onHeaderTap(columnId)
                }
            }
    }

    private func columnGapDragGesture(beforeColumnIndex idx: Int) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($columnResizeDragTranslation) { value, state, _ in
                state = value.translation.width
            }
            .onChanged { _ in
                columnResizeActive = true
                if columnResizeSession == nil {
                    columnResizeSession = ColumnResizeSession(
                        beforeColumnIndex: idx,
                        anchorSplitX: leftEdgeBeforeColumn(at: idx)
                    )
                }
            }
            .onEnded { value in
                columnResizeActive = false
                columnResizeSession = nil
                let L = orderedColumns[idx - 1]
                let R = orderedColumns[idx]
                let (newL, newR) = pairWidthsAfterResize(L: L, R: R, translation: value.translation.width)
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    columnWidthOverrides[L.id] = newL
                    columnWidthOverrides[R.id] = newR
                }
            }
    }

    var body: some View {
        GeometryReader { outerGeo in
            let viewportW = max(1, outerGeo.size.width)
            let viewportH = max(1, outerGeo.size.height)
            let tableMinW = max(totalWidth, 400)
            let contentMinW = max(tableMinW, viewportW)
            let scrollLocked = headerReorderDragActive || columnResizeActive
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    tableHorizontalRule
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(rows) { row in
                                dataRow(row)
                                tableHorizontalRule
                            }
                        }
                        .frame(minWidth: contentMinW, alignment: .topLeading)
                    }
                    .scrollDisabled(scrollLocked)
                    #if os(iOS)
                    .scrollDismissesKeyboard(.never)
                    #endif
                }
                .frame(minWidth: contentMinW, alignment: .topLeading)
                .frame(height: viewportH)
            }
            .scrollDisabled(scrollLocked)
            .frame(width: viewportW, height: viewportH, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if columnOrder.isEmpty {
                columnOrder = columns.map(\.id)
            } else {
                mergeColumnOrderWithColumns()
            }
        }
        .onChange(of: columns.map(\.id)) { _ in
            columnWidthOverrides = columnWidthOverrides.filter { id, _ in columns.contains(where: { $0.id == id }) }
            mergeColumnOrderWithColumns()
        }
        #if os(iOS)
        .onChange(of: focusedCellKey) { newFocus in
            let old = previousIOSFocusedCellKey
            previousIOSFocusedCellKey = newFocus
            if let old, old != newFocus, editingCellKey == old, let onCellCommit {
                if let pair = rowAndColumn(forCellKey: old) {
                    let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
                    onCellCommit(pair.row, pair.columnId, trimmed)
                }
                editingCellKey = nil
                editingText = ""
            }
            if let k = newFocus {
                editingCellKey = k
                if let v = valueString(forCellKey: k) {
                    editingText = v
                }
            }
        }
        #endif
    }

    /// 与 `Divider()` 等效的细横线，无系统 Divider 额外内边距，便于列竖线在表头/表体衔接处贯通。
    private var tableHorizontalRule: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.22))
            .frame(height: ObjectTableWideGridMetrics.rowSeparatorHeight)
    }

    private var headerRow: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .center, spacing: 0) {
                ObjectTableColumnVerticalDivider(fillsRowVertically: false, isHighlighted: false)
                    .allowsHitTesting(false)
                ForEach(Array(orderedColumns.enumerated()), id: \.element.id) { idx, col in
                    let isDraggingThisHeader = headerDragColumnId == col.id
                    Group {
                        if idx > 0 {
                            ObjectTableColumnVerticalDivider(
                                fillsRowVertically: false,
                                isHighlighted: headerDividerSplitHighlighted(beforeColumnIndex: idx)
                            )
                            .contentShape(Rectangle())
                            .highPriorityGesture(columnGapDragGesture(beforeColumnIndex: idx))
                            #if os(macOS)
                            .onHover { hovering in
                                if hovering {
                                    headerDividerHoverBeforeIndex = idx
                                } else if headerDividerHoverBeforeIndex == idx {
                                    headerDividerHoverBeforeIndex = nil
                                }
                            }
                            #endif
                        }
                        HStack(spacing: 4) {
                            Text(col.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if sortColumnId == col.id {
                                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, ObjectTableWideGridMetrics.cellHPadding)
                        .frame(width: effectiveWidth(for: col), alignment: .center)
                        .frame(minHeight: ObjectTableWideGridMetrics.rowCellMinHeight, alignment: .center)
                        .background {
                            if isDraggingThisHeader {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.14))
                            }
                        }
                        .overlay {
                            if isDraggingThisHeader {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                            }
                        }
                        .contentShape(Rectangle())
                        .scaleEffect(isDraggingThisHeader ? 1.02 : 1, anchor: .center)
                        .shadow(
                            color: isDraggingThisHeader ? Color.black.opacity(0.18) : .clear,
                            radius: isDraggingThisHeader ? 5 : 0,
                            y: isDraggingThisHeader ? 2 : 0
                        )
                        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isDraggingThisHeader)
                        .simultaneousGesture(headerColumnDragGesture(columnId: col.id))
                    }
                    .zIndex(isDraggingThisHeader ? 2 : 0)
                }
                ObjectTableColumnVerticalDivider(fillsRowVertically: false, isHighlighted: false)
                    .allowsHitTesting(false)
            }
            .padding(.vertical, ObjectTableWideGridMetrics.rowVPadding)
            .frame(minHeight: ObjectTableWideGridMetrics.rowTotalHeight)
            .background(headerBackground)

            if let drag = columnReorderDrag {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
                    .frame(width: drag.columnWidth, height: ObjectTableWideGridMetrics.rowTotalHeight)
                    .offset(x: drag.columnLeftEdge + columnReorderTranslation, y: 0)
                    .allowsHitTesting(false)
                    .zIndex(10)
            }

            if let s = columnResizeSession {
                let lineW = ObjectTableWideGridMetrics.headerDividerHighlightLineWidth
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: lineW, height: ObjectTableWideGridMetrics.rowTotalHeight)
                    .offset(
                        x: s.anchorSplitX + columnResizeDragTranslation - lineW * 0.5,
                        y: 0
                    )
                    .allowsHitTesting(false)
                    .zIndex(11)
            }
        }
    }

    private func dataRow(_ row: Row) -> some View {
        HStack(alignment: .center, spacing: 0) {
            ObjectTableColumnVerticalDivider()
                .allowsHitTesting(false)
            ForEach(Array(orderedColumns.enumerated()), id: \.element.id) { idx, col in
                let isDraggingThisColumn = headerDragColumnId == col.id
                let cellKey = cellKeyString(row: row, columnId: col.id)
                let editable = col.isEditable(row) && onCellCommit != nil
                let cellFrameAlign: Alignment = col.cellContentAlignment == .center ? .center : .trailing
                Group {
                    if idx > 0 {
                        ObjectTableColumnVerticalDivider()
                            .contentShape(Rectangle())
                            .highPriorityGesture(columnGapDragGesture(beforeColumnIndex: idx))
                    }
                    Group {
                    if editable {
                        #if os(macOS)
                        ObjectTableEditableCellMac(
                            text: cellTextBinding(row: row, col: col, cellKey: cellKey),
                            font: NSFont.systemFont(ofSize: 12),
                            textAlignment: col.cellContentAlignment == .center ? .center : .right,
                            onBeginEditing: {
                                editingCellKey = cellKey
                                editingText = col.value(row)
                            },
                            onEndEditing: { final in
                                guard let onCellCommit else { return }
                                let trimmed = final.trimmingCharacters(in: .whitespacesAndNewlines)
                                onCellCommit(row, col.id, trimmed)
                                if editingCellKey == cellKey {
                                    editingCellKey = nil
                                    editingText = ""
                                }
                            }
                        )
                        .padding(.horizontal, ObjectTableWideGridMetrics.cellHPadding)
                        .frame(width: effectiveWidth(for: col), alignment: cellFrameAlign)
                        .frame(minHeight: ObjectTableWideGridMetrics.rowCellMinHeight)
                        #else
                        TextField("", text: cellTextBinding(row: row, col: col, cellKey: cellKey))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .multilineTextAlignment(col.cellContentAlignment == .center ? .center : .trailing)
                            .padding(.horizontal, ObjectTableWideGridMetrics.cellHPadding)
                            .frame(width: effectiveWidth(for: col), alignment: cellFrameAlign)
                            .frame(minHeight: ObjectTableWideGridMetrics.rowCellMinHeight)
                            .foregroundStyle(Color.accentColor)
                            .focused($focusedCellKey, equals: cellKey)
                            .onSubmit {
                                guard let onCellCommit else { return }
                                let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
                                onCellCommit(row, col.id, trimmed)
                                focusedCellKey = nil
                                editingCellKey = nil
                                editingText = ""
                            }
                        #endif
                    } else {
                        Text(col.value(row))
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .multilineTextAlignment(col.cellContentAlignment == .center ? .center : .trailing)
                            .padding(.horizontal, ObjectTableWideGridMetrics.cellHPadding)
                            .frame(width: effectiveWidth(for: col), alignment: cellFrameAlign)
                            .frame(minHeight: ObjectTableWideGridMetrics.rowCellMinHeight)
                            .foregroundStyle(Color.primary)
                    }
                    }
                }
                .background {
                    if isDraggingThisColumn {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.06))
                    }
                }
                .zIndex(isDraggingThisColumn ? 1 : 0)
            }
            ObjectTableColumnVerticalDivider()
                .allowsHitTesting(false)
        }
        .padding(.vertical, ObjectTableWideGridMetrics.rowVPadding)
        .background(dataRowBackground)
    }

    private func cellKeyString(row: Row, columnId: String) -> String {
        "\(row.engineRowIndex)|\(columnId)"
    }

    private func cellTextBinding(row: Row, col: Column, cellKey: String) -> Binding<String> {
        Binding(
            get: {
                editingCellKey == cellKey ? editingText : col.value(row)
            },
            set: { new in
                if editingCellKey != cellKey {
                    editingCellKey = cellKey
                }
                editingText = new
            }
        )
    }

    private func rowAndColumn(forCellKey key: String) -> (row: Row, columnId: String)? {
        let parts = key.split(separator: "|", maxSplits: 1)
        guard parts.count == 2,
              let rowIdx = Int(parts[0]),
              let row = rows.first(where: { $0.engineRowIndex == rowIdx })
        else { return nil }
        return (row, String(parts[1]))
    }

    private func valueString(forCellKey key: String) -> String? {
        guard let pair = rowAndColumn(forCellKey: key),
              let col = columns.first(where: { $0.id == pair.columnId })
        else { return nil }
        return col.value(pair.row)
    }

    /// 表头整行填充，与数据区区分（略深于 `controlBackground` / `secondarySystemBackground`）。
    private var headerBackground: Color {
        #if os(macOS)
        Color(
            nsColor: NSColor.controlBackgroundColor
                .blended(withFraction: 0.1, of: NSColor.black) ?? NSColor.controlBackgroundColor
        )
        #else
        Color(UIColor.tertiarySystemGroupedBackground)
        #endif
    }

    /// 数据行背景（与表头 `controlBackground` / `secondarySystemBackground` 形成对比）。
    private var dataRowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(UIColor.systemBackground)
        #endif
    }
}

// MARK: - 线类宽表：列定义、排序

enum LinkWideColumn: Int, CaseIterable {
    case index = 0
    case linkId
    case typeLabel
    case node1
    case node2
    case length
    case diameter
    case roughness
    case minorLoss
    case initStatus
    case initSetting
    case kbulk
    case kwall
    case setting
    case energy
    case leakCoeff1
    case leakCoeff2
    case leakage
    case flow
    case velocity
    case headloss
    case status

    var title: String {
        switch self {
        case .index: return "序号"
        case .linkId: return "ID"
        case .typeLabel: return "类型"
        case .node1: return "起点"
        case .node2: return "终点"
        case .length: return "长度"
        case .diameter: return "管径"
        case .roughness: return "粗糙系数"
        case .minorLoss: return "局部损失"
        case .initStatus: return "初态"
        case .initSetting: return "初设"
        case .kbulk: return "Kbulk"
        case .kwall: return "Kwall"
        case .setting: return "设定"
        case .energy: return "能耗"
        case .leakCoeff1: return "泄漏系数1"
        case .leakCoeff2: return "泄漏系数2"
        case .leakage: return "泄漏"
        case .flow: return "流量"
        case .velocity: return "流速"
        case .headloss: return "水头损失"
        case .status: return "状态"
        }
    }

    /// 拖动列宽时下限：约一个字符宽度 + 水平内边距（可压到极窄）。
    var minimumWidth: CGFloat {
        ObjectTableWideGridMetrics.minimumColumnWidthOneCharacter
    }

    /// 初始列宽：表头与典型单元格样本在 12pt 下可读宽度。
    var width: CGFloat {
        ObjectTableWideGridMetrics.minContentColumnWidth(header: title, cellSamples: minimumContentSamples)
    }

    /// 用于测算列宽下限的典型单元格字符串（与 `cellText` 格式一致，取偏宽样本以保证可读）。
    private var minimumContentSamples: [String] {
        switch self {
        case .index: return ["999999"]
        case .linkId: return ["PIPE_12345678"]
        case .typeLabel: return ["Pump"]
        case .node1, .node2: return ["Junction_12"]
        case .length, .diameter: return ["123456.789"]
        case .roughness: return ["9999", "1234.5678"]
        case .minorLoss, .initStatus, .initSetting, .setting, .energy: return ["123456.7890"]
        case .kbulk, .kwall, .leakCoeff1, .leakCoeff2, .leakage: return ["1.23456e+10", "0.000000"]
        case .flow, .velocity: return ["123456789.1234"]
        case .headloss, .status: return ["123456789.1234"]
        }
    }

    /// 数据区：序号、管段 ID、类型 居中，其余列右对齐。
    var cellContentAlignment: ObjectTableColumnCellAlignment {
        switch self {
        case .index, .linkId, .typeLabel: return .center
        default: return .trailing
        }
    }

    /// `headlossHint` 与 `[OPTIONS] HEADLOSS` 一致，用于 H-W 下粗糙系数按整数显示。
    static func linkTableColumns(headlossHint: String?) -> [WideScrollTableView<LinkTableRow>.Column] {
        let hazenWilliams = (headlossHint?.uppercased() ?? "H-W") == "H-W"
        return LinkWideColumn.allCases.map { col in
            WideScrollTableView<LinkTableRow>.Column(
                id: "link.\(col.rawValue)",
                title: col.title,
                width: col.width,
                minimumWidth: col.minimumWidth,
                value: { row in col.cellText(row: row, hazenWilliamsRoughness: hazenWilliams) },
                isEditable: { _ in col.isObjectTableCellEditable },
                cellContentAlignment: col.cellContentAlignment
            )
        }
    }

    /// 对象表可编辑列（与属性面板「基本信息」一致：长度 / 管径 / 粗糙系数）。
    private var isObjectTableCellEditable: Bool {
        switch self {
        case .length, .diameter, .roughness: return true
        default: return false
        }
    }

    private func cellText(row: LinkTableRow, hazenWilliamsRoughness: Bool) -> String {
        switch self {
        case .index:
            return "\(row.index + 1)"
        case .linkId:
            return row.linkId
        case .typeLabel:
            return row.typeLabel
        case .node1:
            return row.node1Id
        case .node2:
            return row.node2Id
        case .length:
            return NumericDisplayFormat.formatPipeLengthOrDiameter(row.length)
        case .diameter:
            return NumericDisplayFormat.formatPipeLengthOrDiameter(row.diameter)
        case .roughness:
            return formatRoughnessDisplay(row.roughness, hazenWilliams: hazenWilliamsRoughness)
        case .minorLoss:
            return String(format: "%.4f", row.minorLoss)
        case .initStatus:
            return String(format: "%.4f", row.initStatus)
        case .initSetting:
            return String(format: "%.4f", row.initSetting)
        case .kbulk:
            return String(format: "%.6g", row.kbulk)
        case .kwall:
            return String(format: "%.6g", row.kwall)
        case .setting:
            return String(format: "%.4f", row.setting)
        case .energy:
            return String(format: "%.4f", row.energy)
        case .leakCoeff1:
            return String(format: "%.6g", row.leakCoeff1)
        case .leakCoeff2:
            return String(format: "%.6g", row.leakCoeff2)
        case .leakage:
            return String(format: "%.6g", row.leakage)
        case .flow:
            return formatOptionalFlowVelocity(row.flow)
        case .velocity:
            return formatOptionalFlowVelocity(row.velocity)
        case .headloss:
            return formatOptionalDouble(row.headloss, format: "%.4f")
        case .status:
            return formatOptionalDouble(row.status, format: "%.4f")
        }
    }

    private func formatRoughnessDisplay(_ roughness: Double, hazenWilliams: Bool) -> String {
        if hazenWilliams {
            return String(format: "%.0f", roughness.rounded())
        }
        return String(format: "%.4f", roughness)
    }

    private func formatOptionalDouble(_ v: Double?, format: String) -> String {
        guard let v else { return "" }
        return String(format: format, v)
    }

    private func formatOptionalFlowVelocity(_ v: Double?) -> String {
        guard let v else { return "" }
        return NumericDisplayFormat.formatLinkFlowOrVelocity(v)
    }

    /// 由 `Column.id`（`link.<rawValue>`）解析列枚举。
    static func column(fromColumnId id: String) -> LinkWideColumn? {
        guard id.hasPrefix("link.") else { return nil }
        guard let raw = Int(id.dropFirst(5)) else { return nil }
        return LinkWideColumn(rawValue: raw)
    }

    /// 表头点击：同列则反向，否则新列升序。
    static func cycleSort(
        tappedColumnId: String,
        currentColumn: inout LinkWideColumn,
        ascending: inout Bool
    ) {
        guard let col = column(fromColumnId: tappedColumnId) else { return }
        if col == currentColumn {
            ascending.toggle()
        } else {
            currentColumn = col
            ascending = true
        }
    }

    static func sortRows(_ rows: [LinkTableRow], column: LinkWideColumn, ascending: Bool) -> [LinkTableRow] {
        rows.sorted { a, b in
            let cmp = compareRows(a, b, column: column)
            if cmp == .orderedSame {
                return a.index < b.index
            }
            if ascending {
                return cmp == .orderedAscending
            }
            return cmp == .orderedDescending
        }
    }

    private static func compareRows(_ a: LinkTableRow, _ b: LinkTableRow, column: LinkWideColumn) -> ComparisonResult {
        switch column {
        case .index:
            return a.index < b.index ? .orderedAscending : (a.index > b.index ? .orderedDescending : .orderedSame)
        case .linkId:
            return a.linkId.localizedStandardCompare(b.linkId)
        case .typeLabel:
            return a.typeLabel.localizedStandardCompare(b.typeLabel)
        case .node1:
            return a.node1Id.localizedStandardCompare(b.node1Id)
        case .node2:
            return a.node2Id.localizedStandardCompare(b.node2Id)
        case .length:
            return compareNumeric(a.length, b.length)
        case .diameter:
            return compareNumeric(a.diameter, b.diameter)
        case .roughness:
            return compareNumeric(a.roughness, b.roughness)
        case .minorLoss:
            return compareNumeric(a.minorLoss, b.minorLoss)
        case .initStatus:
            return compareNumeric(a.initStatus, b.initStatus)
        case .initSetting:
            return compareNumeric(a.initSetting, b.initSetting)
        case .kbulk:
            return compareNumeric(a.kbulk, b.kbulk)
        case .kwall:
            return compareNumeric(a.kwall, b.kwall)
        case .setting:
            return compareNumeric(a.setting, b.setting)
        case .energy:
            return compareNumeric(a.energy, b.energy)
        case .leakCoeff1:
            return compareNumeric(a.leakCoeff1, b.leakCoeff1)
        case .leakCoeff2:
            return compareNumeric(a.leakCoeff2, b.leakCoeff2)
        case .leakage:
            return compareNumeric(a.leakage, b.leakage)
        case .flow:
            return compareNumeric(a.flowSortKey, b.flowSortKey)
        case .velocity:
            return compareNumeric(a.velocitySortKey, b.velocitySortKey)
        case .headloss:
            return compareNumeric(a.headlossSortKey, b.headlossSortKey)
        case .status:
            return compareNumeric(a.statusSortKey, b.statusSortKey)
        }
    }
}

// MARK: - 节点宽表

enum NodeWideColumn: Int, CaseIterable {
    case index = 0
    case nodeId
    case x
    case y
    case pressure
    case head
    case demand
    case tankLevel

    var title: String {
        switch self {
        case .index: return "序号"
        case .nodeId: return "ID"
        case .x: return "X"
        case .y: return "Y"
        case .pressure: return "压力"
        case .head: return "水头"
        case .demand: return "需水量"
        case .tankLevel: return "水位"
        }
    }

    /// 拖动列宽时下限：约一个字符宽度 + 水平内边距（可压到极窄）。
    var minimumWidth: CGFloat {
        ObjectTableWideGridMetrics.minimumColumnWidthOneCharacter
    }

    /// 初始列宽：表头与典型单元格样本在 12pt 下可读宽度。
    var width: CGFloat {
        ObjectTableWideGridMetrics.minContentColumnWidth(header: title, cellSamples: minimumContentSamples)
    }

    private var minimumContentSamples: [String] {
        switch self {
        case .index: return ["999999"]
        case .nodeId: return ["Junction_12345"]
        case .x, .y: return ["123456789.123"]
        case .pressure, .head, .tankLevel: return ["123456.789"]
        case .demand: return ["1234567890.1234"]
        }
    }

    /// 数据区：序号、节点 ID 居中，其余列右对齐。
    var cellContentAlignment: ObjectTableColumnCellAlignment {
        switch self {
        case .index, .nodeId: return .center
        default: return .trailing
        }
    }

    static func nodeTableColumns() -> [WideScrollTableView<NodeTableRow>.Column] {
        NodeWideColumn.allCases.map { col in
            WideScrollTableView<NodeTableRow>.Column(
                id: "node.\(col.rawValue)",
                title: col.title,
                width: col.width,
                minimumWidth: col.minimumWidth,
                value: { row in col.cellText(row: row) },
                isEditable: { row in col.isObjectTableCellEditable(row: row) },
                cellContentAlignment: col.cellContentAlignment
            )
        }
    }

    private func isObjectTableCellEditable(row: NodeTableRow) -> Bool {
        switch self {
        case .x, .y: return true
        case .demand: return row.junctionBaseDemand != nil
        default: return false
        }
    }

    private func cellText(row: NodeTableRow) -> String {
        switch self {
        case .index:
            return "\(row.index + 1)"
        case .nodeId:
            return row.nodeId
        case .x:
            return String(format: "%.3f", row.x)
        case .y:
            return String(format: "%.3f", row.y)
        case .pressure:
            return formatOptionalDouble(row.pressure, format: "%.2f")
        case .head:
            return formatOptionalDouble(row.head, format: "%.2f")
        case .demand:
            if let jb = row.junctionBaseDemand {
                return String(format: "%.4f", jb)
            }
            return formatOptionalDouble(row.demand, format: "%.4f")
        case .tankLevel:
            return formatOptionalDouble(row.tankLevel, format: "%.2f")
        }
    }

    private func formatOptionalDouble(_ v: Double?, format: String) -> String {
        guard let v else { return "" }
        return String(format: format, v)
    }

    static func column(fromColumnId id: String) -> NodeWideColumn? {
        guard id.hasPrefix("node.") else { return nil }
        guard let raw = Int(id.dropFirst(5)) else { return nil }
        return NodeWideColumn(rawValue: raw)
    }

    static func cycleSort(
        tappedColumnId: String,
        currentColumn: inout NodeWideColumn,
        ascending: inout Bool
    ) {
        guard let col = column(fromColumnId: tappedColumnId) else { return }
        if col == currentColumn {
            ascending.toggle()
        } else {
            currentColumn = col
            ascending = true
        }
    }

    static func sortRows(_ rows: [NodeTableRow], column: NodeWideColumn, ascending: Bool) -> [NodeTableRow] {
        rows.sorted { a, b in
            let cmp = compareRows(a, b, column: column)
            if cmp == .orderedSame {
                return a.index < b.index
            }
            if ascending {
                return cmp == .orderedAscending
            }
            return cmp == .orderedDescending
        }
    }

    private static func compareRows(_ a: NodeTableRow, _ b: NodeTableRow, column: NodeWideColumn) -> ComparisonResult {
        switch column {
        case .index:
            return a.index < b.index ? .orderedAscending : (a.index > b.index ? .orderedDescending : .orderedSame)
        case .nodeId:
            return a.nodeId.localizedStandardCompare(b.nodeId)
        case .x:
            return compareNumeric(a.x, b.x)
        case .y:
            return compareNumeric(a.y, b.y)
        case .pressure:
            return compareNumeric(a.pressureSortKey, b.pressureSortKey)
        case .head:
            return compareNumeric(a.headSortKey, b.headSortKey)
        case .demand:
            return compareNumeric(a.demandSortKey, b.demandSortKey)
        case .tankLevel:
            return compareNumeric(a.tankLevelSortKey, b.tankLevelSortKey)
        }
    }
}

// MARK: - 列宽下限（表头 + 数值完整可读）

extension ObjectTableWideGridMetrics {
    /// 拖动列宽时可压到的下限：12pt 下单字符（数字与中文取较大）+ 左右内边距。
    static var minimumColumnWidthOneCharacter: CGFloat {
        #if os(macOS)
        let cellFont = NSFont.systemFont(ofSize: 12)
        #else
        let cellFont = UIFont.systemFont(ofSize: 12)
        #endif
        var maxW: CGFloat = 0
        for s in ["0", "水"] {
            let w = (s as NSString).size(withAttributes: [.font: cellFont]).width
            maxW = max(maxW, w)
        }
        return ceil(maxW + 2 * cellHPadding + 1)
    }

    /// 单列：该列标题与给定单元格样本在表头（12pt semibold）与数据（12pt）下的最大宽度，加内边距与排序箭头占位；尽量小且能完整显示表头与样本。
    static func minContentColumnWidth(header: String, cellSamples: [String]) -> CGFloat {
        #if os(macOS)
        let headerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let cellFont = NSFont.systemFont(ofSize: 12)
        #else
        let headerFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let cellFont = UIFont.systemFont(ofSize: 12)
        #endif
        var maxW = (header as NSString).size(withAttributes: [.font: headerFont]).width
        for s in cellSamples {
            let w = (s as NSString).size(withAttributes: [.font: cellFont]).width
            maxW = max(maxW, w)
        }
        let sortChevronReserve: CGFloat = 12
        let margin: CGFloat = 2
        return ceil(maxW + 2 * cellHPadding + sortChevronReserve + margin)
    }
}
