/// Maps a vertical drag on the slider track to a value. Pure maths, tested on its own.
public struct HmmSliderMapping: Sendable, Equatable {
    public var range: ClosedRange<Double>
    /// Track length in points.
    public var length: Double
    /// Dragging this far sideways (in points) makes the drag 4× finer (precision control, like Procreate's).
    public var precisionDistance: Double

    public init(range: ClosedRange<Double>, length: Double, precisionDistance: Double = 60) {
        self.range = range
        self.length = max(length, 1)
        self.precisionDistance = precisionDistance
    }

    /// 0…1 position of a value on the track (0 = bottom).
    public func fraction(of value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    /// The value after dragging `dy` points (up = negative, as on screen) starting from `start`, with the finger
    /// `dx` points to the side of the track.
    public func value(start: Double, dy: Double, dx: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        let fine = abs(dx) > precisionDistance ? 0.25 : 1
        let moved = -dy / length * span * fine
        return min(max(start + moved, range.lowerBound), range.upperBound)
    }
}
