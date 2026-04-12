/* NetworkScene - Lightweight scene model for rendering
 * Holds node positions and link topology for Metal rendering.
 */
import Foundation

public struct NodeVertex {
    public let x: Float
    public let y: Float
    public let nodeIndex: Int
    /// 与 `NodeTypes` 一致：0=junction，1=reservoir，2=tank（供画布按设置着色）
    public let kind: UInt8

    public init(x: Float, y: Float, nodeIndex: Int, kind: UInt8 = 0) {
        self.x = x
        self.y = y
        self.nodeIndex = nodeIndex
        self.kind = kind
    }
}

public struct LinkVertex {
    public let x1: Float, y1: Float
    public let x2: Float, y2: Float
    public let linkIndex: Int
    /// 0=Pipe/CVPIPE，1=Pump，2=阀门等（与画布设置着色一致）
    public let kind: UInt8

    public init(x1: Float, y1: Float, x2: Float, y2: Float, linkIndex: Int, kind: UInt8 = 0) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
        self.linkIndex = linkIndex
        self.kind = kind
    }
}

public struct NetworkScene {
    public let nodes: [NodeVertex]
    public let links: [LinkVertex]
    public let bounds: (minX: Float, minY: Float, maxX: Float, maxY: Float)

    public init(nodes: [NodeVertex], links: [LinkVertex]) {
        self.nodes = nodes
        self.links = links
        var minX: Float = .greatestFiniteMagnitude, minY = minX
        var maxX: Float = -.greatestFiniteMagnitude, maxY = maxX
        for n in nodes {
            minX = min(minX, n.x)
            minY = min(minY, n.y)
            maxX = max(maxX, n.x)
            maxY = max(maxY, n.y)
        }
        if nodes.isEmpty {
            minX = 0; minY = 0; maxX = 100; maxY = 100
        } else {
            let minExtent: Float = 80
            if maxX - minX < minExtent {
                let c = (minX + maxX) * 0.5
                minX = c - minExtent * 0.5
                maxX = c + minExtent * 0.5
            }
            if maxY - minY < minExtent {
                let c = (minY + maxY) * 0.5
                minY = c - minExtent * 0.5
                maxY = c + minExtent * 0.5
            }
        }
        self.bounds = (minX, minY, maxX, maxY)
    }
}

/// 画布按类型显示/隐藏（与 `NodeVertex.kind` / `LinkVertex.kind` 一致：节点 0/1/2，管段 0=Pipe 1=Pump 2=Valve）。
public struct CanvasLayerVisibility: Equatable, Sendable {
    public var showJunction: Bool
    public var showReservoir: Bool
    public var showTank: Bool
    public var showPipe: Bool
    public var showPump: Bool
    public var showValve: Bool

    public init(
        showJunction: Bool = true,
        showReservoir: Bool = true,
        showTank: Bool = true,
        showPipe: Bool = true,
        showPump: Bool = true,
        showValve: Bool = true
    ) {
        self.showJunction = showJunction
        self.showReservoir = showReservoir
        self.showTank = showTank
        self.showPipe = showPipe
        self.showPump = showPump
        self.showValve = showValve
    }

    public static let allVisible = CanvasLayerVisibility()

    public func isNodeKindVisible(_ kind: UInt8) -> Bool {
        switch kind {
        case 0: return showJunction
        case 1: return showReservoir
        case 2: return showTank
        default: return true
        }
    }

    public func isLinkKindVisible(_ kind: UInt8) -> Bool {
        switch kind {
        case 0: return showPipe
        case 1: return showPump
        default: return showValve
        }
    }
}
