import Foundation

public struct FlowNode: Equatable, Sendable {
    public var topicId: Int
    public var column: Int      // 0'dan başlar; konuların ilk isteğine göre sıra
    public var lane: Int        // 0 ana hat; -1, -2 yukarı; +1, +2 aşağı
    public var parent: Int?     // lane != 0 iken dalın ayrıldığı konunun id'si
    public init(topicId: Int, column: Int, lane: Int, parent: Int?) {
        self.topicId = topicId; self.column = column; self.lane = lane; self.parent = parent
    }
}

public func flowLayout(_ topics: [Topic]) -> [FlowNode] {
    let sorted = topics.sorted { ($0.requests.min() ?? .max) < ($1.requests.min() ?? .max) }
    let byId = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var lanes: [Int: Int] = [:]
    var next = -1
    return sorted.enumerated().map { col, t in
        var lane = 0
        var parent: Int?
        if t.state != "done", let f = t.from, f != t.id, let p = byId[f],
           let pm = p.requests.min(), let tm = t.requests.min(), pm < tm {
            parent = f
            if let pl = lanes[f], pl != 0 {
                lane = pl + pl.signum()
            } else {
                lane = next
                next = -next   // -1, +1, -1, ... dönüşümlü
            }
        }
        lanes[t.id] = lane
        return FlowNode(topicId: t.id, column: col, lane: lane, parent: parent)
    }
}

/// ekran = dünya * scale + (x, y)
public struct Camera: Equatable, Sendable {
    public var x: Double; public var y: Double; public var scale: Double
    public init(x: Double, y: Double, scale: Double) { self.x = x; self.y = y; self.scale = scale }
}

public let cameraScaleRange: ClosedRange<Double> = 0.4...2.0

public func clampCamera(_ c: Camera, content: CGRect, viewport: CGSize) -> Camera {
    let s = min(max(c.scale, cameraScaleRange.lowerBound), cameraScaleRange.upperBound)
    let cx = min(max((viewport.width / 2 - c.x) / s, content.origin.x), (content.origin.x + content.size.width))
    let cy = min(max((viewport.height / 2 - c.y) / s, content.origin.y), (content.origin.y + content.size.height))
    return Camera(x: viewport.width / 2 - cx * s, y: viewport.height / 2 - cy * s, scale: s)
}

public func fitCamera(content: CGRect, viewport: CGSize, padding: Double = 40) -> Camera {
    let fit = min((viewport.width - 2 * padding) / content.size.width, (viewport.height - 2 * padding) / content.size.height)
    return focusCamera(on: content, scale: min(1, max(0.4, fit)), viewport: viewport)
}

public func focusCamera(on rect: CGRect, scale: Double, viewport: CGSize) -> Camera {
    let s = min(max(scale, cameraScaleRange.lowerBound), cameraScaleRange.upperBound)
    return Camera(x: viewport.width / 2 - (rect.origin.x + rect.size.width / 2) * s, y: viewport.height / 2 - (rect.origin.y + rect.size.height / 2) * s, scale: s)
}

public func resolveTopicSelection(_ selected: Int?, topics: [Topic]) -> Int? {
    if let s = selected, topics.contains(where: { $0.id == s }) { return s }
    return topics.first(where: { $0.state == "active" })?.id ?? topics.last?.id
}
