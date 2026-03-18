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

func makeLineVertices(from scene: NetworkScene) -> [Float] {
    var v: [Float] = []
    for l in scene.links {
        v.append(contentsOf: [l.x1, l.y1, l.x2, l.y2])
    }
    return v
}

func makePointVertices(from scene: NetworkScene) -> [Float] {
    var v: [Float] = []
    for n in scene.nodes {
        v.append(contentsOf: [n.x, n.y])
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
        var onSelect: ((Int?, Int?) -> Void)?
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
        var pipelineState: MTLRenderPipelineState?
        var linePipeline: MTLRenderPipelineState?
        var lineScalarPipeline: MTLRenderPipelineState?
        var pointScalarPipeline: MTLRenderPipelineState?
        var lineHighlightPipeline: MTLRenderPipelineState?
        var pointHighlightPipeline: MTLRenderPipelineState?

        override init() {
            super.init()
        }

    static let metalSource = """
        #include <metal_stdlib>
        using namespace metal;
        struct VertexOut { float4 pos [[position]]; float scalar; };
        struct PointOut { float4 pos [[position]]; float point_size [[point_size]]; float scalar; };
        float3 colorMap(float t) {
            t = clamp(t, 0.0, 1.0);
            return float3(t, 0.2, 1.0 - t); // blue -> red
        }
        vertex VertexOut vertex_line_plain(constant float *uniforms [[buffer(0)]], constant float *verts [[buffer(1)]], uint vid [[vertex_id]]) {
            float scaleX=uniforms[0], scaleY=uniforms[1], offX=uniforms[2], offY=uniforms[3];
            float x=verts[vid*2], y=verts[vid*2+1];
            VertexOut o; o.pos = float4(x*scaleX+offX, y*scaleY+offY, 0, 1); o.scalar = 0.0; return o;
        }
        vertex VertexOut vertex_line_scalar(constant float *uniforms [[buffer(0)]], constant float *verts [[buffer(1)]], constant float *vals [[buffer(2)]], uint vid [[vertex_id]]) {
            float scaleX=uniforms[0], scaleY=uniforms[1], offX=uniforms[2], offY=uniforms[3];
            float x=verts[vid*2], y=verts[vid*2+1];
            VertexOut o; o.pos = float4(x*scaleX+offX, y*scaleY+offY, 0, 1); o.scalar = vals[vid/2]; return o;
        }
        fragment float4 fragment_line(VertexOut in [[stage_in]]) { return float4(0.2, 0.4, 0.7, 1); }
        fragment float4 fragment_line_scalar(VertexOut in [[stage_in]], constant float *range [[buffer(0)]]) {
            float lo = range[0], hi = range[1];
            float t = (hi > lo) ? ((in.scalar - lo) / (hi - lo)) : 0.5;
            float3 c = colorMap(t);
            return float4(c, 1);
        }
        fragment float4 fragment_highlight_line(VertexOut in [[stage_in]]) { return float4(0.9, 0.45, 0.1, 1); }
        vertex PointOut vertex_main_plain(constant float *uniforms [[buffer(0)]], constant float *verts [[buffer(1)]], uint vid [[vertex_id]]) {
            float scaleX=uniforms[0], scaleY=uniforms[1], offX=uniforms[2], offY=uniforms[3];
            float x=verts[vid*2], y=verts[vid*2+1];
            PointOut o; o.pos = float4(x*scaleX+offX, y*scaleY+offY, 0, 1); o.point_size = 6.0; o.scalar = 0.0; return o;
        }
        vertex PointOut vertex_main_scalar(constant float *uniforms [[buffer(0)]], constant float *verts [[buffer(1)]], constant float *vals [[buffer(2)]], uint vid [[vertex_id]]) {
            float scaleX=uniforms[0], scaleY=uniforms[1], offX=uniforms[2], offY=uniforms[3];
            float x=verts[vid*2], y=verts[vid*2+1];
            PointOut o; o.pos = float4(x*scaleX+offX, y*scaleY+offY, 0, 1); o.point_size = 6.0; o.scalar = vals[vid]; return o;
        }
        fragment float4 fragment_main(PointOut in [[stage_in]]) { return float4(0.1, 0.2, 0.5, 1); }
        fragment float4 fragment_main_scalar(PointOut in [[stage_in]], constant float *range [[buffer(0)]]) {
            float lo = range[0], hi = range[1];
            float t = (hi > lo) ? ((in.scalar - lo) / (hi - lo)) : 0.5;
            float3 c = colorMap(t);
            return float4(c, 1);
        }
        fragment float4 fragment_highlight_point(PointOut in [[stage_in]]) { return float4(0.9, 0.45, 0.1, 1); }
        """

        func buildPipelines(device: MTLDevice) {
            guard pipelineState == nil else { return }
            let library = try? device.makeLibrary(source: Self.metalSource, options: nil)
            let vert = library?.makeFunction(name: "vertex_main_plain")
            let frag = library?.makeFunction(name: "fragment_main")
            let vertLine = library?.makeFunction(name: "vertex_line_plain")
            let fragLine = library?.makeFunction(name: "fragment_line")
            let vertLineScalar = library?.makeFunction(name: "vertex_line_scalar")
            let vertPointScalar = library?.makeFunction(name: "vertex_main_scalar")
            let pipelineDesc = MTLRenderPipelineDescriptor()
            pipelineDesc.vertexFunction = vert
            pipelineDesc.fragmentFunction = frag
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
            let fragPointHi = library?.makeFunction(name: "fragment_highlight_point")
            let pointHiDesc = MTLRenderPipelineDescriptor()
            pointHiDesc.vertexFunction = vert
            pointHiDesc.fragmentFunction = fragPointHi
            pointHiDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pointHighlightPipeline = try? device.makeRenderPipelineState(descriptor: pointHiDesc)
            let fragPointScalar = library?.makeFunction(name: "fragment_main_scalar")
            let pointScalarDesc = MTLRenderPipelineDescriptor()
            pointScalarDesc.vertexFunction = vertPointScalar
            pointScalarDesc.fragmentFunction = fragPointScalar
            pointScalarDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pointScalarPipeline = try? device.makeRenderPipelineState(descriptor: pointScalarDesc)
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        public func draw(in view: MTKView) {
            guard let device = view.device,
                  let drawable = view.currentDrawable,
                  let rpd = view.currentRenderPassDescriptor,
                  let scene = scene, !scene.nodes.isEmpty else {
                return
            }
            buildPipelines(device: device)

            // Update buffers if scene changed
            let lineVerts = makeLineVertices(from: scene)
            let pointVerts = makePointVertices(from: scene)
            if lineVerts.count > 0 {
                lineBuffer = device.makeBuffer(bytes: lineVerts, length: lineVerts.count * MemoryLayout<Float>.stride, options: .storageModeShared)
                lineCount = scene.links.count
                if let linkScalars = linkScalars, linkScalars.count == lineCount {
                    lineScalarBuffer = device.makeBuffer(bytes: linkScalars, length: linkScalars.count * MemoryLayout<Float>.stride, options: .storageModeShared)
                } else {
                    lineScalarBuffer = nil
                }
            }
            if pointVerts.count > 0 {
                pointBuffer = device.makeBuffer(bytes: pointVerts, length: pointVerts.count * MemoryLayout<Float>.stride, options: .storageModeShared)
                pointCount = scene.nodes.count
                if let nodeScalars = nodeScalars, nodeScalars.count == pointCount {
                    pointScalarBuffer = device.makeBuffer(bytes: nodeScalars, length: nodeScalars.count * MemoryLayout<Float>.stride, options: .storageModeShared)
                } else {
                    pointScalarBuffer = nil
                }
            }

            // Viewport: full size. XY 比例一致 — 同一场景单位在 X/Y 方向映射到相同像素长度，不拉变形
            let dw = Float(view.drawableSize.width), dh = Float(view.drawableSize.height)
            let bw = scene.bounds.maxX - scene.bounds.minX
            let bh = scene.bounds.maxY - scene.bounds.minY
            let pad: Float = max(bw, bh) * 0.05 + 1
            let baseScale = min(2.0 / (bw + pad * 2), 2.0 / (bh + pad * 2))
            let s = baseScale * Float(scale)
            let centerX = (scene.bounds.minX + scene.bounds.maxX) * 0.5
            let centerY = (scene.bounds.minY + scene.bounds.maxY) * 0.5
            let scaleX: Float
            let scaleYVal: Float
            if dw >= dh {
                scaleYVal = s
                scaleX = s * dh / dw
            } else {
                scaleX = s
                scaleYVal = s * dw / dh
            }
            let offX = -centerX * scaleX + Float(panX) * scaleX * 0.01
            let offY = -centerY * scaleYVal - Float(panY) * scaleYVal * 0.01

            guard let cmdBuf = device.makeCommandQueue()?.makeCommandBuffer(),
                  let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return }

            enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(dw), height: Double(dh), znear: 0, zfar: 1))

            // Line width 1 (default); point size 6 so node radius = 3× line width
            // Draw lines
            if let buf = lineBuffer, lineCount > 0 {
                var uniforms: [Float] = [scaleX, scaleYVal, offX, offY]
                // Always clear optional scalar buffer binding to avoid stale GPU pointers
                // when toggling overlay modes across frames/scenes.
                enc.setVertexBuffer(nil, offset: 0, index: 2)
                if let lineScalarPipeline = lineScalarPipeline,
                   let scalarBuf = lineScalarBuffer,
                   let range = linkScalarRange {
                    enc.setRenderPipelineState(lineScalarPipeline)
                    var r: [Float] = [range.0, range.1]
                    enc.setFragmentBytes(&r, length: 8, index: 0)
                    enc.setVertexBuffer(scalarBuf, offset: 0, index: 2)
                } else if let linePipeline = linePipeline {
                    enc.setRenderPipelineState(linePipeline)
                }
                enc.setVertexBytes(&uniforms, length: 16, index: 0)
                enc.setVertexBuffer(buf, offset: 0, index: 1)
                enc.drawPrimitives(type: .line, vertexStart: 0, vertexCount: lineCount * 2)
            }

            // Draw points
            if let buf = pointBuffer, pointCount > 0 {
                var uniforms: [Float] = [scaleX, scaleYVal, offX, offY]
                // Always clear optional scalar buffer binding to avoid stale GPU pointers.
                enc.setVertexBuffer(nil, offset: 0, index: 2)
                if let pointScalarPipeline = pointScalarPipeline,
                   let scalarBuf = pointScalarBuffer,
                   let range = nodeScalarRange {
                    enc.setRenderPipelineState(pointScalarPipeline)
                    var r: [Float] = [range.0, range.1]
                    enc.setFragmentBytes(&r, length: 8, index: 0)
                    enc.setVertexBuffer(scalarBuf, offset: 0, index: 2)
                } else if let pipelineState = pipelineState {
                    enc.setRenderPipelineState(pipelineState)
                }
                enc.setVertexBytes(&uniforms, length: 16, index: 0)
                enc.setVertexBuffer(buf, offset: 0, index: 1)
                enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pointCount)
            }
            // Highlight selected link
            if let idx = selectedLinkIndex, idx >= 0, idx < lineCount, let lineHi = lineHighlightPipeline, let buf = lineBuffer {
                enc.setRenderPipelineState(lineHi)
                var uniforms: [Float] = [scaleX, scaleYVal, offX, offY]
                enc.setVertexBytes(&uniforms, length: 16, index: 0)
                enc.setVertexBuffer(buf, offset: 0, index: 1)
                enc.drawPrimitives(type: .line, vertexStart: idx * 2, vertexCount: 2)
            }
            // Highlight selected node
            if let idx = selectedNodeIndex, idx >= 0, idx < pointCount, let pointHi = pointHighlightPipeline, let buf = pointBuffer {
                enc.setRenderPipelineState(pointHi)
                var uniforms: [Float] = [scaleX, scaleYVal, offX, offY]
                enc.setVertexBytes(&uniforms, length: 16, index: 0)
                enc.setVertexBuffer(buf, offset: 0, index: 1)
                enc.drawPrimitives(type: .point, vertexStart: idx, vertexCount: 1)
            }

            enc.endEncoding()
            cmdBuf.present(drawable)
            cmdBuf.commit()
        }

        /// Hit test: 点优先于线。节点在容差内则选节点，否则在管段容差内才选管段。管段容差收紧，避免离管线较远仍选中。
        func hitTest(viewPoint: CGPoint, viewSize: CGSize) -> (Int?, Int?) {
            guard let scene = scene, !scene.nodes.isEmpty, viewSize.width > 0, viewSize.height > 0 else { return (nil, nil) }
            let w = Float(viewSize.width), h = Float(viewSize.height)
            let bw = scene.bounds.maxX - scene.bounds.minX
            let bh = scene.bounds.maxY - scene.bounds.minY
            let pad: Float = max(bw, bh) * 0.05 + 1
            let baseScale = min(2.0 / (bw + pad * 2), 2.0 / (bh + pad * 2))
            let s = baseScale * Float(scale)
            let (scaleX, scaleY): (Float, Float)
            if w >= h {
                scaleY = s
                scaleX = s * h / w
            } else {
                scaleX = s
                scaleY = s * w / h
            }
            let centerX = (scene.bounds.minX + scene.bounds.maxX) * 0.5
            let centerY = (scene.bounds.minY + scene.bounds.maxY) * 0.5
            let offX = -centerX * scaleX + Float(panX) * scaleX * 0.01
            let offY = -centerY * scaleY - Float(panY) * scaleY * 0.01
            let ndcX = 2 * Float(viewPoint.x) / w - 1
            let ndcY = 1 - 2 * Float(viewPoint.y) / h
            let sx = (ndcX - offX) / scaleX
            let sy = (ndcY - offY) / scaleY
            let viewPixels = min(w, h)
            let scenePixelsPerUnit = viewPixels > 0 ? viewPixels / max(bw, bh) : 1
            let nodeRadiusScene = 10 / max(scenePixelsPerUnit, 0.1)
            let linkHalfWidthScene = min(4 / max(scenePixelsPerUnit, 0.1), max(bw, bh) * 0.03)
            var bestNode: (index: Int, dist: Float)?
            for (i, n) in scene.nodes.enumerated() {
                let d = (n.x - sx) * (n.x - sx) + (n.y - sy) * (n.y - sy)
                let r = nodeRadiusScene * nodeRadiusScene
                if d <= r, bestNode == nil || d < bestNode!.dist { bestNode = (i, d) }
            }
            var bestLink: (index: Int, dist: Float)?
            for (i, l) in scene.links.enumerated() {
                let d = Self.distToSegment(px: sx, py: sy, x1: l.x1, y1: l.y1, x2: l.x2, y2: l.y2)
                if d <= linkHalfWidthScene, bestLink == nil || d < bestLink!.dist { bestLink = (i, d) }
            }
            if let b = bestNode, b.dist.squareRoot() <= nodeRadiusScene { return (b.index, nil) }
            if let b = bestLink { return (nil, b.index) }
            return (nil, nil)
        }
        /// 视图坐标转场景坐标（与 hitTest 一致），无场景时返回 nil
        func viewToScene(viewPoint: CGPoint, viewSize: CGSize) -> (Float, Float)? {
            guard let scene = scene, !scene.nodes.isEmpty, viewSize.width > 0, viewSize.height > 0 else { return nil }
            let w = Float(viewSize.width), h = Float(viewSize.height)
            let bw = scene.bounds.maxX - scene.bounds.minX
            let bh = scene.bounds.maxY - scene.bounds.minY
            let pad: Float = max(bw, bh) * 0.05 + 1
            let baseScale = min(2.0 / (bw + pad * 2), 2.0 / (bh + pad * 2))
            let s = baseScale * Float(scale)
            let (scaleX, scaleY): (Float, Float)
            if w >= h {
                scaleY = s
                scaleX = s * h / w
            } else {
                scaleX = s
                scaleY = s * w / h
            }
            let centerX = (scene.bounds.minX + scene.bounds.maxX) * 0.5
            let centerY = (scene.bounds.minY + scene.bounds.maxY) * 0.5
            let offX = -centerX * scaleX + Float(panX) * scaleX * 0.01
            let offY = -centerY * scaleY - Float(panY) * scaleY * 0.01
            let ndcX = 2 * Float(viewPoint.x) / w - 1
            let ndcY = 1 - 2 * Float(viewPoint.y) / h
            let sx = (ndcX - offX) / scaleX
            let sy = (ndcY - offY) / scaleY
            return (sx, sy)
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

        #if os(iOS)
        @objc func handleTap(_ recognizer: UIGestureRecognizer) {
            guard let v = view, let uv = v as? UIView else { return }
            let loc = recognizer.location(in: uv)
            let (node, link) = hitTest(viewPoint: loc, viewSize: uv.bounds.size)
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
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
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
        addCursorRect(bounds, cursor: NSCursor.arrow)
    }
    override func mouseDown(with event: NSEvent) {
        eventHandler?.handleMouseDown(with: event, from: self)
        super.mouseDown(with: event)
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
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: NSCursor.arrow)
    }
    var onScrollWheel: ((CGFloat, CGPoint, CGSize) -> Void)?
    var onPanDelta: ((CGFloat, CGFloat, CGSize) -> Void)?
    var onPressEscape: (() -> Void)?
    var onMouseMove: (((Float, Float)?) -> Void)?
    weak var coordinator: MetalNetworkCoordinator?
    private var isPanning = false
    private var lastDragLocation: CGPoint = .zero
    private var mouseDownWasOnEmpty = false
    private var totalDragDistance: CGFloat = 0

    func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 {
            onPressEscape?()
        }
    }
    func handleMouseMoved(location: CGPoint, from view: NSView) {
        let loc = convert(location, from: view)
        let size = bounds.size
        if let (sx, sy) = coordinator?.viewToScene(viewPoint: loc, viewSize: size) {
            onMouseMove?((sx, sy))
        } else {
            onMouseMove?(nil)
        }
    }
    func handleMouseExited() {
        onMouseMove?(nil)
    }

    func handleScrollWheel(with event: NSEvent, from view: NSView) {
        let loc = convert(event.locationInWindow, from: nil)
        let delta = CGFloat(event.scrollingDeltaY) * 0.012
        onScrollWheel?(delta, loc, bounds.size)
    }
    func handleMouseDown(with event: NSEvent, from view: NSView) {
        let loc = convert(event.locationInWindow, from: nil)
        let size = bounds.size
        if event.type == .otherMouseDown || event.buttonNumber == 2 {
            isPanning = true
            lastDragLocation = loc
            return
        }
        if event.buttonNumber == 0 {
            let (node, link) = coordinator?.hitTest(viewPoint: loc, viewSize: size) ?? (nil, nil)
            if node != nil || link != nil {
                coordinator?.onSelect?(node, link)
                mouseDownWasOnEmpty = false
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
        if isPanning {
            let dx = loc.x - lastDragLocation.x
            let dy = loc.y - lastDragLocation.y
            totalDragDistance += (dx * dx + dy * dy).squareRoot()
            onPanDelta?(dx, dy, size)
            lastDragLocation = loc
        }
    }
    func handleMouseUp(with event: NSEvent, from view: NSView) {
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
    let scale: CGFloat
    let panX: CGFloat
    let panY: CGFloat
    let selectedNodeIndex: Int?
    let selectedLinkIndex: Int?
    let nodeScalars: [Float]?
    let linkScalars: [Float]?
    let nodeScalarRange: (Float, Float)?
    let linkScalarRange: (Float, Float)?
    let onScrollWheel: ((CGFloat, CGPoint, CGSize) -> Void)?
    let onPanDelta: ((CGFloat, CGFloat, CGSize) -> Void)?
    let onPressEscape: (() -> Void)?
    let onMouseMove: (((Float, Float)?) -> Void)?
    let onSelect: ((Int?, Int?) -> Void)?

    public init(scene: NetworkScene?, scale: CGFloat = 1, panX: CGFloat = 0, panY: CGFloat = 0, selectedNodeIndex: Int? = nil, selectedLinkIndex: Int? = nil, nodeScalars: [Float]? = nil, linkScalars: [Float]? = nil, nodeScalarRange: (Float, Float)? = nil, linkScalarRange: (Float, Float)? = nil, onScrollWheel: ((CGFloat, CGPoint, CGSize) -> Void)? = nil, onPanDelta: ((CGFloat, CGFloat, CGSize) -> Void)? = nil, onPressEscape: (() -> Void)? = nil, onMouseMove: (((Float, Float)?) -> Void)? = nil, onSelect: ((Int?, Int?) -> Void)? = nil) {
        self.scene = scene
        self.scale = scale
        self.panX = panX
        self.panY = panY
        self.selectedNodeIndex = selectedNodeIndex
        self.selectedLinkIndex = selectedLinkIndex
        self.nodeScalars = nodeScalars
        self.linkScalars = linkScalars
        self.nodeScalarRange = nodeScalarRange
        self.linkScalarRange = linkScalarRange
        self.onScrollWheel = onScrollWheel
        self.onPanDelta = onPanDelta
        self.onPressEscape = onPressEscape
        self.onMouseMove = onMouseMove
        self.onSelect = onSelect
    }
    public func makeNSView(context: Context) -> NSView {
        let container = ScrollableContainerView()
        container.onScrollWheel = onScrollWheel
        container.onPanDelta = onPanDelta
        container.onPressEscape = onPressEscape
        container.onMouseMove = onMouseMove
        context.coordinator.onSelect = onSelect
        container.coordinator = context.coordinator
        let mtkView = MapMTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        mtkView.enableSetNeedsDisplay = true
        mtkView.eventHandler = container
        context.coordinator.view = mtkView
        context.coordinator.scene = scene
        context.coordinator.scale = scale
        context.coordinator.panX = panX
        context.coordinator.panY = panY
        context.coordinator.selectedNodeIndex = selectedNodeIndex
        context.coordinator.selectedLinkIndex = selectedLinkIndex
        context.coordinator.nodeScalars = nodeScalars
        context.coordinator.linkScalars = linkScalars
        context.coordinator.nodeScalarRange = nodeScalarRange
        context.coordinator.linkScalarRange = linkScalarRange
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
        context.coordinator.scale = scale
        context.coordinator.panX = panX
        context.coordinator.panY = panY
        context.coordinator.selectedNodeIndex = selectedNodeIndex
        context.coordinator.selectedLinkIndex = selectedLinkIndex
        context.coordinator.nodeScalars = nodeScalars
        context.coordinator.linkScalars = linkScalars
        context.coordinator.nodeScalarRange = nodeScalarRange
        context.coordinator.linkScalarRange = linkScalarRange
        context.coordinator.onSelect = onSelect
        (container as? ScrollableContainerView)?.onScrollWheel = onScrollWheel
        (container as? ScrollableContainerView)?.onPanDelta = onPanDelta
        (container as? ScrollableContainerView)?.onPressEscape = onPressEscape
        (container as? ScrollableContainerView)?.onMouseMove = onMouseMove
        if let mtk = container.subviews.first as? MTKView { mtk.setNeedsDisplay(mtk.bounds) }
    }
    public func makeCoordinator() -> MetalNetworkCoordinator { MetalNetworkCoordinator() }
}

#else
public struct MetalNetworkView: UIViewRepresentable {
    let scene: NetworkScene?
    let scale: CGFloat
    let panX: CGFloat
    let panY: CGFloat
    let selectedNodeIndex: Int?
    let selectedLinkIndex: Int?
    let nodeScalars: [Float]?
    let linkScalars: [Float]?
    let nodeScalarRange: (Float, Float)?
    let linkScalarRange: (Float, Float)?
    let onScrollWheel: ((CGFloat, CGPoint, CGSize) -> Void)?
    let onPanDelta: ((CGFloat, CGFloat, CGSize) -> Void)?
    let onPressEscape: (() -> Void)?
    let onMouseMove: (((Float, Float)?) -> Void)?
    let onSelect: ((Int?, Int?) -> Void)?

    public init(scene: NetworkScene?, scale: CGFloat = 1, panX: CGFloat = 0, panY: CGFloat = 0, selectedNodeIndex: Int? = nil, selectedLinkIndex: Int? = nil, nodeScalars: [Float]? = nil, linkScalars: [Float]? = nil, nodeScalarRange: (Float, Float)? = nil, linkScalarRange: (Float, Float)? = nil, onScrollWheel: ((CGFloat, CGPoint, CGSize) -> Void)? = nil, onPanDelta: ((CGFloat, CGFloat, CGSize) -> Void)? = nil, onPressEscape: (() -> Void)? = nil, onMouseMove: (((Float, Float)?) -> Void)? = nil, onSelect: ((Int?, Int?) -> Void)? = nil) {
        self.scene = scene
        self.scale = scale
        self.panX = panX
        self.panY = panY
        self.selectedNodeIndex = selectedNodeIndex
        self.selectedLinkIndex = selectedLinkIndex
        self.nodeScalars = nodeScalars
        self.linkScalars = linkScalars
        self.nodeScalarRange = nodeScalarRange
        self.linkScalarRange = linkScalarRange
        self.onScrollWheel = onScrollWheel
        self.onPanDelta = onPanDelta
        self.onPressEscape = onPressEscape
        self.onMouseMove = onMouseMove
        self.onSelect = onSelect
    }

    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.isUserInteractionEnabled = true
        context.coordinator.view = mtkView
        context.coordinator.scene = scene
        context.coordinator.scale = scale
        context.coordinator.panX = panX
        context.coordinator.panY = panY
        context.coordinator.selectedNodeIndex = selectedNodeIndex
        context.coordinator.selectedLinkIndex = selectedLinkIndex
        context.coordinator.nodeScalars = nodeScalars
        context.coordinator.linkScalars = linkScalars
        context.coordinator.nodeScalarRange = nodeScalarRange
        context.coordinator.linkScalarRange = linkScalarRange
        context.coordinator.onSelect = onSelect
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(MetalNetworkCoordinator.handleTap(_:)))
        mtkView.addGestureRecognizer(tap)
        return mtkView
    }

    public func updateUIView(_ mtkView: MTKView, context: Context) {
        context.coordinator.scene = scene
        context.coordinator.scale = scale
        context.coordinator.panX = panX
        context.coordinator.panY = panY
        context.coordinator.selectedNodeIndex = selectedNodeIndex
        context.coordinator.selectedLinkIndex = selectedLinkIndex
        context.coordinator.nodeScalars = nodeScalars
        context.coordinator.linkScalars = linkScalars
        context.coordinator.nodeScalarRange = nodeScalarRange
        context.coordinator.linkScalarRange = linkScalarRange
        context.coordinator.onSelect = onSelect
        mtkView.setNeedsDisplay(mtkView.bounds)
    }

    public func makeCoordinator() -> MetalNetworkCoordinator { MetalNetworkCoordinator() }
}
#endif
