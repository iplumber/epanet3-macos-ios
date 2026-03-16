/* 仅显示用 .inp 解析：当 EN_loadProject 返回 200 时，只解析节点/管段/坐标用于显示 */
import Foundation
import EPANET3Renderer

struct InpDisplayParser {
    static func parse(path: String) throws -> NetworkScene {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        var nodeIds: [String] = []
        var linkList: [(id: String, node1: String, node2: String)] = []
        var coords: [String: (x: Float, y: Float)] = [:]

        let lines = content.components(separatedBy: .newlines)
        var section = ""

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") {
                let upper = line.uppercased()
                if upper.hasPrefix("[JUNCTION") { section = "JUNCTION" }
                else if upper.hasPrefix("[RESERVOIR") { section = "RESERVOIR" }
                else if upper.hasPrefix("[TANK") { section = "TANK" }
                else if upper.hasPrefix("[PIPE") { section = "PIPE" }
                else if upper.hasPrefix("[PUMP") { section = "PUMP" }
                else if upper.hasPrefix("[VALVE") { section = "VALVE" }
                else if upper.hasPrefix("[COORD") { section = "COORD" }
                else if upper.hasPrefix("[VERTICES") { section = "VERTICES" }
                else if upper.hasPrefix("[END") { break }
                else { section = "" }
                continue
            }

            let tokens = line.split(whereSeparator: { $0.isWhitespace })
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if tokens.isEmpty { continue }

            switch section {
            case "JUNCTION":
                if tokens.count >= 1 { nodeIds.append(tokens[0]) }
            case "RESERVOIR":
                if tokens.count >= 1 { nodeIds.append(tokens[0]) }
            case "TANK":
                if tokens.count >= 1 { nodeIds.append(tokens[0]) }
            case "PIPE":
                if tokens.count >= 3 { linkList.append((tokens[0], tokens[1], tokens[2])) }
            case "PUMP":
                if tokens.count >= 3 { linkList.append((tokens[0], tokens[1], tokens[2])) }
            case "VALVE":
                if tokens.count >= 3 { linkList.append((tokens[0], tokens[1], tokens[2])) }
            case "COORD":
                if tokens.count >= 3, let x = Float(tokens[1]), let y = Float(tokens[2]) {
                    coords[tokens[0]] = (x, y)
                }
            default:
                break
            }
        }

        let idToIndex = Dictionary(uniqueKeysWithValues: nodeIds.enumerated().map { ($0.element, $0.offset) })
        var nodes: [NodeVertex] = []
        for (i, id) in nodeIds.enumerated() {
            if let c = coords[id] {
                nodes.append(NodeVertex(x: c.x, y: c.y, nodeIndex: i))
            }
        }

        var links: [LinkVertex] = []
        for (idx, link) in linkList.enumerated() {
            guard idToIndex[link.node1] != nil, idToIndex[link.node2] != nil else { continue }
            let c1 = coords[link.node1] ?? (Float(0), Float(0))
            let c2 = coords[link.node2] ?? (Float(0), Float(0))
            links.append(LinkVertex(x1: c1.x, y1: c1.y, x2: c2.x, y2: c2.y, linkIndex: idx))
        }

        if nodes.isEmpty && links.isEmpty { throw NSError(domain: "InpDisplayParser", code: 200, userInfo: [NSLocalizedDescriptionKey: "无可显示节点或管段"]) }
        if nodes.isEmpty { nodes = [NodeVertex(x: 0, y: 0, nodeIndex: 0)] }
        return NetworkScene(nodes: nodes, links: links)
    }
}
