import Foundation

/// A rectangle in normalised frame coordinates (0…1, origin top-left) or in pixels, depending on use.
public struct PerceptionRect: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var area: Double { max(width, 0) * max(height, 0) }

    public func intersection(_ other: PerceptionRect) -> PerceptionRect? {
        let left = max(x, other.x)
        let top = max(y, other.y)
        let right = min(maxX, other.maxX)
        let bottom = min(maxY, other.maxY)
        guard right > left, bottom > top else { return nil }
        return PerceptionRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    public func scaled(width scaleX: Double, height scaleY: Double) -> PerceptionRect {
        PerceptionRect(x: x * scaleX, y: y * scaleY, width: width * scaleX, height: height * scaleY)
    }
}

/// Where the cells of a contact sheet go.
public struct ContactSheetLayout: Hashable, Sendable {
    public var columns: Int
    public var rows: Int
    public var cellWidth: Double
    public var cellHeight: Double
    /// Space under each frame for its timecode and notes.
    public var captionHeight: Double
    public var padding: Double

    /// `count` frames of `aspect` (width / height) in a sheet at most `maxWidth` wide. Columns: 2 for ≤ 4 frames,
    /// 3 up to 9, then 4 (so each frame stays big enough to judge).
    public init(count: Int, aspect: Double, maxWidth: Double, captionHeight: Double = 36, padding: Double = 12) {
        let safeCount = max(count, 1)
        columns = safeCount <= 4 ? min(safeCount, 2) : (safeCount <= 9 ? 3 : 4)
        rows = Int((Double(safeCount) / Double(columns)).rounded(.up))
        self.padding = padding
        self.captionHeight = captionHeight
        cellWidth = ((maxWidth - padding * Double(columns + 1)) / Double(columns)).rounded(.down)
        cellHeight = (cellWidth / max(aspect, 0.1)).rounded(.down)
    }

    public var width: Double { Double(columns) * cellWidth + Double(columns + 1) * padding }
    public var height: Double { Double(rows) * (cellHeight + captionHeight) + Double(rows + 1) * padding }

    /// The frame rectangle of cell `index` (pixels, top-left origin).
    public func frame(_ index: Int) -> PerceptionRect {
        let column = index % columns
        let row = index / columns
        return PerceptionRect(x: padding + Double(column) * (cellWidth + padding),
                              y: padding + Double(row) * (cellHeight + captionHeight + padding),
                              width: cellWidth, height: cellHeight)
    }

    /// The caption rectangle under cell `index`.
    public func caption(_ index: Int) -> PerceptionRect {
        let cell = frame(index)
        return PerceptionRect(x: cell.x, y: cell.maxY, width: cell.width, height: captionHeight)
    }
}

/// One numbered marker for set-of-marks prompting ("#3 is the lamp").
public struct Mark: Hashable, Sendable, Codable {
    public var number: Int
    /// Normalised centre of the marker.
    public var x: Double
    public var y: Double
    /// Normalised bounding box of what it labels.
    public var box: PerceptionRect

    public init(number: Int, x: Double, y: Double, box: PerceptionRect) {
        self.number = number
        self.x = x
        self.y = y
        self.box = box
    }
}

/// Places set-of-marks markers: each at its object's visible centre, kept inside the frame, nudged apart so no two
/// markers overlap (bigger objects keep their spot; smaller ones move).
public enum MarkLayout {
    /// `boxes` normalised; `radius` of a marker, normalised to the frame height; `aspect` = width / height.
    public static func place(_ boxes: [PerceptionRect], radius: Double = 0.022, aspect: Double = 16.0 / 9.0) -> [Mark] {
        let order = boxes.indices.sorted { boxes[$0].area > boxes[$1].area }
        var placed: [Int: Mark] = [:]
        let rx = radius / aspect
        let ry = radius
        for index in order {
            let box = boxes[index]
            var x = min(max(box.midX, rx), 1 - rx)
            var y = min(max(box.midY, ry), 1 - ry)
            var attempt = 0
            while attempt < 24, placed.values.contains(where: { abs($0.x - x) < rx * 2.1 && abs($0.y - y) < ry * 2.1 }) {
                attempt += 1
                // Spiral outwards in small steps.
                let angle = Double(attempt) * 2.4
                let distance = Double(attempt) * radius * 0.9
                x = min(max(box.midX + cos(angle) * distance / aspect, rx), 1 - rx)
                y = min(max(box.midY + sin(angle) * distance, ry), 1 - ry)
            }
            placed[index] = Mark(number: index + 1, x: x, y: y, box: box)
        }
        return boxes.indices.compactMap { placed[$0] }
    }
}

/// Safe zones for the three delivery shapes: 16:9 title safe, 1:1, and 9:16 with the parts the Shorts / Reels /
/// TikTok interface covers (caption and buttons), all normalised.
public enum SafeZones {
    public enum Shape: String, Sendable, CaseIterable {
        case landscape, square, vertical
    }

    /// Where important things may go.
    public static func safe(_ shape: Shape) -> PerceptionRect {
        switch shape {
        case .landscape: PerceptionRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
        case .square: PerceptionRect(x: 0.06, y: 0.06, width: 0.88, height: 0.88)
        case .vertical: PerceptionRect(x: 0.06, y: 0.14, width: 0.76, height: 0.6)
        }
    }

    /// What the platform's own interface covers (9:16 only).
    public static func covered(_ shape: Shape) -> [PerceptionRect] {
        guard shape == .vertical else { return [] }
        return [
            PerceptionRect(x: 0, y: 0, width: 1, height: 0.1), // top bar
            PerceptionRect(x: 0, y: 0.78, width: 1, height: 0.22), // caption, handle, music
            PerceptionRect(x: 0.84, y: 0.42, width: 0.16, height: 0.4) // like / comment / share column
        ]
    }

    /// Fraction of `box` that falls outside the safe area or under the interface.
    public static func unsafeFraction(_ box: PerceptionRect, shape: Shape) -> Double {
        guard box.area > 0 else { return 0 }
        let inside = box.intersection(safe(shape))?.area ?? 0
        var outside = (box.area - inside) / box.area
        for zone in covered(shape) {
            outside += (box.intersection(zone)?.area ?? 0) / box.area
        }
        return outside < 1e-9 ? 0 : min(outside, 1)
    }
}
