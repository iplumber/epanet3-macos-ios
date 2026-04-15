/* EPANET 3 Swift Bridge
 * Wraps the EPANET 3 C API for use from Swift.
 * Only .inp format is supported.
 */

import Foundation

// MARK: - C API declarations (via @_silgen_name)

@_silgen_name("EN_getVersion")
func _EN_getVersion(_ version: UnsafeMutablePointer<Int32>) -> Int32

@_silgen_name("EN_runEpanet")
func _EN_runEpanet(_ inpFile: UnsafePointer<CChar>?, _ rptFile: UnsafePointer<CChar>?, _ outFile: UnsafePointer<CChar>?) -> Int32

@_silgen_name("EN_createProject")
func _EN_createProject() -> UnsafeMutableRawPointer?

@_silgen_name("EN_cloneProject")
func _EN_cloneProject(_ pClone: UnsafeMutableRawPointer?, _ pSource: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_deleteProject")
func _EN_deleteProject(_ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_loadProject")
func _EN_loadProject(_ fname: UnsafePointer<CChar>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_saveProject")
func _EN_saveProject(_ fname: UnsafePointer<CChar>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_clearProject")
func _EN_clearProject(_ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_initSolver")
func _EN_initSolver(_ initFlows: Int32, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_runSolver")
func _EN_runSolver(_ t: UnsafeMutablePointer<Int32>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_advanceSolver")
func _EN_advanceSolver(_ dt: UnsafeMutablePointer<Int32>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_openOutputFile")
func _EN_openOutputFile(_ fname: UnsafePointer<CChar>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_saveOutput")
func _EN_saveOutput(_ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_openReportFile")
func _EN_openReportFile(_ fname: UnsafePointer<CChar>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_writeReport")
func _EN_writeReport(_ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_writeSummary")
func _EN_writeSummary(_ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_writeResults")
func _EN_writeResults(_ t: Int32, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_writeMsgLog")
func _EN_writeMsgLog(_ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getMessageLog")
func _EN_getMessageLog(_ buf: UnsafeMutablePointer<CChar>?, _ maxLen: Int32, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getCount")
func _EN_getCount(_ type: Int32, _ count: UnsafeMutablePointer<Int32>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getNodeIndex")
func _EN_getNodeIndex(_ id: UnsafePointer<CChar>?, _ index: UnsafeMutablePointer<Int32>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getNodeId")
func _EN_getNodeId(_ index: Int32, _ id: UnsafeMutablePointer<CChar>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getNodeType")
func _EN_getNodeType(_ index: Int32, _ type: UnsafeMutablePointer<Int32>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getNodeValue")
func _EN_getNodeValue(_ index: Int32, _ param: Int32, _ value: UnsafeMutablePointer<Double>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getLinkIndex")
func _EN_getLinkIndex(_ id: UnsafePointer<CChar>?, _ index: UnsafeMutablePointer<Int32>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getLinkId")
func _EN_getLinkId(_ index: Int32, _ id: UnsafeMutablePointer<CChar>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getLinkType")
func _EN_getLinkType(_ index: Int32, _ type: UnsafeMutablePointer<Int32>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getLinkNodes")
func _EN_getLinkNodes(_ index: Int32, _ node1: UnsafeMutablePointer<Int32>?, _ node2: UnsafeMutablePointer<Int32>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getLinkValue")
func _EN_getLinkValue(_ index: Int32, _ param: Int32, _ value: UnsafeMutablePointer<Double>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getOption")
func _EN_getOption(_ type: Int32, _ value: UnsafeMutablePointer<Double>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getTimeParam")
func _EN_getTimeParam(_ type: Int32, _ value: UnsafeMutablePointer<CLong>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getFlowUnits")
func _EN_getFlowUnits(_ units: UnsafeMutablePointer<Int32>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_setOption")
func _EN_setOption(_ type: Int32, _ value: Double, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_setTimeParam")
func _EN_setTimeParam(_ type: Int32, _ value: Int32, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getError")
func _EN_getError(_ code: Int32, _ msg: UnsafeMutablePointer<CChar>?, _ maxLen: Int32, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_setNodeValue")
func _EN_setNodeValue(_ index: Int32, _ param: Int32, _ value: Double, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_setLinkValue")
func _EN_setLinkValue(_ index: Int32, _ param: Int32, _ value: Double, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_createNode")
func _EN_createNode(_ id: UnsafePointer<CChar>?, _ type: Int32, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_createLink")
func _EN_createLink(_ id: UnsafePointer<CChar>?, _ type: Int32, _ fromNode: Int32, _ toNode: Int32, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_deleteNode")
func _EN_deleteNode(_ id: UnsafePointer<CChar>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_deleteLink")
func _EN_deleteLink(_ id: UnsafePointer<CChar>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_setNoriaExportVersion")
func _EN_setNoriaExportVersion(_ version: UnsafePointer<CChar>?, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_setInpWriterSectionFractionDigits")
func _EN_setInpWriterSectionFractionDigits(_ section: UnsafePointer<CChar>?, _ digits: Int32, _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getNodeResultsBulkF")
func _EN_getNodeResultsBulkF(
    _ pressure: UnsafeMutablePointer<Float>?,
    _ head: UnsafeMutablePointer<Float>?,
    _ demand: UnsafeMutablePointer<Float>?,
    _ tankLevel: UnsafeMutablePointer<Float>?,
    _ p: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("EN_getLinkResultsBulkF")
func _EN_getLinkResultsBulkF(
    _ flow: UnsafeMutablePointer<Float>?,
    _ velocity: UnsafeMutablePointer<Float>?,
    _ headloss: UnsafeMutablePointer<Float>?,
    _ status: UnsafeMutablePointer<Float>?,
    _ p: UnsafeMutableRawPointer?) -> Int32

// MARK: - Enums (matching epanet3.h)

public enum NodeParams: Int32 {
    case elevation = 0, basedemand, basepattern, emitterflow, initqual, sourcequal, sourcepat, sourcetype
    case tanklevel, fulldemand, head, pressure, quality, sourcemass
    case initvolume, mixmodel, mixzonevol, tankdiam, minvolume, volcurve, minlevel, maxlevel, mixfraction, tankKbulk, tankvolume
    case actualdemand, outflow
    case xcoord = 27, ycoord = 28  // extended for GUI
}

public enum LinkParams: Int32 {
    case diameter = 0, length, roughness, minorloss, initstatus, initsetting
    case kbulk, kwall, flow, velocity, headloss, status, setting, energy
    case linkqual, leakcoeff1, leakcoeff2, leakage
}

public enum ElementCounts: Int32 {
    case nodeCount = 0, tankCount, linkCount, patCount, curveCount, controlCount, ruleCount, resvCount
}

public enum NodeTypes: Int32 {
    case junction = 0, reservoir, tank
}

public enum LinkTypes: Int32 {
    case cvpipe = 0, pipe, pump, prv, psv, pbv, fcv, tcv, gpv
}

public enum OptionParams: Int32 {
    case trials = 0, accuracy, qualTol, emitExpon, demandMult
    case hydTol, minPressure, maxPressure, pressExpon, netLeakCoeff1, netLeakCoeff2
}

public enum TimeParams: Int32 {
    case duration = 0, hydStep, qualStep, patternStep, patternStart
    case reportStep, reportStart, ruleStep, statistic, periods, startDate
}

public struct EpanetErrorContext: Equatable {
    public let api: String
    public let objectType: String?
    public let objectIndex: Int?
    public let objectID: String?
    public let parameter: String?

    public init(
        api: String,
        objectType: String? = nil,
        objectIndex: Int? = nil,
        objectID: String? = nil,
        parameter: String? = nil
    ) {
        self.api = api
        self.objectType = objectType
        self.objectIndex = objectIndex
        self.objectID = objectID
        self.parameter = parameter
    }
}

// MARK: - Project wrapper

public final class EpanetProject {
    private var handle: UnsafeMutableRawPointer?

    private func throwIfError(
        _ err: Int32,
        api: String,
        objectType: String? = nil,
        objectIndex: Int? = nil,
        objectID: String? = nil,
        parameter: String? = nil
    ) throws {
        if err == 0 { return }
        throw EpanetError.apiContext(
            code: err,
            context: EpanetErrorContext(
                api: api,
                objectType: objectType,
                objectIndex: objectIndex,
                objectID: objectID,
                parameter: parameter
            )
        )
    }

    public init() {
        handle = _EN_createProject()
    }

    deinit {
        if let h = handle {
            _ = _EN_clearProject(h)
            _ = _EN_deleteProject(h)
        }
    }

    public func load(path: String) throws {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        let err = path.withCString { _EN_loadProject($0, h) }
        if err != 0 {
            var buf = [CChar](repeating: 0, count: 8192)
            _ = buf.withUnsafeMutableBufferPointer { ptr in
                _EN_getMessageLog(ptr.baseAddress, Int32(ptr.count), h)
            }
            let log = String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
            if !log.isEmpty {
                throw EpanetError.apiErrorWithInputDetail(code: err, inputDetail: log)
            }
            throw EpanetError.apiError(err)
        }
    }

    public func save(path: String) throws {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        let err = path.withCString { _EN_saveProject($0, h) }
        if err != 0 { throw EpanetError.apiError(err) }
    }

    /// Sets Noria export footer (`exported by noria (version)`) and per-section / default INP float precision before `save(path:)`.
    public func configureNoriaInpExport(version: String, sectionFractionDigits: [String: Int], defaultFractionDigits: Int) throws {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        try throwIfError(
            version.withCString { _EN_setNoriaExportVersion($0, h) },
            api: "EN_setNoriaExportVersion"
        )
        let def = min(max(defaultFractionDigits, 0), 15)
        try throwIfError(
            _EN_setInpWriterSectionFractionDigits(nil, Int32(def), h),
            api: "EN_setInpWriterSectionFractionDigits"
        )
        for (sec, digits) in sectionFractionDigits {
            let d = min(max(digits, 0), 15)
            try throwIfError(
                sec.withCString { _EN_setInpWriterSectionFractionDigits($0, Int32(d), h) },
                api: "EN_setInpWriterSectionFractionDigits"
            )
        }
    }

    public func initSolver(initFlows: Bool = false) throws {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        let err = _EN_initSolver(initFlows ? 1 : 0, h)
        if err != 0 { throw EpanetError.apiError(err) }
    }

    public func runSolver(time: inout Int32) throws {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        let err = _EN_runSolver(&time, h)
        if err != 0 { throw EpanetError.apiError(err) }
    }

    public func advanceSolver(dt: inout Int32) throws {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        let err = _EN_advanceSolver(&dt, h)
        if err != 0 { throw EpanetError.apiError(err) }
    }

    public func nodeCount() throws -> Int {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var count: Int32 = 0
        let err = _EN_getCount(ElementCounts.nodeCount.rawValue, &count, h)
        if err != 0 { throw EpanetError.apiError(err) }
        return Int(count)
    }

    public func linkCount() throws -> Int {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var count: Int32 = 0
        let err = _EN_getCount(ElementCounts.linkCount.rawValue, &count, h)
        if err != 0 { throw EpanetError.apiError(err) }
        return Int(count)
    }

    /// `[PATTERNS]` 条目数。
    public func patternCount() throws -> Int {
        try elementCount(.patCount)
    }

    /// `[CURVES]` 条目数。
    public func curveCount() throws -> Int {
        try elementCount(.curveCount)
    }

    /// 简单控制（`[CONTROLS]`）条目数。
    public func controlCount() throws -> Int {
        try elementCount(.controlCount)
    }

    private func elementCount(_ type: ElementCounts) throws -> Int {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var count: Int32 = 0
        let err = _EN_getCount(type.rawValue, &count, h)
        if err != 0 { throw EpanetError.apiError(err) }
        return Int(count)
    }

    public func getNodeId(index: Int) throws -> String {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var buf = [CChar](repeating: 0, count: 256)
        let err = buf.withUnsafeMutableBufferPointer { ptr in
            _EN_getNodeId(Int32(index), ptr.baseAddress, h)
        }
        if err != 0 { throw EpanetError.apiError(err) }
        return String(cString: buf)
    }

    public func getNodeIndex(id: String) throws -> Int {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var index: Int32 = 0
        let err = id.withCString { _EN_getNodeIndex($0, &index, h) }
        if err != 0 { throw EpanetError.apiError(err) }
        return Int(index)
    }

    public func getLinkId(index: Int) throws -> String {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var buf = [CChar](repeating: 0, count: 256)
        let err = buf.withUnsafeMutableBufferPointer { ptr in
            _EN_getLinkId(Int32(index), ptr.baseAddress, h)
        }
        if err != 0 { throw EpanetError.apiError(err) }
        return String(cString: buf)
    }

    public func getLinkIndex(id: String) throws -> Int {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var index: Int32 = 0
        let err = id.withCString { _EN_getLinkIndex($0, &index, h) }
        if err != 0 { throw EpanetError.apiError(err) }
        return Int(index)
    }

    public func getNodeValue(nodeIndex: Int, param: NodeParams) throws -> Double {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var value: Double = 0
        let err = _EN_getNodeValue(Int32(nodeIndex), param.rawValue, &value, h)
        try throwIfError(
            err,
            api: "EN_getNodeValue",
            objectType: "节点",
            objectIndex: nodeIndex,
            parameter: String(describing: param)
        )
        return value
    }

    public func getNodeCoords(nodeIndex: Int) throws -> (x: Double, y: Double) {
        let x = try getNodeValue(nodeIndex: nodeIndex, param: .xcoord)
        let y = try getNodeValue(nodeIndex: nodeIndex, param: .ycoord)
        return (x, y)
    }

    public func getLinkNodes(linkIndex: Int) throws -> (node1: Int, node2: Int) {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var n1: Int32 = 0, n2: Int32 = 0
        let err = _EN_getLinkNodes(Int32(linkIndex), &n1, &n2, h)
        try throwIfError(
            err,
            api: "EN_getLinkNodes",
            objectType: "管段",
            objectIndex: linkIndex
        )
        return (Int(n1), Int(n2))
    }

    public func getLinkValue(linkIndex: Int, param: LinkParams) throws -> Double {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var value: Double = 0
        let err = _EN_getLinkValue(Int32(linkIndex), param.rawValue, &value, h)
        try throwIfError(
            err,
            api: "EN_getLinkValue",
            objectType: "管段",
            objectIndex: linkIndex,
            parameter: String(describing: param)
        )
        return value
    }

    public func getNodeType(index: Int) throws -> NodeTypes {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var t: Int32 = 0
        let err = _EN_getNodeType(Int32(index), &t, h)
        if err != 0 { throw EpanetError.apiError(err) }
        return NodeTypes(rawValue: t) ?? .junction
    }

    public func getLinkType(index: Int) throws -> LinkTypes {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var t: Int32 = 0
        let err = _EN_getLinkType(Int32(index), &t, h)
        if err != 0 { throw EpanetError.apiError(err) }
        return LinkTypes(rawValue: t) ?? .pipe
    }

    public func getOption(param: OptionParams) throws -> Double {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var value: Double = 0
        let err = _EN_getOption(param.rawValue, &value, h)
        if err != 0 { throw EpanetError.apiError(err) }
        return value
    }

    public func setOption(param: OptionParams, value: Double) throws {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        let err = _EN_setOption(param.rawValue, value, h)
        if err != 0 { throw EpanetError.apiError(err) }
    }

    public func getTimeParam(param: TimeParams) throws -> Int {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var value: CLong = 0
        let err = _EN_getTimeParam(param.rawValue, &value, h)
        if err != 0 { throw EpanetError.apiError(err) }
        return Int(value)
    }

    public func setTimeParam(param: TimeParams, value: Int) throws {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        let err = _EN_setTimeParam(param.rawValue, Int32(value), h)
        if err != 0 { throw EpanetError.apiError(err) }
    }

    public func getFlowUnits() throws -> Int {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var units: Int32 = 0
        let err = _EN_getFlowUnits(&units, h)
        if err != 0 { throw EpanetError.apiError(err) }
        return Int(units)
    }

    public static func describeError(code: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 512)
        let rc = buffer.withUnsafeMutableBufferPointer { ptr in
            _EN_getError(code, ptr.baseAddress, Int32(ptr.count), nil)
        }
        if rc != 0 { return "未知错误" }
        let message = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "未知错误" : message
    }

    public func describeError(code: Int32) -> String {
        guard let h = handle else { return Self.describeError(code: code) }
        var buffer = [CChar](repeating: 0, count: 512)
        let rc = buffer.withUnsafeMutableBufferPointer { ptr in
            _EN_getError(code, ptr.baseAddress, Int32(ptr.count), h)
        }
        if rc != 0 { return "未知错误" }
        let message = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "未知错误" : message
    }

    public func setNodeValue(nodeIndex: Int, param: NodeParams, value: Double) throws {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        let err = _EN_setNodeValue(Int32(nodeIndex), param.rawValue, value, h)
        try throwIfError(
            err,
            api: "EN_setNodeValue",
            objectType: "节点",
            objectIndex: nodeIndex,
            parameter: String(describing: param)
        )
    }

    public func setLinkValue(linkIndex: Int, param: LinkParams, value: Double) throws {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        let err = _EN_setLinkValue(Int32(linkIndex), param.rawValue, value, h)
        try throwIfError(
            err,
            api: "EN_setLinkValue",
            objectType: "管段",
            objectIndex: linkIndex,
            parameter: String(describing: param)
        )
    }

    @discardableResult
    public func createNode(id: String, type: NodeTypes) throws -> Int {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        let err = id.withCString { _EN_createNode($0, type.rawValue, h) }
        try throwIfError(
            err,
            api: "EN_createNode",
            objectType: "节点",
            objectID: id,
            parameter: String(describing: type)
        )
        return try getNodeIndex(id: id)
    }

    @discardableResult
    public func createLink(id: String, type: LinkTypes, fromNodeIndex: Int, toNodeIndex: Int) throws -> Int {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        let err = id.withCString {
            _EN_createLink($0, type.rawValue, Int32(fromNodeIndex), Int32(toNodeIndex), h)
        }
        try throwIfError(
            err,
            api: "EN_createLink",
            objectType: "管段",
            objectID: id,
            parameter: "\(type) (\(fromNodeIndex)->\(toNodeIndex))"
        )
        return try getLinkIndex(id: id)
    }

    public func deleteNode(id: String) throws {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        let err = id.withCString { _EN_deleteNode($0, h) }
        try throwIfError(
            err,
            api: "EN_deleteNode",
            objectType: "节点",
            objectID: id,
            parameter: "删除前需无连接管段"
        )
    }

    public func deleteLink(id: String) throws {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        let err = id.withCString { _EN_deleteLink($0, h) }
        try throwIfError(
            err,
            api: "EN_deleteLink",
            objectType: "管段",
            objectID: id
        )
    }

    /// Bulk-read all node results directly into caller-provided `[Float]` arrays.
    public func getNodeResultsBulkF(pressure: inout [Float], head: inout [Float], demand: inout [Float], tankLevel: inout [Float]) {
        guard let h = handle else { return }
        pressure.withUnsafeMutableBufferPointer { pBuf in
            head.withUnsafeMutableBufferPointer { hBuf in
                demand.withUnsafeMutableBufferPointer { dBuf in
                    tankLevel.withUnsafeMutableBufferPointer { tBuf in
                        _ = _EN_getNodeResultsBulkF(pBuf.baseAddress, hBuf.baseAddress, dBuf.baseAddress, tBuf.baseAddress, h)
                    }
                }
            }
        }
    }

    /// Bulk-read all link results directly into caller-provided `[Float]` arrays.
    public func getLinkResultsBulkF(flow: inout [Float], velocity: inout [Float], headloss: inout [Float], status: inout [Float]) {
        guard let h = handle else { return }
        flow.withUnsafeMutableBufferPointer { fBuf in
            velocity.withUnsafeMutableBufferPointer { vBuf in
                headloss.withUnsafeMutableBufferPointer { hBuf in
                    status.withUnsafeMutableBufferPointer { sBuf in
                        _ = _EN_getLinkResultsBulkF(fBuf.baseAddress, vBuf.baseAddress, hBuf.baseAddress, sBuf.baseAddress, h)
                    }
                }
            }
        }
    }
}

// MARK: - One-shot run

public func runEpanet(inpPath: String, rptPath: String, outPath: String) throws {
    let err = inpPath.withCString { inp in
        rptPath.withCString { rpt in
            outPath.withCString { out in
                _EN_runEpanet(inp, rpt, out)
            }
        }
    }
    if err != 0 { throw EpanetError.apiError(err) }
}

// MARK: - Error

public enum EpanetError: Error, LocalizedError {
    case projectNotCreated
    case apiError(Int32)
    /// Load/read failed; `inputDetail` is EPANET’s parser log (problem lines), when available.
    case apiErrorWithInputDetail(code: Int32, inputDetail: String)
    case apiContext(code: Int32, context: EpanetErrorContext)

    public var code: Int32? {
        switch self {
        case .projectNotCreated:
            return nil
        case .apiError(let code):
            return code
        case .apiErrorWithInputDetail(let code, _):
            return code
        case .apiContext(let code, _):
            return code
        }
    }

    public var context: EpanetErrorContext? {
        switch self {
        case .apiContext(_, let context):
            return context
        default:
            return nil
        }
    }

    public var errorDescription: String? {
        switch self {
        case .projectNotCreated:
            return "EPANET 项目未创建"
        case .apiError(let code):
            return "EPANET 错误 \(code): \(EpanetProject.describeError(code: code))"
        case .apiErrorWithInputDetail(let code, let inputDetail):
            let base = "EPANET 错误 \(code): \(EpanetProject.describeError(code: code))"
            return inputDetail.isEmpty ? base : "\(base)\n\(inputDetail)"
        case .apiContext(let code, let context):
            let base = "EPANET 错误 \(code): \(EpanetProject.describeError(code: code))"
            let objectText: String
            if let objectType = context.objectType {
                if let objectID = context.objectID {
                    objectText = "\(objectType)(ID=\(objectID))"
                } else if let objectIndex = context.objectIndex {
                    objectText = "\(objectType)(索引=\(objectIndex))"
                } else {
                    objectText = objectType
                }
            } else {
                objectText = "未指定对象"
            }
            let parameterText = context.parameter.map { ", 参数=\($0)" } ?? ""
            return "\(base) [接口=\(context.api), 对象=\(objectText)\(parameterText)]"
        }
    }
}
