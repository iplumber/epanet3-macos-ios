/* NetworkScene - Lightweight scene model for rendering
 * Holds node positions and link topology for Metal rendering.
 */
import Foundation

public struct NodeVertex {
    public let x: Float
    public let y: Float
    public let nodeIndex: Int

    public init(x: Float, y: Float, nodeIndex: Int) {
        self.x = x
        self.y = y
        self.nodeIndex = nodeIndex
    }
}

public struct LinkVertex {
    public let x1: Float, y1: Float
    public let x2: Float, y2: Float
    public let linkIndex: Int

    public init(x1: Float, y1: Float, x2: Float, y2: Float, linkIndex: Int) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
        self.linkIndex = linkIndex
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
        }
        self.bounds = (minX, minY, maxX, maxY)
    }
}
