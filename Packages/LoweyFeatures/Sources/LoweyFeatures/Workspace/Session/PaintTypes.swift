import CoreGraphics
import Foundation
import LoweyCore

/// Paint ▸ Colour (CONTEXT §10.4): what the Pencil does on a model, the brush's size and opacity, the layer each object
/// paints on, and a picture being placed to project.
public struct ColourPaintSettings: Equatable {
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case paint, erase, fill, pick

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .paint: "Paint"
            case .erase: "Erase"
            case .fill: "Fill"
            case .pick: "Eyedropper"
            }
        }

        public var systemImage: String {
            switch self {
            case .paint: "paintbrush.pointed"
            case .erase: "eraser"
            case .fill: "drop.fill"
            case .pick: "eyedropper"
            }
        }
    }

    public var mode: Mode = .paint
    /// The brush's size in points at full pressure.
    public var size: Double = 16
    public var opacity: Double = 1
    /// The object being painted (the last one touched or chosen).
    public var target: ObjectID?
    /// The layer each object paints on (its top layer until another is chosen).
    public var layers: [ObjectID: String] = [:]
    /// Objects being made ready to paint (laid flat in the background).
    public var preparing: Set<ObjectID> = []
    /// A picture placed over the stage, to project onto the target.
    public var picture: PaintPicture?

    public init() {}
}

/// A picture over the stage, placed with the fingers, then projected from the camera onto what it covers.
public struct PaintPicture: Equatable {
    public let id = UUID()
    public let image: CGImage
    /// Where it sits on the stage (points).
    public var rect: CGRect

    public init(image: CGImage, rect: CGRect) {
        self.image = image
        self.rect = rect
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.rect == rhs.rect
    }
}
