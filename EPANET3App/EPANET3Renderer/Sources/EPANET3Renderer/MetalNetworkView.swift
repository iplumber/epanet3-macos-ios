/* MetalNetworkView - Metal-based network map rendering
 * Renders pipes as lines and nodes as points. Single draw calls for 100k+ elements.
 */
import SwiftUI
import Metal
import MetalKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Scene to vertex buffer conversion

/// 每管段 6 个 float：x1,y1,k,x2,y2,k；GPU 上展开为 6 顶点（两个三角形）的粗线
func makeLineVertices(from scene: NetworkScene) -> [Float] {
    var v: [Float] = []
    for l in scene.links {
        let k = Float(l.kind)
        v.append(contentsOf: [l.x1, l.y1, k, l.x2, l.y2, k])
    }
    return v
}

/// 每阀门 4 float：中点 mx,my，管线单位方向 dx,dy（与 `vertex_valve_glyph` instance 缓冲一致）
func makeValveGlyphInstances(from scene: NetworkScene) -> [Float] {
    var v: [Float] = []
    for l in scene.links where l.kind == 2 {
        let mx = (l.x1 + l.x2) * 0.5
        let my = (l.y1 + l.y2) * 0.5
        var dx = l.x2 - l.x1
        var dy = l.y2 - l.y1
        let len = (dx * dx + dy * dy).squareRoot()
        if len < 1e-5 {
            dx = 1
            dy = 0
        } else {
            dx /= len
            dy /= len
        }
        v.append(contentsOf: [mx, my, dx, dy])
    }
    return v
}

/// 每水泵 4 float：中点与管线单位方向（`vertex_pump_glyph` instance，仅 `kind == 1`）
fileprivate func appendPumpGlyphInstance(link: LinkVertex, to v: inout [Float]) {
    guard link.kind == 1 else { return }
    let mx = (link.x1 + link.x2) * 0.5
    let my = (link.y1 + link.y2) * 0.5
    var dx = link.x2 - link.x1
    var dy = link.y2 - link.y1
    let len = (dx * dx + dy * dy).squareRoot()
    if len < 1e-5 {
        dx = 1
        dy = 0
    } else {
        dx /= len
        dy /= len
    }
    v.append(contentsOf: [mx, my, dx, dy])
}

func makePointVertices(from scene: NetworkScene) -> [Float] {
    var v: [Float] = []
    for n in scene.nodes {
        v.append(contentsOf: [n.x, n.y, Float(n.kind)])
    }
    return v
}

// MARK: - Metal Coordinator (shared)

public final class MetalNetworkCoordinator: NSObject, MTKViewDelegate {
        var view: MTKView?
        var scene: NetworkScene?
        var scale: CGFloat = 1
        var panX: CGFloat = 0
        var panY: CGFloat = 0
        var selectedNodeIndex: Int?
        var selectedLinkIndex: Int?
        /// 非空时优先于 `selectedNodeIndex` 用于多选高亮（与 `AppState` 框选一致）。
        var selectedNodeIndices: [Int] = []
        var selectedLinkIndices: [Int] = []
        var onSelect: ((Int?, Int?) -> Void)?
        /// 画布布线命令：返回 true 表示已消费主键按下（不进入空白拖曳平移、也不在 mouseUp 时清除选中）。
        var onPlacementPrimaryClick: ((CGPoint, CGSize) -> Bool)?
        var lineBuffer: MTLBuffer?
        var pointBuffer: MTLBuffer?
        var lineScalarBuffer: MTLBuffer?
        var pointScalarBuffer: MTLBuffer?
        var lineCount: Int = 0
        var pointCount: Int = 0
        var nodeScalars: [Float]?
        var linkScalars: [Float]?
        var nodeScalarRange: (Float, Float)?
        var linkScalarRange: (Float, Float)?
        /// 画布节点直径（像素），与设置 `settings.display.nodeSize` 一致
        var nodePointSizePixels: Float = 6
        /// sRGB 0…1，顺序 junction / reservoir / tank（与 NodeVertex.kind 一致）
        var nodeRGBJunction: (Float, Float, Float) = (0.1, 0.2, 0.5)
        var nodeRGBReservoir: (Float, Float, Float) = (0.5, 0.2, 0.75)
        var nodeRGBTank: (Float, Float, Float) = (0.2, 0.75, 0.35)
        /// 管段线宽（像素）；用三角形四边形绘制，macOS / iOS 均生效
        var linkLineWidthPixels: Float = 2
        var linkRGBPipe: (Float, Float, Float) = (0.2, 0.4, 0.7)
        var linkRGBPump: (Float, Float, Float) = (0.8, 0.2, 0.2)
        var linkRGBValve: (Float, Float, Float) = (1.0, 0.58, 0)
        /// 与侧栏「图层」开关一致；仅影响绘制与命中，不改场景数据。
        var layerVisibility: CanvasLayerVisibility = .allVisible
        var pipelineState: MTLRenderPipelineState?
        var linePipeline: MTLRenderPipelineState?
        var lineScalarPipeline: MTLRenderPipelineState?
        var pointScalarPipeline: MTLRenderPipelineState?
        var lineHighlightPipeline: MTLRenderPipelineState?
        var pointHighlightPipeline: MTLRenderPipelineState?
        var valveGlyphPipeline: MTLRenderPipelineState?
        var valveGlyphHighlightPipeline: MTLRenderPipelineState?
        var valveGlyphBuffer: MTLBuffer?
        var valveGlyphCount: Int = 0
        var pumpGlyphPipeline: MTLRenderPipelineState?
        var pumpGlyphHighlightPipeline: MTLRenderPipelineState?
        /// 每帧写入可见水泵 instance；容量随最大需求增长
        private var pumpDrawInstancesBuffer: MTLBuffer?
        private var pumpDrawInstancesCapacityBytes: Int = 0
        /// 选中阀门/水泵符号叠绘（与 `pumpDrawInstancesBuffer` 错开使用）
        private var selectionGlyphOverlayBuffer: MTLBuffer?
        private var selectionGlyphOverlayCapacityBytes: Int = 0
        /// 与 AppState.sceneGeometryRevision 同步；仅平移/缩放时不递增，避免每帧重建万级顶点缓冲。
        var sceneGeometryRevision: UInt64 = 0
        /// 与 AppState.resultScalarRevision 同步；压力/流量上色数组更新时递增。
        var resultScalarRevision: UInt64 = 0
        private var commandQueue: MTLCommandQueue?
        private var lastUploadedGeometryRevision: UInt64 = .max
        private var lastUploadedResultScalarRevision: UInt64 = .max
        /// 与 `view.drawableSize` 一致（像素）；用于 SwiftUI 侧按「每像素多少场景单位」计算最大缩放
        var onDrawableSizeChange: ((CGSize) -> Void)?
        private var lastNotifiedDrawableSize: CGSize = .zero
        /// 非 nil 时与 SwiftUI 侧 `CanvasViewportFraming` 一致；nil 时用 `scene.bounds` 做投影。
        var canvasTransformBounds: (minX: Float, maxX: Float, minY: Float, maxY: Float)?

        private func framingRect(for scene: NetworkScene) -> (minX: Float, maxX: Float, minY: Float, maxY: Float) {
            if let t = canvasTransformBounds { return t }
            return (scene.bounds.minX, scene.bounds.maxX, scene.bounds.minY, scene.bounds.maxY)
        }

        private func ensureSelectionGlyphOverlayBuffer(device: MTLDevice, byteCount: Int) -> MTLBuffer? {
            guard byteCount > 0 else { return nil }
            if selectionGlyphOverlayCapacityBytes < byteCount {
                selectionGlyphOverlayCapacityBytes = max(byteCount, 64 * MemoryLayout<Float>.stride)
                selectionGlyphOverlayBuffer = device.makeBuffer(length: selectionGlyphOverlayCapacityBytes, options: .storageModeShared)
            }
            return selectionGlyphOverlayBuffer
        }

        /// 与 `draw` / `hitTest` / `viewToScene` 共用的场景→NDC 线性部分（scale、偏移、用于管段容差的场景跨度）。
        private func viewportProjection(drawableW: Float, drawableH: Float, scene: NetworkScene) -> (sx: Float, sy: Float, ox: Float, oy: Float, span: Float) {
            let fr = framingRect(for: scene)
            let bw = fr.maxX - fr.minX
            let bh = fr.maxY - fr.minY
            let pad: Float = max(bw, bh) * 0.05 + 1
            let baseScale = min(2.0 / (bw + pad * 2), 2.0 / (bh + pad * 2))
            let s = baseScale * Float(scale)
            let centerX = (fr.minX + fr.maxX) * 0.5
            let centerY = (fr.minY + fr.maxY) * 0.5
            let scaleX: Float
            let scaleYVal: Float
            if drawableW >= drawableH {
                scaleYVal = s
                scaleX = s * drawableH / drawableW
            } else {
                scaleX = s
                scaleYVal = s * drawableW / drawableH
            }
            let offX = Float(-Double(centerX) * Double(scaleX) + Double(panX) * Double(scaleX) * 0.01)
            let offY = Float(-Double(centerY) * Double(scaleYVal) - Double(panY) * Double(scaleYVal) * 0.01)
            return (scaleX, scaleYVal, offX, offY, max(bw, bh))
        }

        /// 视窗内可能可见的管段数 **小于** 该值时用双剖分画两遍；≥ 该值只画一遍（与 `draw` 中 ndc 变换一致的场景可见矩形统计）
        private static let lineGeometryDualPassVisibleLinkThreshold = 3000
        /// 管段选取：垂直于管线方向至少按「半宽」这么多 **屏幕像素** 计容差（1–2px 线宽时仍约 12px 直径可点区域）
        private static let linkHitTestMinHalfWidthPixels: Float = 6

        override init() {
            super.init()
        }

    static let metalSource = """
        #include <metal_stdlib>
        using namespace metal;
        struct LineVertexOut { float4 pos [[position]]; float scalar; float kind; float2 p0 [[flat]]; float2 p1 [[flat]]; };
        /// 节点标记：Junction 圆 · Reservoir 等腰梯形 · Tank 正方形底左/底右各挖矩形（宽=边长1/4，高=边长1/2，与 `SidebarTankNotchedSquareShape` 同步）
        struct NodeMarkerOut { float4 pos [[position]]; float2 local; float kind; };
        struct NodeMarkerScalarOut { float4 pos [[position]]; float2 local; float kind; float scalar; };
        float3 colorMap(float t) {
            t = clamp(t, 0.0, 1.0);
            return float3(t, 0.2, 1.0 - t); // blue -> red
        }
        // 图层可见性：vis[0..2] 为 0/1（管段 pipe/pump/valve；节点 junction/reservoir/tank），与 kind 一致。
        void layer_link_discard(float k, constant float *vis) {
            if (k < 0.5) { if (vis[0] < 0.5) discard_fragment(); }
            else if (k < 1.5) { if (vis[1] < 0.5) discard_fragment(); }
            else { if (vis[2] < 0.5) discard_fragment(); }
        }
        void layer_node_discard(float k, constant float *vis) {
            if (k < 0.5) { if (vis[0] < 0.5) discard_fragment(); }
            else if (k < 1.5) { if (vis[1] < 0.5) discard_fragment(); }
            else { if (vis[2] < 0.5) discard_fragment(); }
        }
        // 管段：先在场景→NDC，再在「像素空间算法向」后转回 NDC 偏移，线宽为恒定屏幕像素，与缩放/走向无关。
        // uniforms[0..3]=scaleX,scaleY,offX,offY；[4]=线宽(像素)；[5]=0/1 双剖分；[6],[7]=viewport W,H（像素）
        float2 line_extrude_ndc(float2 p0s, float2 p1s, float sx, float sy, float ox, float oy, float lineWpx, float vw, float vh) {
            float2 a = float2(p0s.x * sx + ox, p0s.y * sy + oy);
            float2 b = float2(p1s.x * sx + ox, p1s.y * sy + oy);
            float2 dN = b - a;
            float hw = max(vw, 1.0) * 0.5;
            float hh = max(vh, 1.0) * 0.5;
            float2 dPx = float2(dN.x * hw, dN.y * hh);
            float lp = length(dPx);
            float2 nPx = lp > 1e-5 ? float2(-dPx.y, dPx.x) / lp : float2(0.0, 1.0);
            float2 ePx = nPx * (lineWpx * 0.5);
            return float2(ePx.x / hw, ePx.y / hh);
        }
        vertex LineVertexOut vertex_line_plain(constant float *uniforms [[buffer(0)]], constant float *verts [[buffer(1)]], uint vid [[vertex_id]]) {
            float scaleX=uniforms[0], scaleY=uniforms[1], offX=uniforms[2], offY=uniforms[3];
            float lineWpx = max(uniforms[4], 0.5);
            float splitB = uniforms[5];
            float vw = uniforms[6], vh = uniforms[7];
            uint lid = vid / 6u;
            uint c = vid % 6u;
            uint b = lid * 6u;
            float2 p0 = float2(verts[b+0], verts[b+1]);
            float lk = verts[b+2];
            float2 p1 = float2(verts[b+3], verts[b+4]);
            float2 ext = line_extrude_ndc(p0, p1, scaleX, scaleY, offX, offY, lineWpx, vw, vh);
            float2 aNdc = float2(p0.x * scaleX + offX, p0.y * scaleY + offY);
            float2 bNdc = float2(p1.x * scaleX + offX, p1.y * scaleY + offY);
            float2 corner0 = aNdc + ext;
            float2 corner1 = aNdc - ext;
            float2 corner2 = bNdc + ext;
            float2 corner3 = bNdc - ext;
            float2 pos;
            if (splitB < 0.5) {
                if (c == 0u) pos = corner0;
                else if (c == 1u) pos = corner1;
                else if (c == 2u) pos = corner3;
                else if (c == 3u) pos = corner0;
                else if (c == 4u) pos = corner3;
                else pos = corner2;
            } else {
                if (c == 0u) pos = corner0;
                else if (c == 1u) pos = corner1;
                else if (c == 2u) pos = corner2;
                else if (c == 3u) pos = corner1;
                else if (c == 4u) pos = corner3;
                else pos = corner2;
            }
            LineVertexOut o;
            o.pos = float4(pos.x, pos.y, 0, 1);
            o.scalar = 0.0;
            o.kind = lk;
            o.p0 = p0;
            o.p1 = p1;
            return o;
        }
        vertex LineVertexOut vertex_line_scalar(constant float *uniforms [[buffer(0)]], constant float *verts [[buffer(1)]], constant float *vals [[buffer(2)]], uint vid [[vertex_id]]) {
            float scaleX=uniforms[0], scaleY=uniforms[1], offX=uniforms[2], offY=uniforms[3];
            float lineWpx = max(uniforms[4], 0.5);
            float splitB = uniforms[5];
            float vw = uniforms[6], vh = uniforms[7];
            uint lid = vid / 6u;
            uint c = vid % 6u;
            uint b = lid * 6u;
            float2 p0 = float2(verts[b+0], verts[b+1]);
            float lk = verts[b+2];
            float2 p1 = float2(verts[b+3], verts[b+4]);
            float2 ext = line_extrude_ndc(p0, p1, scaleX, scaleY, offX, offY, lineWpx, vw, vh);
            float2 aNdc = float2(p0.x * scaleX + offX, p0.y * scaleY + offY);
            float2 bNdc = float2(p1.x * scaleX + offX, p1.y * scaleY + offY);
            float2 corner0 = aNdc + ext;
            float2 corner1 = aNdc - ext;
            float2 corner2 = bNdc + ext;
            float2 corner3 = bNdc - ext;
            float2 pos;
            if (splitB < 0.5) {
                if (c == 0u) pos = corner0;
                else if (c == 1u) pos = corner1;
                else if (c == 2u) pos = corner3;
                else if (c == 3u) pos = corner0;
                else if (c == 4u) pos = corner3;
                else pos = corner2;
            } else {
                if (c == 0u) pos = corner0;
                else if (c == 1u) pos = corner1;
                else if (c == 2u) pos = corner2;
                else if (c == 3u) pos = corner1;
                else if (c == 4u) pos = corner3;
                else pos = corner2;
            }
            LineVertexOut o;
            o.pos = float4(pos.x, pos.y, 0, 1);
            o.scalar = vals[lid];
            o.kind = lk;
            o.p0 = p0;
            o.p1 = p1;
            return o;
        }
        // hole[0..6]=scaleX,scaleY,offX,offY,vw,vh,pumpCircumPx；[7]=minSegPx 管段屏幕像素长度低于此则不挖孔、且不画水泵符号（与 Swift 一致）
        // 注意：片段着色器里 in.pos.xy 是像素坐标（视口左上为原点、y 向下），与顶点输出的 NDC 不同；须与 hitTest / viewToScene 一致先转 NDC 再转场景。
        void fragment_pump_line_hole_discard(LineVertexOut in, constant float *hole) {
            float k = in.kind;
            if (k < 0.5 || k >= 1.5) return;
            float sx = hole[0], sy = hole[1], ox = hole[2], oy = hole[3], vw = max(hole[4], 1.0), vh = max(hole[5], 1.0);
            float circumPx = max(hole[6], 1.0);
            float minSegPx = max(hole[7], 0.0);
            float2 p0s = in.p0, p1s = in.p1;
            float2 p0n = float2(p0s.x * sx + ox, p0s.y * sy + oy);
            float2 p1n = float2(p1s.x * sx + ox, p1s.y * sy + oy);
            float hw = vw * 0.5, hh = vh * 0.5;
            float2 dPx = float2((p1n.x - p0n.x) * hw, (p1n.y - p0n.y) * hh);
            float segPx = length(dPx);
            if (segPx < minSegPx) return;
            float px = in.pos.x, py = in.pos.y;
            float ndcX = 2.0 * px / vw - 1.0;
            float ndcY = 1.0 - 2.0 * py / vh;
            float2 fragScene = float2((ndcX - ox) / sx, (ndcY - oy) / sy);
            float2 M = (p0s + p1s) * 0.5;
            float2 seg = p1s - p0s;
            float slen = length(seg);
            float2 d = slen > 1e-6 ? seg / slen : float2(1.0, 0.0);
            float2 n = float2(-d.y, d.x);
            float pxX = max(vw * 0.5 * sx, 1e-9);
            float pxY = max(vh * 0.5 * sy, 1e-9);
            float pps = min(pxX, pxY);
            float g = circumPx / pps;
            float2 lm = float2(dot(fragScene - M, d), dot(fragScene - M, n));
            if (dot(lm, lm) < g * g) discard_fragment();
        }
        fragment float4 fragment_line_kind(LineVertexOut in [[stage_in]], constant float *rgb [[buffer(0)]], constant float *hole [[buffer(1)]], constant float *layerVis [[buffer(2)]]) {
            fragment_pump_line_hole_discard(in, hole);
            layer_link_discard(in.kind, layerVis);
            float3 cp = float3(rgb[0], rgb[1], rgb[2]);
            float3 cpm = float3(rgb[3], rgb[4], rgb[5]);
            float3 cv = float3(rgb[6], rgb[7], rgb[8]);
            float k = in.kind;
            float3 c = (k < 0.5) ? cp : ((k < 1.5) ? cpm : cv);
            return float4(c, 1);
        }
        fragment float4 fragment_line_scalar(LineVertexOut in [[stage_in]], constant float *range [[buffer(0)]], constant float *hole [[buffer(1)]], constant float *layerVis [[buffer(2)]]) {
            fragment_pump_line_hole_discard(in, hole);
            layer_link_discard(in.kind, layerVis);
            float lo = range[0], hi = range[1];
            float t = (hi > lo) ? ((in.scalar - lo) / (hi - lo)) : 0.5;
            float3 c = colorMap(t);
            return float4(c, 1);
        }
        fragment float4 fragment_highlight_line(LineVertexOut in [[stage_in]], constant float *hole [[buffer(1)]], constant float *layerVis [[buffer(2)]]) {
            fragment_pump_line_hole_discard(in, hole);
            layer_link_discard(in.kind, layerVis);
            return float4(1.0, 0.12, 0.12, 1);
        }
        // 阀门（闸阀简笔）：左右竖法兰 + 中间鼓起阀体 + 顶部横向手轮；uniform[8]=符号半宽(像素)
        struct ValveGlyphOut { float4 pos [[position]]; float2 q; };
        vertex ValveGlyphOut vertex_valve_glyph(
            constant float *uniforms [[buffer(0)]],
            constant float *inst [[buffer(1)]],
            uint vid [[vertex_id]],
            uint iid [[instance_id]])
        {
            float scaleX = uniforms[0], scaleY = uniforms[1], offX = uniforms[2], offY = uniforms[3];
            float vw = uniforms[6], vh = uniforms[7];
            float edgePx = max(uniforms[8], 1.0);
            float pxX = max(vw * 0.5 * scaleX, 1e-9);
            float pxY = max(vh * 0.5 * scaleY, 1e-9);
            float pps = min(pxX, pxY);
            float g = edgePx / pps;
            uint b = iid * 4u;
            float2 M = float2(inst[b], inst[b+1]);
            float2 d = float2(inst[b+2], inst[b+3]);
            float2 n = float2(-d.y, d.x);
            uint c = vid % 6u;
            float2 uvl[6];
            uvl[0]=float2(-1,-1); uvl[1]=float2(1,-1); uvl[2]=float2(1,1);
            uvl[3]=float2(-1,-1); uvl[4]=float2(1,1); uvl[5]=float2(-1,1);
            float2 qu = uvl[c];
            float2 w = M + qu.x * g * d + qu.y * g * n;
            ValveGlyphOut o;
            o.pos = float4(w.x * scaleX + offX, w.y * scaleY + offY, 0, 1);
            o.q = qu;
            return o;
        }
        float valve_sd_box(float2 p, float2 c, float2 b) {
            float2 d = abs(p - c) - b;
            return length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0);
        }
        bool valve_gate_hit(float2 q) {
            // q ∈ [-1,1]^2
            // 去掉法兰外侧短线：不再绘制主流向短管
            bool bodyPipe = false;
            // 法兰高度减少 30%：0.52 -> 0.364
            bool flangeL  = (abs(q.x + 0.55) <= 0.07) && (abs(q.y) <= 0.364);
            bool flangeR  = (abs(q.x - 0.55) <= 0.07) && (abs(q.y) <= 0.364);
            bool bulgedBody = valve_sd_box(q, float2(0.0, 0.0), float2(0.30, 0.23)) <= 0.0;
            bool stem = (abs(q.x) <= 0.045) && (q.y >= 0.22) && (q.y <= 0.58);
            bool wheel = (abs(q.x) <= 0.30) && (abs(q.y - 0.70) <= 0.05);
            return bodyPipe || flangeL || flangeR || bulgedBody || stem || wheel;
        }
        fragment float4 fragment_valve_glyph(ValveGlyphOut in [[stage_in]], constant float *rgb [[buffer(0)]], constant float *layerVis [[buffer(2)]]) {
            layer_link_discard(2.0, layerVis);
            if (!valve_gate_hit(in.q)) discard_fragment();
            return float4(rgb[6], rgb[7], rgb[8], 1);
        }
        // 水泵：空心圆 + 圆上内接等边三角；q∈[-1,1]² 上 |q|=1 为圆，三角顶点 (1,0),(-0.5,±√3/2)；uniform[8]=外接圆半径(像素)，[9]=线宽(像素)
        struct PumpGlyphOut { float4 pos [[position]]; float2 q; float lh [[flat]]; };
        float pump_dist_seg(float2 p, float2 a, float2 b) {
            float2 pa = p - a;
            float2 ba = b - a;
            float denom = max(dot(ba, ba), 1e-9);
            float t = clamp(dot(pa, ba) / denom, 0.0, 1.0);
            float2 proj = a + t * ba;
            return distance(p, proj);
        }
        vertex PumpGlyphOut vertex_pump_glyph(
            constant float *uniforms [[buffer(0)]],
            constant float *inst [[buffer(1)]],
            uint vid [[vertex_id]],
            uint iid [[instance_id]])
        {
            float scaleX = uniforms[0], scaleY = uniforms[1], offX = uniforms[2], offY = uniforms[3];
            float vw = uniforms[6], vh = uniforms[7];
            float circumPx = max(uniforms[8], 1.0);
            float lineWpx = max(uniforms[9], 0.75);
            float pxX = max(vw * 0.5 * scaleX, 1e-9);
            float pxY = max(vh * 0.5 * scaleY, 1e-9);
            float pps = min(pxX, pxY);
            float g = circumPx / pps;
            uint b = iid * 4u;
            float2 M = float2(inst[b], inst[b+1]);
            float2 d = float2(inst[b+2], inst[b+3]);
            float2 n = float2(-d.y, d.x);
            uint c = vid % 6u;
            float2 uvl[6];
            uvl[0]=float2(-1,-1); uvl[1]=float2(1,-1); uvl[2]=float2(1,1);
            uvl[3]=float2(-1,-1); uvl[4]=float2(1,1); uvl[5]=float2(-1,1);
            float2 qu = uvl[c];
            float2 w = M + qu.x * g * d + qu.y * g * n;
            PumpGlyphOut o;
            o.pos = float4(w.x * scaleX + offX, w.y * scaleY + offY, 0, 1);
            o.q = qu;
            o.lh = lineWpx / (2.0 * circumPx);
            return o;
        }
        fragment float4 fragment_pump_hollow(PumpGlyphOut in [[stage_in]], constant float *rgb [[buffer(0)]], constant float *layerVis [[buffer(1)]]) {
            layer_link_discard(1.0, layerVis);
            float r = length(in.q);
            float2 v0 = float2(1.0, 0.0);
            float2 v1 = float2(-0.5, 0.8660254037844386);
            float2 v2 = float2(-0.5, -0.8660254037844386);
            float dtr = min(pump_dist_seg(in.q, v0, v1), min(pump_dist_seg(in.q, v1, v2), pump_dist_seg(in.q, v2, v0)));
            float h = in.lh;
            if ((abs(r - 1.0) >= h) && (dtr >= h)) discard_fragment();
            return float4(rgb[0], rgb[1], rgb[2], 1);
        }
        fragment float4 fragment_pump_hollow_red(PumpGlyphOut in [[stage_in]], constant float *layerVis [[buffer(0)]]) {
            layer_link_discard(1.0, layerVis);
            float r = length(in.q);
            float2 v0 = float2(1.0, 0.0);
            float2 v1 = float2(-0.5, 0.8660254037844386);
            float2 v2 = float2(-0.5, -0.8660254037844386);
            float dtr = min(pump_dist_seg(in.q, v0, v1), min(pump_dist_seg(in.q, v1, v2), pump_dist_seg(in.q, v2, v0)));
            float h = in.lh;
            if ((abs(r - 1.0) >= h) && (dtr >= h)) discard_fragment();
            return float4(1.0, 0.12, 0.12, 1);
        }
        fragment float4 fragment_valve_glyph_red(ValveGlyphOut in [[stage_in]], constant float *layerVis [[buffer(0)]]) {
            layer_link_discard(2.0, layerVis);
            if (!valve_gate_hit(in.q)) discard_fragment();
            return float4(1.0, 0.12, 0.12, 1);
        }
        // uniforms[0..3]=scaleX,scaleY,offX,offY；[4]=标记直径(像素)；[6],[7]=viewport W,H
        float2 node_marker_px_to_ndc(float2 pxFromCenter, float vw, float vh) {
            float hw = max(vw, 1.0) * 0.5;
            float hh = max(vh, 1.0) * 0.5;
            return float2(pxFromCenter.x / hw, -pxFromCenter.y / hh);
        }
        bool node_marker_miss(float2 u, float k) {
            if (k < 0.5) return dot(u, u) > 1.0;
            if (k < 1.5) {
                // local.y ∈ [-0.8,0.8]（顶点侧水库高度为原来的 80%）
                float t = clamp((u.y + 0.8) / 1.6, 0.0, 1.0);
                // 上宽下窄；底端半宽 0.32→+20%
                float halfW = mix(1.0, 0.384, t);
                return abs(u.x) > halfW;
            }
            // Tank：大正方形 [-1,1]²（边长 2）；uy 与画布一致。底角矩形：宽 2/4，高 2/2
            float uy = -u.y;
            float notchW = 0.5;
            float notchH = 1.0;
            bool inBig = (abs(u.x) <= 1.0) && (abs(uy) <= 1.0);
            bool notchBL = (u.x >= -1.0) && (u.x <= -1.0 + notchW) && (uy >= -1.0) && (uy <= -1.0 + notchH);
            bool notchBR = (u.x >= 1.0 - notchW) && (u.x <= 1.0) && (uy >= -1.0) && (uy <= -1.0 + notchH);
            return !(inBig && !notchBL && !notchBR);
        }
        vertex NodeMarkerOut vertex_node_marker_plain(constant float *uniforms [[buffer(0)]], constant float *verts [[buffer(1)]], uint vid [[vertex_id]]) {
            float scaleX = uniforms[0], scaleY = uniforms[1], offX = uniforms[2], offY = uniforms[3];
            float diamPx = max(uniforms[4], 1.0);
            float vw = uniforms[6], vh = uniforms[7];
            uint n = vid / 6u;
            uint c = vid % 6u;
            uint b = n * 3u;
            float2 ps = float2(verts[b], verts[b + 1]);
            float k = verts[b + 2];
            float2 uvl[6];
            uvl[0] = float2(-1, -1); uvl[1] = float2(1, -1); uvl[2] = float2(1, 1);
            uvl[3] = float2(-1, -1); uvl[4] = float2(1, 1); uvl[5] = float2(-1, 1);
            float2 uv = uvl[c];
            float mult = (k < 0.5) ? 1.0 : 3.0;
            float h = diamPx * 0.5 * mult;
            bool res = (k > 0.5 && k < 1.5);
            float2 uvGeom = res ? float2(uv.x, uv.y * 0.8) : uv;
            float2 dNdc = node_marker_px_to_ndc(uvGeom * h, vw, vh);
            float2 cNdc = float2(ps.x * scaleX + offX, ps.y * scaleY + offY);
            NodeMarkerOut o;
            o.pos = float4(cNdc + dNdc, 0, 1);
            o.local = uvGeom;
            o.kind = k;
            return o;
        }
        vertex NodeMarkerScalarOut vertex_node_marker_scalar(constant float *uniforms [[buffer(0)]], constant float *verts [[buffer(1)]], constant float *vals [[buffer(2)]], uint vid [[vertex_id]]) {
            float scaleX = uniforms[0], scaleY = uniforms[1], offX = uniforms[2], offY = uniforms[3];
            float diamPx = max(uniforms[4], 1.0);
            float vw = uniforms[6], vh = uniforms[7];
            uint n = vid / 6u;
            uint c = vid % 6u;
            uint b = n * 3u;
            float2 ps = float2(verts[b], verts[b + 1]);
            float k = verts[b + 2];
            float2 uvl[6];
            uvl[0] = float2(-1, -1); uvl[1] = float2(1, -1); uvl[2] = float2(1, 1);
            uvl[3] = float2(-1, -1); uvl[4] = float2(1, 1); uvl[5] = float2(-1, 1);
            float2 uv = uvl[c];
            float mult = (k < 0.5) ? 1.0 : 3.0;
            float h = diamPx * 0.5 * mult;
            bool res = (k > 0.5 && k < 1.5);
            float2 uvGeom = res ? float2(uv.x, uv.y * 0.8) : uv;
            float2 dNdc = node_marker_px_to_ndc(uvGeom * h, vw, vh);
            float2 cNdc = float2(ps.x * scaleX + offX, ps.y * scaleY + offY);
            NodeMarkerScalarOut o;
            o.pos = float4(cNdc + dNdc, 0, 1);
            o.local = uvGeom;
            o.kind = k;
            o.scalar = vals[n];
            return o;
        }
        fragment float4 fragment_node_marker_kind(NodeMarkerOut in [[stage_in]], constant float *rgb [[buffer(0)]], constant float *layerVis [[buffer(1)]]) {
            if (node_marker_miss(in.local, in.kind)) discard_fragment();
            layer_node_discard(in.kind, layerVis);
            float3 cj = float3(rgb[0], rgb[1], rgb[2]);
            float3 cr = float3(rgb[3], rgb[4], rgb[5]);
            float3 ct = float3(rgb[6], rgb[7], rgb[8]);
            float k = in.kind;
            float3 c = (k < 0.5) ? cj : ((k < 1.5) ? cr : ct);
            return float4(c, 1);
        }
        fragment float4 fragment_node_marker_scalar(NodeMarkerScalarOut in [[stage_in]], constant float *range [[buffer(0)]], constant float *layerVis [[buffer(1)]]) {
            if (node_marker_miss(in.local, in.kind)) discard_fragment();
            layer_node_discard(in.kind, layerVis);
            float lo = range[0], hi = range[1];
            float t = (hi > lo) ? ((in.scalar - lo) / (hi - lo)) : 0.5;
            float3 c = colorMap(t);
            return float4(c, 1);
        }
        fragment float4 fragment_node_marker_highlight(NodeMarkerOut in [[stage_in]], constant float *layerVis [[buffer(0)]]) {
            if (node_marker_miss(in.local, in.kind)) discard_fragment();
            layer_node_discard(in.kind, layerVis);
            return float4(1.0, 0.12, 0.12, 1);
        }
        """

        func buildPipelines(device: MTLDevice) {
            guard pipelineState == nil else { return }
            let library = try? device.makeLibrary(source: Self.metalSource, options: nil)
            let vertNodeMarker = library?.makeFunction(name: "vertex_node_marker_plain")
            let fragNodeMarkerKind = library?.makeFunction(name: "fragment_node_marker_kind")
            let vertLine = library?.makeFunction(name: "vertex_line_plain")
            let fragLine = library?.makeFunction(name: "fragment_line_kind")
            let vertLineScalar = library?.makeFunction(name: "vertex_line_scalar")
            let vertNodeMarkerScalar = library?.makeFunction(name: "vertex_node_marker_scalar")
            let pipelineDesc = MTLRenderPipelineDescriptor()
            pipelineDesc.vertexFunction = vertNodeMarker
            pipelineDesc.fragmentFunction = fragNodeMarkerKind
            pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDesc)
            let lineDesc = MTLRenderPipelineDescriptor()
            lineDesc.vertexFunction = vertLine
            lineDesc.fragmentFunction = fragLine
            lineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            linePipeline = try? device.makeRenderPipelineState(descriptor: lineDesc)
            let fragLineScalar = library?.makeFunction(name: "fragment_line_scalar")
            let lineScalarDesc = MTLRenderPipelineDescriptor()
            lineScalarDesc.vertexFunction = vertLineScalar
            lineScalarDesc.fragmentFunction = fragLineScalar
            lineScalarDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            lineScalarPipeline = try? device.makeRenderPipelineState(descriptor: lineScalarDesc)
            let fragLineHi = library?.makeFunction(name: "fragment_highlight_line")
            let lineHiDesc = MTLRenderPipelineDescriptor()
            lineHiDesc.vertexFunction = vertLine
            lineHiDesc.fragmentFunction = fragLineHi
            lineHiDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            lineHighlightPipeline = try? device.makeRenderPipelineState(descriptor: lineHiDesc)
            let vertValveGlyph = library?.makeFunction(name: "vertex_valve_glyph")
            let fragValveGlyph = library?.makeFunction(name: "fragment_valve_glyph")
            let valveGlyphDesc = MTLRenderPipelineDescriptor()
            valveGlyphDesc.vertexFunction = vertValveGlyph
            valveGlyphDesc.fragmentFunction = fragValveGlyph
            valveGlyphDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            valveGlyphPipeline = try? device.makeRenderPipelineState(descriptor: valveGlyphDesc)
            let fragValveRed = library?.makeFunction(name: "fragment_valve_glyph_red")
            let valveGlyphHiDesc = MTLRenderPipelineDescriptor()
            valveGlyphHiDesc.vertexFunction = vertValveGlyph
            valveGlyphHiDesc.fragmentFunction = fragValveRed
            valveGlyphHiDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            valveGlyphHighlightPipeline = try? device.makeRenderPipelineState(descriptor: valveGlyphHiDesc)
            let vertPumpGlyph = library?.makeFunction(name: "vertex_pump_glyph")
            let fragPumpHollow = library?.makeFunction(name: "fragment_pump_hollow")
            let pumpGlyphDesc = MTLRenderPipelineDescriptor()
            pumpGlyphDesc.vertexFunction = vertPumpGlyph
            pumpGlyphDesc.fragmentFunction = fragPumpHollow
            pumpGlyphDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pumpGlyphPipeline = try? device.makeRenderPipelineState(descriptor: pumpGlyphDesc)
            let fragPumpHollowRed = library?.makeFunction(name: "fragment_pump_hollow_red")
            let pumpGlyphHiDesc = MTLRenderPipelineDescriptor()
            pumpGlyphHiDesc.vertexFunction = vertPumpGlyph
            pumpGlyphHiDesc.fragmentFunction = fragPumpHollowRed
            pumpGlyphHiDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pumpGlyphHighlightPipeline = try? device.makeRenderPipelineState(descriptor: pumpGlyphHiDesc)
            let fragNodeMarkerHi = library?.makeFunction(name: "fragment_node_marker_highlight")
            let pointHiDesc = MTLRenderPipelineDescriptor()
            pointHiDesc.vertexFunction = vertNodeMarker
            pointHiDesc.fragmentFunction = fragNodeMarkerHi
            pointHiDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pointHighlightPipeline = try? device.makeRenderPipelineState(descriptor: pointHiDesc)
            let fragNodeMarkerScalar = library?.makeFunction(name: "fragment_node_marker_scalar")
            let pointScalarDesc = MTLRenderPipelineDescriptor()
            pointScalarDesc.vertexFunction = vertNodeMarkerScalar
            pointScalarDesc.fragmentFunction = fragNodeMarkerScalar
            pointScalarDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pointScalarPipeline = try? device.makeRenderPipelineState(descriptor: pointScalarDesc)
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            guard size.width > 0, size.height > 0 else { return }
            if size.width != lastNotifiedDrawableSize.width || size.height != lastNotifiedDrawableSize.height {
                lastNotifiedDrawableSize = size
                onDrawableSizeChange?(size)
            }
            // isPaused 时需在尺寸变化后主动提交一帧，避免画布空白或与覆盖层错位
            view.draw()
        }

        public func draw(in view: MTKView) {
            guard let device = view.device,
                  let drawable = view.currentDrawable,
                  let rpd = view.currentRenderPassDescriptor,
                  let scene = scene, !scene.nodes.isEmpty else {
                return
            }
            buildPipelines(device: device)
            if commandQueue == nil {
                commandQueue = device.makeCommandQueue()
            }
            guard let queue = commandQueue else { return }

            let geomDirty = sceneGeometryRevision != lastUploadedGeometryRevision
            if geomDirty {
                lastUploadedGeometryRevision = sceneGeometryRevision
                let lineVerts = makeLineVertices(from: scene)
                let pointVerts = makePointVertices(from: scene)
                if lineVerts.count > 0 {
                    lineBuffer = device.makeBuffer(bytes: lineVerts, length: lineVerts.count * MemoryLayout<Float>.stride, options: .storageModeShared)
                    lineCount = scene.links.count
                } else {
                    lineBuffer = nil
                    lineCount = 0
                }
                let valveInst = makeValveGlyphInstances(from: scene)
                if !valveInst.isEmpty {
                    valveGlyphBuffer = device.makeBuffer(bytes: valveInst, length: valveInst.count * MemoryLayout<Float>.stride, options: .storageModeShared)
                    valveGlyphCount = valveInst.count / 4
                } else {
                    valveGlyphBuffer = nil
                    valveGlyphCount = 0
                }
                if pointVerts.count > 0 {
                    pointBuffer = device.makeBuffer(bytes: pointVerts, length: pointVerts.count * MemoryLayout<Float>.stride, options: .storageModeShared)
                    pointCount = scene.nodes.count
                } else {
                    pointBuffer = nil
                    pointCount = 0
                }
            }

            let scalarDirty = geomDirty || resultScalarRevision != lastUploadedResultScalarRevision
            if scalarDirty {
                lastUploadedResultScalarRevision = resultScalarRevision
                if let linkScalars = linkScalars, linkScalars.count == lineCount, lineCount > 0 {
                    lineScalarBuffer = device.makeBuffer(bytes: linkScalars, length: linkScalars.count * MemoryLayout<Float>.stride, options: .storageModeShared)
                } else {
                    lineScalarBuffer = nil
                }
                if let nodeScalars = nodeScalars, nodeScalars.count == pointCount, pointCount > 0 {
                    pointScalarBuffer = device.makeBuffer(bytes: nodeScalars, length: nodeScalars.count * MemoryLayout<Float>.stride, options: .storageModeShared)
                } else {
                    pointScalarBuffer = nil
                }
            }

            // Viewport: full size. XY 比例一致 — 同一场景单位在 X/Y 方向映射到相同像素长度，不拉变形
            let dw = Float(view.drawableSize.width), dh = Float(view.drawableSize.height)
            let proj = viewportProjection(drawableW: dw, drawableH: dh, scene: scene)
            let scaleX = proj.sx
            let scaleYVal = proj.sy
            let offX = proj.ox
            let offY = proj.oy

            // 管段线宽：顶点着色器内按「屏幕像素」在 NDC 侧展开，uniform 传像素线宽 + viewport（见 metal 中 line_extrude_ndc）
            let lineWpx = max(linkLineWidthPixels, 0.5)
            // 与水泵符号绘制一致，供 fragment 在圆盘内 discard 管线（不穿过空心圆内部）
            let pumpLegendCircumPt = Float(min(12, 10)) * 0.5 - Float(1.05) * 0.5 - 0.25
            let pumpCircumPx = pumpLegendCircumPt * 3
            // 屏幕上线段长度须至少约等于外接圆直径，否则不画水泵符号、管线也不挖孔
            let minPumpSegPx = 2 * pumpCircumPx * 1.08
            let lineHoleUniforms: [Float] = [scaleX, scaleYVal, offX, offY, dw, dh, pumpCircumPx, minPumpSegPx]
            let lineUniLen = 9 * MemoryLayout<Float>.stride
            var linkLayerVis: [Float] = [
                layerVisibility.showPipe ? 1 : 0,
                layerVisibility.showPump ? 1 : 0,
                layerVisibility.showValve ? 1 : 0,
            ]
            var nodeLayerVis: [Float] = [
                layerVisibility.showJunction ? 1 : 0,
                layerVisibility.showReservoir ? 1 : 0,
                layerVisibility.showTank ? 1 : 0,
            ]
            let layerVisBytes = 3 * MemoryLayout<Float>.stride

            guard let cmdBuf = queue.makeCommandBuffer(),
                  let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return }

            enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(dw), height: Double(dh), znear: 0, zfar: 1))

            // Draw links：每段 6 顶点；双剖分第二遍仅在「视窗内可见管段」少于阈值时启用
            if let buf = lineBuffer, lineCount > 0 {
                let visRect = Self.visibleSceneRect(scaleX: scaleX, scaleY: scaleYVal, offX: offX, offY: offY)
                let visibleLinkCount = Self.countLinksIntersectingVisibleRect(links: scene.links, rect: visRect)
                // 1px 级仍易在三角剖分接缝露白，细线时保留双剖分
                let useLineDualPass = visibleLinkCount < Self.lineGeometryDualPassVisibleLinkThreshold
                    || lineWpx <= 1.5
                enc.setCullMode(.none)
                enc.setVertexBuffer(nil, offset: 0, index: 2)
                var lineHole = lineHoleUniforms
                if let lineScalarPipeline = lineScalarPipeline,
                   let scalarBuf = lineScalarBuffer,
                   let range = linkScalarRange {
                    enc.setRenderPipelineState(lineScalarPipeline)
                    var r: [Float] = [range.0, range.1]
                    enc.setFragmentBytes(&r, length: 8, index: 0)
                    enc.setFragmentBytes(&lineHole, length: lineHole.count * MemoryLayout<Float>.stride, index: 1)
                    enc.setFragmentBytes(&linkLayerVis, length: layerVisBytes, index: 2)
                    enc.setVertexBuffer(scalarBuf, offset: 0, index: 2)
                    var uniforms: [Float] = [scaleX, scaleYVal, offX, offY, lineWpx, 0, dw, dh, pumpCircumPx]
                    enc.setVertexBytes(&uniforms, length: lineUniLen, index: 0)
                    enc.setVertexBuffer(buf, offset: 0, index: 1)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: lineCount * 6)
                    if useLineDualPass {
                        uniforms[5] = 1
                        enc.setVertexBytes(&uniforms, length: lineUniLen, index: 0)
                        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: lineCount * 6)
                    }
                } else if let linePipeline = linePipeline {
                    enc.setRenderPipelineState(linePipeline)
                    var rgb: [Float] = [
                        linkRGBPipe.0, linkRGBPipe.1, linkRGBPipe.2,
                        linkRGBPump.0, linkRGBPump.1, linkRGBPump.2,
                        linkRGBValve.0, linkRGBValve.1, linkRGBValve.2,
                    ]
                    enc.setFragmentBytes(&rgb, length: rgb.count * MemoryLayout<Float>.stride, index: 0)
                    enc.setFragmentBytes(&lineHole, length: lineHole.count * MemoryLayout<Float>.stride, index: 1)
                    enc.setFragmentBytes(&linkLayerVis, length: layerVisBytes, index: 2)
                    var uniforms: [Float] = [scaleX, scaleYVal, offX, offY, lineWpx, 0, dw, dh, pumpCircumPx]
                    enc.setVertexBytes(&uniforms, length: lineUniLen, index: 0)
                    enc.setVertexBuffer(buf, offset: 0, index: 1)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: lineCount * 6)
                    if useLineDualPass {
                        uniforms[5] = 1
                        enc.setVertexBytes(&uniforms, length: lineUniLen, index: 0)
                        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: lineCount * 6)
                    }
                }
            }

            // 阀门符号：盖在阀门管段中点（与管线同向，scalar 模式下仍用阀门色）
            if let vbuf = valveGlyphBuffer, valveGlyphCount > 0, let vpipe = valveGlyphPipeline {
                let valveEdgePx = max(linkLineWidthPixels * 4.5, 7) * 3
                enc.setRenderPipelineState(vpipe)
                enc.setCullMode(.none)
                enc.setVertexBuffer(nil, offset: 0, index: 2)
                var rgbV: [Float] = [
                    linkRGBPipe.0, linkRGBPipe.1, linkRGBPipe.2,
                    linkRGBPump.0, linkRGBPump.1, linkRGBPump.2,
                    linkRGBValve.0, linkRGBValve.1, linkRGBValve.2,
                ]
                enc.setFragmentBytes(&rgbV, length: rgbV.count * MemoryLayout<Float>.stride, index: 0)
                var lineHoleV = lineHoleUniforms
                enc.setFragmentBytes(&lineHoleV, length: lineHoleV.count * MemoryLayout<Float>.stride, index: 1)
                enc.setFragmentBytes(&linkLayerVis, length: layerVisBytes, index: 2)
                var vuni: [Float] = [scaleX, scaleYVal, offX, offY, 0, 0, dw, dh, valveEdgePx]
                enc.setVertexBytes(&vuni, length: vuni.count * MemoryLayout<Float>.stride, index: 0)
                enc.setVertexBuffer(vbuf, offset: 0, index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: valveGlyphCount)
            }

            // 水泵符号：仅当两端点在当前缩放下屏幕距离 ≥ 外接圆直径时绘制（否则隐藏，避免符号压扁/重叠）
            if let ppipe = pumpGlyphPipeline {
                var pumpInst: [Float] = []
                pumpInst.reserveCapacity(scene.links.count * 4)
                for l in scene.links where l.kind == 1 && layerVisibility.showPump {
                    let span = Self.linkScreenSpanPixels(
                        x1: l.x1, y1: l.y1, x2: l.x2, y2: l.y2,
                        scaleX: scaleX, scaleY: scaleYVal, offX: offX, offY: offY,
                        drawableW: dw, drawableH: dh
                    )
                    if span >= minPumpSegPx {
                        appendPumpGlyphInstance(link: l, to: &pumpInst)
                    }
                }
                if !pumpInst.isEmpty {
                    let byteCount = pumpInst.count * MemoryLayout<Float>.stride
                    if pumpDrawInstancesCapacityBytes < byteCount {
                        pumpDrawInstancesCapacityBytes = max(byteCount, 64 * MemoryLayout<Float>.stride)
                        pumpDrawInstancesBuffer = device.makeBuffer(length: pumpDrawInstancesCapacityBytes, options: .storageModeShared)
                    }
                    if let pbuf = pumpDrawInstancesBuffer {
                        pumpInst.withUnsafeBytes { raw in
                            if let base = raw.bindMemory(to: UInt8.self).baseAddress {
                                memcpy(pbuf.contents(), base, byteCount)
                            }
                        }
                        let pumpStrokePx = max(linkLineWidthPixels, 0.85)
                        enc.setRenderPipelineState(ppipe)
                        enc.setCullMode(.none)
                        enc.setVertexBuffer(nil, offset: 0, index: 2)
                        var rgbP: [Float] = [linkRGBPump.0, linkRGBPump.1, linkRGBPump.2]
                        enc.setFragmentBytes(&rgbP, length: rgbP.count * MemoryLayout<Float>.stride, index: 0)
                        enc.setFragmentBytes(&linkLayerVis, length: layerVisBytes, index: 1)
                        var puni: [Float] = [scaleX, scaleYVal, offX, offY, 0, 0, dw, dh, pumpCircumPx, pumpStrokePx]
                        enc.setVertexBytes(&puni, length: puni.count * MemoryLayout<Float>.stride, index: 0)
                        enc.setVertexBuffer(pbuf, offset: 0, index: 1)
                        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: pumpInst.count / 4)
                    }
                }
            }

            // Draw node markers（每节点 6 顶点三角带；顶点 x,y,kind；uniform 与线一致含 viewport）
            if let buf = pointBuffer, pointCount > 0 {
                let nodeUniLen = 8 * MemoryLayout<Float>.stride
                var uniforms: [Float] = [scaleX, scaleYVal, offX, offY, nodePointSizePixels, 0, dw, dh]
                // Always clear optional scalar buffer binding to avoid stale GPU pointers.
                enc.setVertexBuffer(nil, offset: 0, index: 2)
                if let pointScalarPipeline = pointScalarPipeline,
                   let scalarBuf = pointScalarBuffer,
                   let range = nodeScalarRange {
                    enc.setRenderPipelineState(pointScalarPipeline)
                    var r: [Float] = [range.0, range.1]
                    enc.setFragmentBytes(&r, length: 8, index: 0)
                    enc.setFragmentBytes(&nodeLayerVis, length: layerVisBytes, index: 1)
                    enc.setVertexBuffer(scalarBuf, offset: 0, index: 2)
                } else if let pipelineState = pipelineState {
                    enc.setRenderPipelineState(pipelineState)
                    var rgb: [Float] = [
                        nodeRGBJunction.0, nodeRGBJunction.1, nodeRGBJunction.2,
                        nodeRGBReservoir.0, nodeRGBReservoir.1, nodeRGBReservoir.2,
                        nodeRGBTank.0, nodeRGBTank.1, nodeRGBTank.2,
                    ]
                    enc.setFragmentBytes(&rgb, length: rgb.count * MemoryLayout<Float>.stride, index: 0)
                    enc.setFragmentBytes(&nodeLayerVis, length: layerVisBytes, index: 1)
                }
                enc.setVertexBytes(&uniforms, length: nodeUniLen, index: 0)
                enc.setVertexBuffer(buf, offset: 0, index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: pointCount * 6)
            }
            // Highlight selected link(s)（略宽，像素空间与常规定义一致）
            let linkHiList: [Int] = {
                if !selectedLinkIndices.isEmpty { return selectedLinkIndices }
                if let idx = selectedLinkIndex, idx >= 0 { return [idx] }
                return []
            }()
            if !linkHiList.isEmpty, let lineHi = lineHighlightPipeline, let buf = lineBuffer {
                enc.setRenderPipelineState(lineHi)
                enc.setCullMode(.none)
                let hiWpx = min(max(linkLineWidthPixels * 1.5, lineWpx + 1), 32)
                var lineHoleHi = lineHoleUniforms
                enc.setFragmentBytes(&lineHoleHi, length: lineHoleHi.count * MemoryLayout<Float>.stride, index: 1)
                enc.setFragmentBytes(&linkLayerVis, length: layerVisBytes, index: 2)
                var uniforms: [Float] = [scaleX, scaleYVal, offX, offY, hiWpx, 0, dw, dh, pumpCircumPx]
                for idx in linkHiList where idx >= 0 && idx < lineCount {
                    enc.setVertexBytes(&uniforms, length: lineUniLen, index: 0)
                    enc.setVertexBuffer(buf, offset: 0, index: 1)
                    enc.drawPrimitives(type: .triangle, vertexStart: idx * 6, vertexCount: 6)
                    uniforms[5] = 1
                    enc.setVertexBytes(&uniforms, length: lineUniLen, index: 0)
                    enc.drawPrimitives(type: .triangle, vertexStart: idx * 6, vertexCount: 6)
                    uniforms[5] = 0
                }
            }
            // 选中阀门/水泵：管段高亮对水泵段挖孔、粗线未必盖住阀门三角，再叠一层红色符号
            if !linkHiList.isEmpty {
                var hiValveInst: [Float] = []
                hiValveInst.reserveCapacity(linkHiList.count * 4)
                var hiPumpInst: [Float] = []
                hiPumpInst.reserveCapacity(linkHiList.count * 4)
                for idx in linkHiList where idx >= 0 && idx < scene.links.count {
                    let l = scene.links[idx]
                    if l.kind == 2 {
                        let mx = (l.x1 + l.x2) * 0.5
                        let my = (l.y1 + l.y2) * 0.5
                        var dx = l.x2 - l.x1
                        var dy = l.y2 - l.y1
                        let len = (dx * dx + dy * dy).squareRoot()
                        if len < 1e-5 {
                            dx = 1
                            dy = 0
                        } else {
                            dx /= len
                            dy /= len
                        }
                        hiValveInst.append(contentsOf: [mx, my, dx, dy])
                    } else if l.kind == 1 {
                        let span = Self.linkScreenSpanPixels(
                            x1: l.x1, y1: l.y1, x2: l.x2, y2: l.y2,
                            scaleX: scaleX, scaleY: scaleYVal, offX: offX, offY: offY,
                            drawableW: dw, drawableH: dh
                        )
                        if span >= minPumpSegPx {
                            appendPumpGlyphInstance(link: l, to: &hiPumpInst)
                        }
                    }
                }
                let valveEdgePx = max(linkLineWidthPixels * 4.5, 7) * 3
                enc.setCullMode(.none)
                enc.setVertexBuffer(nil, offset: 0, index: 2)
                if !hiValveInst.isEmpty, let vpipe = valveGlyphHighlightPipeline,
                   let ob = ensureSelectionGlyphOverlayBuffer(device: device, byteCount: hiValveInst.count * MemoryLayout<Float>.stride) {
                    let byteCount = hiValveInst.count * MemoryLayout<Float>.stride
                    hiValveInst.withUnsafeBytes { raw in
                        if let base = raw.bindMemory(to: UInt8.self).baseAddress {
                            memcpy(ob.contents(), base, byteCount)
                        }
                    }
                    enc.setRenderPipelineState(vpipe)
                    enc.setFragmentBytes(&linkLayerVis, length: layerVisBytes, index: 0)
                    var vuni: [Float] = [scaleX, scaleYVal, offX, offY, 0, 0, dw, dh, valveEdgePx]
                    enc.setVertexBytes(&vuni, length: vuni.count * MemoryLayout<Float>.stride, index: 0)
                    enc.setVertexBuffer(ob, offset: 0, index: 1)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: hiValveInst.count / 4)
                }
                if !hiPumpInst.isEmpty, let ppipe = pumpGlyphHighlightPipeline,
                   let ob = ensureSelectionGlyphOverlayBuffer(device: device, byteCount: hiPumpInst.count * MemoryLayout<Float>.stride) {
                    let byteCount = hiPumpInst.count * MemoryLayout<Float>.stride
                    hiPumpInst.withUnsafeBytes { raw in
                        if let base = raw.bindMemory(to: UInt8.self).baseAddress {
                            memcpy(ob.contents(), base, byteCount)
                        }
                    }
                    let pumpStrokePx = max(linkLineWidthPixels, 0.85)
                    enc.setRenderPipelineState(ppipe)
                    enc.setFragmentBytes(&linkLayerVis, length: layerVisBytes, index: 0)
                    var puni: [Float] = [scaleX, scaleYVal, offX, offY, 0, 0, dw, dh, pumpCircumPx, pumpStrokePx]
                    enc.setVertexBytes(&puni, length: puni.count * MemoryLayout<Float>.stride, index: 0)
                    enc.setVertexBuffer(ob, offset: 0, index: 1)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: hiPumpInst.count / 4)
                }
            }
            // Highlight selected node(s)（同三角标记，略放大直径）
            let nodeHiList: [Int] = {
                if !selectedNodeIndices.isEmpty { return selectedNodeIndices }
                if let idx = selectedNodeIndex, idx >= 0 { return [idx] }
                return []
            }()
            if !nodeHiList.isEmpty, let pointHi = pointHighlightPipeline, let buf = pointBuffer {
                enc.setRenderPipelineState(pointHi)
                enc.setFragmentBytes(&nodeLayerVis, length: layerVisBytes, index: 0)
                let nodeUniLen = 8 * MemoryLayout<Float>.stride
                let hiDiam = min(max(nodePointSizePixels * 1.35, nodePointSizePixels + 2), 40)
                var uniforms: [Float] = [scaleX, scaleYVal, offX, offY, hiDiam, 0, dw, dh]
                for idx in nodeHiList where idx >= 0 && idx < pointCount {
                    enc.setVertexBytes(&uniforms, length: nodeUniLen, index: 0)
                    enc.setVertexBuffer(buf, offset: 0, index: 1)
                    enc.drawPrimitives(type: .triangle, vertexStart: idx * 6, vertexCount: 6)
                }
            }

            enc.endEncoding()
            cmdBuf.present(drawable)
            cmdBuf.commit()
        }

        /// Hit test: 点优先于线。节点在容差内则选节点，否则在管段容差内才选管段。管段在「半线宽」与最小屏幕像素容差间取较大者，再上封顶避免误选过远对象。
        public func hitTest(viewPoint: CGPoint, viewSize: CGSize) -> (Int?, Int?) {
            guard let scene = scene, !scene.nodes.isEmpty, viewSize.width > 0, viewSize.height > 0 else { return (nil, nil) }
            let w = Float(viewSize.width), h = Float(viewSize.height)
            let proj = viewportProjection(drawableW: w, drawableH: h, scene: scene)
            let scaleX = proj.sx
            let scaleY = proj.sy
            let offX = proj.ox
            let offY = proj.oy
            let ndcX = 2 * Float(viewPoint.x) / w - 1
            let ndcY = 1 - 2 * Float(viewPoint.y) / h
            let sx = (ndcX - offX) / scaleX
            let sy = (ndcY - offY) / scaleY
            let pixelsPerScene = Self.pixelsPerSceneUnitForConstantScreenLineWidth(scaleX: scaleX, scaleY: scaleY, drawableW: w, drawableH: h)
            let nodeRadiusBase = max(nodePointSizePixels * 0.5, 1) / pixelsPerScene
            let visualLinkHalfScene = max(linkLineWidthPixels, 0.5) * 0.5 / pixelsPerScene
            let minPickHalfScene = Self.linkHitTestMinHalfWidthPixels / pixelsPerScene
            var linkHalfWidthScene = max(visualLinkHalfScene, minPickHalfScene)
            linkHalfWidthScene = min(linkHalfWidthScene, proj.span * 0.04)
            var bestNode: (index: Int, dist: Float)?
            for (i, n) in scene.nodes.enumerated() {
                if !layerVisibility.isNodeKindVisible(n.kind) { continue }
                let d = (n.x - sx) * (n.x - sx) + (n.y - sy) * (n.y - sy)
                // 水池/水塔画布标记为 junction 直径的 3 倍，hit 与方形角点略放大
                let nodeRadiusScene = nodeRadiusBase * (n.kind == 0 ? 1 : (3 * 1.12))
                let r = nodeRadiusScene * nodeRadiusScene
                if d <= r, bestNode == nil || d < bestNode!.dist { bestNode = (i, d) }
            }
            var bestLink: (index: Int, dist: Float)?
            for (i, l) in scene.links.enumerated() {
                if !layerVisibility.isLinkKindVisible(l.kind) { continue }
                let d = Self.distToSegment(px: sx, py: sy, x1: l.x1, y1: l.y1, x2: l.x2, y2: l.y2)
                if d <= linkHalfWidthScene, bestLink == nil || d < bestLink!.dist { bestLink = (i, d) }
            }
            if let b = bestNode {
                let n = scene.nodes[b.index]
                let nodeRadiusScene = nodeRadiusBase * (n.kind == 0 ? 1 : (3 * 1.12))
                if b.dist.squareRoot() <= nodeRadiusScene { return (b.index, nil) }
            }
            if let b = bestLink { return (nil, b.index) }
            return (nil, nil)
        }
        /// 视图坐标转场景坐标（与 hitTest 一致），无场景时返回 nil
        public func viewToScene(viewPoint: CGPoint, viewSize: CGSize) -> (Float, Float)? {
            guard let scene = scene, viewSize.width > 0, viewSize.height > 0 else { return nil }
            let w = Float(viewSize.width), h = Float(viewSize.height)
            let fr = framingRect(for: scene)
            let bw = fr.maxX - fr.minX
            let bh = fr.maxY - fr.minY
            guard bw > 0, bh > 0 else { return nil }
            let proj = viewportProjection(drawableW: w, drawableH: h, scene: scene)
            let scaleX = proj.sx
            let scaleY = proj.sy
            let offX = proj.ox
            let offY = proj.oy
            let ndcX = 2 * Float(viewPoint.x) / w - 1
            let ndcY = 1 - 2 * Float(viewPoint.y) / h
            let sx = (ndcX - offX) / scaleX
            let sy = (ndcY - offY) / scaleY
            return (sx, sy)
        }
        /// ndc x,y ∈ [-1,1] 对应场景轴对齐可见矩形（与 draw 变换一致）
        private static func visibleSceneRect(scaleX: Float, scaleY: Float, offX: Float, offY: Float) -> (minX: Float, maxX: Float, minY: Float, maxY: Float) {
            let xLo = (-1 - offX) / scaleX
            let xHi = (1 - offX) / scaleX
            let yLo = (-1 - offY) / scaleY
            let yHi = (1 - offY) / scaleY
            return (Swift.min(xLo, xHi), Swift.max(xLo, xHi), Swift.min(yLo, yHi), Swift.max(yLo, yHi))
        }

        /// 管段端点 AABB 与视窗可见矩形相交则视为视窗内可能可见
        private static func countLinksIntersectingVisibleRect(links: [LinkVertex], rect: (minX: Float, maxX: Float, minY: Float, maxY: Float)) -> Int {
            let vx0 = rect.minX, vx1 = rect.maxX, vy0 = rect.minY, vy1 = rect.maxY
            var n = 0
            for l in links {
                let lx0 = min(l.x1, l.x2), lx1 = max(l.x1, l.x2)
                let ly0 = min(l.y1, l.y2), ly1 = max(l.y1, l.y2)
                if lx1 < vx0 || lx0 > vx1 || ly1 < vy0 || ly0 > vy1 { continue }
                n += 1
            }
            return n
        }

        /// hitTest / 节点：等效「每场景单位」像素数（与 NDC 缩放一致）；管段渲染已改屏幕空间展开，不再用此值算管宽。
        private static func pixelsPerSceneUnitForConstantScreenLineWidth(scaleX: Float, scaleY: Float, drawableW: Float, drawableH: Float) -> Float {
            let pxX = max(drawableW * 0.5 * scaleX, 1e-9)
            let pxY = max(drawableH * 0.5 * scaleY, 1e-9)
            return min(pxX, pxY)
        }

        /// 管段两端在当前视窗下的屏幕像素长度（与 `line_extrude_ndc` 中 dPx 一致）
        private static func linkScreenSpanPixels(
            x1: Float, y1: Float, x2: Float, y2: Float,
            scaleX: Float, scaleY: Float, offX: Float, offY: Float,
            drawableW: Float, drawableH: Float
        ) -> Float {
            let aNdcX = x1 * scaleX + offX
            let aNdcY = y1 * scaleY + offY
            let bNdcX = x2 * scaleX + offX
            let bNdcY = y2 * scaleY + offY
            let hw = max(drawableW, 1) * 0.5
            let hh = max(drawableH, 1) * 0.5
            let dPxX = (bNdcX - aNdcX) * hw
            let dPxY = (bNdcY - aNdcY) * hh
            return (dPxX * dPxX + dPxY * dPxY).squareRoot()
        }

        private static func distToSegment(px: Float, py: Float, x1: Float, y1: Float, x2: Float, y2: Float) -> Float {
            let dx = x2 - x1, dy = y2 - y1
            let len = (dx * dx + dy * dy).squareRoot()
            if len == 0 { return ((px - x1) * (px - x1) + (py - y1) * (py - y1)).squareRoot() }
            var t = ((px - x1) * dx + (py - y1) * dy) / (len * len)
            t = max(0, min(1, t))
            let qx = x1 + t * dx, qy = y1 + t * dy
            return ((px - qx) * (px - qx) + (py - qy) * (py - qy)).squareRoot()
        }

        /// 框选模式：从左往右为 crossing（与框相交即选中），从右往左为 window（完全在框内才选中）。
        public enum MarqueeSelectionMode {
            case crossing
            case window
        }

        /// 视图轴对齐矩形对应场景轴对齐包围盒（`viewToScene` 对 x/y 可分步线性变换）。
        public func sceneBoundingRectFromViewRect(_ viewRect: CGRect, viewSize: CGSize) -> (minX: Float, maxX: Float, minY: Float, maxY: Float)? {
            guard scene != nil, viewSize.width > 0, viewSize.height > 0 else { return nil }
            guard let pLeft = viewToScene(viewPoint: CGPoint(x: viewRect.minX, y: viewRect.midY), viewSize: viewSize),
                  let pRight = viewToScene(viewPoint: CGPoint(x: viewRect.maxX, y: viewRect.midY), viewSize: viewSize),
                  let pTop = viewToScene(viewPoint: CGPoint(x: viewRect.midX, y: viewRect.minY), viewSize: viewSize),
                  let pBottom = viewToScene(viewPoint: CGPoint(x: viewRect.midX, y: viewRect.maxY), viewSize: viewSize) else { return nil }
            let sxMin = min(pLeft.0, pRight.0)
            let sxMax = max(pLeft.0, pRight.0)
            let syMin = min(pTop.1, pBottom.1)
            let syMax = max(pTop.1, pBottom.1)
            return (sxMin, sxMax, syMin, syMax)
        }

        /// 在场景矩形内按模式筛选节点索引与管段索引（与 `hitTest` 节点半径一致）。
        public func indicesInMarquee(
            sceneRect: (minX: Float, maxX: Float, minY: Float, maxY: Float),
            viewSize: CGSize,
            mode: MarqueeSelectionMode
        ) -> (nodes: Set<Int>, links: Set<Int>) {
            guard let scene = scene, viewSize.width > 0, viewSize.height > 0 else { return ([], []) }
            let w = Float(viewSize.width), h = Float(viewSize.height)
            let proj = viewportProjection(drawableW: w, drawableH: h, scene: scene)
            let pixelsPerScene = Self.pixelsPerSceneUnitForConstantScreenLineWidth(scaleX: proj.sx, scaleY: proj.sy, drawableW: w, drawableH: h)
            let nodeRadiusBase = max(nodePointSizePixels * 0.5, 1) / pixelsPerScene
            let rxMin = min(sceneRect.minX, sceneRect.maxX)
            let rxMax = max(sceneRect.minX, sceneRect.maxX)
            let ryMin = min(sceneRect.minY, sceneRect.maxY)
            let ryMax = max(sceneRect.minY, sceneRect.maxY)
            let rect = (minX: rxMin, maxX: rxMax, minY: ryMin, maxY: ryMax)

            var nodeSet = Set<Int>()
            for (i, n) in scene.nodes.enumerated() {
                if !layerVisibility.isNodeKindVisible(n.kind) { continue }
                let r = nodeRadiusBase * (n.kind == 0 ? 1 : (3 * 1.12))
                let ok: Bool
                switch mode {
                case .crossing:
                    ok = Self.circleIntersectsAxisAlignedRect(cx: n.x, cy: n.y, r: r, rect: rect)
                case .window:
                    ok = Self.circleFullyInsideAxisAlignedRect(cx: n.x, cy: n.y, r: r, rect: rect)
                }
                if ok { nodeSet.insert(i) }
            }

            var linkSet = Set<Int>()
            for (i, l) in scene.links.enumerated() {
                if !layerVisibility.isLinkKindVisible(l.kind) { continue }
                let ok: Bool
                switch mode {
                case .crossing:
                    ok = Self.segmentIntersectsAxisAlignedRect(x1: l.x1, y1: l.y1, x2: l.x2, y2: l.y2, rect: rect)
                case .window:
                    ok = Self.pointInsideRect(l.x1, l.y1, rect) && Self.pointInsideRect(l.x2, l.y2, rect)
                }
                if ok { linkSet.insert(i) }
            }
            return (nodeSet, linkSet)
        }

        private static func pointInsideRect(_ x: Float, _ y: Float, _ rect: (minX: Float, maxX: Float, minY: Float, maxY: Float)) -> Bool {
            x >= rect.minX && x <= rect.maxX && y >= rect.minY && y <= rect.maxY
        }

        private static func circleIntersectsAxisAlignedRect(cx: Float, cy: Float, r: Float, rect: (minX: Float, maxX: Float, minY: Float, maxY: Float)) -> Bool {
            let closestX = min(max(cx, rect.minX), rect.maxX)
            let closestY = min(max(cy, rect.minY), rect.maxY)
            let dx = cx - closestX
            let dy = cy - closestY
            return dx * dx + dy * dy <= r * r
        }

        private static func circleFullyInsideAxisAlignedRect(cx: Float, cy: Float, r: Float, rect: (minX: Float, maxX: Float, minY: Float, maxY: Float)) -> Bool {
            cx - r >= rect.minX && cx + r <= rect.maxX && cy - r >= rect.minY && cy + r <= rect.maxY
        }

        private static func segmentIntersectsAxisAlignedRect(
            x1: Float, y1: Float, x2: Float, y2: Float,
            rect: (minX: Float, maxX: Float, minY: Float, maxY: Float)
        ) -> Bool {
            if pointInsideRect(x1, y1, rect) || pointInsideRect(x2, y2, rect) { return true }
            let rxMin = rect.minX, rxMax = rect.maxX, ryMin = rect.minY, ryMax = rect.maxY
            let edges: [(Float, Float, Float, Float)] = [
                (rxMin, ryMin, rxMin, ryMax),
                (rxMax, ryMin, rxMax, ryMax),
                (rxMin, ryMin, rxMax, ryMin),
                (rxMin, ryMax, rxMax, ryMax),
            ]
            for e in edges {
                if segmentIntersectSegment(x1, y1, x2, y2, e.0, e.1, e.2, e.3) { return true }
            }
            return false
        }

        private static func segmentIntersectSegment(
            _ ax1: Float, _ ay1: Float, _ ax2: Float, _ ay2: Float,
            _ bx1: Float, _ by1: Float, _ bx2: Float, _ by2: Float
        ) -> Bool {
            let rx = ax2 - ax1, ry = ay2 - ay1
            let sx = bx2 - bx1, sy = by2 - by1
            let denom = rx * sy - ry * sx
            if abs(denom) < 1e-8 { return false }
            let qpx = bx1 - ax1, qpy = by1 - ay1
            let t = (qpx * sy - qpy * sx) / denom
            let u = (qpx * ry - qpy * rx) / denom
            return t >= 0 && t <= 1 && u >= 0 && u <= 1
        }

        #if os(iOS)
        @objc func handleTap(_ recognizer: UIGestureRecognizer) {
            guard let v = view, let uv = v as? UIView else { return }
            let loc = recognizer.location(in: uv)
            let sz = uv.bounds.size
            if let ph = onPlacementPrimaryClick, ph(loc, sz) { return }
            let (node, link) = hitTest(viewPoint: loc, viewSize: sz)
            onSelect?(node, link)
        }
        #endif
}

// MARK: - Metal Renderer

#if os(macOS)
/// MTKView subclass that forwards mouse/scroll to container (so middle button and hit test work when view fills container).
final class MapMTKView: MTKView {
    weak var eventHandler: ScrollableContainerView?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        eventHandler?.handleMouseMoved(location: loc, from: self)
    }
    override func mouseExited(with event: NSEvent) {
        eventHandler?.handleMouseExited()
    }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            eventHandler?.handleKeyDown(event)
        } else {
            super.keyDown(with: event)
        }
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if let c = eventHandler, !c.linkPlacementSnapCursor {
            addCursorRect(bounds, cursor: NSCursor.arrow)
        }
    }
    override func mouseDown(with event: NSEvent) {
        eventHandler?.handleMouseDown(with: event, from: self)
        super.mouseDown(with: event)
    }
    override func rightMouseDown(with event: NSEvent) {
        if eventHandler?.handleRightMouseDown(from: self) == true {
            return
        }
        super.rightMouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        eventHandler?.handleMouseDragged(with: event, from: self)
        super.mouseDragged(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        eventHandler?.handleMouseUp(with: event, from: self)
        super.mouseUp(with: event)
    }
    override func otherMouseDown(with event: NSEvent) {
        eventHandler?.handleMouseDown(with: event, from: self)
    }
    override func otherMouseDragged(with event: NSEvent) {
        eventHandler?.handleMouseDragged(with: event, from: self)
    }
    override func otherMouseUp(with event: NSEvent) {
        eventHandler?.handleMouseUp(with: event, from: self)
    }
    override func scrollWheel(with event: NSEvent) {
        eventHandler?.handleScrollWheel(with: event, from: self)
        super.scrollWheel(with: event)
    }
}

final class ScrollableContainerView: NSView {
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 否则 NSEventType.mouseMoved 往往不会投递，状态栏 XY 长期为「—」
        window?.acceptsMouseMovedEvents = true
    }
    /// 为 true 时不在全视图钉死箭头光标，便于 `mouseMoved` 里按节点命中切换十字线。
    var linkPlacementSnapCursor = false
    override func resetCursorRects() {
        super.resetCursorRects()
        if !linkPlacementSnapCursor {
            addCursorRect(bounds, cursor: NSCursor.arrow)
        }
    }
    var onScrollWheel: ((CGFloat, CGPoint, CGSize) -> Void)?
    var onPanDelta: ((CGFloat, CGFloat, CGSize) -> Void)?
    var onPressEscape: (() -> Void)?
    var onMouseMove: (((Float, Float)?) -> Void)?
    /// 返回 true 表示已消费（不调用 `super.rightMouseDown`，避免弹出菜单）。
    var onRightMouseDown: (() -> Bool)?
    weak var coordinator: MetalNetworkCoordinator?
    private var isPanning = false
    private var lastDragLocation: CGPoint = .zero
    private var mouseDownWasOnEmpty = false
    private var totalDragDistance: CGFloat = 0
    /// 上一帧主键按下是否由 `onPlacementPrimaryClick` 消费（避免误触发平移或 mouseUp 清选中）
    private var placementConsumedLastMouseDown = false
    /// 允许编辑拓扑且无布线命令时：空白处拖出框选（不拖动画布平移）
    var marqueeEnabled = false
    private var isMarqueeDragging = false
    private var marqueeStart: CGPoint = .zero
    var onMarqueePreview: ((CGRect?, CGSize) -> Void)?
    var onMarqueeComplete: ((CGRect, CGSize, Bool) -> Void)?

    func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 {
            onPressEscape?()
        }
    }
    func handleMouseMoved(location: CGPoint, from view: NSView) {
        let loc = convert(location, from: view)
        let size = bounds.size
        if linkPlacementSnapCursor, let c = coordinator {
            let (nodeIdx, _) = c.hitTest(viewPoint: loc, viewSize: size)
            if nodeIdx != nil {
                NSCursor.crosshair.set()
            } else {
                NSCursor.arrow.set()
            }
        } else {
            NSCursor.arrow.set()
        }
        if let (sx, sy) = coordinator?.viewToScene(viewPoint: loc, viewSize: size) {
            onMouseMove?((sx, sy))
        } else {
            onMouseMove?(nil)
        }
    }
    func handleMouseExited() {
        NSCursor.arrow.set()
        onMouseMove?(nil)
    }

    /// 画布右键：供线类连续绘制「结束当前链」等；返回 true 时已消费。
    func handleRightMouseDown(from view: NSView) -> Bool {
        onRightMouseDown?() ?? false
    }

    func handleScrollWheel(with event: NSEvent, from view: NSView) {
        let loc = convert(event.locationInWindow, from: nil)
        let delta = CGFloat(event.scrollingDeltaY) * 0.012
        onScrollWheel?(delta, loc, bounds.size)
    }
    func handleMouseDown(with event: NSEvent, from view: NSView) {
        let loc = convert(event.locationInWindow, from: nil)
        let size = bounds.size
        placementConsumedLastMouseDown = false
        if event.type == .otherMouseDown || event.buttonNumber == 2 {
            isPanning = true
            lastDragLocation = loc
            return
        }
        if event.buttonNumber == 0 {
            if let ph = coordinator?.onPlacementPrimaryClick, ph(loc, size) {
                placementConsumedLastMouseDown = true
                mouseDownWasOnEmpty = false
                return
            }
            let (node, link) = coordinator?.hitTest(viewPoint: loc, viewSize: size) ?? (nil, nil)
            if node != nil || link != nil {
                coordinator?.onSelect?(node, link)
                mouseDownWasOnEmpty = false
            } else if marqueeEnabled {
                isMarqueeDragging = true
                marqueeStart = loc
                mouseDownWasOnEmpty = false
                totalDragDistance = 0
                let r = CGRect(x: loc.x, y: loc.y, width: 0, height: 0)
                onMarqueePreview?(r, size)
            } else {
                mouseDownWasOnEmpty = true
                totalDragDistance = 0
                isPanning = true
                lastDragLocation = loc
            }
        }
    }
    func handleMouseDragged(with event: NSEvent, from view: NSView) {
        let loc = convert(event.locationInWindow, from: nil)
        let size = bounds.size
        if isMarqueeDragging {
            let x0 = min(marqueeStart.x, loc.x)
            let y0 = min(marqueeStart.y, loc.y)
            let x1 = max(marqueeStart.x, loc.x)
            let y1 = max(marqueeStart.y, loc.y)
            let r = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
            onMarqueePreview?(r, size)
            return
        }
        if isPanning {
            let dx = loc.x - lastDragLocation.x
            let dy = loc.y - lastDragLocation.y
            totalDragDistance += (dx * dx + dy * dy).squareRoot()
            onPanDelta?(dx, dy, size)
            lastDragLocation = loc
        }
    }
    func handleMouseUp(with event: NSEvent, from view: NSView) {
        if placementConsumedLastMouseDown {
            placementConsumedLastMouseDown = false
            isPanning = false
            mouseDownWasOnEmpty = false
            totalDragDistance = 0
            return
        }
        if isMarqueeDragging {
            let loc = convert(event.locationInWindow, from: nil)
            let size = bounds.size
            let x0 = min(marqueeStart.x, loc.x)
            let y0 = min(marqueeStart.y, loc.y)
            let x1 = max(marqueeStart.x, loc.x)
            let y1 = max(marqueeStart.y, loc.y)
            let r = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
            let crossing = loc.x >= marqueeStart.x
            onMarqueePreview?(nil, size)
            if r.width < 3, r.height < 3 {
                coordinator?.onSelect?(nil, nil)
            } else {
                onMarqueeComplete?(r, size, crossing)
            }
            isMarqueeDragging = false
            return
        }
        if isPanning, mouseDownWasOnEmpty, totalDragDistance < 3 {
            coordinator?.onSelect?(nil, nil)
        }
        isPanning = false
        mouseDownWasOnEmpty = false
        totalDragDistance = 0
    }
    override func scrollWheel(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let delta = CGFloat(event.scrollingDeltaY) * 0.012
        onScrollWheel?(delta, loc, bounds.size)
    }
}
public struct MetalNetworkView: NSViewRepresentable {
    let scene: NetworkScene?
    /// 非 nil 时用于投影（与 SwiftUI `CanvasViewportFraming` 一致）；nil 时用 `scene.bounds`。
    let canvasTransformBounds: (minX: Float, maxX: Float, minY: Float, maxY: Float)?
    let sceneGeometryRevision: UInt64
    let resultScalarRevision: UInt64
    let scale: CGFloat
    let panX: CGFloat
    let panY: CGFloat
    let selectedNodeIndex: Int?
    let selectedLinkIndex: Int?
    let selectedNodeIndices: [Int]
    let selectedLinkIndices: [Int]
    let nodeScalars: [Float]?
    let linkScalars: [Float]?
    let nodeScalarRange: (Float, Float)?
    let linkScalarRange: (Float, Float)?
    /// 节点直径（像素），与设置 `settings.display.nodeSize` 一致
    let nodePointSizePixels: CGFloat
    /// sRGB 线性 0…1（Junction / Reservoir / Tank）
    let nodeColorJunction: (Float, Float, Float)
    let nodeColorReservoir: (Float, Float, Float)
    let nodeColorTank: (Float, Float, Float)
    let linkLineWidthPixels: CGFloat
    let linkColorPipe: (Float, Float, Float)
    let linkColorPump: (Float, Float, Float)
    let linkColorValve: (Float, Float, Float)
    let layerVisibility: CanvasLayerVisibility
    let clearColor: MTLClearColor?
    let onScrollWheel: ((CGFloat, CGPoint, CGSize) -> Void)?
    let onPanDelta: ((CGFloat, CGFloat, CGSize) -> Void)?
    let onPressEscape: (() -> Void)?
    let onMouseMove: (((Float, Float)?) -> Void)?
    let onSelect: ((Int?, Int?) -> Void)?
    let onDrawableSizeChange: ((CGSize) -> Void)?
    let onPlacementPrimaryClick: ((MetalNetworkCoordinator, CGPoint, CGSize) -> Bool)?
    /// 绘制管段/阀门/水泵时，鼠标落在可命中节点上显示十字光标（与 `hitTest` 热区一致）。
    let linkPlacementSnapCursor: Bool
    /// macOS：线类连续绘制时右键结束当前链；返回 true 表示已消费右键。
    let onRightMouseDown: (() -> Bool)?
    let marqueeEnabled: Bool
    let onMarqueePreview: ((CGRect?, CGSize) -> Void)?
    let onMarqueeComplete: ((MetalNetworkCoordinator, CGRect, CGSize, Bool) -> Void)?

    public init(
        scene: NetworkScene?,
        canvasTransformBounds: (minX: Float, maxX: Float, minY: Float, maxY: Float)? = nil,
        sceneGeometryRevision: UInt64 = 0,
        resultScalarRevision: UInt64 = 0,
        scale: CGFloat = 1,
        panX: CGFloat = 0,
        panY: CGFloat = 0,
        selectedNodeIndex: Int? = nil,
        selectedLinkIndex: Int? = nil,
        selectedNodeIndices: [Int] = [],
        selectedLinkIndices: [Int] = [],
        nodeScalars: [Float]? = nil,
        linkScalars: [Float]? = nil,
        nodeScalarRange: (Float, Float)? = nil,
        linkScalarRange: (Float, Float)? = nil,
        nodePointSizePixels: CGFloat = 6,
        nodeColorJunction: (Float, Float, Float) = (0.1, 0.2, 0.5),
        nodeColorReservoir: (Float, Float, Float) = (0.49, 0.24, 0.72),
        nodeColorTank: (Float, Float, Float) = (0.2, 0.66, 0.33),
        linkLineWidthPixels: CGFloat = 2,
        linkColorPipe: (Float, Float, Float) = (0.2, 0.4, 0.7),
        linkColorPump: (Float, Float, Float) = (0.8, 0.2, 0.2),
        linkColorValve: (Float, Float, Float) = (1.0, 0.58, 0),
        layerVisibility: CanvasLayerVisibility = .allVisible,
        clearColor: MTLClearColor? = nil,
        onScrollWheel: ((CGFloat, CGPoint, CGSize) -> Void)? = nil,
        onPanDelta: ((CGFloat, CGFloat, CGSize) -> Void)? = nil,
        onPressEscape: (() -> Void)? = nil,
        onMouseMove: (((Float, Float)?) -> Void)? = nil,
        onSelect: ((Int?, Int?) -> Void)? = nil,
        onDrawableSizeChange: ((CGSize) -> Void)? = nil,
        onPlacementPrimaryClick: ((MetalNetworkCoordinator, CGPoint, CGSize) -> Bool)? = nil,
        linkPlacementSnapCursor: Bool = false,
        onRightMouseDown: (() -> Bool)? = nil,
        marqueeEnabled: Bool = false,
        onMarqueePreview: ((CGRect?, CGSize) -> Void)? = nil,
        onMarqueeComplete: ((MetalNetworkCoordinator, CGRect, CGSize, Bool) -> Void)? = nil
    ) {
        self.scene = scene
        self.canvasTransformBounds = canvasTransformBounds
        self.sceneGeometryRevision = sceneGeometryRevision
        self.resultScalarRevision = resultScalarRevision
        self.scale = scale
        self.panX = panX
        self.panY = panY
        self.selectedNodeIndex = selectedNodeIndex
        self.selectedLinkIndex = selectedLinkIndex
        self.selectedNodeIndices = selectedNodeIndices
        self.selectedLinkIndices = selectedLinkIndices
        self.nodeScalars = nodeScalars
        self.linkScalars = linkScalars
        self.nodeScalarRange = nodeScalarRange
        self.linkScalarRange = linkScalarRange
        self.nodePointSizePixels = nodePointSizePixels
        self.nodeColorJunction = nodeColorJunction
        self.nodeColorReservoir = nodeColorReservoir
        self.nodeColorTank = nodeColorTank
        self.linkLineWidthPixels = linkLineWidthPixels
        self.linkColorPipe = linkColorPipe
        self.linkColorPump = linkColorPump
        self.linkColorValve = linkColorValve
        self.layerVisibility = layerVisibility
        self.clearColor = clearColor
        self.onScrollWheel = onScrollWheel
        self.onPanDelta = onPanDelta
        self.onPressEscape = onPressEscape
        self.onMouseMove = onMouseMove
        self.onSelect = onSelect
        self.onDrawableSizeChange = onDrawableSizeChange
        self.onPlacementPrimaryClick = onPlacementPrimaryClick
        self.linkPlacementSnapCursor = linkPlacementSnapCursor
        self.onRightMouseDown = onRightMouseDown
        self.marqueeEnabled = marqueeEnabled
        self.onMarqueePreview = onMarqueePreview
        self.onMarqueeComplete = onMarqueeComplete
    }
    public func makeNSView(context: Context) -> NSView {
        let container = ScrollableContainerView()
        container.linkPlacementSnapCursor = linkPlacementSnapCursor
        container.onRightMouseDown = onRightMouseDown
        container.onScrollWheel = onScrollWheel
        container.onPanDelta = onPanDelta
        container.onPressEscape = onPressEscape
        container.onMouseMove = onMouseMove
        context.coordinator.onSelect = onSelect
        let coord = context.coordinator
        coord.onPlacementPrimaryClick = onPlacementPrimaryClick.map { fn in { fn(coord, $0, $1) } }
        container.coordinator = coord
        container.marqueeEnabled = marqueeEnabled
        container.onMarqueePreview = onMarqueePreview
        container.onMarqueeComplete = { rect, size, crossing in
            onMarqueeComplete?(coord, rect, size, crossing)
        }
        let mtkView = MapMTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.clearColor = clearColor ?? MTLClearColor(red: 248/255.0, green: 247/255.0, blue: 242/255.0, alpha: 1)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        if let cc = clearColor, cc.alpha == 0 {
            mtkView.layer?.isOpaque = false
            #if os(macOS)
            mtkView.wantsLayer = true
            mtkView.layer?.backgroundColor = NSColor.clear.cgColor
            #endif
        }
        mtkView.enableSetNeedsDisplay = true
        // 与 SwiftUI 覆盖层（Canvas 标注）同一帧对齐：避免 display link 晚一帧才读到新 pan/scale
        mtkView.isPaused = true
        mtkView.eventHandler = container
        context.coordinator.view = mtkView
        context.coordinator.scene = scene
        context.coordinator.canvasTransformBounds = canvasTransformBounds
        context.coordinator.sceneGeometryRevision = sceneGeometryRevision
        context.coordinator.resultScalarRevision = resultScalarRevision
        context.coordinator.scale = scale
        context.coordinator.panX = panX
        context.coordinator.panY = panY
        context.coordinator.selectedNodeIndex = selectedNodeIndex
        context.coordinator.selectedLinkIndex = selectedLinkIndex
        context.coordinator.selectedNodeIndices = selectedNodeIndices
        context.coordinator.selectedLinkIndices = selectedLinkIndices
        context.coordinator.nodeScalars = nodeScalars
        context.coordinator.linkScalars = linkScalars
        context.coordinator.nodeScalarRange = nodeScalarRange
        context.coordinator.linkScalarRange = linkScalarRange
        context.coordinator.nodePointSizePixels = Float(nodePointSizePixels)
        context.coordinator.nodeRGBJunction = nodeColorJunction
        context.coordinator.nodeRGBReservoir = nodeColorReservoir
        context.coordinator.nodeRGBTank = nodeColorTank
        context.coordinator.linkLineWidthPixels = Float(linkLineWidthPixels)
        context.coordinator.linkRGBPipe = linkColorPipe
        context.coordinator.linkRGBPump = linkColorPump
        context.coordinator.linkRGBValve = linkColorValve
        context.coordinator.layerVisibility = layerVisibility
        context.coordinator.onDrawableSizeChange = onDrawableSizeChange
        container.addSubview(mtkView)
        mtkView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mtkView.topAnchor.constraint(equalTo: container.topAnchor),
            mtkView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mtkView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mtkView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }
    public func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.scene = scene
        context.coordinator.canvasTransformBounds = canvasTransformBounds
        context.coordinator.sceneGeometryRevision = sceneGeometryRevision
        context.coordinator.resultScalarRevision = resultScalarRevision
        context.coordinator.scale = scale
        context.coordinator.panX = panX
        context.coordinator.panY = panY
        context.coordinator.selectedNodeIndex = selectedNodeIndex
        context.coordinator.selectedLinkIndex = selectedLinkIndex
        context.coordinator.selectedNodeIndices = selectedNodeIndices
        context.coordinator.selectedLinkIndices = selectedLinkIndices
        context.coordinator.nodeScalars = nodeScalars
        context.coordinator.linkScalars = linkScalars
        context.coordinator.nodeScalarRange = nodeScalarRange
        context.coordinator.linkScalarRange = linkScalarRange
        context.coordinator.nodePointSizePixels = Float(nodePointSizePixels)
        context.coordinator.nodeRGBJunction = nodeColorJunction
        context.coordinator.nodeRGBReservoir = nodeColorReservoir
        context.coordinator.nodeRGBTank = nodeColorTank
        context.coordinator.linkLineWidthPixels = Float(linkLineWidthPixels)
        context.coordinator.linkRGBPipe = linkColorPipe
        context.coordinator.linkRGBPump = linkColorPump
        context.coordinator.linkRGBValve = linkColorValve
        context.coordinator.layerVisibility = layerVisibility
        context.coordinator.onSelect = onSelect
        context.coordinator.onDrawableSizeChange = onDrawableSizeChange
        let coord2 = context.coordinator
        coord2.onPlacementPrimaryClick = onPlacementPrimaryClick.map { fn in { fn(coord2, $0, $1) } }
        if let c = container as? ScrollableContainerView {
            c.marqueeEnabled = marqueeEnabled
            c.onMarqueePreview = onMarqueePreview
            c.onMarqueeComplete = { rect, size, crossing in
                onMarqueeComplete?(coord2, rect, size, crossing)
            }
        }
        (container as? ScrollableContainerView)?.onScrollWheel = onScrollWheel
        (container as? ScrollableContainerView)?.onPanDelta = onPanDelta
        (container as? ScrollableContainerView)?.onPressEscape = onPressEscape
        (container as? ScrollableContainerView)?.onMouseMove = onMouseMove
        (container as? ScrollableContainerView)?.onRightMouseDown = onRightMouseDown
        if let c = container as? ScrollableContainerView {
            let old = c.linkPlacementSnapCursor
            c.linkPlacementSnapCursor = linkPlacementSnapCursor
            if old != linkPlacementSnapCursor {
                c.window?.invalidateCursorRects(for: c)
                for sub in c.subviews {
                    c.window?.invalidateCursorRects(for: sub)
                }
            }
        }
        if let mtk = container.subviews.first as? MTKView {
            // 立即绘制一帧，与 SwiftUI Canvas 标注使用同一组 pan/scale（避免晚一帧）
            mtk.draw()
        }
    }
    public func makeCoordinator() -> MetalNetworkCoordinator { MetalNetworkCoordinator() }
}

#else
public struct MetalNetworkView: UIViewRepresentable {
    let scene: NetworkScene?
    let canvasTransformBounds: (minX: Float, maxX: Float, minY: Float, maxY: Float)?
    let sceneGeometryRevision: UInt64
    let resultScalarRevision: UInt64
    let scale: CGFloat
    let panX: CGFloat
    let panY: CGFloat
    let selectedNodeIndex: Int?
    let selectedLinkIndex: Int?
    let selectedNodeIndices: [Int]
    let selectedLinkIndices: [Int]
    let nodeScalars: [Float]?
    let linkScalars: [Float]?
    let nodeScalarRange: (Float, Float)?
    let linkScalarRange: (Float, Float)?
    let nodePointSizePixels: CGFloat
    let nodeColorJunction: (Float, Float, Float)
    let nodeColorReservoir: (Float, Float, Float)
    let nodeColorTank: (Float, Float, Float)
    let linkLineWidthPixels: CGFloat
    let linkColorPipe: (Float, Float, Float)
    let linkColorPump: (Float, Float, Float)
    let linkColorValve: (Float, Float, Float)
    let layerVisibility: CanvasLayerVisibility
    let clearColor: MTLClearColor?
    let onScrollWheel: ((CGFloat, CGPoint, CGSize) -> Void)?
    let onPanDelta: ((CGFloat, CGFloat, CGSize) -> Void)?
    let onPressEscape: (() -> Void)?
    let onMouseMove: (((Float, Float)?) -> Void)?
    let onSelect: ((Int?, Int?) -> Void)?
    let onDrawableSizeChange: ((CGSize) -> Void)?
    let onPlacementPrimaryClick: ((MetalNetworkCoordinator, CGPoint, CGSize) -> Bool)?
    let linkPlacementSnapCursor: Bool
    let onRightMouseDown: (() -> Bool)?
    let marqueeEnabled: Bool
    let onMarqueePreview: ((CGRect?, CGSize) -> Void)?
    let onMarqueeComplete: ((MetalNetworkCoordinator, CGRect, CGSize, Bool) -> Void)?

    public init(
        scene: NetworkScene?,
        canvasTransformBounds: (minX: Float, maxX: Float, minY: Float, maxY: Float)? = nil,
        sceneGeometryRevision: UInt64 = 0,
        resultScalarRevision: UInt64 = 0,
        scale: CGFloat = 1,
        panX: CGFloat = 0,
        panY: CGFloat = 0,
        selectedNodeIndex: Int? = nil,
        selectedLinkIndex: Int? = nil,
        selectedNodeIndices: [Int] = [],
        selectedLinkIndices: [Int] = [],
        nodeScalars: [Float]? = nil,
        linkScalars: [Float]? = nil,
        nodeScalarRange: (Float, Float)? = nil,
        linkScalarRange: (Float, Float)? = nil,
        nodePointSizePixels: CGFloat = 6,
        nodeColorJunction: (Float, Float, Float) = (0.1, 0.2, 0.5),
        nodeColorReservoir: (Float, Float, Float) = (0.49, 0.24, 0.72),
        nodeColorTank: (Float, Float, Float) = (0.2, 0.66, 0.33),
        linkLineWidthPixels: CGFloat = 2,
        linkColorPipe: (Float, Float, Float) = (0.2, 0.4, 0.7),
        linkColorPump: (Float, Float, Float) = (0.8, 0.2, 0.2),
        linkColorValve: (Float, Float, Float) = (1.0, 0.58, 0),
        layerVisibility: CanvasLayerVisibility = .allVisible,
        clearColor: MTLClearColor? = nil,
        onScrollWheel: ((CGFloat, CGPoint, CGSize) -> Void)? = nil,
        onPanDelta: ((CGFloat, CGFloat, CGSize) -> Void)? = nil,
        onPressEscape: (() -> Void)? = nil,
        onMouseMove: (((Float, Float)?) -> Void)? = nil,
        onSelect: ((Int?, Int?) -> Void)? = nil,
        onDrawableSizeChange: ((CGSize) -> Void)? = nil,
        onPlacementPrimaryClick: ((MetalNetworkCoordinator, CGPoint, CGSize) -> Bool)? = nil,
        linkPlacementSnapCursor: Bool = false,
        onRightMouseDown: (() -> Bool)? = nil,
        marqueeEnabled: Bool = false,
        onMarqueePreview: ((CGRect?, CGSize) -> Void)? = nil,
        onMarqueeComplete: ((MetalNetworkCoordinator, CGRect, CGSize, Bool) -> Void)? = nil
    ) {
        self.scene = scene
        self.canvasTransformBounds = canvasTransformBounds
        self.sceneGeometryRevision = sceneGeometryRevision
        self.resultScalarRevision = resultScalarRevision
        self.scale = scale
        self.panX = panX
        self.panY = panY
        self.selectedNodeIndex = selectedNodeIndex
        self.selectedLinkIndex = selectedLinkIndex
        self.selectedNodeIndices = selectedNodeIndices
        self.selectedLinkIndices = selectedLinkIndices
        self.nodeScalars = nodeScalars
        self.linkScalars = linkScalars
        self.nodeScalarRange = nodeScalarRange
        self.linkScalarRange = linkScalarRange
        self.nodePointSizePixels = nodePointSizePixels
        self.nodeColorJunction = nodeColorJunction
        self.nodeColorReservoir = nodeColorReservoir
        self.nodeColorTank = nodeColorTank
        self.linkLineWidthPixels = linkLineWidthPixels
        self.linkColorPipe = linkColorPipe
        self.linkColorPump = linkColorPump
        self.linkColorValve = linkColorValve
        self.layerVisibility = layerVisibility
        self.clearColor = clearColor
        self.onScrollWheel = onScrollWheel
        self.onPanDelta = onPanDelta
        self.onPressEscape = onPressEscape
        self.onMouseMove = onMouseMove
        self.onSelect = onSelect
        self.onDrawableSizeChange = onDrawableSizeChange
        self.onPlacementPrimaryClick = onPlacementPrimaryClick
        self.linkPlacementSnapCursor = linkPlacementSnapCursor
        self.onRightMouseDown = onRightMouseDown
        self.marqueeEnabled = marqueeEnabled
        self.onMarqueePreview = onMarqueePreview
        self.onMarqueeComplete = onMarqueeComplete
    }

    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.clearColor = clearColor ?? MTLClearColor(red: 248/255.0, green: 247/255.0, blue: 242/255.0, alpha: 1)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.isUserInteractionEnabled = true
        if let cc = clearColor, cc.alpha == 0 {
            mtkView.layer.isOpaque = false
            mtkView.backgroundColor = .clear
        }
        mtkView.isPaused = true
        context.coordinator.view = mtkView
        context.coordinator.scene = scene
        context.coordinator.canvasTransformBounds = canvasTransformBounds
        context.coordinator.sceneGeometryRevision = sceneGeometryRevision
        context.coordinator.resultScalarRevision = resultScalarRevision
        context.coordinator.scale = scale
        context.coordinator.panX = panX
        context.coordinator.panY = panY
        context.coordinator.selectedNodeIndex = selectedNodeIndex
        context.coordinator.selectedLinkIndex = selectedLinkIndex
        context.coordinator.selectedNodeIndices = selectedNodeIndices
        context.coordinator.selectedLinkIndices = selectedLinkIndices
        context.coordinator.nodeScalars = nodeScalars
        context.coordinator.linkScalars = linkScalars
        context.coordinator.nodeScalarRange = nodeScalarRange
        context.coordinator.linkScalarRange = linkScalarRange
        context.coordinator.nodePointSizePixels = Float(nodePointSizePixels)
        context.coordinator.nodeRGBJunction = nodeColorJunction
        context.coordinator.nodeRGBReservoir = nodeColorReservoir
        context.coordinator.nodeRGBTank = nodeColorTank
        context.coordinator.linkLineWidthPixels = Float(linkLineWidthPixels)
        context.coordinator.linkRGBPipe = linkColorPipe
        context.coordinator.linkRGBPump = linkColorPump
        context.coordinator.linkRGBValve = linkColorValve
        context.coordinator.layerVisibility = layerVisibility
        context.coordinator.onSelect = onSelect
        context.coordinator.onDrawableSizeChange = onDrawableSizeChange
        let coord0 = context.coordinator
        coord0.onPlacementPrimaryClick = onPlacementPrimaryClick.map { fn in { fn(coord0, $0, $1) } }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(MetalNetworkCoordinator.handleTap(_:)))
        mtkView.addGestureRecognizer(tap)
        return mtkView
    }

    public func updateUIView(_ mtkView: MTKView, context: Context) {
        context.coordinator.scene = scene
        context.coordinator.canvasTransformBounds = canvasTransformBounds
        context.coordinator.sceneGeometryRevision = sceneGeometryRevision
        context.coordinator.resultScalarRevision = resultScalarRevision
        context.coordinator.scale = scale
        context.coordinator.panX = panX
        context.coordinator.panY = panY
        context.coordinator.selectedNodeIndex = selectedNodeIndex
        context.coordinator.selectedLinkIndex = selectedLinkIndex
        context.coordinator.selectedNodeIndices = selectedNodeIndices
        context.coordinator.selectedLinkIndices = selectedLinkIndices
        context.coordinator.nodeScalars = nodeScalars
        context.coordinator.linkScalars = linkScalars
        context.coordinator.nodeScalarRange = nodeScalarRange
        context.coordinator.linkScalarRange = linkScalarRange
        context.coordinator.nodePointSizePixels = Float(nodePointSizePixels)
        context.coordinator.nodeRGBJunction = nodeColorJunction
        context.coordinator.nodeRGBReservoir = nodeColorReservoir
        context.coordinator.nodeRGBTank = nodeColorTank
        context.coordinator.linkLineWidthPixels = Float(linkLineWidthPixels)
        context.coordinator.linkRGBPipe = linkColorPipe
        context.coordinator.linkRGBPump = linkColorPump
        context.coordinator.linkRGBValve = linkColorValve
        context.coordinator.layerVisibility = layerVisibility
        context.coordinator.onSelect = onSelect
        context.coordinator.onDrawableSizeChange = onDrawableSizeChange
        let coordU = context.coordinator
        coordU.onPlacementPrimaryClick = onPlacementPrimaryClick.map { fn in { fn(coordU, $0, $1) } }
        mtkView.draw()
    }

    public func makeCoordinator() -> MetalNetworkCoordinator { MetalNetworkCoordinator() }
}
#endif
