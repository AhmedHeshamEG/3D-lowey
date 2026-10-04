import Foundation

/// A small depth-tested rasteriser for perception: which labelled object covers each pixel of a low-resolution frame,
/// and how many pixels each would cover if nothing stood in front of it. Visible % is the first over the second.
/// Pure Swift, so reports are the same on the iPad, a Mac and the Linux tests.
public struct CoverageRaster: Sendable {
    public let width: Int
    public let height: Int
    /// The nearest label per pixel (−1: nothing, sky or ground), row-major, top row first.
    public private(set) var labels: [Int32]
    /// Nearness per pixel (bigger is nearer): 1 / depth for perspective, −depth for orthographic.
    private var nearness: [Double]
    /// Pixels each label covers on its own (its unoccluded silhouette).
    public private(set) var soloCounts: [Int32: Int] = [:]

    public init(width: Int, height: Int) {
        self.width = max(width, 1)
        self.height = max(height, 1)
        labels = [Int32](repeating: -1, count: self.width * self.height)
        nearness = [Double](repeating: -.infinity, count: self.width * self.height)
    }

    /// A frame whose labels are already known (from the renderer's object buffer).
    init(width: Int, height: Int, labels: [Int32]) {
        self.init(width: width, height: height)
        self.labels = labels
    }

    /// An analysis frame of about `pixels` pixels at `aspect`.
    public init(aspect: Double, pixels: Int = 320 * 180) {
        let height = Int((Double(pixels) / max(aspect, 0.05)).squareRoot().rounded())
        self.init(width: Int((Double(height) * aspect).rounded()), height: height)
    }

    /// Draws world-space triangles (three points each) as `label`.
    public mutating func draw(_ triangles: [Vec3], label: Int32, camera: ObserveCamera) {
        var solo = [Bool](repeating: false, count: width * height)
        var count = 0
        var index = 0
        while index + 2 < triangles.count {
            let polygon = clip([camera.local(triangles[index]), camera.local(triangles[index + 1]), camera.local(triangles[index + 2])],
                               camera: camera)
            index += 3
            guard polygon.count >= 3 else { continue }
            let points = polygon.compactMap { point -> (x: Double, y: Double, near: Double)? in
                guard let projected = camera.project(local: point) else { return nil }
                let near = camera.orthographicHeight == nil ? 1 / max(projected.depth, 1e-6) : -projected.depth
                return (projected.x * Double(width), projected.y * Double(height), near)
            }
            guard points.count == polygon.count else { continue }
            for fan in 1 ..< points.count - 1 {
                fill(points[0], points[fan], points[fan + 1], label: label, solo: &solo, count: &count)
            }
        }
        soloCounts[label, default: 0] += count
    }

    /// Pixels where `label` is the nearest thing.
    public func visibleCount(of label: Int32) -> Int {
        labels.reduce(0) { $0 + ($1 == label ? 1 : 0) }
    }

    /// Whether a pixel shows `label`.
    public func shows(_ label: Int32, x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height && labels[y * width + x] == label
    }

    /// The label at a pixel (−1: nothing).
    public func label(x: Int, y: Int) -> Int32 {
        guard x >= 0, y >= 0, x < width, y < height else { return -1 }
        return labels[y * width + x]
    }

    // MARK: Private

    /// Clips a camera-space polygon to the near plane (perspective only).
    private func clip(_ polygon: [Vec3], camera: ObserveCamera) -> [Vec3] {
        guard camera.orthographicHeight == nil else { return polygon }
        let plane = -camera.near
        var result: [Vec3] = []
        for index in polygon.indices {
            let current = polygon[index]
            let next = polygon[(index + 1) % polygon.count]
            let currentIn = current.z <= plane
            let nextIn = next.z <= plane
            if currentIn { result.append(current) }
            if currentIn != nextIn {
                let t = (plane - current.z) / (next.z - current.z)
                result.append(current + (next - current) * t)
            }
        }
        return result
    }

    private mutating func fill(_ a: (x: Double, y: Double, near: Double), _ b: (x: Double, y: Double, near: Double),
                               _ c: (x: Double, y: Double, near: Double), label: Int32, solo: inout [Bool], count: inout Int) {
        let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        guard abs(area) > 1e-12 else { return }
        let minX = max(Int(min(a.x, b.x, c.x).rounded(.down)), 0)
        let maxX = min(Int(max(a.x, b.x, c.x).rounded(.up)), width - 1)
        let minY = max(Int(min(a.y, b.y, c.y).rounded(.down)), 0)
        let maxY = min(Int(max(a.y, b.y, c.y).rounded(.up)), height - 1)
        guard minX <= maxX, minY <= maxY else { return }
        for row in minY ... maxY {
            let py = Double(row) + 0.5
            for column in minX ... maxX {
                let px = Double(column) + 0.5
                let w0 = ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) / area
                let w1 = ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) / area
                let w2 = 1 - w0 - w1
                guard w0 >= 0, w1 >= 0, w2 >= 0 else { continue }
                let pixel = row * width + column
                if !solo[pixel] {
                    solo[pixel] = true
                    count += 1
                }
                let near = w0 * a.near + w1 * b.near + w2 * c.near
                if near > nearness[pixel] {
                    nearness[pixel] = near
                    labels[pixel] = label
                }
            }
        }
    }
}
