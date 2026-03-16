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

// MARK: - Project wrapper

public final class EpanetProject {
    private var handle: UnsafeMutableRawPointer?

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
        if err != 0 { throw EpanetError.apiError(err) }
    }

    public func save(path: String) throws {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        let err = path.withCString { _EN_saveProject($0, h) }
        if err != 0 { throw EpanetError.apiError(err) }
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

    public func getNodeId(index: Int) throws -> String {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var buf = [CChar](repeating: 0, count: 256)
        let err = buf.withUnsafeMutableBufferPointer { ptr in
            _EN_getNodeId(Int32(index), ptr.baseAddress, h)
        }
        if err != 0 { throw EpanetError.apiError(err) }
        return String(cString: buf)
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

    public func getNodeValue(nodeIndex: Int, param: NodeParams) throws -> Double {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var value: Double = 0
        let err = _EN_getNodeValue(Int32(nodeIndex), param.rawValue, &value, h)
        if err != 0 { throw EpanetError.apiError(err) }
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
        if err != 0 { throw EpanetError.apiError(err) }
        return (Int(n1), Int(n2))
    }

    public func getLinkValue(linkIndex: Int, param: LinkParams) throws -> Double {
        guard let h = handle else { throw EpanetError.projectNotCreated }
        var value: Double = 0
        let err = _EN_getLinkValue(Int32(linkIndex), param.rawValue, &value, h)
        if err != 0 { throw EpanetError.apiError(err) }
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

public enum EpanetError: Error {
    case projectNotCreated
    case apiError(Int32)
}
