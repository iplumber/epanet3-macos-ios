/* 在保留原始 .inp 文本结构的前提下写回修改；支持按字段增量补丁（只改用户动过的 token）。 */
import Foundation
import EPANET3Bridge

// MARK: - Delta types（与 AppState / 属性面板共享）

/// `[PIPES]` 行上要写回文件的字段子集。
enum InpLinkPatchField: Hashable, Sendable {
    case fromNodeToNode
    case length
    case diameter
    case roughness
}

/// 节点在 `[JUNCTIONS]` / `[COORDINATES]` 中的待写回字段。
enum InpNodePatchField: Hashable, Sendable {
    case elevation
    case baseDemand
    case xCoord
    case yCoord
}

/// 自上次成功落盘以来，需要在 .inp 快照上应用的修改集合。
struct InpSaveDelta: Equatable, Sendable {
    private(set) var linkFieldMasks: [String: Set<InpLinkPatchField>] = [:]
    private(set) var nodeFieldMasks: [String: Set<InpNodePatchField>] = [:]
    /// 引擎对 `EN_BASEDEMAND` 读取不完整时，用属性面板写入的数值写回 `[JUNCTIONS]`。
    private(set) var nodeDemandById: [String: Double] = [:]

    var isEmpty: Bool {
        !linkFieldMasks.contains { !$0.value.isEmpty } && !nodeFieldMasks.contains { !$0.value.isEmpty }
    }

    mutating func record(linkID: String, fields: Set<InpLinkPatchField>) {
        guard !fields.isEmpty else { return }
        linkFieldMasks[linkID, default: []].formUnion(fields)
    }

    mutating func record(nodeID: String, fields: Set<InpNodePatchField>, baseDemandForFile: Double? = nil) {
        guard !fields.isEmpty else { return }
        nodeFieldMasks[nodeID, default: []].formUnion(fields)
        if fields.contains(.baseDemand), let v = baseDemandForFile {
            nodeDemandById[nodeID] = v
        }
    }

    mutating func clear() {
        linkFieldMasks.removeAll()
        nodeFieldMasks.removeAll()
        nodeDemandById.removeAll()
    }
}

// MARK: - Saver

enum InpPreservingSaver {
    /// 仅对 `delta` 中记录的管段/节点字段替换对应 token，其余字符与行完全不变。
    static func applyPatches(original: String, project: EpanetProject, delta: InpSaveDelta) -> String {
        let newline = detectNewline(original)
        let lines = splitLines(original)
        var section = ""
        var out: [String] = []
        out.reserveCapacity(lines.count)

        for rawLine in lines {
            if let name = sectionHeaderName(rawLine) {
                section = name
                out.append(rawLine)
                continue
            }

            let merged: String?
            switch section {
            case "PIPES":
                merged = patchPipesLineIfNeeded(rawLine, project: project, delta: delta)
            case "JUNCTIONS":
                merged = patchJunctionLineIfNeeded(rawLine, project: project, delta: delta)
            case "COORDINATES":
                merged = patchCoordinateLineIfNeeded(rawLine, project: project, delta: delta)
            default:
                merged = nil
            }

            out.append(merged ?? rawLine)
        }

        return out.joined(separator: newline)
    }

    // MARK: - PIPES

    private static func patchPipesLineIfNeeded(
        _ rawLine: String,
        project: EpanetProject,
        delta: InpSaveDelta
    ) -> String? {
        let (leading, body, trailingComment) = decomposeDataLine(rawLine)
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix(";") { return nil }
        if trimmed.hasPrefix("[") { return nil }

        var tokens = splitTokens(trimmed)
        guard !tokens.isEmpty else { return nil }
        let linkId = tokens[0]
        guard let fields = delta.linkFieldMasks[linkId], !fields.isEmpty else { return nil }

        guard let linkIndex = try? project.getLinkIndex(id: linkId) else { return nil }
        guard let linkType = try? project.getLinkType(index: linkIndex) else { return nil }
        guard linkType == .pipe || linkType == .cvpipe else { return nil }

        var changed = false

        if fields.contains(.fromNodeToNode), tokens.count >= 3 {
            if let nodes = try? project.getLinkNodes(linkIndex: linkIndex),
               let fromName = try? project.getNodeId(index: nodes.node1),
               let toName = try? project.getNodeId(index: nodes.node2)
            {
                if tokens[1] != fromName || tokens[2] != toName {
                    tokens[1] = fromName
                    tokens[2] = toName
                    changed = true
                }
            }
        }

        if fields.contains(.length) || fields.contains(.diameter) || fields.contains(.roughness) {
            guard tokens.count >= 6 else { return nil }
        }

        if fields.contains(.length), let v = try? project.getLinkValue(linkIndex: linkIndex, param: .length) {
            let s = formatInpNumber(v)
            if tokens[3] != s {
                tokens[3] = s
                changed = true
            }
        }
        if fields.contains(.diameter), let v = try? project.getLinkValue(linkIndex: linkIndex, param: .diameter) {
            let s = formatInpNumber(v)
            if tokens[4] != s {
                tokens[4] = s
                changed = true
            }
        }
        if fields.contains(.roughness), let v = try? project.getLinkValue(linkIndex: linkIndex, param: .roughness) {
            let s = formatInpNumber(v)
            if tokens[5] != s {
                tokens[5] = s
                changed = true
            }
        }

        guard changed else { return rawLine }
        let rebuilt = tokens.joined(separator: " ")
        return leading + rebuilt + trailingComment
    }

    // MARK: - JUNCTIONS

    private static func patchJunctionLineIfNeeded(
        _ rawLine: String,
        project: EpanetProject,
        delta: InpSaveDelta
    ) -> String? {
        let (leading, body, trailingComment) = decomposeDataLine(rawLine)
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix(";") { return nil }
        if trimmed.hasPrefix("[") { return nil }

        var tokens = splitTokens(trimmed)
        guard tokens.count >= 2 else { return nil }
        let nodeId = tokens[0]
        guard let fields = delta.nodeFieldMasks[nodeId], !fields.isEmpty else { return nil }
        let needsJunction = fields.contains(.elevation) || fields.contains(.baseDemand)
        guard needsJunction else { return nil }

        guard let nodeIndex = try? project.getNodeIndex(id: nodeId) else { return nil }
        guard let nodeType = try? project.getNodeType(index: nodeIndex), nodeType == .junction else { return nil }

        var changed = false

        if fields.contains(.elevation), let v = try? project.getNodeValue(nodeIndex: nodeIndex, param: .elevation) {
            let s = formatInpNumber(v)
            if tokens[1] != s {
                tokens[1] = s
                changed = true
            }
        }
        if fields.contains(.baseDemand), tokens.count > 2, let v = delta.nodeDemandById[nodeId] {
            let s = formatInpNumber(v)
            if tokens[2] != s {
                tokens[2] = s
                changed = true
            }
        }

        guard changed else { return rawLine }
        let rebuilt = tokens.joined(separator: " ")
        return leading + rebuilt + trailingComment
    }

    // MARK: - COORDINATES

    private static func patchCoordinateLineIfNeeded(
        _ rawLine: String,
        project: EpanetProject,
        delta: InpSaveDelta
    ) -> String? {
        let (leading, body, trailingComment) = decomposeDataLine(rawLine)
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix(";") { return nil }
        if trimmed.hasPrefix("[") { return nil }

        var tokens = splitTokens(trimmed)
        guard tokens.count >= 3 else { return nil }
        let nodeId = tokens[0]
        guard let fields = delta.nodeFieldMasks[nodeId], !fields.isEmpty else { return nil }
        let needsCoord = fields.contains(.xCoord) || fields.contains(.yCoord)
        guard needsCoord else { return nil }

        guard let nodeIndex = try? project.getNodeIndex(id: nodeId) else { return nil }

        var changed = false

        if fields.contains(.xCoord), let v = try? project.getNodeValue(nodeIndex: nodeIndex, param: .xcoord) {
            let s = formatInpNumber(v)
            if tokens[1] != s {
                tokens[1] = s
                changed = true
            }
        }
        if fields.contains(.yCoord), let v = try? project.getNodeValue(nodeIndex: nodeIndex, param: .ycoord) {
            let s = formatInpNumber(v)
            if tokens[2] != s {
                tokens[2] = s
                changed = true
            }
        }

        guard changed else { return rawLine }
        let rebuilt = tokens.joined(separator: " ")
        return leading + rebuilt + trailingComment
    }

    // MARK: - Line / token helpers

    private static func sectionHeaderName(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("["), let end = t.firstIndex(of: "]"), end > t.index(after: t.startIndex) else {
            return nil
        }
        let inner = t[t.index(after: t.startIndex)..<end]
        return inner.uppercased()
    }

    private static func decomposeDataLine(_ line: String) -> (leading: String, body: String, trailingComment: String) {
        let leadingEnd = line.firstIndex { ch in
            !(ch == " " || ch == "\t")
        } ?? line.endIndex
        let leading = String(line[..<leadingEnd])
        let rest = String(line[leadingEnd...])

        if let semi = rest.firstIndex(of: ";") {
            let body = String(rest[..<semi])
            let comment = String(rest[semi...])
            return (leading, body, comment)
        }
        return (leading, rest, "")
    }

    private static func splitTokens(_ dataBody: String) -> [String] {
        dataBody.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func formatInpNumber(_ x: Double) -> String {
        if x.isNaN || x.isInfinite { return "0" }
        return String(format: "%.10g", x)
    }

    private static func detectNewline(_ s: String) -> String {
        s.contains("\r\n") ? "\r\n" : "\n"
    }

    private static func splitLines(_ s: String) -> [String] {
        var lines: [String] = []
        var current = s.startIndex
        while current < s.endIndex {
            let slice = s[current...]
            if let r = slice.range(of: "\r\n") {
                lines.append(String(s[current..<r.lowerBound]))
                current = r.upperBound
            } else if let nl = slice.firstIndex(of: "\n") {
                lines.append(String(s[current..<nl]))
                current = s.index(after: nl)
            } else {
                lines.append(String(s[current...]))
                break
            }
        }
        return lines
    }
}
