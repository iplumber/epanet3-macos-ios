import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 节点图例行模型

private struct NodeLegendRow: Identifiable {
    let id: String
    let title: String
    let unit: String?
}

// MARK: - 画布标注图例

/// 绘图区左下角：微型「2 节点 + 1 管段」示意图，标注样式与画布一致，内容为说明性「名称 (单位)」等。
struct CanvasLabelsLegend: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("settings.display.label.node.id") private var nodeId = true
    @AppStorage("settings.display.label.node.elevation") private var nodeElev = false
    @AppStorage("settings.display.label.node.baseDemand") private var nodeDemand = false
    @AppStorage("settings.display.label.node.pressure") private var nodePressure = false
    @AppStorage("settings.display.label.node.head") private var nodeHead = false

    @AppStorage("settings.display.label.link.id") private var linkId = false
    @AppStorage("settings.display.label.link.diameter") private var linkDiameter = false
    @AppStorage("settings.display.label.link.length") private var linkLength = false
    @AppStorage("settings.display.label.link.flow") private var linkFlow = false
    @AppStorage("settings.display.label.link.velocity") private var linkVelocity = false

    @AppStorage(DisplayCanvasNodeColor.junctionKey) private var nodeJunctionPacked = DisplayCanvasNodeColor.defaultJunction
    @AppStorage(DisplayCanvasLinkColor.pipeKey) private var linkPipePacked = DisplayCanvasLinkColor.defaultPipe
    @AppStorage("settings.display.labelsVisible") private var labelsVisible = true

    private var anyOn: Bool {
        nodeId || nodeElev || nodeDemand || nodePressure || nodeHead
            || linkId || linkDiameter || linkLength || linkFlow || linkVelocity
    }

    private var isUS: Bool {
        InpOptionsParser.isUSCustomary(flowUnits: appState.inpFlowUnits)
    }

    private var flowUnitDisplay: String {
        InpOptionsParser.flowUnitDisplaySuffix(code: appState.inpFlowUnits)
    }

    private var linkSeparatorColor: Color {
        Color.primary.opacity(0.48)
    }

    private var textPrimary: Color {
        colorScheme == .dark ? DesignColors.darkText : DesignColors.lightText
    }

    private var borderColor: Color {
        colorScheme == .dark ? DesignColors.darkBorder : DesignColors.lightBorder
    }

    private var nodeDotColor: Color {
        Color(srgbRGB24: nodeJunctionPacked)
    }

    private var pipeColor: Color {
        Color(srgbRGB24: linkPipePacked)
    }

    private static var legendPanelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LegendMetrics.panelCornerRadius, style: .continuous)
    }

    /// 节点旁多行标注（自上而下）；有单位时中文左对齐、单位右对齐，行间同宽。
    private var nodeLegendRows: [NodeLegendRow] {
        var rows: [NodeLegendRow] = []
        if nodeId { rows.append(NodeLegendRow(id: "nid", title: "ID", unit: nil)) }
        if nodeElev { rows.append(NodeLegendRow(id: "elev", title: "高程", unit: isUS ? "(ft)" : "(m)")) }
        if nodeDemand { rows.append(NodeLegendRow(id: "demand", title: "基本需水量", unit: "(\(flowUnitDisplay))")) }
        if nodePressure { rows.append(NodeLegendRow(id: "pres", title: "压力", unit: isUS ? "(psi)" : "(m)")) }
        if nodeHead { rows.append(NodeLegendRow(id: "head", title: "水头", unit: isUS ? "(ft)" : "(m)")) }
        return rows
    }

    private var linkLegendParts: [String] {
        var parts: [String] = []
        if linkId { parts.append("ID") }
        if linkDiameter { parts.append(isUS ? "管径 (in)" : "管径 (mm)") }
        if linkLength { parts.append(isUS ? "管长 (ft)" : "管长 (m)") }
        if linkFlow { parts.append("流量 (\(flowUnitDisplay))") }
        if linkVelocity { parts.append(isUS ? "流速 (ft/s)" : "流速 (m/s)") }
        return parts
    }

    var body: some View {
        if anyOn && labelsVisible {
            miniNetworkLegend
                .padding(LegendMetrics.panelPadding)
                // 宽度随内容收缩，避免为 minWidth 在右侧节点外留白（曾用 268 易显空）。
                .fixedSize(horizontal: true, vertical: false)
                .background { DesignSurfaceBackground() }
                .clipShape(Self.legendPanelShape)
                .overlay(
                    Self.legendPanelShape
                        .stroke(borderColor.opacity(0.9), lineWidth: 1)
                )
                .contentShape(Self.legendPanelShape)
                #if os(macOS)
                .onTapGesture {
                    appState.openMacSettingsDisplayLabelSection()
                }
                .help("打开标注设置")
                #endif
        }
    }

    // MARK: - 微型拓扑

    private var miniNetworkLegend: some View {
        let font = Font.system(size: LegendMetrics.fontSize, weight: .regular)
        let typo = Self.legendCaptionTypography(fontSize: LegendMetrics.fontSize)
        let captionPlain = linkLegendParts.joined(separator: " - ")
        let pipeBase: CGFloat = {
            guard !captionPlain.isEmpty else { return LegendMetrics.minPipeWidth }
            let measured = typo.measureSingleLineWidth(captionPlain)
            return max(LegendMetrics.minPipeWidth, measured + LegendMetrics.captionHorizontalPad)
        }()
        let pipeWidth = pipeBase * LegendMetrics.pipeLengthScale
        let captionAbovePipe = typo.lineHeight * LegendMetrics.captionAbovePipeLineFactor
        let pipeNudge = -(LegendMetrics.dotDiameter - LegendMetrics.pipeLineHeight) / 2
        let titleUnitGap = max(typo.measureSingleLineWidth(" "), 1)

        return HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .trailing, spacing: LegendMetrics.nodeLabelToDotSpacing) {
                nodeLegendLabels(font: font, titleUnitGap: titleUnitGap)
                junctionDot(diameter: LegendMetrics.dotDiameter)
            }
            .fixedSize(horizontal: true, vertical: false)

            pipeLegendColumn(
                pipeWidth: pipeWidth,
                captionAbovePipe: captionAbovePipe,
                pipeNudge: pipeNudge,
                font: font
            )

            junctionDot(diameter: LegendMetrics.dotDiameter)
        }
        .padding(.vertical, LegendMetrics.innerVerticalPad)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("画布标注示意：两节点一管段")
    }

    @ViewBuilder
    private func nodeLegendLabels(font: Font, titleUnitGap: CGFloat) -> some View {
        let rows = nodeLegendRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: LegendMetrics.nodeLegendLineSpacing) {
                ForEach(rows) { row in
                    if let u = row.unit {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(row.title)
                                .font(font)
                                .foregroundColor(textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: true, vertical: true)
                            Spacer(minLength: titleUnitGap)
                            Text(u)
                                .font(font)
                                .foregroundColor(textPrimary)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: true, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(row.title)
                            .font(font)
                            .foregroundColor(textPrimary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private func pipeLegendColumn(
        pipeWidth: CGFloat,
        captionAbovePipe: CGFloat,
        pipeNudge: CGFloat,
        font: Font
    ) -> some View {
        if linkLegendParts.isEmpty {
            Rectangle()
                .fill(pipeColor)
                .frame(width: pipeWidth, height: LegendMetrics.pipeLineHeight)
                .offset(y: pipeNudge)
        } else {
            VStack(alignment: .center, spacing: captionAbovePipe) {
                Self.linkComposedCaption(parts: linkLegendParts, separatorColor: linkSeparatorColor, textColor: textPrimary)
                    .font(font)
                    .multilineTextAlignment(.center)
                    .frame(width: pipeWidth)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle()
                    .fill(pipeColor)
                    .frame(width: pipeWidth, height: LegendMetrics.pipeLineHeight)
                    .offset(y: pipeNudge)
            }
        }
    }

    private func junctionDot(diameter: CGFloat) -> some View {
        Circle()
            .fill(nodeDotColor)
            .frame(width: diameter, height: diameter)
    }

    /// 与图例标注同字号：行高、单行测宽（管段长度与「管顶留白」用）。
    private static func legendCaptionTypography(fontSize: CGFloat) -> (lineHeight: CGFloat, measureSingleLineWidth: (String) -> CGFloat) {
        #if canImport(UIKit)
        let f = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        return (
            f.lineHeight,
            { s in ceil((s as NSString).size(withAttributes: [.font: f]).width) }
        )
        #elseif canImport(AppKit)
        let f = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        let lh = ceil(f.ascender - f.descender + f.leading)
        return (
            lh,
            { s in ceil((s as NSString).size(withAttributes: [.font: f]).width) }
        )
        #else
        return (fontSize * 1.2, { _ in 0 })
        #endif
    }

    private static func linkComposedCaption(parts: [String], separatorColor: Color, textColor: Color) -> Text {
        guard let first = parts.first else { return Text("") }
        let sep = Text(" - ").foregroundColor(separatorColor)
        var t = Text(first).foregroundColor(textColor)
        for p in parts.dropFirst() {
            t = t + sep + Text(p).foregroundColor(textColor)
        }
        return t
    }
}

// MARK: - 尺寸常量（图例专用）

private enum LegendMetrics {
    /// 图例内缘（边距、节点–圆点竖距、管段文案与线间距等）相对原基准再放宽 10%。
    private static let internalInsetScale: CGFloat = 1.1

    static let fontSize: CGFloat = 12
    static let minPipeWidth: CGFloat = 108
    static let pipeLengthScale: CGFloat = 1.1
    static let captionHorizontalPad: CGFloat = 8
    /// 管段文案与管线之间 = 行高 × 该系数（基准 0.8 × internalInsetScale）
    static let captionAbovePipeLineFactor: CGFloat = 0.8 * internalInsetScale
    static let dotDiameter: CGFloat = 6
    static let pipeLineHeight: CGFloat = 1
    static let nodeLabelToDotSpacing: CGFloat = 2 * internalInsetScale
    /// 节点多行标注行距（基准 2pt × internalInsetScale）
    static let nodeLegendLineSpacing: CGFloat = 2 * internalInsetScale
    static let innerVerticalPad: CGFloat = 2 * internalInsetScale
    static let panelPadding: CGFloat = 12 * internalInsetScale
    /// 图例外框四角统一连续圆角半径。
    static let panelCornerRadius: CGFloat = 8
}
