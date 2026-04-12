import SwiftUI
import UniformTypeIdentifiers
import Metal
import Charts
import EPANET3Renderer
import EPANET3Bridge
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

private enum AppColors {
    static var controlBackground: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(UIColor.secondarySystemBackground)
        #endif
    }
    static var windowBackground: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }
}

public struct ContentView: View {
    @EnvironmentObject var appState: AppState
    public init() {}
    @State private var scale: CGFloat = 1
    @State private var panX: CGFloat = 0
    @State private var panY: CGFloat = 0
    @State private var lastScale: CGFloat = 1
    /// iOS：单指拖动画布时记录手势起点处的 pan，避免把「屏幕位移」误当作 pan 单位（与 macOS `onPanDelta` 公式对齐）。
    @State private var touchPanAnchor: CGSize?
    @State private var mouseSceneX: Float?
    @State private var mouseSceneY: Float?
    @State private var showRunResultSheet = false
    @State private var resultLegendOffset: CGSize = .zero
    @State private var resultLegendLastOffset: CGSize = .zero
    @State private var showLeftSidebar = true
    @State private var showRightPanel = true
    /// 画布投影锚点（场景坐标）：新建/全貌适配/打开文件时与当前 `scene.bounds` 中心对齐；拓扑编辑中保持不变。
    @State private var canvasViewportAnchor: (x: Float, y: Float) = (50, 50)
    /// 当前投影用正方形视口的内禀 `baseScale`；视口扩大时按比例调 `userScale`，保持「像素—场景」比例不跳变。
    @State private var lastIntrinsicTransformBaseScale: CGFloat?
    /// 底部时序图表面板总高度（含顶部分隔条），可拖拽调整。
    @State private var bottomChartPanelHeight: CGFloat = 200
    @State private var bottomChartPanelDragStartHeight: CGFloat?

    /// iOS：属性面板 overlay 时给图例/缩放钮留右内边距；Mac 侧栏在 `HStack` 内不叠画布。
    private var floatingSidebarTrailingInset: CGFloat {
        #if os(macOS)
        return 0
        #else
        return showRightPanel ? 260 : 0
        #endif
    }
    /// MTKView `drawableSize`（像素），用于 `maxUserScale`（取高度，与 Metal 在 w≥h 时的 Y 向缩放一致）。
    @State private var canvasDrawablePixelSize: CGSize = .zero

    @AppStorage("settings.display.nodeSize") private var canvasNodeSize = 6
    @AppStorage(DisplayCanvasNodeColor.junctionKey) private var canvasNodeRGBJunction = DisplayCanvasNodeColor.defaultJunction
    @AppStorage(DisplayCanvasNodeColor.reservoirKey) private var canvasNodeRGBReservoir = DisplayCanvasNodeColor.defaultReservoir
    @AppStorage(DisplayCanvasNodeColor.tankKey) private var canvasNodeRGBTank = DisplayCanvasNodeColor.defaultTank
    @AppStorage("settings.display.lineWidth") private var canvasLineWidth = 2
    @AppStorage(DisplayCanvasLinkColor.pipeKey) private var canvasLinkRGBPipe = DisplayCanvasLinkColor.defaultPipe
    @AppStorage(DisplayCanvasLinkColor.pumpKey) private var canvasLinkRGBPump = DisplayCanvasLinkColor.defaultPump
    @AppStorage(DisplayCanvasLinkColor.valveKey) private var canvasLinkRGBValve = DisplayCanvasLinkColor.defaultValve
    /// 总开关：关闭时不绘画布标注、不显示左下角标注图例（各分项设置仍保留）。
    @AppStorage("settings.display.labelsVisible") private var canvasLabelsVisible = true
    @AppStorage("settings.display.layer.junction") private var layerJunctionVisible = true
    @AppStorage("settings.display.layer.reservoir") private var layerReservoirVisible = true
    @AppStorage("settings.display.layer.tank") private var layerTankVisible = true
    @AppStorage("settings.display.layer.pipe") private var layerPipeVisible = true
    @AppStorage("settings.display.layer.pump") private var layerPumpVisible = true
    @AppStorage("settings.display.layer.valve") private var layerValveVisible = true

    private var canvasLayerVisibility: CanvasLayerVisibility {
        CanvasLayerVisibility(
            showJunction: layerJunctionVisible,
            showReservoir: layerReservoirVisible,
            showTank: layerTankVisible,
            showPipe: layerPipeVisible,
            showPump: layerPumpVisible,
            showValve: layerValveVisible
        )
    }

    private var nodeRange: (Float, Float)? {
        guard !appState.nodePressureValues.isEmpty else { return nil }
        guard let minV = appState.nodePressureValues.min(), let maxV = appState.nodePressureValues.max() else { return nil }
        return (minV, maxV)
    }

    private var linkRange: (Float, Float)? {
        guard !appState.linkFlowValues.isEmpty else { return nil }
        guard let minV = appState.linkFlowValues.min(), let maxV = appState.linkFlowValues.max() else { return nil }
        return (minV, maxV)
    }

    #if !os(macOS)
    private var iosRunResultColor: Color {
        if appState.isRunning { return .orange }
        guard let result = appState.runResult else { return .secondary }
        switch result {
        case .success: return .green
        case .failure: return .red
        }
    }

    private var iosRunResultTitle: String {
        if appState.isRunning { return "计算中" }
        guard let result = appState.runResult else { return "未计算" }
        switch result {
        case .success: return "计算完成"
        case .failure: return "计算失败"
        }
    }
    #endif

    /// 管段/阀门/水泵放置：与 `hitTest` 一致，节点热区内显示十字光标（仅 macOS）。
    private var linkPlacementSnapCursorActive: Bool {
        #if os(macOS)
        switch appState.activeCanvasPlacementTool {
        case .pipe, .valve, .pump: return true
        default: return false
        }
        #else
        return false
        #endif
    }

    // MARK: - 画布视口（缩放 / 平移；与 MetalNetworkCoordinator.viewportProjection 一致）
    private enum CanvasZoomPolicy {
        static let minUserScale: CGFloat = 0.2
        static let maxUserScaleFloor: CGFloat = 20
        /// 最大缩放时：1 像素对应多少场景坐标单位
        static let maxSceneUnitsPerPixel: CGFloat = 0.01
        /// 尚未收到 `drawableSize` 时的占位 min 边（像素），避免首帧 max 为无穷
        static let fallbackMinDrawablePixels: CGFloat = 1024
        static let absoluteMaxUserScale: CGFloat = 100_000_000
    }

    private var referencePixelDimensionForMaxZoom: CGFloat {
        let s = canvasDrawablePixelSize
        guard s.width > 0, s.height > 0 else { return CanvasZoomPolicy.fallbackMinDrawablePixels }
        return max(s.height, 1)
    }

    private func squareFraming(for scene: NetworkScene) -> (minX: Float, maxX: Float, minY: Float, maxY: Float) {
        CanvasViewportFraming.squareTransformBounds(scene: scene, anchor: canvasViewportAnchor)
    }

    private func maxUserScale(transformBounds t: (minX: Float, maxX: Float, minY: Float, maxY: Float)) -> CGFloat {
        let bs = CanvasViewportFraming.intrinsicBaseScale(transformBounds: t)
        guard bs > 0, bs.isFinite else { return CanvasZoomPolicy.maxUserScaleFloor }
        let refPx = max(referencePixelDimensionForMaxZoom, 1)
        let u = CanvasZoomPolicy.maxSceneUnitsPerPixel
        let idealMax = 2.0 / (refPx * bs * u)
        if idealMax < 1 {
            return CanvasZoomPolicy.maxUserScaleFloor
        }
        return min(CanvasZoomPolicy.absoluteMaxUserScale, idealMax)
    }

    private func clampUserScale(_ s: CGFloat, transformBounds t: (minX: Float, maxX: Float, minY: Float, maxY: Float)) -> CGFloat {
        min(maxUserScale(transformBounds: t), max(CanvasZoomPolicy.minUserScale, s))
    }

    private func clampUserScale(_ s: CGFloat, scene: NetworkScene) -> CGFloat {
        clampUserScale(s, transformBounds: squareFraming(for: scene))
    }

    /// 与 `MetalNetworkCoordinator.draw` 中 NDC 缩放一致（Double，减轻高倍缩放时 Float 舍入）。
    private func canvasNdcScaleXY(
        viewWidth: Double,
        viewHeight: Double,
        transformBounds t: (minX: Float, maxX: Float, minY: Float, maxY: Float),
        userScale: CGFloat
    ) -> (scaleX: Double, scaleY: Double) {
        let bw = Double(t.maxX - t.minX)
        let bh = Double(t.maxY - t.minY)
        let pad = max(bw, bh) * 0.05 + 1
        let baseScale = min(2.0 / (bw + pad * 2), 2.0 / (bh + pad * 2))
        let s = baseScale * Double(userScale)
        if viewWidth >= viewHeight {
            let scaleY = s
            let scaleX = s * viewHeight / viewWidth
            return (scaleX, scaleY)
        } else {
            let scaleX = s
            let scaleY = s * viewWidth / viewHeight
            return (scaleX, scaleY)
        }
    }

    private func canvasNdcScaleXY(viewWidth: Double, viewHeight: Double, scene: NetworkScene, userScale: CGFloat) -> (scaleX: Double, scaleY: Double) {
        canvasNdcScaleXY(viewWidth: viewWidth, viewHeight: viewHeight, transformBounds: squareFraming(for: scene), userScale: userScale)
    }

    /// 屏幕像素位移 → 与 `offX/offY` 一致的 pan 增量（非 1:1 点坐标）。
    private func applyCanvasScreenPanDelta(dx: CGFloat, dy: CGFloat, viewSize: CGSize, scene: NetworkScene) {
        let w = Double(viewSize.width), h = Double(viewSize.height)
        guard w > 0, h > 0 else { return }
        let (scaleX, scaleY) = canvasNdcScaleXY(viewWidth: w, viewHeight: h, scene: scene, userScale: scale)
        panX += CGFloat(Double(dx) * 2.0 / (w * scaleX * 0.01))
        panY += CGFloat(Double(dy) * 2.0 / (h * scaleY * 0.01))
    }

    private func sceneBoundsCenterXY(_ scene: NetworkScene) -> (cx: Float, cy: Float) {
        let b = scene.bounds
        return ((b.minX + b.maxX) * 0.5, (b.minY + b.maxY) * 0.5)
    }

    private func clampScaleToCurrentSceneIfNeeded() {
        guard let sc = appState.scene else { return }
        let c = clampUserScale(scale, scene: sc)
        if abs(c - scale) > 1e-6 {
            scale = c
            lastScale = c
        }
    }

    /// 进入浏览或结果模式时：对齐 `lastIntrinsic`，并只做 clamp（不乘 old/new 比例）。
    private func resyncCanvasIntrinsicBaselineNoRatio(scene: NetworkScene) {
        let tB = squareFraming(for: scene)
        let newBase = CanvasViewportFraming.intrinsicBaseScale(transformBounds: tB)
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr) {
            lastIntrinsicTransformBaseScale = newBase
            clampScaleToCurrentSceneIfNeeded()
        }
    }

    /// 场景包围变化（`zoomFingerprint`）：浏览/结果下按比例调 userScale；拓扑编辑冻结时只更新内禀基准。
    private func applyViewportAfterZoomFingerprintChange(scene: NetworkScene) {
        let tB = squareFraming(for: scene)
        let newBase = CanvasViewportFraming.intrinsicBaseScale(transformBounds: tB)
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr) {
            if appState.freezesCanvasViewportWhileEditingTopology {
                lastIntrinsicTransformBaseScale = newBase
                return
            }
            if let old = lastIntrinsicTransformBaseScale, old > 0, newBase > 0 {
                let ratio = old / newBase
                if abs(ratio - 1.0) > 1e-5 {
                    scale = clampUserScale(scale * ratio, transformBounds: tB)
                    lastScale = scale
                }
            }
            lastIntrinsicTransformBaseScale = newBase
            clampScaleToCurrentSceneIfNeeded()
        }
    }

    /// 与「适应窗口」一致：userScale=1、pan=0，即整图（含 padding）落在视图中
    private func resetCanvasToFitDefaults() {
        scale = 1
        panX = 0
        panY = 0
        lastScale = 1
    }

    /// 全貌重置后同步锚点与内禀缩放基准，供后续拓扑编辑稳定投影。
    private func resetCanvasToFitDefaultsAndSyncBoundsAnchor(scene: NetworkScene?) {
        resetCanvasToFitDefaults()
        if let sc = scene {
            let c = sceneBoundsCenterXY(sc)
            canvasViewportAnchor = (x: c.cx, y: c.cy)
            let t = squareFraming(for: sc)
            lastIntrinsicTransformBaseScale = CanvasViewportFraming.intrinsicBaseScale(transformBounds: t)
        } else {
            canvasViewportAnchor = (50, 50)
            lastIntrinsicTransformBaseScale = nil
        }
    }

    /// 画布右下角缩放/适配按钮：整块圆角矩形为点击热区（避免仅文字可点）
    /// 缩放按钮：禁用隐式动画，保证视觉得到反馈在 100ms 内量级（避免与画布手势竞争 + 避免动画拖尾）
    private func applyZoomButtonStep(multiply: CGFloat, scene: NetworkScene) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            let c = clampUserScale(scale * multiply, scene: scene)
            scale = c
            lastScale = c
        }
    }

    private func canvasZoomChipButton(title: String, font: Font, action: @escaping () -> Void) -> some View {
        let corner: CGFloat = 7
        let side: CGFloat = 30
        return Button(action: action) {
            Text(title)
                .font(font)
                .frame(width: side, height: side)
                .contentShape(RoundedRectangle(cornerRadius: corner))
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(AppColors.controlBackground.opacity(0.22))
                    }
                    // 毛玻璃+淡色底整体不透明度：0.6 基础上再提高 20% → 0.72（符号仍由 Text 全不透明绘制）
                    .opacity(0.72)
                }
                        }
                        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func loadedSceneProjectToolbar() -> some View {
        if appState.scene != nil {
            #if os(macOS)
            MacDesignToolbar(appState: appState)
            #else
            HStack(spacing: 8) {
                Button { appState.setEditorMode(.browse) } label: { Label("浏览", systemImage: "hand.tap") }
                    .buttonStyle(.bordered)
                    .tint(appState.editorMode == .browse ? .accentColor : .gray)
                Button { appState.setEditorMode(.add) } label: { Label("添加", systemImage: "plus.circle") }
                    .buttonStyle(.bordered)
                    .tint(appState.editorMode == .add ? .accentColor : .gray)
                    .disabled(!appState.canEditTopologyOnCanvas || !appState.isTopologyEditingEnabled)
                Button { appState.setEditorMode(.delete) } label: { Label("删除", systemImage: "trash") }
                    .buttonStyle(.bordered)
                    .tint(appState.editorMode == .delete ? .accentColor : .gray)
                    .disabled(!appState.canEditTopologyOnCanvas || !appState.isTopologyEditingEnabled)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.controlBackground)
            #endif
        }
    }

    /// MetalNetworkView + 覆盖层；`AnyView` 避免 Metal 多闭包 init 导致类型推断超时
    private func loadedSceneCanvasZStack(scene: NetworkScene) -> AnyView {
        AnyView(ZStack {
            CanvasBackgroundView()
                .overlay(CanvasGridView())
            if let hint = appState.canvasPlacementStatusHint, !hint.isEmpty {
                Text(hint)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }
            GeometryReader { geo in
                MetalNetworkView(
                    scene: scene,
                    canvasTransformBounds: squareFraming(for: scene),
                    sceneGeometryRevision: appState.sceneGeometryRevision,
                    resultScalarRevision: appState.resultScalarRevision,
                    scale: scale,
                    panX: panX,
                    panY: panY,
                    selectedNodeIndex: appState.selectedNodeIndex,
                    selectedLinkIndex: appState.selectedLinkIndex,
                    selectedNodeIndices: Array(appState.selectedNodeIndices).sorted(),
                    selectedLinkIndices: Array(appState.selectedLinkIndices).sorted(),
                    nodeScalars: appState.resultOverlayMode == .pressure ? appState.nodePressureValues : nil,
                    linkScalars: appState.resultOverlayMode == .flow ? appState.linkFlowValues : nil,
                    nodeScalarRange: appState.resultOverlayMode == .pressure ? nodeRange : nil,
                    linkScalarRange: appState.resultOverlayMode == .flow ? linkRange : nil,
                    nodePointSizePixels: CGFloat(canvasNodeSize),
                    nodeColorJunction: DisplayCanvasNodeColor.rgbFloats(packed: canvasNodeRGBJunction),
                    nodeColorReservoir: DisplayCanvasNodeColor.rgbFloats(packed: canvasNodeRGBReservoir),
                    nodeColorTank: DisplayCanvasNodeColor.rgbFloats(packed: canvasNodeRGBTank),
                    linkLineWidthPixels: CGFloat(canvasLineWidth),
                    linkColorPipe: DisplayCanvasLinkColor.rgbFloats(packed: canvasLinkRGBPipe),
                    linkColorPump: DisplayCanvasLinkColor.rgbFloats(packed: canvasLinkRGBPump),
                    linkColorValve: DisplayCanvasLinkColor.rgbFloats(packed: canvasLinkRGBValve),
                    layerVisibility: canvasLayerVisibility,
                    clearColor: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0),
                    onScrollWheel: { delta, viewPoint, viewSize in
                        let tb = squareFraming(for: scene)
                        let newScale = clampUserScale(scale * (1 + delta), transformBounds: tb)
                        if viewSize.width > 0, viewSize.height > 0 {
                            let w = Float(viewSize.width), h = Float(viewSize.height)
                            let ndcX = 2 * Float(viewPoint.x) / w - 1
                            let ndcY = 1 - 2 * Float(viewPoint.y) / h
                            let bw = tb.maxX - tb.minX
                            let bh = tb.maxY - tb.minY
                            let pad = max(bw, bh) * 0.05 + 1
                            let baseScale = min(2.0 / (bw + pad * 2), 2.0 / (bh + pad * 2))
                            let (scaleXOld, scaleYOld): (Float, Float)
                            if w >= h {
                                scaleYOld = baseScale * Float(scale)
                                scaleXOld = scaleYOld * h / w
                            } else {
                                scaleXOld = baseScale * Float(scale)
                                scaleYOld = scaleXOld * w / h
                            }
                            let centerX = (tb.minX + tb.maxX) * 0.5
                            let centerY = (tb.minY + tb.maxY) * 0.5
                            let offXOld = -centerX * scaleXOld + Float(panX) * scaleXOld * 0.01
                            let offYOld = -centerY * scaleYOld - Float(panY) * scaleYOld * 0.01
                            let sceneX = (ndcX - offXOld) / scaleXOld
                            let sceneY = (ndcY - offYOld) / scaleYOld
                            let (scaleXNew, scaleYNew): (Float, Float)
                            if w >= h {
                                scaleYNew = baseScale * Float(newScale)
                                scaleXNew = scaleYNew * h / w
                            } else {
                                scaleXNew = baseScale * Float(newScale)
                                scaleYNew = scaleXNew * w / h
                            }
                            let offXNew = ndcX - sceneX * scaleXNew
                            let offYNew = ndcY - sceneY * scaleYNew
                            let cx = Double(centerX), cy = Double(centerY)
                            let sxN = Double(scaleXNew), syN = Double(scaleYNew)
                            panX = CGFloat((Double(offXNew) + cx * sxN) / (sxN * 0.01))
                            panY = CGFloat(-(Double(offYNew) + cy * syN) / (syN * 0.01))
                        }
                        scale = newScale
                        lastScale = scale
                    },
                    onPanDelta: { dx, dy, viewSize in
                        applyCanvasScreenPanDelta(dx: dx, dy: dy, viewSize: viewSize, scene: scene)
                    },
                    onPressEscape: {
                        if appState.cancelCanvasPlacementIfActive() { return }
                        appState.clearSelection()
                    },
                    onMouseMove: { coords in
                        if let (x, y) = coords {
                            mouseSceneX = x
                            mouseSceneY = y
                        } else {
                            mouseSceneX = nil
                            mouseSceneY = nil
                        }
                    },
                    onSelect: { node, link in
                        appState.setSelection(nodeIndex: node, linkIndex: link)
                    },
                    onDrawableSizeChange: { size in
                        guard size.width > 0, size.height > 0 else { return }
                        canvasDrawablePixelSize = size
                    },
                    onPlacementPrimaryClick: { coord, pt, sz in
                        appState.handleCanvasPlacementClick(coordinator: coord, viewPoint: pt, viewSize: sz)
                    },
                    linkPlacementSnapCursor: linkPlacementSnapCursorActive,
                    onRightMouseDown: {
                        #if os(macOS)
                        appState.endContinuousLinkPlacementChainIfActive()
                        #else
                        false
                        #endif
                    },
                    marqueeEnabled: appState.isTopologyEditingEnabled && appState.activeCanvasPlacementTool == nil,
                    onMarqueePreview: { rect, _ in
                        appState.marqueeRectInView = rect
                    },
                    onMarqueeComplete: { coord, rect, size, crossing in
                        appState.applyMarqueeSelection(coordinator: coord, viewRect: rect, viewSize: size, crossingMode: crossing)
                    }
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                #if os(macOS)
                .overlay {
                    if let r = appState.marqueeRectInView, r.width > 0.5 || r.height > 0.5 {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.12))
                            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                            .allowsHitTesting(false)
                    }
                }
                #endif
                #if os(macOS)
                .onChange(of: appState.activeCanvasPlacementTool) { _ in
                    NSCursor.arrow.set()
                }
                #endif
                #if os(iOS)
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale = clampUserScale(lastScale * $0, scene: scene) }
                        .onEnded { _ in
                            let c = clampUserScale(scale, scene: scene)
                            scale = c
                            lastScale = c
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { v in
                            let sz = geo.size
                            if touchPanAnchor == nil {
                                touchPanAnchor = CGSize(width: panX, height: panY)
                            }
                            guard let anchor = touchPanAnchor, sz.width > 0, sz.height > 0 else { return }
                            let w = Double(sz.width), h = Double(sz.height)
                            let (scaleX, scaleY) = canvasNdcScaleXY(viewWidth: w, viewHeight: h, scene: scene, userScale: scale)
                            panX = anchor.width + CGFloat(Double(v.translation.width) * 2.0 / (w * scaleX * 0.01))
                            panY = anchor.height + CGFloat(Double(v.translation.height) * 2.0 / (h * scaleY * 0.01))
                        }
                        .onEnded { _ in
                            touchPanAnchor = nil
                        }
                )
                #endif
                .onTapGesture(count: 2) {
                    resetCanvasToFitDefaultsAndSyncBoundsAnchor(scene: scene)
                    appState.clearSelection()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

            GeometryReader { _ in
                CanvasMapLabelsOverlay(
                    scene: scene,
                    transformBounds: squareFraming(for: scene),
                    scale: scale,
                    panX: panX,
                    panY: panY,
                    project: appState.project,
                    layerVisibility: canvasLayerVisibility,
                    pressureSeries: appState.nodePressureValues.isEmpty ? nil : appState.nodePressureValues,
                    headSeries: appState.nodeHeadValues.isEmpty ? nil : appState.nodeHeadValues,
                    flowSeries: appState.linkFlowValues.isEmpty ? nil : appState.linkFlowValues,
                    velocitySeries: appState.linkVelocityValues.isEmpty ? nil : appState.linkVelocityValues
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)

            // 左下角标注图例：叠在 Metal + 画布标注之上（与管网重叠时覆盖管网）
            // 底层透明层不拦截手势，仅图例本体在 macOS 上可点进「显示 → 标注设置」。
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                CanvasLabelsLegend()
                    .padding(.top, 14)
                    .padding(.trailing, 14)
                    .padding(.leading, 7)
                    .padding(.bottom, 7)
                    #if os(macOS)
                    .allowsHitTesting(true)
                    #else
                    .allowsHitTesting(false)
                    #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            if appState.resultOverlayMode != .none {
                ResultOverlayLegend(
                    mode: appState.resultOverlayMode,
                    nodeRange: nodeRange,
                    linkRange: linkRange,
                    offset: resultLegendOffset
                )
                .padding(14)
                .padding(.trailing, floatingSidebarTrailingInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            resultLegendOffset = CGSize(
                                width: resultLegendLastOffset.width + value.translation.width,
                                height: resultLegendLastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in resultLegendLastOffset = resultLegendOffset }
                )
            }

            VStack(spacing: 6) {
                canvasZoomChipButton(title: "+", font: .body) {
                    applyZoomButtonStep(multiply: 1.12, scene: scene)
                }
                canvasZoomChipButton(title: "⊡", font: .system(size: 11, weight: .medium, design: .monospaced)) {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        resetCanvasToFitDefaultsAndSyncBoundsAnchor(scene: scene)
                    }
                }
                canvasZoomChipButton(title: "−", font: .body) {
                    applyZoomButtonStep(multiply: 0.88, scene: scene)
                }
            }
            .padding(14)
            .padding(.trailing, floatingSidebarTrailingInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        })
    }

    @ViewBuilder
    private func loadedSceneMainRow(scene: NetworkScene) -> some View {
        #if os(macOS)
        HStack(spacing: 0) {
            if showLeftSidebar {
                MacDesignSidebar(appState: appState)
                    .frame(width: 200)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(DesignSurfaceBackground())
            }
            // 图表面板仅与画布同列，不延伸到左/右侧栏下方。
            VStack(spacing: 0) {
                loadedSceneCanvasZStack(scene: scene)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showBottomChartPanel {
                    Divider()
                    bottomChartPanelChrome
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showRightPanel {
                PropertyPanelView(appState: appState, selectedNodeIndex: appState.selectedNodeIndex, selectedLinkIndex: appState.selectedLinkIndex, onClose: {
                    appState.clearSelection()
                        })
                        .frame(width: 260)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(nil, value: showLeftSidebar)
        .animation(nil, value: showRightPanel)
        #else
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                loadedSceneCanvasZStack(scene: scene)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showBottomChartPanel {
                    Divider()
                    bottomChartPanelChrome
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if showRightPanel {
                PropertyPanelView(appState: appState, selectedNodeIndex: appState.selectedNodeIndex, selectedLinkIndex: appState.selectedLinkIndex, onClose: {
                    appState.clearSelection()
                })
                .frame(width: 260)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        #endif
    }

    private var showBottomChartPanel: Bool {
        guard appState.timeSeriesResults != nil else { return false }
        return appState.selectedNodeIndex != nil || appState.selectedLinkIndex != nil
    }

    private let bottomChartResizeHandleHeight: CGFloat = 8

    /// 底部时序图：顶部分隔条可上下拖拽调整高度，图表区铺满其下长方形。
    private var bottomChartPanelChrome: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.14))
                    .frame(height: bottomChartResizeHandleHeight)
                Capsule()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 36, height: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .help("上下拖拽调整绘图区高度")
                    .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if bottomChartPanelDragStartHeight == nil {
                            bottomChartPanelDragStartHeight = bottomChartPanelHeight
                        }
                        let base = bottomChartPanelDragStartHeight ?? bottomChartPanelHeight
                        bottomChartPanelHeight = min(560, max(132, base - g.translation.height))
                    }
                    .onEnded { _ in
                        bottomChartPanelDragStartHeight = nil
                    }
            )
            ResultTimeSeriesChartView(appState: appState)
                .frame(height: max(96, bottomChartPanelHeight - bottomChartResizeHandleHeight))
                .background(AppColors.controlBackground)
        }
    }

    private func loadedSceneRoot(scene: NetworkScene) -> some View {
        VStack(spacing: 0) {
            loadedSceneProjectToolbar()
            loadedSceneMainRow(scene: scene)
                .onChange(of: appState.errorFocusNodeIndex) { node in
                    guard let node = node else { return }
                    appState.setSelection(nodeIndex: node, linkIndex: nil)
                }
                .onChange(of: appState.errorFocusLinkIndex) { link in
                    guard let link = link else { return }
                    appState.setSelection(nodeIndex: nil, linkIndex: link)
                }
                .onChange(of: appState.focusSelectionToken) { _ in
                    focusOnCurrentSelection(in: scene)
                }
                .onChange(of: CanvasViewportFraming.zoomFingerprint(scene: scene, anchor: canvasViewportAnchor)) { _ in
                    applyViewportAfterZoomFingerprintChange(scene: scene)
                }
                .onChange(of: appState.editorMode) { mode in
                    if mode == .browse || mode == .result {
                        resyncCanvasIntrinsicBaselineNoRatio(scene: scene)
                    }
                }
                .onChange(of: appState.simulationTimelinePlayheadSeconds) { _ in
                    appState.applyResultScalarsForCurrentPlayhead()
                }
        }
        .macSimulationTimelineArrowKeys(appState: appState)
    }

    #if os(macOS)
    private var displayFileName: String {
        if let path = appState.filePath, !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if appState.scene != nil {
            return "未命名.inp"
        }
        return ""
    }
    #endif

    private func centerView(on target: (x: Float, y: Float), in scene: NetworkScene) {
        let tb = squareFraming(for: scene)
        let centerX = (tb.minX + tb.maxX) * 0.5
        let centerY = (tb.minY + tb.maxY) * 0.5
        panX = CGFloat((centerX - target.x) / 0.01)
        panY = CGFloat((target.y - centerY) / 0.01)
    }

    private func focusOnCurrentSelection(in scene: NetworkScene) {
        if let nodeIndex = appState.selectedNodeIndex,
           let node = scene.nodes.first(where: { $0.nodeIndex == nodeIndex }) {
            centerView(on: (node.x, node.y), in: scene)
            return
        }
        if let linkIndex = appState.selectedLinkIndex,
           let link = scene.links.first(where: { $0.linkIndex == linkIndex }) {
            centerView(on: ((link.x1 + link.x2) * 0.5, (link.y1 + link.y2) * 0.5), in: scene)
        }
    }

    public var body: some View {
        mainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(displayFileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showLeftSidebar.toggle()
                } label: {
                    Image(systemName: "sidebar.leading")
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(showLeftSidebar ? 0.3 : 0), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(showLeftSidebar ? "隐藏图例列表" : "显示图例列表")

                Button {
                    showRightPanel.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(showRightPanel ? 0.3 : 0), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(showRightPanel ? "隐藏属性列表" : "显示属性列表")
            }
        }
        #elseif os(iOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("打开") { appState.openFile() }
            }
        }
        #endif
        .fileImporter(isPresented: $appState.showFileImporter, allowedContentTypes: [UTType(filenameExtension: "inp") ?? .plainText], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            appState.openFileFromURL(url)
        }
        #if os(iOS)
        .alert("未保存的更改", isPresented: Binding(
            get: { appState.pendingUnsavedOperation != nil },
            set: { if !$0 { appState.cancelPendingUnsavedOperation() } }
        )) {
            Button("保存") { appState.resolvePendingUnsavedOperation(saveFirst: true) }
            Button("不保存", role: .destructive) { appState.resolvePendingUnsavedOperation(saveFirst: false) }
            Button("取消", role: .cancel) { appState.cancelPendingUnsavedOperation() }
        } message: {
            Text("您有尚未保存到 .inp 的修改。")
        }
        #endif
        .sheet(isPresented: $showRunResultSheet) {
            RunResultSheet(appState: appState)
                #if os(macOS)
                .modifier(SheetPresentationChrome())
                #endif
        }
        #if os(macOS)
        .onAppear { updateMacWindowTitle() }
        .onChange(of: appState.filePath) { _ in updateMacWindowTitle() }
        .onChange(of: appState.scene != nil) { _ in updateMacWindowTitle() }
        .onChange(of: appState.macDismissRightSidebarNonce) { _ in
            showRightPanel = false
        }
        #endif
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            if let msg = appState.errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    ScrollView {
                        Text(msg)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 220)
                    Button {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(msg, forType: .string)
                        #elseif canImport(UIKit)
                        UIPasteboard.general.string = msg
                        #endif
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("将完整错误信息复制到剪贴板")
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
            }

            if appState.isLoading {
                Spacer()
                ProgressView("加载中...")
                Spacer()
            } else if let scene = appState.scene {
                loadedSceneRoot(scene: scene)
            } else {
                #if os(macOS)
                StartupSplitView(appState: appState)
                #else
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "map")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("新建空白管网或打开 .inp 文件")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Button("新建文件") {
                        appState.newFile()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(minWidth: 220, minHeight: 44)
                    Button("打开文件") {
                        appState.openFile()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(minWidth: 220, minHeight: 44)
                    .padding(.top, 4)
                    Spacer()
                }
                #endif
            }
            if appState.scene != nil {
                #if os(macOS)
                MacDesignStatusBar(
                    appState: appState,
                    scale: scale,
                    mouseSceneX: mouseSceneX,
                    mouseSceneY: mouseSceneY,
                    labelsVisible: $canvasLabelsVisible,
                    onTapRunResult: { showRunResultSheet = true }
                )
                #else
                HStack(spacing: 12) {
                        Button {
                            showRunResultSheet = true
                        } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(iosRunResultColor)
                                .frame(width: 6, height: 6)
                            Text(iosRunResultTitle)
                        }
                        .font(.caption.monospaced())
                        }
                        .buttonStyle(.plain)
                    .help("读入/渲染与模型统计；已计算时含模拟时长与平差耗时")
                    Divider().frame(height: 12)
                    Text("X: \(mouseSceneX.map { String(format: "%.2f", $0) } ?? "—")")
                    Text("Y: \(mouseSceneY.map { String(format: "%.2f", $0) } ?? "—")")
                    Spacer()
                    Button {
                        canvasLabelsVisible.toggle()
                    } label: {
                        Image(systemName: canvasLabelsVisible ? "tag.fill" : "tag")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(canvasLabelsVisible ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(canvasLabelsVisible ? "隐藏标注" : "显示标注")
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColors.controlBackground)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3)), alignment: .top)
                #endif
            }
        }
        .onChange(of: appState.canvasViewportFitResetNonce) { _ in
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                resetCanvasToFitDefaultsAndSyncBoundsAnchor(scene: appState.scene)
            }
        }
        .onChange(of: appState.scene == nil) { noScene in
            guard noScene else { return }
            lastIntrinsicTransformBaseScale = nil
            canvasDrawablePixelSize = .zero
        }
    }

    #if os(macOS)
    private func updateMacWindowTitle() {
        DispatchQueue.main.async {
            NSApp.mainWindow?.title = ""
        }
    }
    #endif
}

private extension View {
    @ViewBuilder
    func macSimulationTimelineArrowKeys(appState: AppState) -> some View {
        #if os(macOS)
        modifier(MacSimulationTimelineArrowKeyMonitor(appState: appState))
        #else
        self
        #endif
    }
}

#if os(macOS)
/// 启动页侧栏文件操作按钮：固定高度、较小圆角（避免系统 `bordered` 过于圆润）。
private struct StartupFileActionButtonStyle: ButtonStyle {
    enum Role {
        case secondary
        case primary
    }

    var role: Role
    /// 垂直高度（pt）
    static let height: CGFloat = 36
    /// 圆角：比系统 bordered 克制，略大于纯小方角
    private let cornerRadius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        let isPrimary = role == .primary
        return configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isPrimary ? Color.accentColor : Color.primary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(isPrimary ? 0.35 : 0.2),
                        lineWidth: 1
                    )
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct StartupSplitView: View {
    @ObservedObject var appState: AppState
    @State private var isManagingRecentList = false
    @State private var selectedRecentPaths: Set<String> = []

    private let columns = [
        GridItem(.adaptive(minimum: 210), spacing: 14)
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("EPANET 3")
                    .font(.title2.weight(.semibold))
                Text("新建空白管网或打开已有 .inp")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: StartupFileActionButtonStyle.height * 0.5) {
                    Button {
                        appState.newFile()
                    } label: {
                        Label("新建文件", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(StartupFileActionButtonStyle(role: .primary))
                    Button {
                        appState.openFile()
                    } label: {
                        Label("打开文件", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(StartupFileActionButtonStyle(role: .primary))
                }

                if let path = appState.filePath {
                    Text("最近路径")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            .padding(20)
            .frame(width: 260)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(AppColors.controlBackground)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("近期打开")
                        .font(.headline)
                    Spacer(minLength: 8)
                    if !appState.recentFiles.isEmpty {
                        Button {
                            if isManagingRecentList {
                                selectedRecentPaths.removeAll()
                            }
                            isManagingRecentList.toggle()
                        } label: {
                            Text(isManagingRecentList ? "完成" : "选择…")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.borderless)
                        .help(isManagingRecentList ? "退出多选" : "选择多项并从列表中移除（不删除文件）")
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)

                if isManagingRecentList && !selectedRecentPaths.isEmpty {
                    HStack(spacing: 12) {
                        Text("已选 \(selectedRecentPaths.count) 项")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("从列表中移除") {
                            appState.removeRecentFilesFromList(paths: Array(selectedRecentPaths))
                            selectedRecentPaths.removeAll()
                            if appState.recentFiles.isEmpty {
                                isManagingRecentList = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help("仅从「近期打开」中移除记录，不会删除磁盘上的文件")
                    }
                    .padding(.horizontal, 16)
                }

                if appState.recentFiles.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 22))
                            .foregroundColor(.secondary)
                        Text("暂无近期文件")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(appState.recentFiles) { item in
                                Group {
                                    if isManagingRecentList {
                                        Button {
                                            if selectedRecentPaths.contains(item.id) {
                                                selectedRecentPaths.remove(item.id)
                                            } else {
                                                selectedRecentPaths.insert(item.id)
                                            }
                                        } label: {
                                            ZStack(alignment: .topLeading) {
                                                RecentFileThumbnailCard(item: item)
                                                Image(systemName: selectedRecentPaths.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                                    .symbolRenderingMode(.hierarchical)
                                                    .foregroundStyle(.primary, Color.accentColor)
                                                    .font(.title3)
                                                    .padding(8)
                                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(
                                            selectedRecentPaths.contains(item.id)
                                                ? "已选，\(item.displayName)"
                                                : "未选，\(item.displayName)"
                                        )
                                    } else {
                                        Button {
                                            appState.openRecentFile(item)
                                        } label: {
                                            RecentFileThumbnailCard(item: item)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button("从最近列表中移除", systemImage: "xmark.circle") {
                                                appState.removeRecentFilesFromList(paths: [item.path])
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppColors.windowBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RecentFileThumbnailCard: View {
    let item: RecentFileItem

    private var openedText: String {
        item.lastOpenedAt.formatted(.dateTime.month().day().hour().minute())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.10))
                .overlay(
                    VStack(alignment: .leading, spacing: 5) {
                        Text(".inp")
                            .font(.caption2.monospaced())
                            .foregroundColor(.blue)
                        HStack(spacing: 10) {
                            Label {
                                Text(verbatim: String(item.nodeCount ?? 0))
                            } icon: {
                                Image(systemName: "smallcircle.filled.circle")
                            }
                            Label {
                                Text(verbatim: String(item.linkCount ?? 0))
                            } icon: {
                                Image(systemName: "line.diagonal")
                            }
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    .padding(10),
                    alignment: .topLeading
                )
                .frame(height: 92)

            Text(item.displayName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(openedText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(item.path)
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }
}

#endif

private struct NetworkTypeSummary {
    var junctions: Int = 0
    var tanks: Int = 0
    var reservoirs: Int = 0
    var pipes: Int = 0
    var valves: Int = 0
    var pumps: Int = 0

    var nodeTotal: Int { junctions + tanks + reservoirs }
    var linkTotal: Int { pipes + valves + pumps }
}

/// .inp 中无画布几何的对象：模式 / 曲线 / 简单控制的数量（与引擎 `EN_getCount` 一致）。
private struct InpInvisibleObjectCounts {
    var patterns: Int = 0
    var curves: Int = 0
    var controls: Int = 0
}

// MARK: - Result time-series chart panel

/// 底部图表：按选中对象类型展示逐时间步仿真结果。
private struct ResultTimeSeriesChartView: View {
    @ObservedObject var appState: AppState

    private var store: TimeSeriesResultStore? { appState.timeSeriesResults }
    private var project: EpanetProject? { appState.project }

    private var totalDuration: Int { appState.lastCompletedSimulationDurationSeconds ?? 0 }

    var body: some View {
        Group {
            if let store = store, store.stepCount >= 1 {
                if let ni = appState.selectedNodeIndex {
                    nodeChart(store: store, nodeIndex: ni)
                } else if let li = appState.selectedLinkIndex {
                    linkChart(store: store, linkIndex: li)
                } else {
                    placeholder("选中节点或管段以查看时序结果")
                }
            } else {
                placeholder("无可用时序数据")
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Node chart

    @ViewBuilder
    private func nodeChart(store: TimeSeriesResultStore, nodeIndex: Int) -> some View {
        if appState.chartPanelCurves.isEmpty {
            placeholder("在右侧「计算结果」中点击属性以添加曲线")
        } else {
            let nodeType = try? project?.getNodeType(index: nodeIndex)
            let params = nodeChartParams(for: nodeType ?? .junction)
            let seriesByKey: [String: [Float]] = {
                var m: [String: [Float]] = [:]
                for p in params {
                    guard let vals = store.nodeTimeSeries(nodeIndex: nodeIndex, param: p) else { continue }
                    if p == .tankLevel && vals.allSatisfy({ $0.isNaN }) { continue }
                    m[p.rawValue] = vals
                }
                return m
            }()
            if seriesByKey.isEmpty {
                placeholder("选中对象无可用数据")
            } else {
                let axis = Self.xAxisConfig(totalDurationSeconds: totalDuration)
                let dataPoints = Self.buildChartData(
                    timePoints: store.timePoints,
                    curves: appState.chartPanelCurves,
                    seriesByParam: seriesByKey,
                    divisor: axis.divisor
                )
                if dataPoints.isEmpty {
                    placeholder("所选属性暂无有效时序数据")
                } else {
                    let legendOrder = appState.chartPanelCurves.map(\.paramKey).filter { seriesByKey[$0] != nil }
                    chartBody(dataPoints: dataPoints, legendOrder: legendOrder)
                }
            }
        }
    }

    private func nodeChartParams(for type: NodeTypes) -> [NodeChartParam] {
        switch type {
        case .tank:      return [.tankLevel, .pressure, .head]
        case .reservoir: return [.head, .pressure, .demand]
        case .junction:  return [.pressure, .head, .demand]
        }
    }

    // MARK: - Link chart

    @ViewBuilder
    private func linkChart(store: TimeSeriesResultStore, linkIndex: Int) -> some View {
        if appState.chartPanelCurves.isEmpty {
            placeholder("在右侧「计算结果」中点击属性以添加曲线")
        } else {
            let linkType = try? project?.getLinkType(index: linkIndex)
            let params = linkChartParams(for: linkType ?? .pipe)
            let seriesByKey: [String: [Float]] = {
                var m: [String: [Float]] = [:]
                for p in params {
                    guard let vals = store.linkTimeSeries(linkIndex: linkIndex, param: p) else { continue }
                    m[p.rawValue] = vals
                }
                return m
            }()
            if seriesByKey.isEmpty {
                placeholder("选中对象无可用数据")
            } else {
                let axis = Self.xAxisConfig(totalDurationSeconds: totalDuration)
                let dataPoints = Self.buildChartData(
                    timePoints: store.timePoints,
                    curves: appState.chartPanelCurves,
                    seriesByParam: seriesByKey,
                    divisor: axis.divisor
                )
                if dataPoints.isEmpty {
                    placeholder("所选属性暂无有效时序数据")
                } else {
                    let legendOrder = appState.chartPanelCurves.map(\.paramKey).filter { seriesByKey[$0] != nil }
                    chartBody(dataPoints: dataPoints, legendOrder: legendOrder)
                }
            }
        }
    }

    private func linkChartParams(for type: LinkTypes) -> [LinkChartParam] {
        switch type {
        case .pump:                      return [.flow, .status]
        case .prv, .psv, .pbv, .fcv, .tcv, .gpv: return [.flow, .status]
        case .pipe, .cvpipe:             return [.flow, .velocity]
        }
    }

    // MARK: - Shared chart body

    @ViewBuilder
    private func chartBody(dataPoints: [ResultChartDataPoint], legendOrder: [String]) -> some View {
        let axis = Self.xAxisConfig(totalDurationSeconds: totalDuration)
        let playheadX = appState.simulationTimelinePlayheadSeconds / axis.divisor
        let hydStep = max(1, appState.lastCompletedSimulationHydraulicStepSeconds ?? 3600)
        let secTicks = Self.discreteTimePoints(duration: totalDuration, step: hydStep)
        let xAxisTickValues = secTicks.map { Double($0) / axis.divisor }

        ResultTimeSeriesChartContent(
            dataPoints: dataPoints,
            legendParamOrder: legendOrder,
            playheadX: playheadX,
            xDomain: axis.domain,
            xAxisTitle: axis.title,
            xAxisTickValues: xAxisTickValues
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 与 `SimulationDurationTimelineBar` 一致：0, Δt, 2Δt, …，末段不足一步则补总时长。
    private static func discreteTimePoints(duration: Int, step: Int) -> [Int] {
        guard duration > 0 else { return [0] }
        let s = max(1, step)
        var pts: [Int] = []
        var t = 0
        while true {
            pts.append(t)
            if t >= duration { break }
            let next = t + s
            if next >= duration {
                if pts.last != duration { pts.append(duration) }
                break
            }
            t = next
        }
        return pts
    }

    private static func buildChartData(
        timePoints: [Int],
        curves: [ChartPanelCurve],
        seriesByParam: [String: [Float]],
        divisor: Double
    ) -> [ResultChartDataPoint] {
        var pts: [ResultChartDataPoint] = []
        for curve in curves {
            guard let values = seriesByParam[curve.paramKey] else { continue }
            for (i, t) in timePoints.enumerated() where i < values.count {
                let v = values[i]
                guard !v.isNaN else { continue }
                pts.append(
                    ResultChartDataPoint(
                        param: curve.paramKey,
                        time: Double(t) / divisor,
                        value: Double(v),
                        axis: curve.axis
                    )
                )
            }
        }
        return pts
    }

    /// 横轴：与常见日仿真一致时优先用 **小时 0…T**；短时用分/秒。
    private static func xAxisConfig(totalDurationSeconds: Int) -> (divisor: Double, domain: ClosedRange<Double>, title: String) {
        let d = max(0, totalDurationSeconds)
        if d >= 3600 {
            let h = max(Double(d) / 3600.0, 1.0 / 3600.0)
            return (3600.0, 0...h, "时间 (h)")
        }
        if d >= 60 {
            let m = max(Double(d) / 60.0, 1.0 / 60.0)
            return (60.0, 0...m, "时间 (min)")
        }
        if d > 0 {
            return (1.0, 0...Double(d), "时间 (s)")
        }
        return (3600.0, 0...24, "时间 (h)")
    }

    // MARK: - Helpers

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct ResultChartDataPoint: Identifiable {
    let param: String
    let time: Double
    let value: Double
    let axis: ChartAxisSlot
    var id: String { "\(param)|\(time)|\(axis.rawValue)" }
}

/// 各序列量纲差异过大时拆成左/右 Y 轴；右轴为其余序列合并标度。
private struct DualAxisSplit {
    let useDual: Bool
    let left: [ResultChartDataPoint]
    let right: [ResultChartDataPoint]
    let leftYDomain: ClosedRange<Double>
    let rightYDomain: ClosedRange<Double>
}

/// 测量曲线区图例尺寸，供拖动时限制在绘图区内。
private struct ChartLegendContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct ResultTimeSeriesChartContent: View {
    let dataPoints: [ResultChartDataPoint]
    /// 图例顺序（与属性面板添加顺序一致）；为空时按参数字符串排序。
    let legendParamOrder: [String]
    let playheadX: Double
    let xDomain: ClosedRange<Double>
    let xAxisTitle: String
    /// 横轴刻度（与横轴单位一致：h / min / s），由水力时间步离散时刻换算而来。
    let xAxisTickValues: [Double]

    @Environment(\.colorScheme) private var colorScheme

    @State private var legendMeasuredSize: CGSize = .zero
    /// 相对「自动角落」基准位置的累计偏移（拖动结束后仍保留）。
    @State private var legendDragOffset: CGSize = .zero
    @State private var legendDragOffsetAtGestureStart: CGSize = .zero
    @State private var legendIsDragging: Bool = false

    /// 外层绘图区圆角容器（淡化）。
    private var chartPanelFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.03)
            : Color.black.opacity(0.02)
    }

    private var chartPanelStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.05)
            : Color.black.opacity(0.04)
    }

    private var gridColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.10)
    }

    /// 坐标轴线（绘图区底边与 Y 轴脊线）比网格线更明显。
    private var axisLineColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.42)
            : Color.black.opacity(0.36)
    }

    /// 落在横轴域内、去重后的刻度，供 `AxisMarks` 使用。
    private var effectiveXAxisTicks: [Double] {
        let lo = xDomain.lowerBound
        let hi = xDomain.upperBound
        let filtered = xAxisTickValues.filter { $0 >= lo - 1e-9 && $0 <= hi + 1e-9 }
        var u: [Double] = []
        for t in filtered.sorted() {
            if u.last == nil || abs(t - u.last!) > 1e-12 {
                u.append(t)
            }
        }
        if u.isEmpty {
            return [lo, hi]
        }
        return u
    }

    private var playheadClamped: Double {
        min(max(playheadX, xDomain.lowerBound), xDomain.upperBound)
    }

    private var y1Points: [ResultChartDataPoint] { dataPoints.filter { $0.axis == .y1 } }
    private var y2Points: [ResultChartDataPoint] { dataPoints.filter { $0.axis == .y2 } }
    private var useDualAxis: Bool { !y1Points.isEmpty && !y2Points.isEmpty }

    private var dualSplit: DualAxisSplit {
        Self.splitForDualNormalized(left: y1Points, right: y2Points)
    }

    private var legendParams: [String] {
        let names = Set(dataPoints.map(\.param))
        if !legendParamOrder.isEmpty {
            return legendParamOrder.filter { names.contains($0) }
        }
        return Array(names).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if useDualAxis {
                    dualAxisCombinedChart(split: dualSplit)
                } else if !y1Points.isEmpty {
                    singleAxisChart(
                        points: y1Points,
                        yDomain: Self.yDomain(for: y1Points),
                        yAxisLeading: true,
                        showLegend: false
                    )
                } else if !y2Points.isEmpty {
                    singleAxisChart(
                        points: y2Points,
                        yDomain: Self.yDomain(for: y2Points),
                        yAxisLeading: false,
                        showLegend: false
                    )
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(xAxisTitle)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 1)
        }
        .padding(.horizontal, useDualAxis ? 8 : 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(chartPanelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(chartPanelStroke, lineWidth: 0.5)
                }
        }
    }

    // MARK: - 图例（绘图区内，避开曲线，避不开则右上角）

    /// 图例圆角矩形边界与**绘图区**（坐标轴围成的曲线区）边缘的间隙（pt；@1x 下与 px 一致）。
    private static let legendPlotAxisMargin: CGFloat = 5

    /// 图例左上角在绘图区坐标系中的默认位置（四周与绘图区边缘保持 `margin`）。
    private static func legendBaseTopLeading(
        corner: Alignment,
        plotW: CGFloat,
        plotH: CGFloat,
        legendW: CGFloat,
        legendH: CGFloat,
        margin: CGFloat
    ) -> CGPoint {
        switch corner {
        case .topTrailing:
            return CGPoint(x: plotW - margin - legendW, y: margin)
        case .topLeading:
            return CGPoint(x: margin, y: margin)
        case .bottomTrailing:
            return CGPoint(x: plotW - margin - legendW, y: plotH - margin - legendH)
        case .bottomLeading:
            return CGPoint(x: margin, y: plotH - margin - legendH)
        default:
            return CGPoint(x: plotW - margin - legendW, y: margin)
        }
    }

    /// 将图例左上角限制在绘图区内（保留 `margin`）。
    private static func clampLegendTopLeft(
        origin: CGPoint,
        plotW: CGFloat,
        plotH: CGFloat,
        legendW: CGFloat,
        legendH: CGFloat,
        margin: CGFloat
    ) -> CGPoint {
        let maxX = max(margin, plotW - margin - legendW)
        let maxY = max(margin, plotH - margin - legendH)
        return CGPoint(
            x: min(max(origin.x, margin), maxX),
            y: min(max(origin.y, margin), maxY)
        )
    }

    /// 将相对基准的拖动增量限制在合法范围内。
    private static func clampDragOffset(
        _ drag: CGSize,
        base: CGPoint,
        plotW: CGFloat,
        plotH: CGFloat,
        legendW: CGFloat,
        legendH: CGFloat,
        margin: CGFloat
    ) -> CGSize {
        let ox = base.x + drag.width
        let oy = base.y + drag.height
        let c = clampLegendTopLeft(
            origin: CGPoint(x: ox, y: oy),
            plotW: plotW,
            plotH: plotH,
            legendW: legendW,
            legendH: legendH,
            margin: margin
        )
        return CGSize(width: c.x - base.x, height: c.y - base.y)
    }

    /// 首帧 `PreferenceKey` 尚未回填时，用行数与最长标签粗估图例尺寸，避免用极小宽高做 clamp 导致图例画出绘图区。
    private static func estimatedLegendSize(for params: [String]) -> CGSize {
        let rows = max(1, params.count)
        let longest = params.map(\.count).max() ?? 8
        let w = CGFloat(longest) * 6.5 + 120
        let h = CGFloat(rows) * 18 + 14
        return CGSize(width: min(max(w, 96), 360), height: max(h, 28))
    }

    /// 在数据归一化坐标中沿折线插值采样，用于判定四角曲线密度。
    private static func densifiedNormPoints(
        data: [ResultChartDataPoint],
        xDomain: ClosedRange<Double>,
        yDomainForAxis: (_ axis: ChartAxisSlot) -> ClosedRange<Double>
    ) -> [(Double, Double)] {
        let xLo = xDomain.lowerBound
        let xSpan = xDomain.upperBound - xLo
        guard xSpan > 0, xSpan.isFinite else { return [] }
        var out: [(Double, Double)] = []
        out.reserveCapacity(data.count * 8)
        for param in Set(data.map(\.param)) {
            let sorted = data.filter { $0.param == param }.sorted { $0.time < $1.time }
            let coords: [(Double, Double)] = sorted.compactMap { pt in
                let xn = (pt.time - xLo) / xSpan
                let yDom = yDomainForAxis(pt.axis)
                let yn = normalizedY(pt.value, domain: yDom)
                return (xn, yn)
            }
            guard coords.count >= 2 else {
                if let one = coords.first { out.append(one) }
                continue
            }
            for i in 0..<(coords.count - 1) {
                let a = coords[i], b = coords[i + 1]
                for s in 0..<7 {
                    let t = Double(s) / 6.0
                    out.append((a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t))
                }
            }
        }
        return out
    }

    /// 四角候选：在归一化空间中统计每个角落被曲线穿过的次数，选最少的；全部有则右上角。
    private static func bestPlotCorner(points: [(Double, Double)]) -> Alignment {
        let corners: [(Alignment, ClosedRange<Double>, ClosedRange<Double>)] = [
            (.topTrailing,    0.55...1.0, 0.55...1.0),
            (.topLeading,     0.0...0.45, 0.55...1.0),
            (.bottomTrailing, 0.55...1.0, 0.0...0.45),
            (.bottomLeading,  0.0...0.45, 0.0...0.45),
        ]
        guard !points.isEmpty else { return .topTrailing }
        var best = Alignment.topTrailing
        var minHits = Int.max
        for (align, xr, yr) in corners {
            let hits = points.filter { xr.contains($0.0) && yr.contains($0.1) }.count
            if hits < minHits {
                minHits = hits
                best = align
            }
        }
        return best
    }

    /// 与游标时刻最接近的数据点上的物理量（横轴单位与 `playheadClamped` 一致）。
    private func legendValueAtPlayhead(for paramKey: String) -> Double? {
        let pts = dataPoints.filter { $0.param == paramKey }.sorted { $0.time < $1.time }
        guard !pts.isEmpty else { return nil }
        let x = playheadClamped
        var best = pts[0]
        var bestDist = abs(pts[0].time - x)
        for p in pts.dropFirst() {
            let d = abs(p.time - x)
            if d < bestDist {
                bestDist = d
                best = p
            }
        }
        return best.value
    }

    private static func formatLegendPlayheadValue(paramKey: String, value: Double) -> String {
        switch paramKey {
        case NodeChartParam.head.rawValue, NodeChartParam.pressure.rawValue:
            return String(format: "%.2f", value)
        case NodeChartParam.demand.rawValue:
            return String(format: "%.4f", value)
        case NodeChartParam.tankLevel.rawValue:
            return String(format: "%.2f", value)
        case LinkChartParam.flow.rawValue, LinkChartParam.velocity.rawValue:
            return NumericDisplayFormat.formatLinkFlowOrVelocity(value)
        case LinkChartParam.headloss.rawValue, LinkChartParam.status.rawValue:
            return String(format: "%.4f", value)
        default:
            let av = abs(value)
            if value != 0, (av < 1e-4 || av >= 1e6) { return String(format: "%.4e", value) }
            return String(format: "%.4f", value)
        }
    }

    /// 图例块视图（样式）；第二列为当前时刻数值，**右对齐**；`Grid` 统一列宽，数字列齐右缘。
    private var legendPillContent: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            ForEach(Array(legendParams.enumerated()), id: \.offset) { _, name in
                GridRow(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Capsule()
                            .fill(Self.seriesColor(param: name, among: legendParams))
                            .frame(width: 10, height: 3)
                        Text(name)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Group {
                        if let v = legendValueAtPlayhead(for: name) {
                            Text(Self.formatLegendPlayheadValue(paramKey: name, value: v))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        } else {
                            Text("—")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(colorScheme == .dark ? Color.black.opacity(0.50) : Color.white.opacity(0.88))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                }
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.10), radius: 3, y: 1)
        /// 避免 overlay 内 `Spacer` 把图例拉满 plot 宽度；按内容紧凑排版。
        .fixedSize(horizontal: true, vertical: false)
    }

    /// macOS 14+ / iOS 17+：`ChartProxy.plotFrame` 与真实曲线区一致；低版本 overlay 仅覆盖整块 chart 区（与轴标签可能对齐略差）。
    private static func resolvedChartPlotRect(geo: GeometryProxy, chartProxy: ChartProxy) -> CGRect {
        if #available(macOS 14.0, iOS 17.0, *) {
            if let anchor = chartProxy.plotFrame {
                return geo[anchor]
            }
        }
        return CGRect(origin: .zero, size: geo.size)
    }

    /// 绘图区内可拖动的图例：使用 `chartOverlay` +（可用时）`ChartProxy.plotFrame`；用 padding 布局以便命中区域与视觉一致。
    @ViewBuilder
    private func chartLegendDraggableOverlay(corner: Alignment, chartProxy: ChartProxy) -> some View {
        GeometryReader { geo in
            let plotRect = Self.resolvedChartPlotRect(geo: geo, chartProxy: chartProxy)
            let plotW = max(plotRect.width, 1)
            let plotH = max(plotRect.height, 1)
            let m = Self.legendPlotAxisMargin
            let est = Self.estimatedLegendSize(for: legendParams)
            let wRaw = max(legendMeasuredSize.width > 0 ? legendMeasuredSize.width : est.width, 40)
            let hRaw = max(legendMeasuredSize.height > 0 ? legendMeasuredSize.height : est.height, 24)
            /// 图例实际可能比绘图区宽/高，clamp 时用「可容纳」尺寸，避免算出的位置仍把图例画到坐标轴外。
            let w = min(wRaw, max(1, plotW - 2 * m))
            let h = min(hRaw, max(1, plotH - 2 * m))
            let base = Self.legendBaseTopLeading(
                corner: corner,
                plotW: plotW,
                plotH: plotH,
                legendW: w,
                legendH: h,
                margin: m
            )
            let topLeft = Self.clampLegendTopLeft(
                origin: CGPoint(
                    x: base.x + legendDragOffset.width,
                    y: base.y + legendDragOffset.height
                ),
                plotW: plotW,
                plotH: plotH,
                legendW: w,
                legendH: h,
                margin: m
            )
            ZStack(alignment: .topLeading) {
                legendPillContent
                    .background {
                        GeometryReader { g in
                            Color.clear.preference(key: ChartLegendContentSizeKey.self, value: g.size)
                        }
                    }
                    .onPreferenceChange(ChartLegendContentSizeKey.self) { legendMeasuredSize = $0 }
                    .padding(.leading, plotRect.minX + topLeft.x)
                    .padding(.top, plotRect.minY + topLeft.y)
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { v in
                                if !legendIsDragging {
                                    legendDragOffsetAtGestureStart = legendDragOffset
                                    legendIsDragging = true
                                }
                                let proposed = CGSize(
                                    width: legendDragOffsetAtGestureStart.width + v.translation.width,
                                    height: legendDragOffsetAtGestureStart.height + v.translation.height
                                )
                                legendDragOffset = Self.clampDragOffset(
                                    proposed,
                                    base: base,
                                    plotW: plotW,
                                    plotH: plotH,
                                    legendW: w,
                                    legendH: h,
                                    margin: m
                                )
                            }
                            .onEnded { _ in
                                legendIsDragging = false
                            }
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: corner) { _ in
            legendDragOffset = .zero
        }
        .onChange(of: legendParams) { _ in
            legendDragOffset = .zero
        }
    }

    private func dualAxisNormalize(_ v: Double, domain: ClosedRange<Double>) -> Double {
        let lo = domain.lowerBound
        let hi = domain.upperBound
        let span = hi - lo
        guard span.isFinite, span > 0 else { return 0.5 }
        let t = (v - lo) / span
        return min(max(t, 0), 1)
    }

    /// 双轴归一化图：用 `niceDomainAndTicks` 保证 domain 边界就是整齐刻度值，
    /// 等分后「像素等距」与「数字等距」天然一致——不再依赖 denormalize + 格式化。
    private func dualAxisCombinedChart(split: DualAxisSplit) -> some View {
        let (leftDom, leftTicks) = Self.niceDomainAndTicks(for: split.left, maxTicks: 7)
        let (rightDom, rightTicks) = Self.niceDomainAndTicks(for: split.right, maxTicks: 7)
        let leftNormTicks = Self.uniformNormYTicks(intervals: max(1, leftTicks.count - 1))
        let rightNormTicks = Self.uniformNormYTicks(intervals: max(1, rightTicks.count - 1))
        let leftStep = leftTicks.count >= 2 ? leftTicks[1] - leftTicks[0] : 1.0
        let rightStep = rightTicks.count >= 2 ? rightTicks[1] - rightTicks[0] : 1.0
        let leftByParam = Dictionary(grouping: split.left, by: \.param)
        let rightByParam = Dictionary(grouping: split.right, by: \.param)
        let dualPts = Self.densifiedNormPoints(data: dataPoints, xDomain: xDomain) { axis in
            axis == .y1 ? leftDom : rightDom
        }
        let dualAlign = Self.bestPlotCorner(points: dualPts)
        return Chart {
            ForEach(leftByParam.keys.sorted(), id: \.self) { param in
                let pts = (leftByParam[param] ?? []).sorted { $0.time < $1.time }
                ForEach(pts) { pt in
                    LineMark(
                        x: .value("时间", pt.time),
                        y: .value("y", dualAxisNormalize(pt.value, domain: leftDom))
                    )
                    .foregroundStyle(by: .value("序列", pt.param))
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                }
            }
            ForEach(rightByParam.keys.sorted(), id: \.self) { param in
                let pts = (rightByParam[param] ?? []).sorted { $0.time < $1.time }
                ForEach(pts) { pt in
                    LineMark(
                        x: .value("时间", pt.time),
                        y: .value("y", dualAxisNormalize(pt.value, domain: rightDom))
                    )
                    .foregroundStyle(by: .value("序列", pt.param))
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                }
            }
            RuleMark(x: .value("当前", playheadClamped))
                .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [5, 4]))
                .foregroundStyle(Color.accentColor.opacity(0.85))
        }
        .chartForegroundStyleScale(domain: legendParams) { param in
            Self.seriesColor(param: param, among: legendParams)
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...1)
        .chartXAxis {
            AxisMarks(values: effectiveXAxisTicks) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(gridColor.opacity(0.5))
                AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 0.65))
                    .foregroundStyle(axisLineColor)
                AxisValueLabel()
                    .font(.system(size: 9, weight: .medium, design: .rounded))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: leftNormTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(gridColor.opacity(0.4))
                AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 0.65))
                    .foregroundStyle(axisLineColor)
                AxisValueLabel {
                    if let yNorm = value.as(Double.self) {
                        let k = leftTicks.count - 1
                        let j = min(max(0, Int(round(yNorm * Double(k)))), k)
                        Text(Self.formatTickLabel(leftTicks[j], step: leftStep))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                    }
                }
            }
            AxisMarks(position: .trailing, values: rightNormTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.clear)
                AxisTick(length: 5, stroke: StrokeStyle(lineWidth: 0.75))
                    .foregroundStyle(axisLineColor)
                AxisValueLabel {
                    if let yNorm = value.as(Double.self) {
                        let k = rightTicks.count - 1
                        let j = min(max(0, Int(round(yNorm * Double(k)))), k)
                        Text(Self.formatTickLabel(rightTicks[j], step: rightStep))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.primary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot
                .background {
                    ZStack(alignment: .bottomLeading) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle()
                                .fill(axisLineColor)
                                .frame(height: 2.25)
                        }
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(axisLineColor)
                                .frame(width: 2.25)
                            Spacer(minLength: 0)
                            Rectangle()
                                .fill(axisLineColor)
                                .frame(width: 2.25)
                        }
                    }
                }
        }
        .chartOverlay { proxy in
            Group {
                if !legendParams.isEmpty {
                    chartLegendDraggableOverlay(corner: dualAlign, chartProxy: proxy)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 水力逐步数据用线性连接；Catmull-Rom 会在端点外越界，表现为「流速早于 0 时刻」。
    private func lineMarksChart(
        points: [ResultChartDataPoint],
        showRule: Bool
    ) -> some View {
        let byParam = Dictionary(grouping: points, by: \.param)
        return Chart {
            ForEach(byParam.keys.sorted(), id: \.self) { param in
                let pts = (byParam[param] ?? []).sorted { $0.time < $1.time }
                ForEach(pts) { pt in
                    LineMark(
                        x: .value("时间", pt.time),
                        y: .value("v", pt.value)
                    )
                    .foregroundStyle(by: .value("序列", pt.param))
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                }
            }
            if showRule {
                RuleMark(x: .value("当前", playheadClamped))
                    .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [5, 4]))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
            }
        }
    }

    private func singleAxisChart(
        points: [ResultChartDataPoint],
        yDomain: ClosedRange<Double>,
        yAxisLeading: Bool,
        showLegend: Bool,
        showRule: Bool = true
    ) -> some View {
        let paramsOrdered = legendParams
        let yTicks = Self.niceAxisTickValues(domain: yDomain, maxTicks: 6)
        let yTickStep = Self.inferredTickStep(ticks: yTicks, domain: yDomain)
        let singlePts = Self.densifiedNormPoints(data: points, xDomain: xDomain) { _ in yDomain }
        let singleAlign = Self.bestPlotCorner(points: singlePts)
        return lineMarksChart(points: points, showRule: showRule)
            .chartForegroundStyleScale(domain: paramsOrdered) { param in
                Self.seriesColor(param: param, among: paramsOrdered)
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: effectiveXAxisTicks) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(gridColor.opacity(0.5))
                    AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 0.65))
                        .foregroundStyle(axisLineColor)
                    AxisValueLabel()
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                }
            }
            .chartYAxis {
                AxisMarks(position: yAxisLeading ? .leading : .trailing, values: yTicks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(yAxisLeading ? gridColor.opacity(0.4) : .clear)
                    AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 0.65))
                        .foregroundStyle(axisLineColor)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(Self.formatTickLabel(v, step: yTickStep))
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartPlotStyle { plot in
                plot
                    .background {
                        ZStack(alignment: .bottomLeading) {
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                Rectangle()
                                    .fill(axisLineColor)
                                    .frame(height: 2.25)
                            }
                            HStack(spacing: 0) {
                                if yAxisLeading {
                                    Rectangle()
                                        .fill(axisLineColor)
                                        .frame(width: 2.25)
                                }
                                Spacer(minLength: 0)
                                if !yAxisLeading {
                                    Rectangle()
                                        .fill(axisLineColor)
                                        .frame(width: 2.25)
                                }
                            }
                        }
                    }
            }
            .chartOverlay { proxy in
                Group {
                    if !legendParams.isEmpty {
                        chartLegendDraggableOverlay(corner: singleAlign, chartProxy: proxy)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let seriesPalette: [Color] = [
        Color.accentColor, .orange, .green, .purple, .pink, .cyan
    ]

    private static func seriesColor(param: String, among ordered: [String]) -> Color {
        let idx = ordered.firstIndex(of: param) ?? 0
        return seriesPalette[idx % seriesPalette.count]
    }

    // MARK: - 整齐 Y 轴刻度（1/2/2.5/5/10 × 10ⁿ）

    /// 将 `approximate` 调整为 1、2、2.5、5、10 × 10ⁿ 中最接近的「整齐」步长。
    private static func niceStep(approximate: Double) -> Double {
        guard approximate.isFinite, approximate > 0 else { return 1 }
        let exp = floor(log10(approximate))
        let f = approximate / pow(10, exp)
        let nf: Double
        if f <= 1 { nf = 1 }
        else if f <= 2 { nf = 2 }
        else if f <= 2.5 { nf = 2.5 }
        else if f <= 5 { nf = 5 }
        else { nf = 10 }
        return nf * pow(10, exp)
    }

    /// 在 `domain` 内生成约 `maxTicks` 条等间隔的整齐刻度（落在 [lo,hi] 内）。
    private static func niceAxisTickValues(domain: ClosedRange<Double>, maxTicks: Int = 6) -> [Double] {
        let lo = domain.lowerBound
        let hi = domain.upperBound
        let span = hi - lo
        guard span > 0, span.isFinite else {
            return lo.isFinite ? [lo] : [0, 1]
        }
        let cap = max(2, maxTicks)
        var step = niceStep(approximate: span / Double(max(1, cap - 1)))
        if step <= 0 { step = span }
        for _ in 0..<10 {
            var t = floor(lo / step) * step
            while t < lo - 1e-12 * max(abs(step), 1) {
                t += step
            }
            var ticks: [Double] = []
            while t <= hi + 1e-9 * max(abs(step), 1) {
                ticks.append(t)
                t += step
                if ticks.count > 64 { break }
            }
            if ticks.count <= max(cap + 1, 3) { return ticks }
            step *= 2
        }
        return [lo, hi]
    }

    private static func inferredTickStep(ticks: [Double], domain: ClosedRange<Double>) -> Double {
        guard ticks.count >= 2 else {
            let span = domain.upperBound - domain.lowerBound
            return niceStep(approximate: max(span / 5, 1e-9))
        }
        let s = ticks[1] - ticks[0]
        return s > 0 && s.isFinite ? s : niceStep(approximate: (domain.upperBound - domain.lowerBound) / 5)
    }

    private static func decimalsForTickStep(_ step: Double) -> Int {
        guard step > 0, step.isFinite else { return 2 }
        for d in 0...6 {
            let scaled = step * pow(10.0, Double(d))
            if abs(scaled - scaled.rounded()) < 1e-6 { return d }
        }
        return 2
    }

    /// 刻度数字格式：与步长匹配的小数位，避免出现 110.37 这类杂乱刻度。
    private static func formatTickLabel(_ v: Double, step: Double) -> String {
        let eps = max(abs(step) * 1e-6, 1e-12)
        if abs(v) <= eps {
            let dec = decimalsForTickStep(step)
            return dec == 0 ? "0" : String(format: "%.*f", dec, 0.0)
        }
        let av = abs(v)
        if av != 0, (av < 1e-4 || av >= 1e6) { return String(format: "%.2e", v) }
        let dec = decimalsForTickStep(step)
        return String(format: "%.*f", dec, v)
    }

    /// 双轴共用 Y：在 0…1 上等分（与曲线归一化一致），保证水平网格与两侧标签间隔在物理上均为线性等距。
    private static func uniformNormYTicks(intervals: Int) -> [Double] {
        let k = max(1, intervals)
        return (0...k).map { Double($0) / Double(k) }
    }

    private static func normalizedY(_ v: Double, domain: ClosedRange<Double>) -> Double {
        let lo = domain.lowerBound
        let hi = domain.upperBound
        let span = hi - lo
        guard span.isFinite, span > 0 else { return 0.5 }
        let t = (v - lo) / span
        return min(max(t, 0), 1)
    }

    private static func yDomain(for points: [ResultChartDataPoint]) -> ClosedRange<Double> {
        let vals = points.map(\.value).filter { !$0.isNaN && $0.isFinite }
        guard let lo = vals.min(), let hi = vals.max() else { return 0...1 }
        if lo == hi {
            let e = max(abs(lo) * 0.05, 0.01)
            return (lo - e)...(hi + e)
        }
        let pad = (hi - lo) * 0.06
        return (lo - pad)...(hi + pad)
    }

    /// 用 `niceAxisTickValues` 生成整齐刻度，再把 domain 设为 firstTick...lastTick。
    /// 这样等分 domain 后每个刻度恰好是 niceStep 的整数倍 → 像素等距 **且** 数字等距。
    private static func niceDomainAndTicks(for points: [ResultChartDataPoint], maxTicks: Int = 7) -> (domain: ClosedRange<Double>, ticks: [Double]) {
        let rawDomain = yDomain(for: points)
        let ticks = niceAxisTickValues(domain: rawDomain, maxTicks: maxTicks)
        guard let first = ticks.first, let last = ticks.last, first < last else {
            let lo = rawDomain.lowerBound, hi = rawDomain.upperBound
            return (rawDomain, lo < hi ? [lo, hi] : [lo])
        }
        return (first...last, ticks)
    }

    private static func splitForDualNormalized(left: [ResultChartDataPoint], right: [ResultChartDataPoint]) -> DualAxisSplit {
        DualAxisSplit(
            useDual: true,
            left: left,
            right: right,
            leftYDomain: yDomain(for: left),
            rightYDomain: yDomain(for: right)
        )
    }
}

#if os(macOS)
/// 仿真总时长：数值叠在滑块轨道上（随拇指移动）；单位在滑块末端；仅在水力时间步对应的离散时刻间跳动。
private struct SimulationDurationTimelineBar: View {
    let durationSeconds: Int
    /// 水力时间步长（秒），与 `[TIMES] Hydraulic Timestep` 一致。
    let hydraulicStepSeconds: Int
    @Binding var playheadSeconds: Double

    private var discreteTimePoints: [Int] {
        Self.discreteTimePoints(duration: durationSeconds, step: max(1, hydraulicStepSeconds))
    }

    /// 与引擎一致：0, Δt, 2Δt, …，末段不足一步则补总时长。
    private static func discreteTimePoints(duration: Int, step: Int) -> [Int] {
        guard duration > 0 else { return [0] }
        let s = max(1, step)
        var pts: [Int] = []
        var t = 0
        while true {
            pts.append(t)
            if t >= duration { break }
            let next = t + s
            if next >= duration {
                if pts.last != duration { pts.append(duration) }
                break
            }
            t = next
        }
        return pts
    }

    private static func nearestPointIndex(_ seconds: Double, points: [Int]) -> Int {
        guard !points.isEmpty else { return 0 }
        let s = Int(seconds.rounded())
        var bestIdx = 0
        var bestDist = Int.max
        for (i, p) in points.enumerated() {
            let d = abs(p - s)
            if d < bestDist { bestDist = d; bestIdx = i }
        }
        return bestIdx
    }

    private func indexBinding(points: [Int]) -> Binding<Double> {
        Binding(
            get: { Double(Self.nearestPointIndex(playheadSeconds, points: points)) },
            set: { v in
                let n = points.count
                guard n > 0 else { return }
                let i = min(max(0, Int(v.rounded())), n - 1)
                playheadSeconds = Double(points[i])
            }
        )
    }

    /// 拆成「数字」与「单位」，单位固定画在滑块右端；时钟样式无单独单位。
    private static func splitTimeDisplay(seconds: Double, totalDurationSeconds: Int) -> (numeric: String, unit: String) {
        let T = totalDurationSeconds
        let s = max(0, seconds)
        if T >= 3600 && T % 3600 == 0 {
            let h = s / 3600.0
            if abs(h - round(h)) < 1e-5 {
                return ("\(Int(round(h)))", "h")
            }
            let d = String(format: "%.1f", h)
            let num = d.hasSuffix(".0") ? String(d.dropLast(2)) : d
            return (num, "h")
        }
        if T >= 60 && T % 60 == 0 {
            let m = s / 60.0
            if abs(m - round(m)) < 1e-5 {
                return ("\(Int(round(m)))", "m")
            }
            let d = String(format: "%.1f", m)
            let num = d.hasSuffix(".0") ? String(d.dropLast(2)) : d
            return (num, "m")
        }
        if T < 60 {
            return ("\(Int(floor(s + 0.5)))", "s")
        }
        let sec = Int(floor(s + 0.5))
        return (formatClockFallback(sec), "")
    }

    private static func formatTimeForDisplay(seconds: Double, totalDurationSeconds: Int) -> String {
        let (n, u) = splitTimeDisplay(seconds: seconds, totalDurationSeconds: totalDurationSeconds)
        if u.isEmpty { return n }
        return "\(n)\(u)"
    }

    private static func formatClockFallback(_ sec: Int) -> String {
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private var playheadClamped: Double {
        let d = Double(durationSeconds)
        return min(max(playheadSeconds, 0), d)
    }

    /// 与 NSSlider 拇指大致对齐的水平 inset（大号滑块经验值）。
    private static let sliderHorizontalInset: CGFloat = 15

    private static let sliderRowHeight: CGFloat = 32

    var body: some View {
        let points = discreteTimePoints
        let maxIdx = max(0, points.count - 1)
        let idx = Self.nearestPointIndex(playheadSeconds, points: points)
        let parts = Self.splitTimeDisplay(seconds: playheadClamped, totalDurationSeconds: durationSeconds)
        HStack(alignment: .center, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let inset = Self.sliderHorizontalInset
                let usable = max(1, w - inset * 2)
                let frac: CGFloat = maxIdx > 0 ? CGFloat(idx) / CGFloat(maxIdx) : 0.5
                let x = inset + frac * usable
                ZStack(alignment: .leading) {
                    // 不使用 `step:`，否则 macOS 会在轨道下方绘制离散刻度点；离散时刻在 `indexBinding` 中四舍五入。
                    Slider(value: indexBinding(points: points), in: 0...Double(maxIdx))
                        .controlSize(.large)
                        .tint(.accentColor)
                    Text(parts.numeric)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .shadow(color: .black.opacity(0.22), radius: 0, x: 0, y: 0.5)
                        .shadow(color: .white.opacity(0.55), radius: 0, x: 0, y: -0.5)
                        .position(x: x, y: geo.size.height * 0.5)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: Self.sliderRowHeight)
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .frame(width: 320)
        .onAppear {
            guard !points.isEmpty else { return }
            let i = Self.nearestPointIndex(playheadSeconds, points: points)
            playheadSeconds = Double(points[i])
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "仿真时刻 \(Self.formatTimeForDisplay(seconds: playheadClamped, totalDurationSeconds: durationSeconds))，水力步长 \(hydraulicStepSeconds) 秒"
        )
        .help("按水力时间步（\(hydraulicStepSeconds) 秒）离散拖动选择时刻；键盘左右方向键步进同一离散时刻（在文本框内编辑时不占用）")
    }
}

#if os(macOS)
/// 主窗口内监听 ←/→：在扩展时段仿真成功完成后按水力步长步进时间轴（与工具栏滑块一致）；文本输入焦点下不拦截。
private struct MacSimulationTimelineArrowKeyMonitor: ViewModifier {
    @ObservedObject var appState: AppState
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear { install() }
            .onDisappear { remove() }
    }

    private func install() {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [appState] event in
            guard event.keyCode == 123 || event.keyCode == 124 else { return event }
            guard !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.control),
                  !event.modifierFlags.contains(.option) else { return event }
            if MacKeyResponderChecks.isLikelyTextEditing(NSApp.keyWindow?.firstResponder) {
                return event
            }
            appState.stepSimulationTimelinePlayheadDiscreteSteps(event.keyCode == 123 ? -1 : 1)
            return nil
        }
    }

    private func remove() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}

private enum MacKeyResponderChecks {
    static func isLikelyTextEditing(_ responder: NSResponder?) -> Bool {
        guard let r = responder else { return false }
        if r is NSTextView || r is NSTextField { return true }
        let name = String(describing: type(of: r))
        if name.contains("TextField") || name.contains("TextEditor") || name.contains("TextView") { return true }
        return false
    }
}
#endif

private struct MacDesignToolbar: View {
    @ObservedObject var appState: AppState

    /// 已加载 EPANET 工程（可编辑、可计算、可结果上图）；空白画布仅有 scene 时为 false。
    private var documentReady: Bool { appState.project != nil }
    /// 扩展时段仿真成功完成后显示时间轴（总时长 > 0）。
    private var showSimulationDurationTimeline: Bool {
        guard !appState.isRunning,
              let d = appState.lastCompletedSimulationDurationSeconds, d > 0,
              let r = appState.runResult,
              case .success = r else { return false }
        return true
    }

    private func timelinePlayheadBinding(totalSeconds: Int) -> Binding<Double> {
        Binding(
            get: {
                let d = Double(totalSeconds)
                return min(max(appState.simulationTimelinePlayheadSeconds, 0), d)
            },
            set: { appState.simulationTimelinePlayheadSeconds = $0 }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            // MARK: Undo/Redo 快捷按钮
            HStack(spacing: 2) {
                Button {
                    appState.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 26)
                        .foregroundColor(appState.canUndo ? .primary : .secondary.opacity(0.4))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!appState.canUndo)
                .help("撤销 (Undo)")

                Button {
                    appState.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 26)
                        .foregroundColor(appState.canRedo ? .primary : .secondary.opacity(0.4))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!appState.canRedo)
                .help("重做 (Redo)")
            }

            if appState.isTopologyEditingEnabled {
                Divider().frame(height: 24)
                HStack(spacing: 4) {
                    ForEach(CanvasPlacementTool.allCases, id: \.self) { tool in
                        let active = appState.activeCanvasPlacementTool == tool
                        let help = topologyToolbarHelp(for: tool)
                        Button {
                            if appState.activeCanvasPlacementTool == tool {
                                _ = appState.cancelCanvasPlacementIfActive()
                                appState.setEditorMode(.browse)
                            } else {
                                appState.beginCanvasPlacement(tool)
                            }
                        } label: {
                            TopologyToolbarLegendIcon(tool: tool)
                                .frame(width: 30, height: 26)
                                .background(active ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(!appState.canEditTopologyOnCanvas)
                        .help(help)
                    }
                    Divider().frame(height: 22)
                    Button {
                        appState.deleteSelectedObject()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 30, height: 26)
                            .foregroundStyle(.primary)
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(!documentReady || (appState.selectedNodeIndices.isEmpty && appState.selectedLinkIndices.isEmpty))
                    .help("删除当前选中的节点或管段")
                }
            }

            Divider().frame(height: 24)

            Picker(selection: Binding(
                get: { appState.resultOverlayMode },
                set: { appState.setResultOverlayMode($0) }
            )) {
                Text("图例").tag(ResultOverlayMode.none)
                Text("压力").tag(ResultOverlayMode.pressure)
                Text("流量").tag(ResultOverlayMode.flow)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .disabled(!documentReady)
            .help(documentReady ? "结果上色模式" : "需先打开或保存为含 EPANET 模型的 .inp 后使用")

            Button {
                appState.openMacSettingsDisplayLabelSection()
            } label: {
                Image(systemName: "textformat")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("标注设置")

            Spacer()

            HStack(alignment: .center, spacing: 6) {
                if showSimulationDurationTimeline, let sec = appState.lastCompletedSimulationDurationSeconds {
                    SimulationDurationTimelineBar(
                        durationSeconds: sec,
                        hydraulicStepSeconds: max(1, appState.lastCompletedSimulationHydraulicStepSeconds ?? 3600),
                        playheadSeconds: timelinePlayheadBinding(totalSeconds: sec)
                    )
                }
                Button {
                    appState.runCalculation()
                } label: {
                    Label("运行计算", systemImage: "play.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.canRunHydraulicSolver || appState.isRunning)
                .help(appState.canRunHydraulicSolver ? "在当前 .inp 上运行水力求解" : "请先打开已保存的 .inp 或保存空白文档后再计算")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [Color(NSColor(calibratedWhite: 0.98, alpha: 1)), Color(NSColor(calibratedWhite: 0.95, alpha: 1))],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.2)), alignment: .bottom)
    }

    private func topologyToolbarHelp(for tool: CanvasPlacementTool) -> String {
        switch tool {
        case .junction: return "新增节点（单击画布）"
        case .tankTower: return "新增水塔（凹角方块，单击画布）"
        case .tankPool: return "新增水库（梯形符号，单击画布）"
        case .pipe: return "新增管段（连续多点成链；空白处自动建节点；Esc/右键结束当前链）"
        case .valve: return "新增阀门（连续多点成链；空白处自动建节点；Esc/右键结束当前链）"
        case .pump: return "新增水泵（连续多点成链；空白处自动建节点；Esc/右键结束当前链）"
        }
    }

}

private struct MacDesignSidebar: View {
    @ObservedObject var appState: AppState
    @AppStorage("settings.display.layer.junction") private var layerJunction = true
    @AppStorage("settings.display.layer.reservoir") private var layerReservoir = true
    @AppStorage("settings.display.layer.tank") private var layerTank = true
    @AppStorage("settings.display.layer.pipe") private var layerPipe = true
    @AppStorage("settings.display.layer.pump") private var layerPump = true
    @AppStorage("settings.display.layer.valve") private var layerValve = true

    private var documentReady: Bool { appState.project != nil }

    private var counts: NetworkTypeSummary {
        guard let p = appState.project else { return NetworkTypeSummary() }
        var summary = NetworkTypeSummary()
        do {
            let nodeCount = try p.nodeCount()
            for i in 0..<nodeCount {
                switch try p.getNodeType(index: i) {
                case .junction: summary.junctions += 1
                case .tank: summary.tanks += 1
                case .reservoir: summary.reservoirs += 1
                }
            }
            let linkCount = try p.linkCount()
            for i in 0..<linkCount {
                switch try p.getLinkType(index: i) {
                case .pipe, .cvpipe: summary.pipes += 1
                case .pump: summary.pumps += 1
                default: summary.valves += 1
                }
            }
        } catch {
            return summary
        }
        return summary
    }

    private var invisibleCounts: InpInvisibleObjectCounts {
        guard let p = appState.project else { return InpInvisibleObjectCounts() }
        do {
            return InpInvisibleObjectCounts(
                patterns: try p.patternCount(),
                curves: try p.curveCount(),
                controls: try p.controlCount()
            )
        } catch {
            return InpInvisibleObjectCounts()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("图层")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // 单层列表：节点类与管段类不分组；管段类顺序为 阀门 → 管段 → 水泵
            if counts.junctions > 0 {
                MacTreeRow(
                    title: "节点", count: counts.junctions, icon: "circle.fill", tint: Color(white: 0.35), layerToggle: $layerJunction,
                    layerTableKind: .junction, canOpenObjectTable: documentReady,
                    onOpenObjectTable: { appState.openObjectTable($0) }
                )
            }
            if counts.tanks > 0 {
                MacTreeRow(
                    title: "水塔", count: counts.tanks, icon: "", tint: .green, layerToggle: $layerTank, tankNotchedSquare: true,
                    layerTableKind: .tank, canOpenObjectTable: documentReady,
                    onOpenObjectTable: { appState.openObjectTable($0) }
                )
            }
            if counts.reservoirs > 0 {
                MacTreeRow(
                    title: "水库", count: counts.reservoirs, icon: "", tint: .purple, layerToggle: $layerReservoir, reservoirTrapezoid: true,
                    layerTableKind: .reservoir, canOpenObjectTable: documentReady,
                    onOpenObjectTable: { appState.openObjectTable($0) }
                )
            }
            if counts.valves > 0 {
                MacTreeRow(
                    title: "阀门", count: counts.valves, icon: "", tint: .blue, layerToggle: $layerValve, valveBowtie: true,
                    layerTableKind: .valve, canOpenObjectTable: documentReady,
                    onOpenObjectTable: { appState.openObjectTable($0) }
                )
            }
            if counts.pipes > 0 {
                MacTreeRow(
                    title: "管段", count: counts.pipes, icon: "line.diagonal", tint: .gray, layerToggle: $layerPipe,
                    layerTableKind: .pipe, canOpenObjectTable: documentReady,
                    onOpenObjectTable: { appState.openObjectTable($0) }
                )
            }
            if counts.pumps > 0 {
                MacTreeRow(
                    title: "水泵", count: counts.pumps, icon: "", tint: .red, layerToggle: $layerPump, pumpHollowCircleTriangle: true,
                    layerTableKind: .pump, canOpenObjectTable: documentReady,
                    onOpenObjectTable: { appState.openObjectTable($0) }
                )
            }

            if documentReady {
                Text("不可见对象")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                MacTreeRow(
                    title: "模式",
                    count: invisibleCounts.patterns,
                    icon: "waveform.path",
                    tint: .secondary,
                    layerToggle: nil,
                    layerTableKind: nil,
                    canOpenObjectTable: false,
                    onOpenObjectTable: nil,
                    onTapRow: documentReady ? { appState.openInpSectionDetail(.patterns) } : nil
                )
                MacTreeRow(
                    title: "曲线",
                    count: invisibleCounts.curves,
                    icon: "chart.xyaxis.line",
                    tint: .secondary,
                    layerToggle: nil,
                    layerTableKind: nil,
                    canOpenObjectTable: false,
                    onOpenObjectTable: nil,
                    onTapRow: documentReady ? { appState.openInpSectionDetail(.curves) } : nil
                )
                MacTreeRow(
                    title: "控制",
                    count: invisibleCounts.controls,
                    icon: "slider.horizontal.3",
                    tint: .secondary,
                    layerToggle: nil,
                    layerTableKind: nil,
                    canOpenObjectTable: false,
                    onOpenObjectTable: nil,
                    onTapRow: documentReady ? { appState.openInpSectionDetail(.controls) } : nil
                )
            }

            Divider().padding(.vertical, 8)

            Text("搜索")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            TextField("按 ID 或名称...", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .disabled(true)

            Spacer()
        }
        .overlay(Rectangle().frame(width: 1).foregroundColor(.secondary.opacity(0.2)), alignment: .trailing)
    }
}

/// 侧边栏水库图例：等腰梯形（上底宽、下底窄且更短），着色与图层一致。
private struct SidebarReservoirTrapezoidShape: Shape {
    func path(in rect: CGRect) -> Path {
        let bottomW = rect.width * 0.28
        let midX = rect.midX
        let y0 = rect.minY
        let y1 = rect.maxY
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: y0))
        p.addLine(to: CGPoint(x: rect.maxX, y: y0))
        p.addLine(to: CGPoint(x: midX + bottomW * 0.5, y: y1))
        p.addLine(to: CGPoint(x: midX - bottomW * 0.5, y: y1))
        p.closeSubpath()
        return p
    }
}

/// 侧边栏水塔图例：与画布 Metal Tank 一致；大正方形底左/底右各挖矩形（宽=边长 1/4，高=边长 1/2）。
private struct SidebarTankNotchedSquareShape: Shape {
    func path(in rect: CGRect) -> Path {
        let nw: CGFloat = 0.5
        let nh: CGFloat = 1.0
        let L = min(rect.width, rect.height)
        let midX = rect.midX
        let midY = rect.midY
        let h = L * 0.5
        func pt(_ ux: CGFloat, _ uy: CGFloat) -> CGPoint {
            CGPoint(x: midX + ux * h, y: midY - uy * h)
        }
        var p = Path()
        p.move(to: pt(-1 + nw, -1))
        p.addLine(to: pt(1 - nw, -1))
        p.addLine(to: pt(1 - nw, -1 + nh))
        p.addLine(to: pt(1, -1 + nh))
        p.addLine(to: pt(1, 1))
        p.addLine(to: pt(-1, 1))
        p.addLine(to: pt(-1, -1 + nh))
        p.addLine(to: pt(-1 + nw, -1 + nh))
        p.addLine(to: pt(-1 + nw, -1))
        p.closeSubpath()
        return p
    }
}

/// 侧栏阀门：两等边三角形共顶点（与画布符号一致；不画穿心线以免与双三角之间竖线重叠）。
private struct SidebarValveBowtieShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let L = min(rect.width, rect.height) * 0.62
        let h = L * CGFloat(3).squareRoot() / 2
        var p = Path()
        p.move(to: CGPoint(x: cx, y: cy))
        p.addLine(to: CGPoint(x: cx - h, y: cy - L / 2))
        p.addLine(to: CGPoint(x: cx - h, y: cy + L / 2))
        p.closeSubpath()
        p.move(to: CGPoint(x: cx, y: cy))
        p.addLine(to: CGPoint(x: cx + h, y: cy - L / 2))
        p.addLine(to: CGPoint(x: cx + h, y: cy + L / 2))
        p.closeSubpath()
        return p
    }
}

/// 阀门拟物图标：保留双三角阀体语义，增加接管、金属高光与中心阀芯。
private struct SkeuomorphicValveIcon: View {
    var tint: Color
    var width: CGFloat = 12
    var height: CGFloat = 10

    var body: some View {
        ZStack {
            // 左右竖法兰盘
            HStack(spacing: width * 0.48) {
                RoundedRectangle(cornerRadius: 0.8)
                    .fill(
                        LinearGradient(
                            colors: [Color.gray.opacity(0.45), Color.gray.opacity(0.72), Color.gray.opacity(0.42)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(1.2, width * 0.14), height: height * (0.665 * 1.35))
                RoundedRectangle(cornerRadius: 0.8)
                    .fill(
                        LinearGradient(
                            colors: [Color.gray.opacity(0.45), Color.gray.opacity(0.72), Color.gray.opacity(0.42)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(1.2, width * 0.14), height: height * (0.665 * 1.35))
            }

            // 中间蓝色阀体（连接左右法兰）
            RoundedRectangle(cornerRadius: height * 0.20)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.98), tint.opacity(0.82), tint.opacity(0.70)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: height * 0.20)
                        .stroke(Color.white.opacity(0.55), lineWidth: 0.55)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: height * 0.20)
                        .stroke(tint.opacity(0.88), lineWidth: 0.65)
                )
                .shadow(color: .black.opacity(0.18), radius: 0.8, x: 0.2, y: 0.55)
                .frame(width: width * 0.62, height: height * (0.64 * 0.8))

            // 顶部阀杆
            Capsule()
                .fill(Color.gray.opacity(0.62))
                .frame(width: max(0.9, width * 0.08), height: height * 0.42)
                .offset(y: -height * 0.47)

            // 顶部横向转动盘（手轮简笔）
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.42), Color.gray.opacity(0.76), Color.gray.opacity(0.46)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    Capsule().stroke(Color.black.opacity(0.20), lineWidth: 0.45)
                )
                .frame(width: width * 0.55, height: max(1.0, height * 0.14))
                .offset(y: -height * 0.66)
        }
        .frame(width: width * 1.25, height: height)
    }
}

/// 与画布水泵符号外接圆像素：`legendCircumPt * 3`（见 `MetalNetworkView` 中计算）。
private enum SidebarPumpLegendLayout {
    static let frameW: CGFloat = 12
    static let frameH: CGFloat = 10
    static let lineW: CGFloat = 1.05
    /// 圆与三角共用外接圆半径（三角三顶点在圆周上）
    static var circumRadiusPt: CGFloat {
        min(frameW, frameH) * 0.5 - lineW * 0.5 - 0.25
    }
}

/// 侧栏：空心圆（半径与三角外接圆一致）。
private struct SidebarPumpCircleStrokeShape: Shape {
    var radiusPt: CGFloat
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        var p = Path()
        p.addEllipse(in: CGRect(x: cx - radiusPt, y: cy - radiusPt, width: radiusPt * 2, height: radiusPt * 2))
        return p
    }
}

/// 侧栏：空心等边三角，三顶点在外接圆上；θ=0 为右顶点（水平对称轴）。
private struct SidebarPumpTriangleInscribedShape: Shape {
    var radiusPt: CGFloat
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        var p = Path()
        for i in 0..<3 {
            let a = 2 * CGFloat.pi * CGFloat(i) / 3
            let pt = CGPoint(x: cx + radiusPt * cos(a), y: cy - radiusPt * sin(a))
            if i == 0 {
                p.move(to: pt)
            } else {
                p.addLine(to: pt)
            }
        }
        p.closeSubpath()
        return p
    }
}

private struct SidebarPumpLegendIcon: View {
    var tint: Color

    var body: some View {
        let R = SidebarPumpLegendLayout.circumRadiusPt
        let lw = SidebarPumpLegendLayout.lineW
        ZStack {
            SidebarPumpCircleStrokeShape(radiusPt: R)
                .stroke(tint, lineWidth: lw)
            SidebarPumpTriangleInscribedShape(radiusPt: R)
                .stroke(tint, lineWidth: lw * 0.95)
        }
        .frame(width: SidebarPumpLegendLayout.frameW, height: SidebarPumpLegendLayout.frameH)
    }
}

/// 与左侧图例一致的小型图符，用于拓扑工具栏按钮。
private struct TopologyToolbarLegendIcon: View {
    let tool: CanvasPlacementTool

    var body: some View {
        Group {
            switch tool {
            case .junction:
                Image(systemName: "circle.fill")
                    .foregroundStyle(Color(white: 0.35))
            case .tankTower:
                SidebarTankNotchedSquareShape()
                    .fill(Color.green)
                    .frame(width: 11, height: 9)
            case .tankPool:
                SidebarReservoirTrapezoidShape()
                    .fill(Color.purple)
                    .frame(width: 12, height: 10)
            case .pipe:
                Image(systemName: "line.diagonal")
                    .foregroundStyle(.gray)
            case .valve:
                SkeuomorphicValveIcon(tint: .blue, width: 12, height: 10)
            case .pump:
                SidebarPumpLegendIcon(tint: .red)
            }
        }
        .frame(width: 22, height: 22)
    }
}

private struct MacTreeRow: View {
    let title: String
    let count: Int
    let icon: String
    let tint: Color
    var isActive: Bool = false
    var depth: Int = 0
    /// 非 nil 时在行尾显示开关，用于图层显示/隐藏（与 `CanvasLayerVisibility` 同步）。
    var layerToggle: Binding<Bool>? = nil
    /// 为 true 时用紫色等腰梯形代替 SF Symbol（`icon` 忽略）。
    var reservoirTrapezoid: Bool = false
    /// 为 true 时用底角双凹正方形代替 SF Symbol（`icon` 忽略），与画布水塔一致。
    var tankNotchedSquare: Bool = false
    /// 为 true 时用双三角代替 SF Symbol（`icon` 忽略），与画布阀门一致。
    var valveBowtie: Bool = false
    /// 为 true 时用圆环 + 空心等边三角代替 SF Symbol（`icon` 忽略），表示水泵图例。
    var pumpHollowCircleTriangle: Bool = false
    /// 非 nil 时点击行尾数字（左键）打开对应类型的对象表。
    var layerTableKind: ObjectTableKind? = nil
    var canOpenObjectTable: Bool = false
    var onOpenObjectTable: ((ObjectTableKind) -> Void)? = nil
    /// 非 nil 时整行可点（如侧栏「模式 / 曲线」打开 .inp 章节详情）。
    var onTapRow: (() -> Void)? = nil

    /// 与开关同宽占位，使无开关的父行数字列与有开关行对齐。
    private static let layerToggleColumnWidth: CGFloat = 20
    /// 固定数字列宽，避免位数变化时推动开关列导致各行勾/横线不齐。
    private static let layerCountColumnWidth: CGFloat = 44

    var body: some View {
        Group {
            if let tap = onTapRow {
                Button(action: tap) {
                    rowCore
                }
                .buttonStyle(.plain)
                .help("点击查看 .inp 章节详情")
                .contentShape(Rectangle())
            } else {
                rowCore
            }
        }
    }

    private var rowCore: some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                if reservoirTrapezoid {
                    SidebarReservoirTrapezoidShape()
                        .fill(tint)
                        .frame(width: 12, height: 10)
                } else if tankNotchedSquare {
                    SidebarTankNotchedSquareShape()
                        .fill(tint)
                        .frame(width: 12, height: 10)
                } else if valveBowtie {
                    SkeuomorphicValveIcon(tint: tint, width: 12, height: 10)
                } else if pumpHollowCircleTriangle {
                    SidebarPumpLegendIcon(tint: tint)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(tint)
                }
            }
            .frame(width: 14, height: 12)
            Text(title)
                .font(.system(size: 13))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            HStack(alignment: .center, spacing: 6) {
                if let toggle = layerToggle {
                    Button {
                        toggle.wrappedValue.toggle()
                    } label: {
                        ZStack {
                            Image(systemName: toggle.wrappedValue ? "checkmark" : "minus")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(toggle.wrappedValue ? .primary : .secondary.opacity(0.8))
                        }
                        .frame(width: Self.layerToggleColumnWidth, height: Self.layerToggleColumnWidth)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(toggle.wrappedValue ? "点击隐藏该类型" : "点击显示该类型")
                    .accessibilityLabel("图层显示")
                    .accessibilityValue(toggle.wrappedValue ? "开" : "关")
                } else {
                    Color.clear
                        .frame(width: Self.layerToggleColumnWidth, height: Self.layerToggleColumnWidth)
                }
                Group {
                    if let k = layerTableKind {
                        Button {
                            guard canOpenObjectTable else { return }
                            onOpenObjectTable?(k)
                        } label: {
                            Text(verbatim: String(count))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canOpenObjectTable)
                        .help(canOpenObjectTable ? "点击查看此类对象表格" : "请先打开工程")
                        .accessibilityLabel("数量 \(count)，打开表格")
                    } else {
                        Text(verbatim: String(count))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: Self.layerCountColumnWidth, alignment: .trailing)
            }
        }
        .padding(.leading, CGFloat(12 + depth * 14))
        .padding(.trailing, 12)
        .frame(minHeight: 24)
        .background(isActive ? Color.blue.opacity(0.08) : .clear)
    }
}

private struct MacDesignStatusBar: View {
    @ObservedObject var appState: AppState
    let scale: CGFloat
    let mouseSceneX: Float?
    let mouseSceneY: Float?
    @Binding var labelsVisible: Bool
    let onTapRunResult: () -> Void

    /// 状态栏：当前 .inp 解析到的流量单位代码 + 易读后缀（与 EPANET 一致）。
    private var statusBarFlowText: String {
        guard appState.project != nil else { return "—" }
        let code = appState.inpFlowUnits?.uppercased().trimmingCharacters(in: .whitespaces) ?? ""
        if code.isEmpty { return "—" }
        let suf = InpOptionsParser.flowUnitDisplaySuffix(code: appState.inpFlowUnits)
        return suf == code ? code : "\(code) (\(suf))"
    }

    /// 由 Flow Units 推导的长度/管径单位（不标注「美制/米制」字样）。
    private var statusBarLengthText: String {
        guard appState.project != nil else { return "—" }
        return InpOptionsParser.isUSCustomary(flowUnits: appState.inpFlowUnits)
            ? "ft / in"
            : "m / mm"
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTapRunResult) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(resultColor)
                        .frame(width: 6, height: 6)
                    Text(resultTitle)
                }
                .font(.caption.monospaced())
            }
            .buttonStyle(.plain)
            .help("点击查看：读入/渲染耗时、模型统计；若已计算则含模拟时长、步长与平差耗时")
            Divider().frame(height: 12)
            Text("Hazen-Williams")
            Divider().frame(height: 12)
            Button {
                appState.openMacSettings(initialTab: 0)
            } label: {
                Text("流量 \(statusBarFlowText) · 长度 \(statusBarLengthText)")
            }
            .buttonStyle(.plain)
            .foregroundColor(Color(nsColor: .linkColor))
            .help("打开设置 · 单位")
            Spacer()
            Button {
                labelsVisible.toggle()
            } label: {
                Image(systemName: labelsVisible ? "tag.fill" : "tag")
            }
            .buttonStyle(.plain)
            .foregroundColor(labelsVisible ? Color(nsColor: .linkColor) : .secondary)
            .help(labelsVisible ? "隐藏画布标注" : "显示画布标注")
            Divider().frame(height: 12)
            Text("缩放 \(Int(scale * 100))%")
                .help("用户缩放倍率（相对「适应全图」）。该数字不控制侧栏；侧栏仅遮挡画布，不应改变管网在屏幕上的比例。")
            Divider().frame(height: 12)
            Text("X \(mouseSceneX.map { String(format: "%.0f", $0) } ?? "—") · Y \(mouseSceneY.map { String(format: "%.0f", $0) } ?? "—")")
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                colors: [Color(NSColor(calibratedWhite: 0.95, alpha: 1)), Color(NSColor(calibratedWhite: 0.92, alpha: 1))],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.25)), alignment: .top)
    }

    private var resultColor: Color {
        if appState.isRunning { return .orange }
        guard let result = appState.runResult else { return .secondary }
        switch result {
        case .success: return .green
        case .failure: return .red
        }
    }

    private var resultTitle: String {
        if appState.isRunning { return "计算中" }
        guard let result = appState.runResult else { return "未计算" }
        switch result {
        case .success: return "计算完成"
        case .failure: return "计算失败"
        }
    }
}
#endif

private struct ResultOverlayLegend: View {
    let mode: ResultOverlayMode
    let nodeRange: (Float, Float)?
    let linkRange: (Float, Float)?
    let offset: CGSize

    var body: some View {
        let range = mode == .pressure ? nodeRange : linkRange
        VStack(alignment: .leading, spacing: 8) {
            Text(mode == .pressure ? "节点压力 (m)" : "管段流量")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            LinearGradient(colors: [.blue, .red], startPoint: .leading, endPoint: .trailing)
                .frame(width: 160, height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            if let r = range {
                Text(
                    mode == .pressure
                        ? String(format: "%.3f  ->  %.3f", r.0, r.1)
                        : String(format: "%.2f  ->  %.2f", r.0, r.1)
                )
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            } else {
                Text("暂无结果数据")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .offset(offset)
    }
}

private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 运行结果 / 模型信息 sheet（状态栏圆点入口）

#if os(macOS)
/// 顶部标题条高度（约为常见单行标题栏 22pt 的两倍）；背景略深于内容区以便区分。
private enum RunResultSheetChrome {
    static let titleBarHeight: CGFloat = 44
    static var titleBarBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }
}

/// 略减小 sheet 圆角（系统默认偏大时）；macOS 14+ 使用 `presentationCornerRadius`。
private struct SheetPresentationChrome: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.presentationCornerRadius(8)
        } else {
            content
        }
    }
}
#endif

private struct RunResultSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var fileTitle: String {
        if let p = appState.filePath, !p.isEmpty {
            return URL(fileURLWithPath: p).lastPathComponent
        }
        if appState.scene != nil { return "未命名画布" }
        return "—"
    }

    private var flowUnitsLine: String {
        guard appState.project != nil || appState.scene != nil else { return "—" }
        let code = appState.inpFlowUnits?.uppercased().trimmingCharacters(in: .whitespaces) ?? ""
        if code.isEmpty { return "—" }
        let suf = InpOptionsParser.flowUnitDisplaySuffix(code: appState.inpFlowUnits)
        return suf == code ? code : "\(code)（\(suf)）"
    }

    private var headlossLine: String {
        if let h = appState.cachedInpOptionsHints?.headloss?.uppercased(), !h.isEmpty {
            return Self.displayHeadlossLabel(h)
        }
        return "—"
    }

    private static func displayHeadlossLabel(_ code: String) -> String {
        let c = code.trimmingCharacters(in: .whitespaces)
        switch c {
        case "H-W", "HW": return "Hazen-Williams (H-W)"
        case "D-W", "DW": return "Darcy-Weisbach (D-W)"
        case "C-M", "CM": return "Chezy-Manning (C-M)"
        default: return c
        }
    }

    private static func formatSecondsHuman(_ sec: Int) -> String {
        guard sec >= 0 else { return "—" }
        if sec < 60 { return "\(sec) 秒" }
        if sec < 3600 {
            let m = sec / 60
            let s = sec % 60
            return s == 0 ? "\(m) 分钟" : "\(m) 分 \(s) 秒"
        }
        let h = sec / 3600
        let m = (sec % 3600) / 60
        return m == 0 ? "\(h) 小时" : "\(h) 小时 \(m) 分"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(macOS)
            HStack(spacing: 10) {
                Text("模型与计算信息")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                SheetWindowDragBarNSView()
                    .frame(maxWidth: .infinity)
                    .frame(height: RunResultSheetChrome.titleBarHeight)
                    .help("拖动此区域可移动窗口")
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .frame(height: RunResultSheetChrome.titleBarHeight)
            .frame(maxWidth: .infinity)
            .background(RunResultSheetChrome.titleBarBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.65))
                    .frame(height: 1)
            }
            #else
            HStack(spacing: 8) {
                Text("模型与计算信息")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding(.bottom, 8)
                    #endif

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text("文件")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                        LabeledContent("名称") { Text(fileTitle).textSelection(.enabled) }
                    }

                    if let loadSec = appState.lastLoadAndRenderElapsedSeconds {
                        Group {
                            Text("读入与渲染")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                            Text("墙钟耗时 \(String(format: "%.3f", loadSec)) 秒（解析、引擎加载/仅显示解析、构建画布场景）")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let stats = appState.modelNetworkStatistics() {
                        Group {
                            Text("模型统计")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                            LabeledContent("节点合计") { Text("\(stats.junctions + stats.tanks + stats.reservoirs)") }
                            LabeledContent("Junction / 水塔 / 水库") {
                                Text("\(stats.junctions) / \(stats.tanks) / \(stats.reservoirs)")
                            }
                            LabeledContent("管段合计") { Text("\(stats.pipes + stats.valves + stats.pumps)") }
                            LabeledContent("Pipe / 阀门 / 水泵") {
                                Text("\(stats.pipes) / \(stats.valves) / \(stats.pumps)")
                            }
                            let lenNote = stats.isPlanarLengthApproximation ? "（仅显示模式：画布平面几何长度之和，非 .inp LENGTH）" : ""
                            LabeledContent("Pipe 长度合计\(lenNote)") {
                                Text(String(format: "%.3f %@", stats.totalPipeLength, stats.lengthUnitLabel))
                            }
                        }
                    }

                    Group {
                        Text("基本选项")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                        LabeledContent("流量单位") { Text(flowUnitsLine) }
                        LabeledContent("水头损失公式") { Text(headlossLine).fixedSize(horizontal: false, vertical: true) }
                    }

                    if let result = appState.runResult {
                        Group {
                            Text("最近一次运行计算")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                switch result {
                            case .success(let hydElapsed):
                                if let d = appState.lastCompletedSimulationDurationSeconds, d > 0 {
                                    LabeledContent("模拟总时长") { Text(Self.formatSecondsHuman(d)) }
                                } else {
                                    LabeledContent("模拟总时长") { Text("0（稳态或未写 DURATION）") }
                                }
                                if let hs = appState.lastCompletedSimulationHydraulicStepSeconds {
                                    LabeledContent("水力时间步长") { Text(Self.formatSecondsHuman(hs)) }
                                }
                                LabeledContent("管网平差计算耗时") {
                                    Text(String(format: "%.3f 秒", hydElapsed))
                                }
                                Text("单次运行总墙钟时间（扩展时段内各水力步均含在内）。")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            case .failure(let message):
                                LabeledContent("状态") { Text("失败").foregroundColor(.red) }
                        Text(message)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                        Text("尚未运行计算；上表为当前已加载模型信息。")
                            .font(.caption)
                    .foregroundColor(.secondary)
            }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        }
        .frame(minWidth: 400, minHeight: 280)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(SheetWindowResizableHost(
            minSize: NSSize(width: 400, height: 280),
            maxSize: NSSize(width: 3200, height: 2800)
        ))
        #endif
    }
}

#if os(macOS)
/// 为 SwiftUI `.sheet` 宿主窗口打开边缘拖动缩放（系统默认部分 sheet 不可调）。
private struct SheetWindowResizableHost: NSViewRepresentable {
    var minSize: NSSize
    var maxSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let v = ResizableSheetAnchorNSView()
        v.minContentSize = minSize
        v.maxContentSize = maxSize
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? ResizableSheetAnchorNSView else { return }
        v.minContentSize = minSize
        v.maxContentSize = maxSize
        v.applyResizableSizingToWindow()
    }
}

private final class ResizableSheetAnchorNSView: NSView {
    var minContentSize = NSSize(width: 400, height: 280)
    var maxContentSize = NSSize(width: 3200, height: 2800)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyResizableSizingToWindow()
    }

    func applyResizableSizingToWindow() {
        guard let w = window else { return }
        w.styleMask.insert(.resizable)
        w.isMovable = true
        w.contentMinSize = minContentSize
        w.contentMaxSize = maxContentSize
    }
}

/// 标题栏中部空白：按住拖动以移动 sheet 窗口（与边缘缩放配合）。
private struct SheetWindowDragBarNSView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SheetWindowDragBarBackingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class SheetWindowDragBarBackingView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
#endif
