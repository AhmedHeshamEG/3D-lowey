import Foundation

/// The type of a property value. Every property is typed; the animatable ones can be
/// keyframed by the timeline (Phase 2) without any change to the model.
public enum PropertyType: String, Codable, Sendable, CaseIterable {
    case float, int, bool, vec3, quat, color, string, enumeration, asset

    /// Whether values of this type interpolate smoothly (others step).
    public var interpolates: Bool {
        switch self {
        case .float, .vec3, .quat, .color: true
        case .int, .bool, .string, .enumeration, .asset: false
        }
    }
}

/// A typed property value.
///
/// JSON form is a one-key object naming the type — unambiguous for humans and AI:
/// `{"vec3":[0,1,0]}`, `{"float":2.5}`, `{"color":"palette:2"}`, `{"bool":true}`.
public enum PropertyValue: Hashable, Sendable {
    case float(Double)
    case int(Int)
    case bool(Bool)
    case vec3(Vec3)
    case quat(Quat)
    case color(ColorValue)
    case string(String)
    case enumeration(String)
    case asset(AssetID)

    public var type: PropertyType {
        switch self {
        case .float: .float
        case .int: .int
        case .bool: .bool
        case .vec3: .vec3
        case .quat: .quat
        case .color: .color
        case .string: .string
        case .enumeration: .enumeration
        case .asset: .asset
        }
    }

    public var floatValue: Double? {
        switch self {
        case let .float(value): value
        case let .int(value): Double(value)
        default: nil
        }
    }

    public var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    public var vec3Value: Vec3? {
        if case let .vec3(value) = self { return value }
        return nil
    }

    public var quatValue: Quat? {
        if case let .quat(value) = self { return value }
        return nil
    }

    public var colorValue: ColorValue? {
        if case let .color(value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        switch self {
        case let .string(value), let .enumeration(value): value
        default: nil
        }
    }

    /// Interpolates between two values of the same type. Non-interpolating types step at t = 1.
    public func interpolated(to other: PropertyValue, _ t: Double, palette: Palette = .empty) -> PropertyValue {
        switch (self, other) {
        case let (.float(a), .float(b)):
            return .float(a + (b - a) * t)
        case let (.vec3(a), .vec3(b)):
            return .vec3(a.lerp(to: b, t))
        case let (.quat(a), .quat(b)):
            return .quat(a.slerp(to: b, t))
        case let (.color(a), .color(b)):
            if a == b { return self }
            return .color(.rgba(a.resolved(in: palette).lerp(to: b.resolved(in: palette), t)))
        default:
            return t >= 1 ? other : self
        }
    }
}

extension PropertyValue: Codable {
    private enum Key: String, CodingKey {
        case float, int, bool, vec3, quat, color, string
        case enumeration = "enum"
        case asset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        guard let key = container.allKeys.first, container.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "A property value must be an object with exactly one type key"
            ))
        }
        switch key {
        case .float: self = try .float(container.decode(Double.self, forKey: key))
        case .int: self = try .int(container.decode(Int.self, forKey: key))
        case .bool: self = try .bool(container.decode(Bool.self, forKey: key))
        case .vec3: self = try .vec3(container.decode(Vec3.self, forKey: key))
        case .quat: self = try .quat(container.decode(Quat.self, forKey: key))
        case .color: self = try .color(container.decode(ColorValue.self, forKey: key))
        case .string: self = try .string(container.decode(String.self, forKey: key))
        case .enumeration: self = try .enumeration(container.decode(String.self, forKey: key))
        case .asset: self = try .asset(container.decode(AssetID.self, forKey: key))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case let .float(value): try container.encode(value, forKey: .float)
        case let .int(value): try container.encode(value, forKey: .int)
        case let .bool(value): try container.encode(value, forKey: .bool)
        case let .vec3(value): try container.encode(value, forKey: .vec3)
        case let .quat(value): try container.encode(value, forKey: .quat)
        case let .color(value): try container.encode(value, forKey: .color)
        case let .string(value): try container.encode(value, forKey: .string)
        case let .enumeration(value): try container.encode(value, forKey: .enumeration)
        case let .asset(value): try container.encode(value, forKey: .asset)
        }
    }
}

/// The name of a property. Well-known keys carry a type and animatability;
/// unknown keys are allowed (forward compatibility, scripting) and are untyped.
public struct PropertyKey: RawRepresentable, Hashable, Sendable, Codable, Comparable, CodingKeyRepresentable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public var description: String { rawValue }
    public static func < (lhs: PropertyKey, rhs: PropertyKey) -> Bool { lhs.rawValue < rhs.rawValue }

    public var codingKey: CodingKey { IdentifierCodingKey(stringValue: rawValue) }
    public init?(codingKey: some CodingKey) { rawValue = codingKey.stringValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    // Transform
    public static let position: PropertyKey = "position"
    public static let rotation: PropertyKey = "rotation"
    public static let scale: PropertyKey = "scale"
    // State
    public static let visible: PropertyKey = "visible"
    public static let locked: PropertyKey = "locked"
    // Material
    public static let color: PropertyKey = "color"
    public static let emissive: PropertyKey = "emissive"
    public static let emissiveIntensity: PropertyKey = "emissiveIntensity"
    public static let roughness: PropertyKey = "roughness"
    public static let metallic: PropertyKey = "metallic"
    public static let shading: PropertyKey = "shading"
    public static let castsShadow: PropertyKey = "castsShadow"
    // Light
    public static let lightColor: PropertyKey = "lightColor"
    public static let lightIntensity: PropertyKey = "lightIntensity"
    public static let lightRange: PropertyKey = "lightRange"
    public static let spotAngle: PropertyKey = "spotAngle"
    public static let lightShadows: PropertyKey = "lightShadows"
    // Camera
    public static let fieldOfView: PropertyKey = "fieldOfView"
    // Generators
    public static let seed: PropertyKey = "seed"

    /// Type and animatability of well-known keys.
    public var spec: PropertySpec? { PropertySpec.known[self] }
}

public struct PropertySpec: Sendable, Hashable {
    public let type: PropertyType
    public let animatable: Bool
    public let label: String

    public static let known: [PropertyKey: PropertySpec] = [
        .position: PropertySpec(type: .vec3, animatable: true, label: "Position"),
        .rotation: PropertySpec(type: .quat, animatable: true, label: "Rotation"),
        .scale: PropertySpec(type: .vec3, animatable: true, label: "Scale"),
        .visible: PropertySpec(type: .bool, animatable: true, label: "Visible"),
        .locked: PropertySpec(type: .bool, animatable: false, label: "Locked"),
        .color: PropertySpec(type: .color, animatable: true, label: "Color"),
        .emissive: PropertySpec(type: .color, animatable: true, label: "Glow color"),
        .emissiveIntensity: PropertySpec(type: .float, animatable: true, label: "Glow"),
        .roughness: PropertySpec(type: .float, animatable: true, label: "Roughness"),
        .metallic: PropertySpec(type: .float, animatable: true, label: "Metallic"),
        .shading: PropertySpec(type: .enumeration, animatable: false, label: "Shading"),
        .castsShadow: PropertySpec(type: .bool, animatable: false, label: "Casts shadow"),
        .lightColor: PropertySpec(type: .color, animatable: true, label: "Light color"),
        .lightIntensity: PropertySpec(type: .float, animatable: true, label: "Intensity"),
        .lightRange: PropertySpec(type: .float, animatable: true, label: "Range"),
        .spotAngle: PropertySpec(type: .float, animatable: true, label: "Spot angle"),
        .lightShadows: PropertySpec(type: .bool, animatable: false, label: "Shadows"),
        .fieldOfView: PropertySpec(type: .float, animatable: true, label: "Field of view"),
        .seed: PropertySpec(type: .int, animatable: false, label: "Seed")
    ]
}

/// Per-object shading override. `.inherit` follows the project Look.
public enum ShadingMode: String, Codable, Sendable, CaseIterable {
    case inherit, smooth, flat
}
