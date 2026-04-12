import EPANET3Bridge

/// 对象表行：用引擎索引生成稳定的单元格编辑键（避免 ID 中含特殊字符）。
protocol ObjectTableRowIndexable: Identifiable {
    var engineRowIndex: Int { get }
}

/// 节点对象表行。
struct NodeTableRow: Identifiable, ObjectTableRowIndexable {
    let id: String
    let index: Int
    let nodeId: String
    let x: Double
    let y: Double
    let pressure: Double?
    let head: Double?
    /// 计算结果（时序当前步）；「需水量」列在 junction 下改为展示/编辑 `junctionBaseDemand`。
    let demand: Double?
    let tankLevel: Double?
    /// 仅 junction：引擎 `[JUNCTIONS]` 基础需水量，可编辑。
    let junctionBaseDemand: Double?
    let pressureSortKey: Double
    let headSortKey: Double
    let demandSortKey: Double
    let tankLevelSortKey: Double

    var engineRowIndex: Int { index }
}

/// 线类对象表行（宽表可展示 15+ 列）。
struct LinkTableRow: Identifiable, ObjectTableRowIndexable {
    let id: String
    let index: Int
    let linkId: String
    let typeLabel: String
    let node1Id: String
    let node2Id: String
    let length: Double
    let diameter: Double
    let roughness: Double
    let minorLoss: Double
    let initStatus: Double
    let initSetting: Double
    let kbulk: Double
    let kwall: Double
    let setting: Double
    let energy: Double
    let leakCoeff1: Double
    let leakCoeff2: Double
    let leakage: Double
    let flow: Double?
    let velocity: Double?
    let headloss: Double?
    let status: Double?
    let flowSortKey: Double
    let velocitySortKey: Double
    let headlossSortKey: Double
    let statusSortKey: Double

    var engineRowIndex: Int { index }
}

enum ObjectTableRows {
    private static func sortKeyForTable(_ v: Double?) -> Double {
        v.map { $0 } ?? .infinity
    }

    @MainActor
    static func nodeRows(project: EpanetProject, kind: ObjectTableKind, appState: AppState) -> [NodeTableRow] {
        guard kind.isNodeKind else { return [] }
        let target: NodeTypes
        switch kind {
        case .junction: target = .junction
        case .tank: target = .tank
        case .reservoir: target = .reservoir
        default: return []
        }
        guard let n = try? project.nodeCount() else { return [] }

        let ts = appState.timeSeriesResults
        let presSlice: [Float]?
        let headSlice: [Float]?
        let demSlice: [Float]?
        let tlvlSlice: [Float]?
        if let ts, ts.stepCount > 0,
           let row = ts.rowIndexNearest(toPlayheadSeconds: appState.simulationTimelinePlayheadSeconds) {
            presSlice = row < ts.nodePressure.count ? ts.nodePressure[row] : nil
            headSlice = row < ts.nodeHead.count ? ts.nodeHead[row] : nil
            demSlice  = row < ts.nodeDemand.count ? ts.nodeDemand[row] : nil
            tlvlSlice = row < ts.tankLevel.count ? ts.tankLevel[row] : nil
        } else {
            presSlice = nil; headSlice = nil; demSlice = nil; tlvlSlice = nil
        }

        var rows: [NodeTableRow] = []
        for i in 0..<n {
            guard let t = try? project.getNodeType(index: i), t == target else { continue }
            guard let id = try? project.getNodeId(index: i) else { continue }
            let xy: (x: Double, y: Double) = (try? project.getNodeCoords(nodeIndex: i)) ?? (x: 0, y: 0)
            let pressure: Double? = presSlice.flatMap { i < $0.count ? Double($0[i]) : nil }
            let head: Double?     = headSlice.flatMap { i < $0.count ? Double($0[i]) : nil }
            let demand: Double?   = demSlice.flatMap  { i < $0.count ? Double($0[i]) : nil }
            let tankLevel: Double? = {
                guard let slice = tlvlSlice, i < slice.count else { return nil as Double? }
                let v = slice[i]
                return v.isFinite ? Double(v) : nil
            }()
            let junctionBaseDemand: Double? = (t == .junction) ? (try? project.getNodeValue(nodeIndex: i, param: .basedemand)) : nil
            let demandSortKey: Double = {
                if let jb = junctionBaseDemand { return jb }
                return sortKeyForTable(demand)
            }()
            rows.append(
                NodeTableRow(
                    id: id,
                    index: i,
                    nodeId: id,
                    x: xy.x,
                    y: xy.y,
                    pressure: pressure,
                    head: head,
                    demand: demand,
                    tankLevel: tankLevel,
                    junctionBaseDemand: junctionBaseDemand,
                    pressureSortKey: sortKeyForTable(pressure),
                    headSortKey: sortKeyForTable(head),
                    demandSortKey: demandSortKey,
                    tankLevelSortKey: sortKeyForTable(tankLevel)
                )
            )
        }
        return rows
    }

    @MainActor
    static func linkRows(project: EpanetProject, kind: ObjectTableKind, appState: AppState) -> [LinkTableRow] {
        guard !kind.isNodeKind else { return [] }
        guard let lc = try? project.linkCount() else { return [] }

        let ts = appState.timeSeriesResults
        let flowSlice: [Float]?
        let velSlice: [Float]?
        let hlSlice: [Float]?
        let stSlice: [Float]?
        if let ts, ts.stepCount > 0,
           let row = ts.rowIndexNearest(toPlayheadSeconds: appState.simulationTimelinePlayheadSeconds) {
            flowSlice = row < ts.linkFlow.count ? ts.linkFlow[row] : nil
            velSlice  = row < ts.linkVelocity.count ? ts.linkVelocity[row] : nil
            hlSlice   = row < ts.linkHeadloss.count ? ts.linkHeadloss[row] : nil
            stSlice   = row < ts.linkStatus.count ? ts.linkStatus[row] : nil
        } else {
            flowSlice = nil; velSlice = nil; hlSlice = nil; stSlice = nil
        }

        var rows: [LinkTableRow] = []
        for i in 0..<lc {
            guard let lt = try? project.getLinkType(index: i) else { continue }
            let include: Bool
            switch kind {
            case .pipe:
                include = (lt == .pipe || lt == .cvpipe)
            case .pump:
                include = (lt == .pump)
            case .valve:
                include = (lt != .pipe && lt != .cvpipe && lt != .pump)
            default:
                include = false
            }
            guard include else { continue }
            guard let lid = try? project.getLinkId(index: i) else { continue }
            let ends: (node1: Int, node2: Int) = (try? project.getLinkNodes(linkIndex: i)) ?? (node1: 0, node2: 0)
            let n1 = (try? project.getNodeId(index: ends.node1)) ?? "—"
            let n2 = (try? project.getNodeId(index: ends.node2)) ?? "—"
            let length = (try? project.getLinkValue(linkIndex: i, param: .length)) ?? 0
            let diameter = (try? project.getLinkValue(linkIndex: i, param: .diameter)) ?? 0
            let roughness = (try? project.getLinkValue(linkIndex: i, param: .roughness)) ?? 0
            let minorLoss = (try? project.getLinkValue(linkIndex: i, param: .minorloss)) ?? 0
            let initStatus = (try? project.getLinkValue(linkIndex: i, param: .initstatus)) ?? 0
            let initSetting = (try? project.getLinkValue(linkIndex: i, param: .initsetting)) ?? 0
            let kbulk = (try? project.getLinkValue(linkIndex: i, param: .kbulk)) ?? 0
            let kwall = (try? project.getLinkValue(linkIndex: i, param: .kwall)) ?? 0
            let setting = (try? project.getLinkValue(linkIndex: i, param: .setting)) ?? 0
            let energy = (try? project.getLinkValue(linkIndex: i, param: .energy)) ?? 0
            let leakCoeff1 = (try? project.getLinkValue(linkIndex: i, param: .leakcoeff1)) ?? 0
            let leakCoeff2 = (try? project.getLinkValue(linkIndex: i, param: .leakcoeff2)) ?? 0
            let leakage = (try? project.getLinkValue(linkIndex: i, param: .leakage)) ?? 0
            let flow: Double?     = flowSlice.flatMap { i < $0.count ? Double($0[i]) : nil }
            let velocity: Double? = velSlice.flatMap  { i < $0.count ? Double($0[i]) : nil }
            let headloss: Double? = hlSlice.flatMap   { i < $0.count ? Double($0[i]) : nil }
            let status: Double?   = stSlice.flatMap   { i < $0.count ? Double($0[i]) : nil }
            rows.append(
                LinkTableRow(
                    id: lid,
                    index: i,
                    linkId: lid,
                    typeLabel: linkTypeShortLabel(lt),
                    node1Id: n1,
                    node2Id: n2,
                    length: length,
                    diameter: diameter,
                    roughness: roughness,
                    minorLoss: minorLoss,
                    initStatus: initStatus,
                    initSetting: initSetting,
                    kbulk: kbulk,
                    kwall: kwall,
                    setting: setting,
                    energy: energy,
                    leakCoeff1: leakCoeff1,
                    leakCoeff2: leakCoeff2,
                    leakage: leakage,
                    flow: flow,
                    velocity: velocity,
                    headloss: headloss,
                    status: status,
                    flowSortKey: sortKeyForTable(flow),
                    velocitySortKey: sortKeyForTable(velocity),
                    headlossSortKey: sortKeyForTable(headloss),
                    statusSortKey: sortKeyForTable(status)
                )
            )
        }
        return rows
    }

    private static func linkTypeShortLabel(_ t: LinkTypes) -> String {
        switch t {
        case .cvpipe: return "CV"
        case .pipe: return "Pipe"
        case .pump: return "Pump"
        case .prv: return "PRV"
        case .psv: return "PSV"
        case .pbv: return "PBV"
        case .fcv: return "FCV"
        case .tcv: return "TCV"
        case .gpv: return "GPV"
        @unknown default: return "?"
        }
    }

    static func kindHasAnyObjects(project: EpanetProject, kind: ObjectTableKind) -> Bool {
        if kind.isNodeKind {
            let target: NodeTypes
            switch kind {
            case .junction: target = .junction
            case .tank: target = .tank
            case .reservoir: target = .reservoir
            default: return false
            }
            guard let n = try? project.nodeCount() else { return false }
            for i in 0..<n {
                guard let t = try? project.getNodeType(index: i), t == target else { continue }
                return true
            }
            return false
        }
        guard let lc = try? project.linkCount() else { return false }
        for i in 0..<lc {
            guard let lt = try? project.getLinkType(index: i) else { continue }
            switch kind {
            case .pipe:
                if lt == .pipe || lt == .cvpipe { return true }
            case .pump:
                if lt == .pump { return true }
            case .valve:
                if lt != .pipe && lt != .cvpipe && lt != .pump { return true }
            default:
                break
            }
        }
        return false
    }
}
