#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation

/// The size a person gave a panel by dragging its corner, remembered per panel on this device.
public struct HmmPanelSize: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double?

    public init(width: Double, height: Double? = nil) {
        self.width = width
        self.height = height
    }
}

/// How far a panel may be resized, and where its size is remembered (`UserDefaults`, key `hmm.panel.<id>`).
public struct HmmPanelSizing: Sendable {
    public var id: String
    public var minimum: CGSize
    public var maximum: CGSize

    public init(id: String, minimum: CGSize = CGSize(width: 280, height: 220), maximum: CGSize = CGSize(width: 620, height: 2000)) {
        self.id = id
        self.minimum = minimum
        self.maximum = maximum
    }

    public var key: String { "hmm.panel.\(id)" }

    public func load(from defaults: UserDefaults = .standard) -> HmmPanelSize? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(HmmPanelSize.self, from: $0) }
    }

    public func save(_ size: HmmPanelSize, to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(clamped(size)), forKey: key)
    }

    public func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    public func clamped(_ size: HmmPanelSize) -> HmmPanelSize {
        let width = min(max(size.width, minimum.width), maximum.width)
        let height = size.height.map { min(max($0, minimum.height), maximum.height) }
        return HmmPanelSize(width: width, height: height)
    }

    /// A drag on the resize grip: `dx` and `dy` in screen points, the grip on the panel's right edge or its left
    /// (a panel docked on the right grows to the left). Height starts from what the panel showed.
    public func resized(_ start: HmmPanelSize, shownHeight: Double, dx: Double, dy: Double, gripOnRight: Bool) -> HmmPanelSize {
        let width = start.width + (gripOnRight ? dx : -dx)
        let height = (start.height ?? shownHeight) + dy
        return clamped(HmmPanelSize(width: width, height: height))
    }
}
