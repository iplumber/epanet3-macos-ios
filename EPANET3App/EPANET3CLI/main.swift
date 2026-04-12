/* EPANET 3 CLI - Test harness for engine + Swift bridge
 * Usage: EPANET3CLI <inp_path> [rpt_path] [out_path]
 * Default: report and output to temp files
 */

import Foundation
import EPANET3Bridge

let args = CommandLine.arguments

if args.count >= 3 && args[1] == "--self-check-errors" {
    let inpPath = args[2]
    guard FileManager.default.fileExists(atPath: inpPath) else {
        print("Error: Input file not found: \(inpPath)")
        exit(1)
    }
    print("EPANET 3 Error Usability Self-Check")
    print("Input: \(inpPath)")
    do {
        let project = EpanetProject()
        try project.load(path: inpPath)

        // 1) Duplicate node ID
        do {
            _ = try project.createNode(id: "11", type: .junction)
            print("[FAIL] duplicate node ID was accepted unexpectedly")
        } catch let e as EpanetError {
            print("[OK] duplicate node ID -> \(e.localizedDescription)")
        }

        // 2) Invalid link parameter (negative length)
        do {
            try project.setLinkValue(linkIndex: 1, param: .length, value: -1)
            print("[FAIL] negative link length was accepted unexpectedly")
        } catch let e as EpanetError {
            print("[OK] invalid link length -> \(e.localizedDescription)")
        }

        // 3) Delete connected node
        do {
            try project.deleteNode(id: "11")
            print("[FAIL] connected node deletion was accepted unexpectedly")
        } catch let e as EpanetError {
            print("[OK] delete connected node -> \(e.localizedDescription)")
        }

        print("Self-check completed.")
        exit(0)
    } catch {
        print("Self-check setup failed: \(error)")
        exit(1)
    }
}

/// Load .inp, save via ProjectWriter (EPANET 2–style [OPTIONS]), then run — verifies Save As round-trip.
if args.count >= 3 && args[1] == "--round-trip-save-run" {
    let inpPath = args[2]
    guard FileManager.default.fileExists(atPath: inpPath) else {
        print("Error: Input file not found: \(inpPath)")
        exit(1)
    }
    let savedName = "epanet3_roundtrip_\(UUID().uuidString).inp"
    let savedPath = FileManager.default.temporaryDirectory.appendingPathComponent(savedName).path
    let rptPath = FileManager.default.temporaryDirectory.appendingPathComponent("epanet3_roundtrip_rpt.txt").path
    let outPath = FileManager.default.temporaryDirectory.appendingPathComponent("epanet3_roundtrip_out.bin").path
    do {
        let project = EpanetProject()
        try project.load(path: inpPath)
        try project.save(path: savedPath)
        print("Round-trip save: \(savedPath)")
        try runEpanet(inpPath: savedPath, rptPath: rptPath, outPath: outPath)
        print("Round-trip run completed successfully (same path EPANET 3 uses after Save As).")
        exit(0)
    } catch {
        print("Round-trip failed: \(error)")
        exit(1)
    }
}

guard args.count >= 2 else {
    print("Usage: EPANET3CLI <inp_path> [rpt_path] [out_path]")
    print("   or: EPANET3CLI --self-check-errors <inp_path>")
    print("   or: EPANET3CLI --round-trip-save-run <inp_path>")
    exit(1)
}

let inpPath = args[1]
let rptPath = args.count >= 3 ? args[2] : (FileManager.default.temporaryDirectory.path + "/epanet3_rpt.txt")
let outPath = args.count >= 4 ? args[3] : (FileManager.default.temporaryDirectory.path + "/epanet3_out.bin")

guard FileManager.default.fileExists(atPath: inpPath) else {
    print("Error: Input file not found: \(inpPath)")
    exit(1)
}

print("EPANET 3 Swift Bridge Test")
print("Input:  \(inpPath)")
print("Report: \(rptPath)")
print("Output: \(outPath)")
print("")

do {
    // Option 1: One-shot run (same as run-epanet3)
    print("--- One-shot run (EN_runEpanet) ---")
    try runEpanet(inpPath: inpPath, rptPath: rptPath, outPath: outPath)
    print("One-shot run completed successfully.\n")

    // Option 2: Project API (load, init, step)
    print("--- Project API (load, initSolver, runSolver loop) ---")
    let project = EpanetProject()
    try project.load(path: inpPath)
    let nodeCount = try project.nodeCount()
    let linkCount = try project.linkCount()
    print("Loaded: \(nodeCount) nodes, \(linkCount) links")

    try project.initSolver(initFlows: false)
    var t: Int32 = 0
    var dt: Int32 = 0
    var stepCount = 0
    repeat {
        try project.runSolver(time: &t)
        dt = 0
        try project.advanceSolver(dt: &dt)
        stepCount += 1
        if stepCount <= 3 || dt == 0 {
            print("  Step \(stepCount): t=\(t), dt=\(dt)")
        } else if stepCount == 4 {
            print("  ...")
        }
    } while dt > 0

    // Sample a node and link
    if nodeCount > 0 {
        let id = try project.getNodeId(index: 1)
        let elev = try project.getNodeValue(nodeIndex: 1, param: .elevation)
        let pressure = try project.getNodeValue(nodeIndex: 1, param: .pressure)
        print("Node 1: id=\(id), elev=\(elev), pressure=\(pressure)")
    }
    if linkCount > 0 {
        let nodes = try project.getLinkNodes(linkIndex: 1)
        let flow = try project.getLinkValue(linkIndex: 1, param: .flow)
        print("Link 1: nodes \(nodes.node1)-\(nodes.node2), flow=\(flow)")

    }

    print("\nProject API test completed successfully.")
} catch let EpanetError.apiErrorWithInputDetail(code, log) {
    let detail = EpanetProject.describeError(code: code)
    print("EPANET API error: [\(code)] \(detail)\n\(log)")
    exit(Int32(truncatingIfNeeded: code))
} catch EpanetError.apiError(let code) {
    let detail = EpanetProject.describeError(code: code)
    print("EPANET API error: [\(code)] \(detail)")
    exit(Int32(truncatingIfNeeded: code))
} catch EpanetError.apiContext(let code, let context) {
    let detail = EpanetProject.describeError(code: code)
    let object = context.objectType ?? "未指定对象"
    let objectRef: String
    if let id = context.objectID {
        objectRef = "\(object)(ID=\(id))"
    } else if let index = context.objectIndex {
        objectRef = "\(object)(索引=\(index))"
    } else {
        objectRef = object
    }
    let param = context.parameter ?? "-"
    print("EPANET API error: [\(code)] \(detail) | 接口=\(context.api) | 对象=\(objectRef) | 参数=\(param)")
    exit(Int32(truncatingIfNeeded: code))
} catch {
    print("Error: \(error)")
    exit(1)
}
