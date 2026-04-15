import SwiftUI
import EPANET3Renderer

/// 视图坐标命中 SCADA 圆标（与 `ScadaCanvasOverlay` 绘制一致；优先于 Metal 管网 `hitTest`）。
enum ScadaCanvasHitTest {
    /// 命中半径（像素），略大于圆半径便于点击。
    private static let hitRadiusPx: CGFloat = 14

    static func pickDevice(
        viewPoint: CGPoint,
        viewSize: CGSize,
        transformBounds: (minX: Float, maxX: Float, minY: Float, maxY: Float),
        scale: CGFloat,
        panX: CGFloat,
        panY: CGFloat,
        pressureDevices: [ScadaDeviceRow],
        flowDevices: [ScadaDeviceRow],
        showPressure: Bool,
        showFlow: Bool
    ) -> ScadaDeviceSelection? {
        guard viewSize.width > 8, viewSize.height > 8 else { return nil }
        var best: (ScadaDeviceSelection, CGFloat)?
        if showPressure {
            for dev in pressureDevices {
                guard let x = dev.x, let y = dev.y else { continue }
                let pt = CanvasMapProjection.sceneToView(
                    sceneX: Float(x), sceneY: Float(y),
                    transformBounds: transformBounds,
                    scale: scale, panX: panX, panY: panY,
                    viewSize: viewSize
                )
                let dx = viewPoint.x - pt.x
                let dy = viewPoint.y - pt.y
                let d = (dx * dx + dy * dy).squareRoot()
                guard d <= hitRadiusPx else { continue }
                let sel = ScadaDeviceSelection(kind: .pressure, deviceId: dev.id)
                if best == nil || d < best!.1 { best = (sel, d) }
            }
        }
        if showFlow {
            for dev in flowDevices {
                guard let x = dev.x, let y = dev.y else { continue }
                let pt = CanvasMapProjection.sceneToView(
                    sceneX: Float(x), sceneY: Float(y),
                    transformBounds: transformBounds,
                    scale: scale, panX: panX, panY: panY,
                    viewSize: viewSize
                )
                let dx = viewPoint.x - pt.x
                let dy = viewPoint.y - pt.y
                let d = (dx * dx + dy * dy).squareRoot()
                guard d <= hitRadiusPx else { continue }
                let sel = ScadaDeviceSelection(kind: .flow, deviceId: dev.id)
                if best == nil || d < best!.1 { best = (sel, d) }
            }
        }
        return best?.0
    }
}

/// 画布上的 SCADA 设备标记：压力用 **P** 圆标、流量用 **Q** 圆标，坐标与管网场景一致。
struct ScadaCanvasOverlay: View {
    let pressureDevices: [ScadaDeviceRow]
    let flowDevices: [ScadaDeviceRow]
    let showPressure: Bool
    let showFlow: Bool
    let selectedDevice: ScadaDeviceSelection?
    let transformBounds: (minX: Float, maxX: Float, minY: Float, maxY: Float)
    let scale: CGFloat
    let panX: CGFloat
    let panY: CGFloat

    private let markerDiameter: CGFloat = 18
    private let pressureColor = Color(red: 0.16, green: 0.55, blue: 0.87)
    private let flowColor = Color(red: 0.85, green: 0.42, blue: 0.14)

    var body: some View {
        Canvas { context, size in
            guard size.width > 8, size.height > 8 else { return }
            if showPressure {
                for dev in pressureDevices {
                    guard let x = dev.x, let y = dev.y else { continue }
                    let pt = sceneToView(Float(x), Float(y), size)
                    guard isInView(pt, size) else { continue }
                    let sel = selectedDevice?.kind == .pressure && selectedDevice?.deviceId == dev.id
                    drawMarker(context: &context, center: pt, letter: "P", color: pressureColor, selected: sel)
                }
            }
            if showFlow {
                for dev in flowDevices {
                    guard let x = dev.x, let y = dev.y else { continue }
                    let pt = sceneToView(Float(x), Float(y), size)
                    guard isInView(pt, size) else { continue }
                    let sel = selectedDevice?.kind == .flow && selectedDevice?.deviceId == dev.id
                    drawMarker(context: &context, center: pt, letter: "Q", color: flowColor, selected: sel)
                }
            }
        }
    }

    private func drawMarker(context: inout GraphicsContext, center: CGPoint, letter: String, color: Color, selected: Bool) {
        let r = markerDiameter * 0.5
        let rect = CGRect(x: center.x - r, y: center.y - r, width: markerDiameter, height: markerDiameter)
        if selected {
            let ring = CGRect(x: center.x - r - 3, y: center.y - r - 3, width: markerDiameter + 6, height: markerDiameter + 6)
            context.stroke(Circle().path(in: ring), with: .color(Color.yellow.opacity(0.95)), lineWidth: 2.5)
        }
        context.fill(Circle().path(in: rect), with: .color(color))
        context.stroke(Circle().path(in: rect), with: .color(.white), lineWidth: 1.5)
        let text = Text(letter).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.white)
        let resolved = context.resolve(text)
        let textSize = resolved.measure(in: CGSize(width: markerDiameter, height: markerDiameter))
        context.draw(resolved, at: CGPoint(x: center.x, y: center.y - textSize.height * 0.02), anchor: .center)
    }

    private func sceneToView(_ sx: Float, _ sy: Float, _ size: CGSize) -> CGPoint {
        CanvasMapProjection.sceneToView(
            sceneX: sx, sceneY: sy,
            transformBounds: transformBounds,
            scale: scale, panX: panX, panY: panY,
            viewSize: size
        )
    }

    private func isInView(_ pt: CGPoint, _ size: CGSize) -> Bool {
        let m = markerDiameter
        return pt.x > -m && pt.x < size.width + m && pt.y > -m && pt.y < size.height + m
    }
}

/// 把 `CanvasMapProjection` 标记为包级可见（与 `CanvasMapLabelsOverlay.swift` 中的 `private` 匹配不了）→ 复制投影逻辑。
private enum CanvasMapProjection {
    static func sceneToView(
        sceneX: Float, sceneY: Float,
        transformBounds: (minX: Float, maxX: Float, minY: Float, maxY: Float),
        scale: CGFloat, panX: CGFloat, panY: CGFloat,
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
            scaleY = s; scaleX = scaleY * h / w
        } else {
            scaleX = s; scaleY = scaleX * w / h
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
}
