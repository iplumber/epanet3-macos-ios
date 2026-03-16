import SwiftUI
import EPANET3Bridge
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 与 Flow Units 联动的属性单位标签：GPM/CFS/MGD/IMGD/AFD → 美制；LPS/LPM/MLD/CMH/CMD → 公制。
/// 美制/公制由 inp 的 Flow Units 决定；未解析到时与引擎默认一致按 GPM（美制）。
private struct PropertyUnits {
    let flowUnit: String
    let flowUnitDisplay: String
    let isUS: Bool
    let elevation: String
    let head: String
    let pressure: String
    let velocity: String
    let length: String
    let diameter: String

    init(flowUnits: String?) {
        let u = (flowUnits ?? "GPM").uppercased().trimmingCharacters(in: .whitespaces)
        flowUnit = u.isEmpty ? "GPM" : u
        isUS = InpOptionsParser.isUSCustomary(flowUnits: flowUnit)
        flowUnitDisplay = Self.flowUnitDisplayName(flowUnit)
        if isUS {
            elevation = "高程 (ft)"
            head = "水头 (ft)"
            pressure = "压力 (psi)"
            velocity = "流速 (ft/s)"
            length = "长度 (ft)"
            diameter = "管径 (in)"
        } else {
            elevation = "高程 (m)"
            head = "水头 (m)"
            pressure = "压力 (m)"
            velocity = "流速 (m/s)"
            length = "长度 (m)"
            diameter = "管径 (mm)"
        }
    }

    /// 需水量/管段流量的显示单位：公制 CMH→m³/h，CMD→m³/d 等；美制保持 GPM 等。
    private static func flowUnitDisplayName(_ unit: String) -> String {
        switch unit.uppercased() {
        case "CMH": return "m³/h"
        case "CMD": return "m³/d"
        case "LPS": return "L/s"
        case "LPM": return "L/min"
        case "MLD": return "ML/d"
        default: return unit.uppercased()
        }
    }
}

struct PropertyPanelView: View {
    @ObservedObject var appState: AppState
    let selectedNodeIndex: Int?
    let selectedLinkIndex: Int?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("属性")
                    .font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            if appState.project != nil {
                Text("单位: \(units.flowUnitDisplay) (\(units.isUS ? "美制" : "公制"))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
            if let proj = appState.project {
                if let i = selectedNodeIndex, i >= 0 {
                    PropertyTableView(rows: nodeRows(project: proj, nodeIndex: i))
                } else if let i = selectedLinkIndex, i >= 0 {
                    PropertyTableView(rows: linkRows(project: proj, linkIndex: i))
                } else {
                    Text("未选中对象")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    PropertyTableView(rows: [])
                }
            } else {
                Text("仅显示模式，无属性数据")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            Spacer(minLength: 0)
        }
        .background(platformWindowBackgroundColor)
        .overlay(Rectangle().frame(width: 1).foregroundColor(.secondary.opacity(0.3)), alignment: .leading)
    }

    private var units: PropertyUnits {
        PropertyUnits(flowUnits: appState.inpFlowUnits)
    }
    private var platformWindowBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }

    private func nodeRows(project: EpanetProject, nodeIndex: Int) -> [(String, String)] {
        var rows: [(String, String)] = []
        let u = units
        do {
            rows.append(("ID", try project.getNodeId(index: nodeIndex)))
            rows.append((u.elevation, String(format: "%.2f", try project.getNodeValue(nodeIndex: nodeIndex, param: .elevation))))
            rows.append((u.head, String(format: "%.2f", try project.getNodeValue(nodeIndex: nodeIndex, param: .head))))
            rows.append((u.pressure, String(format: "%.2f", try project.getNodeValue(nodeIndex: nodeIndex, param: .pressure))))
            rows.append(("需水量 (\(u.flowUnitDisplay))", String(format: "%.4f", try project.getNodeValue(nodeIndex: nodeIndex, param: .actualdemand))))
        } catch {}
        return rows
    }

    private func linkRows(project: EpanetProject, linkIndex: Int) -> [(String, String)] {
        var rows: [(String, String)] = []
        let u = units
        do {
            rows.append(("ID", try project.getLinkId(index: linkIndex)))
            let (n1, n2) = try project.getLinkNodes(linkIndex: linkIndex)
            rows.append(("节点", "\(n1 + 1) → \(n2 + 1)"))
            rows.append(("流量 (\(u.flowUnitDisplay))", String(format: "%.4f", try project.getLinkValue(linkIndex: linkIndex, param: .flow))))
            rows.append((u.velocity, String(format: "%.4f", try project.getLinkValue(linkIndex: linkIndex, param: .velocity))))
            rows.append((u.length, String(format: "%.2f", try project.getLinkValue(linkIndex: linkIndex, param: .length))))
            rows.append((u.diameter, String(format: "%.2f", try project.getLinkValue(linkIndex: linkIndex, param: .diameter))))
        } catch {}
        return rows
    }
}

private struct PropertyTableView: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, pair in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(pair.0)
                        .foregroundColor(.secondary)
                        .frame(width: 72, alignment: .leading)
                    Text(pair.1)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                if idx < rows.count - 1 {
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
        .padding(.top, 4)
    }
}
