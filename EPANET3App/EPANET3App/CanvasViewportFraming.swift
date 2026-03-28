import Foundation
import EPANET3Renderer

/// 画布投影包围盒（锚点固定，与 `NetworkScene.bounds` 解耦）；与 Metal `framingRect` / padding 一致。
enum CanvasViewportFraming {
    /// 以 `anchor` 为中心、半边至少 40，含 padding；空场景与有图元同一公式。
    static func squareTransformBounds(scene: NetworkScene, anchor: (x: Float, y: Float)) -> (minX: Float, maxX: Float, minY: Float, maxY: Float) {
        var halfW: Float = 0
        var halfH: Float = 0
        for n in scene.nodes {
            halfW = max(halfW, abs(n.x - anchor.x))
            halfH = max(halfH, abs(n.y - anchor.y))
        }
        for l in scene.links {
            halfW = max(halfW, abs(l.x1 - anchor.x), abs(l.x2 - anchor.x))
            halfH = max(halfH, abs(l.y1 - anchor.y), abs(l.y2 - anchor.y))
        }
        let half = max(halfW, halfH, 40)
        let bw = 2 * half
        let bh = 2 * half
        let pad = max(bw, bh) * 0.05 + 1
        return (anchor.x - half - pad, anchor.x + half + pad, anchor.y - half - pad, anchor.y + half + pad)
    }

    static func intrinsicBaseScale(transformBounds t: (minX: Float, maxX: Float, minY: Float, maxY: Float)) -> CGFloat {
        let bw = CGFloat(t.maxX - t.minX)
        let bh = CGFloat(t.maxY - t.minY)
        guard bw > 0, bh > 0 else { return 0.02 }
        let pad = max(bw, bh) * 0.05 + 1
        return min(2.0 / (bw + pad * 2), 2.0 / (bh + pad * 2))
    }

    static func zoomFingerprint(scene: NetworkScene, anchor: (x: Float, y: Float)) -> String {
        let t = squareTransformBounds(scene: scene, anchor: anchor)
        return "\(t.minX),\(t.minY),\(t.maxX),\(t.maxY),\(scene.nodes.count),\(scene.links.count)"
    }
}
