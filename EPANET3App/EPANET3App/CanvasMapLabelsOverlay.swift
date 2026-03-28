import SwiftUI
import EPANET3Renderer
import EPANET3Bridge

/// 管段标注里「 - 」分隔符：正文色降对比（在原先基础上加深约 50%）
private let canvasLinkLabelSeparatorOpacity: Double = 0.48

// MARK: - 与 Metal 画布相同的场景 → 视图像素变换（与 MetalNetworkView.hitTest 一致）

private enum CanvasMapProjection {
    static func sceneToView(
        sceneX: Float,
        sceneY: Float,
        transformBounds: (minX: Float, maxX: Float, minY: Float, maxY: Float),
        scale: CGFloat,
        panX: CGFloat,
        panY: CGFloat,
        viewSize: CGSize
    ) -> CGPoint {
        let w = max(Float(viewSize.width), 1)
        let h = max(Float(viewSize.height), 1)
        let bw = transformBounds.maxX - transformBounds.minX
        let bh = transformBounds.maxY - transformBounds.minY
        let pad: Float = max(bw, bh) * 0.05 + 1
        let baseScale = min(2.0 / (bw + pad * 2), 2.0 / (bh + pad * 2))
        let s = baseScale * Float(scale)
        let (scaleX, scaleY): (Float, Float)
        if w >= h {
            scaleY = s
            scaleX = scaleY * h / w
        } else {
            scaleX = s
            scaleY = scaleX * w / h
        }
        let centerX = (transformBounds.minX + transformBounds.maxX) * 0.5
        let centerY = (transformBounds.minY + transformBounds.maxY) * 0.5
        let offX = Float(-Double(centerX) * Double(scaleX) + Double(panX) * Double(scaleX) * 0.01)
        let offY = Float(-Double(centerY) * Double(scaleY) - Double(panY) * Double(scaleY) * 0.01)
        let ndcX = sceneX * scaleX + offX
        let ndcY = sceneY * scaleY + offY
        let vx = CGFloat((ndcX + 1) * 0.5) * CGFloat(w)
        let vy = CGFloat((1 - ndcY) * 0.5) * CGFloat(h)
        return CGPoint(x: vx, y: vy)
    }

    /// 与 `MetalNetworkView.visibleSceneRect` 一致
    static func visibleSceneRect(
        transformBounds: (minX: Float, maxX: Float, minY: Float, maxY: Float),
        scale: CGFloat,
        panX: CGFloat,
        panY: CGFloat,
        viewSize: CGSize
    ) -> (minX: Float, maxX: Float, minY: Float, maxY: Float) {
        let w = max(Float(viewSize.width), 1)
        let h = max(Float(viewSize.height), 1)
        let bw = transformBounds.maxX - transformBounds.minX
        let bh = transformBounds.maxY - transformBounds.minY
        let pad: Float = max(bw, bh) * 0.05 + 1
        let baseScale = min(2.0 / (bw + pad * 2), 2.0 / (bh + pad * 2))
        let s = baseScale * Float(scale)
        let (scaleX, scaleY): (Float, Float)
        if w >= h {
            scaleY = s
            scaleX = scaleY * h / w
        } else {
            scaleX = s
            scaleY = scaleX * w / h
        }
        let centerX = (transformBounds.minX + transformBounds.maxX) * 0.5
        let centerY = (transformBounds.minY + transformBounds.maxY) * 0.5
        let offX = Float(-Double(centerX) * Double(scaleX) + Double(panX) * Double(scaleX) * 0.01)
        let offY = Float(-Double(centerY) * Double(scaleY) - Double(panY) * Double(scaleY) * 0.01)
        let xLo = (-1 - offX) / scaleX
        let xHi = (1 - offX) / scaleX
        let yLo = (-1 - offY) / scaleY
        let yHi = (1 - offY) / scaleY
        return (Swift.min(xLo, xHi), Swift.max(xLo, xHi), Swift.min(yLo, yHi), Swift.max(yLo, yHi))
    }
}

// MARK: - 标注疏密（屏幕像素空间）

/// 已接受标注之间保持最小像素间距；网格分桶 + 邻域检查，O(n) 量级。
private struct LabelSpatialLimiter {
    let cellSize: CGFloat
    private var buckets: [String: [CGPoint]] = [:]

    init(fontPoints: CGFloat) {
        cellSize = max(10, fontPoints * 0.85)
    }

    mutating func tryAccept(_ p: CGPoint, minSep: CGFloat) -> Bool {
        let cs = cellSize
        let ix = Int(floor(p.x / cs))
        let iy = Int(floor(p.y / cs))
        let rings = max(1, Int(ceil(minSep / cs)) + 1)
        let sep2 = minSep * minSep
        for dix in -rings...rings {
            for diy in -rings...rings {
                let key = "\(ix + dix),\(iy + diy)"
                guard let pts = buckets[key] else { continue }
                for q in pts {
                    let dx = p.x - q.x
                    let dy = p.y - q.y
                    if dx * dx + dy * dy < sep2 { return false }
                }
            }
        }
        let k0 = "\(ix),\(iy)"
        buckets[k0, default: []].append(p)
        return true
    }
}

/// 场景空间稳定排序用（平移视窗不改变优先级，避免标注「飘来飘去」）
private struct PreparedNodeMapLabel {
    let sceneY: Float
    let sceneX: Float
    let nodeIndex: Int
    let viewPt: CGPoint
    let lines: [String]
}

private struct PreparedLinkMapLabel {
    let sceneMidY: Float
    let sceneMidX: Float
    let linkIndex: Int
    let drawPt: CGPoint
    let angle: Double
    let parts: [String]
}

/// 管网画布上的节点 / 管段文字标注（与 Metal 变换一致；不拦截点击；数值不带单位）
struct CanvasMapLabelsOverlay: View {
    let scene: NetworkScene
    /// 与 Metal / ContentView 画布投影一致
    let transformBounds: (minX: Float, maxX: Float, minY: Float, maxY: Float)
    let scale: CGFloat
    let panX: CGFloat
    let panY: CGFloat
    let project: EpanetProject?
    /// 与当前时间轴/结果快照一致时，用于压力/水头/流量/流速标注（非空且下标有效则优先于 `project` 实时读数）。
    let pressureSeries: [Float]?
    let headSeries: [Float]?
    let flowSeries: [Float]?
    let velocitySeries: [Float]?

    init(
        scene: NetworkScene,
        transformBounds: (minX: Float, maxX: Float, minY: Float, maxY: Float),
        scale: CGFloat,
        panX: CGFloat,
        panY: CGFloat,
        project: EpanetProject?,
        pressureSeries: [Float]? = nil,
        headSeries: [Float]? = nil,
        flowSeries: [Float]? = nil,
        velocitySeries: [Float]? = nil
    ) {
        self.scene = scene
        self.transformBounds = transformBounds
        self.scale = scale
        self.panX = panX
        self.panY = panY
        self.project = project
        self.pressureSeries = pressureSeries
        self.headSeries = headSeries
        self.flowSeries = flowSeries
        self.velocitySeries = velocitySeries
    }

    @AppStorage("settings.display.labelFontSize") private var labelFontSize = 10
    @AppStorage("settings.display.label.node.id") private var showNodeId = true
    @AppStorage("settings.display.label.node.elevation") private var showNodeElevation = false
    @AppStorage("settings.display.label.node.baseDemand") private var showNodeBaseDemand = false
    @AppStorage("settings.display.label.node.pressure") private var showNodePressure = false
    @AppStorage("settings.display.label.node.head") private var showNodeHead = false

    @AppStorage("settings.display.label.link.id") private var showLinkId = false
    @AppStorage("settings.display.label.link.diameter") private var showLinkDiameter = false
    @AppStorage("settings.display.label.link.length") private var showLinkLength = false
    @AppStorage("settings.display.label.link.flow") private var showLinkFlow = false
    @AppStorage("settings.display.label.link.velocity") private var showLinkVelocity = false
    @AppStorage("settings.display.labelsVisible") private var labelsVisible = true

    private var anyNodeLabel: Bool {
        showNodeId || showNodeElevation || showNodeBaseDemand || showNodePressure || showNodeHead
    }

    private var anyLinkLabel: Bool {
        showLinkId || showLinkDiameter || showLinkLength || showLinkFlow || showLinkVelocity
    }

    var body: some View {
        Group {
            if labelsVisible {
                Canvas { context, size in
            guard scale > 0.5, size.width > 8, size.height > 8 else { return }
            guard anyNodeLabel || anyLinkLabel else { return }

            let vis = CanvasMapProjection.visibleSceneRect(
                transformBounds: transformBounds,
                scale: scale,
                panX: panX,
                panY: panY,
                viewSize: size
            )
            let span = max(transformBounds.maxX - transformBounds.minX, transformBounds.maxY - transformBounds.minY, 1)
            let margin = span * 0.04

            // 视窗内（与标注裁剪同一 margin）节点数过多：整屏不画标注，避免万级管网仍刷屏 + 省掉候选收集
            var visibleNodeCount = 0
            for n in scene.nodes {
                if n.x >= vis.minX - margin, n.x <= vis.maxX + margin,
                   n.y >= vis.minY - margin, n.y <= vis.maxY + margin {
                    visibleNodeCount += 1
                }
            }
            if visibleNodeCount > 500 {
                return
            }

            // 视窗内节点越多，最小间距越大，并限制最终通过数量的上限（约 400 节点时明显减密）
            let sepScale = 1.0 + CGFloat(min(visibleNodeCount, 500)) / 300.0
            let maxAcceptedLabels = min(
                200,
                max(36, Int((52_000.0 / Double(max(visibleNodeCount, 1))).rounded(.down)))
            )

            let font = Font.system(size: CGFloat(labelFontSize))

            let nodeCap = scene.nodes.count > 8000 ? (scale >= 1.15 ? Int.max : 0) : Int.max
            let linkCap = scene.links.count > 8000 ? (scale >= 1.15 ? Int.max : 0) : Int.max

            var preparedNodes: [PreparedNodeMapLabel] = []
            var preparedLinks: [PreparedLinkMapLabel] = []
            preparedNodes.reserveCapacity(min(scene.nodes.count, 6000))
            preparedLinks.reserveCapacity(min(scene.links.count, 6000))

            if anyNodeLabel, nodeCap > 0 {
                var collected = 0
                for n in scene.nodes {
                    if collected >= 6000 { break }
                    if n.x < vis.minX - margin || n.x > vis.maxX + margin || n.y < vis.minY - margin || n.y > vis.maxY + margin {
                        continue
                    }
                    let lines = nodeLabelLines(nodeIndex: n.nodeIndex)
                    guard !lines.isEmpty else { continue }
                    let pt = CanvasMapProjection.sceneToView(
                        sceneX: n.x, sceneY: n.y,
                        transformBounds: transformBounds, scale: scale, panX: panX, panY: panY,
                        viewSize: size
                    )
                    preparedNodes.append(
                        PreparedNodeMapLabel(sceneY: n.y, sceneX: n.x, nodeIndex: n.nodeIndex, viewPt: pt, lines: lines)
                    )
                    collected += 1
                }
            }

            if anyLinkLabel, linkCap > 0 {
                var collected = 0
                for l in scene.links {
                    if collected >= 6000 { break }
                    let mx = (l.x1 + l.x2) * 0.5
                    let my = (l.y1 + l.y2) * 0.5
                    if mx < vis.minX - margin || mx > vis.maxX + margin || my < vis.minY - margin || my > vis.maxY + margin {
                        continue
                    }
                    let parts = linkLabelParts(linkIndex: l.linkIndex)
                    guard !parts.isEmpty else { continue }
                    let pt = CanvasMapProjection.sceneToView(
                        sceneX: mx, sceneY: my,
                        transformBounds: transformBounds, scale: scale, panX: panX, panY: panY,
                        viewSize: size
                    )
                    let p1 = CanvasMapProjection.sceneToView(
                        sceneX: l.x1, sceneY: l.y1,
                        transformBounds: transformBounds, scale: scale, panX: panX, panY: panY,
                        viewSize: size
                    )
                    let p2 = CanvasMapProjection.sceneToView(
                        sceneX: l.x2, sceneY: l.y2,
                        transformBounds: transformBounds, scale: scale, panX: panX, panY: panY,
                        viewSize: size
                    )
                    let angle = Self.linkLabelRotationRadians(from: p1, to: p2)
                    let normal = Self.linkLabelOutwardNormal(from: p1, to: p2)
                    let textHeightOffset = CGFloat(labelFontSize) * 0.8
                    let drawPt = CGPoint(
                        x: pt.x + normal.x * textHeightOffset,
                        y: pt.y + normal.y * textHeightOffset
                    )
                    preparedLinks.append(
                        PreparedLinkMapLabel(
                            sceneMidY: my,
                            sceneMidX: mx,
                            linkIndex: l.linkIndex,
                            drawPt: drawPt,
                            angle: angle,
                            parts: parts
                        )
                    )
                    collected += 1
                }
            }

            // 场景坐标 + 索引排序：平移/缩放不改变相对优先级（仅进入/离开视窗的对象会变化）
            preparedNodes.sort {
                if $0.sceneY != $1.sceneY { return $0.sceneY < $1.sceneY }
                if $0.sceneX != $1.sceneX { return $0.sceneX < $1.sceneX }
                return $0.nodeIndex < $1.nodeIndex
            }
            preparedLinks.sort {
                if $0.sceneMidY != $1.sceneMidY { return $0.sceneMidY < $1.sceneMidY }
                if $0.sceneMidX != $1.sceneMidX { return $0.sceneMidX < $1.sceneMidX }
                return $0.linkIndex < $1.linkIndex
            }

            let fontPx = CGFloat(labelFontSize)
            var limiter = LabelSpatialLimiter(fontPoints: fontPx)
            var toDrawNodes: [PreparedNodeMapLabel] = []
            var toDrawLinks: [PreparedLinkMapLabel] = []
            toDrawNodes.reserveCapacity(preparedNodes.count)
            toDrawLinks.reserveCapacity(preparedLinks.count)

            var acceptedCount = 0
            // 1) 节点优先占格；2) 管段在剩余额度内占格，且不得与已接受节点（及管段）过近
            for cand in preparedNodes {
                guard acceptedCount < maxAcceptedLabels else { break }
                let anchor = Self.nodeLabelDensityAnchor(pt: cand.viewPt, lineCount: cand.lines.count, fontPx: fontPx)
                let sep = Self.nodeLabelMinSeparation(lineCount: cand.lines.count, fontPx: fontPx) * sepScale
                if limiter.tryAccept(anchor, minSep: sep) {
                    toDrawNodes.append(cand)
                    acceptedCount += 1
                }
            }
            for cand in preparedLinks {
                guard acceptedCount < maxAcceptedLabels else { break }
                let sep = Self.linkLabelMinSeparation(parts: cand.parts, fontPx: fontPx) * sepScale
                if limiter.tryAccept(cand.drawPt, minSep: sep) {
                    toDrawLinks.append(cand)
                    acceptedCount += 1
                }
            }

            // 先画管段、再画节点：与节点重叠时视觉上节点压在上层
            for cand in toDrawLinks {
                let text = Self.linkLabelComposedText(
                    parts: cand.parts,
                    font: font,
                    separatorColor: Color.primary.opacity(canvasLinkLabelSeparatorOpacity)
                )
                let resolved = context.resolve(text)
                context.drawLayer { ctx in
                    ctx.translateBy(x: cand.drawPt.x, y: cand.drawPt.y)
                    ctx.rotate(by: .radians(cand.angle))
                    ctx.draw(resolved, at: .zero, anchor: .center)
                }
            }
            for cand in toDrawNodes {
                let pt = cand.viewPt
                let lines = cand.lines
                let lineStep = fontPx * 1.18
                var lineBaselineY = pt.y - fontPx * 0.35 - 4
                for line in lines.reversed() {
                    let text = Text(line)
                        .font(font)
                        .foregroundColor(.primary)
                    let resolved = context.resolve(text)
                    context.draw(resolved, at: CGPoint(x: pt.x, y: lineBaselineY), anchor: .bottomTrailing)
                    lineBaselineY -= lineStep
                }
            }
        }
                .allowsHitTesting(false)
            }
        }
    }

    /// 节点多行标注块的大致几何中心（用于疏密碰撞，非精确字形框）
    private static func nodeLabelDensityAnchor(pt: CGPoint, lineCount: Int, fontPx: CGFloat) -> CGPoint {
        let lineStep = fontPx * 1.18
        let firstLineY = pt.y - fontPx * 0.35 - 4
        let lastLineY = firstLineY - lineStep * CGFloat(max(0, lineCount - 1))
        let midY = (firstLineY + lastLineY) * 0.5
        let estHalfW = fontPx * 2.5
        return CGPoint(x: pt.x - estHalfW, y: midY)
    }

    /// 节点标注与邻近标注的最小中心距（像素）：随行数略增
    private static func nodeLabelMinSeparation(lineCount: Int, fontPx: CGFloat) -> CGFloat {
        max(24, fontPx * (2.35 + 0.42 * CGFloat(max(0, lineCount - 1))))
    }

    /// 管段单行较长时略增大排斥半径，减少长串与邻标重叠
    private static func linkLabelMinSeparation(parts: [String], fontPx: CGFloat) -> CGFloat {
        let text = parts.joined(separator: " - ")
        let extra = min(CGFloat(text.count), 56) * fontPx * 0.1
        return max(30, fontPx * 3.05 + extra)
    }

    /// 视平面内管段方向角（弧度）。非竖线：沿 p1→p2，并收在 (-π/2, π/2] 以免倒置。
    /// 接近竖线：统一按屏幕「下端 → 上端」（y 小为上）定向，文字从下往上读。
    private static func linkLabelRotationRadians(from p1: CGPoint, to p2: CGPoint) -> Double {
        let dx = Double(p2.x - p1.x)
        let dy = Double(p2.y - p1.y)
        let len2 = dx * dx + dy * dy
        guard len2 >= 1e-8 else { return 0 }
        let len = sqrt(len2)

        // |dx|/len 小 ≈ 接近竖直（约 ±66° 以内都算「接近竖线」）
        let nearlyVertical = abs(dx) / len < 0.4

        let ux: Double
        let uy: Double
        if nearlyVertical {
            // 屏幕坐标 y 向下：下端 y 更大，沿 下→上 为阅读方向
            let bottom = (p1.y >= p2.y) ? p1 : p2
            let top = (p1.y >= p2.y) ? p2 : p1
            ux = Double(top.x - bottom.x)
            uy = Double(top.y - bottom.y)
        } else {
            ux = dx
            uy = dy
        }

        var a = atan2(uy, ux)
        if a > .pi / 2 {
            a -= .pi
        } else if a < -.pi / 2 {
            a += .pi
        }
        return a
    }

    /// 视平面内垂直于管段的单位法线，取朝向屏幕「上方」的一侧（y 向下，上为 -y）。
    private static func linkLabelOutwardNormal(from p1: CGPoint, to p2: CGPoint) -> CGPoint {
        let dx = CGFloat(p2.x - p1.x)
        let dy = CGFloat(p2.y - p1.y)
        let len = hypot(dx, dy)
        guard len > 1e-4 else { return CGPoint(x: 0, y: -1) }
        var nx = dy / len
        var ny = -dx / len
        if ny > 0 {
            nx = -nx
            ny = -ny
        }
        return CGPoint(x: nx, y: ny)
    }

    /// 管段：属性间用黑灰「 - 」连接，数值为 `Text` 主色
    private static func linkLabelComposedText(parts: [String], font: Font, separatorColor: Color) -> Text {
        guard let first = parts.first else { return Text("").font(font) }
        let sep = Text(" - ").foregroundColor(separatorColor)
        var t = Text(first).foregroundColor(.primary)
        for p in parts.dropFirst() {
            t = t + sep + Text(p).foregroundColor(.primary)
        }
        return t.font(font)
    }

    private func nodeLabelLines(nodeIndex: Int) -> [String] {
        var lines: [String] = []
        if showNodeId {
            if let p = project, nodeIndex >= 0 {
                let id = (try? p.getNodeId(index: nodeIndex)) ?? "—"
                lines.append(id)
            } else {
                lines.append("—")
            }
        }
        if showNodeElevation {
            lines.append(formatNodeField(nodeIndex: nodeIndex, param: .elevation, fmt: "%.2f"))
        }
        if showNodeBaseDemand {
            lines.append(formatNodeField(nodeIndex: nodeIndex, param: .basedemand, fmt: "%.4f"))
        }
        if showNodePressure {
            lines.append(formatNodeField(nodeIndex: nodeIndex, param: .pressure, fmt: "%.2f"))
        }
        if showNodeHead {
            lines.append(formatNodeField(nodeIndex: nodeIndex, param: .head, fmt: "%.2f"))
        }
        return lines
    }

    private func formatNodeField(nodeIndex: Int, param: NodeParams, fmt: String) -> String {
        guard nodeIndex >= 0 else { return "—" }
        switch param {
        case .pressure:
            if let s = pressureSeries, nodeIndex < s.count {
                return String(format: fmt, Double(s[nodeIndex]))
            }
        case .head:
            if let s = headSeries, nodeIndex < s.count {
                return String(format: fmt, Double(s[nodeIndex]))
            }
        default:
            break
        }
        guard let p = project else { return "—" }
        guard let v = try? p.getNodeValue(nodeIndex: nodeIndex, param: param) else { return "—" }
        return String(format: fmt, v)
    }

    private func linkLabelParts(linkIndex: Int) -> [String] {
        var parts: [String] = []
        if showLinkId {
            if let p = project, linkIndex >= 0 {
                let id = (try? p.getLinkId(index: linkIndex)) ?? "—"
                parts.append(id)
            } else {
                parts.append("—")
            }
        }
        if showLinkDiameter {
            parts.append(formatLinkField(linkIndex: linkIndex, param: .diameter))
        }
        if showLinkLength {
            parts.append(formatLinkField(linkIndex: linkIndex, param: .length))
        }
        if showLinkFlow {
            parts.append(formatLinkField(linkIndex: linkIndex, param: .flow))
        }
        if showLinkVelocity {
            parts.append(formatLinkField(linkIndex: linkIndex, param: .velocity))
        }
        return parts
    }

    private func formatLinkField(linkIndex: Int, param: LinkParams) -> String {
        guard linkIndex >= 0 else { return "—" }
        switch param {
        case .flow:
            if let s = flowSeries, linkIndex < s.count {
                return NumericDisplayFormat.formatLinkFlowOrVelocity(Double(s[linkIndex]))
            }
        case .velocity:
            if let s = velocitySeries, linkIndex < s.count {
                return NumericDisplayFormat.formatLinkFlowOrVelocity(Double(s[linkIndex]))
            }
        default:
            break
        }
        guard let p = project else { return "—" }
        guard let v = try? p.getLinkValue(linkIndex: linkIndex, param: param) else { return "—" }
        switch param {
        case .diameter, .length:
            return NumericDisplayFormat.formatPipeLengthOrDiameter(v)
        case .flow, .velocity:
            return NumericDisplayFormat.formatLinkFlowOrVelocity(v)
        default:
            return String(format: "%.4f", v)
        }
    }
}
