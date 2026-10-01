import Foundation

/// Hesham's own character (or anyone's): a few picks — head, hair, eyes, body, clothes, extras, colours — and the
/// builder makes a low-poly puppet on the Humanoid standard: it plays every humanoid clip, its face is ready for
/// lip sync and face performance, and it saves to the library like anything else.
public struct CharacterRecipe: Codable, Hashable, Sendable {
    public enum Head: String, Codable, Sendable, CaseIterable, Identifiable {
        case round, oval, square, bean
        public var id: String { rawValue }
    }

    public enum Hair: String, Codable, Sendable, CaseIterable, Identifiable {
        case none, short, spiky, curly, long, bun, cap, beanie
        public var id: String { rawValue }
    }

    public enum Eyes: String, Codable, Sendable, CaseIterable, Identifiable {
        case dots, round, sleepy
        public var id: String { rawValue }
    }

    public enum Body: String, Codable, Sendable, CaseIterable, Identifiable {
        case slim, regular, broad
        public var id: String { rawValue }

        var width: Double {
            switch self {
            case .slim: 0.34
            case .regular: 0.4
            case .broad: 0.48
            }
        }
    }

    public enum Top: String, Codable, Sendable, CaseIterable, Identifiable {
        case tshirt, hoodie, shirt, jacket, sweater
        public var id: String { rawValue }
    }

    public enum Bottom: String, Codable, Sendable, CaseIterable, Identifiable {
        case jeans, shorts, skirt
        public var id: String { rawValue }
    }

    public enum Extra: String, Codable, Sendable, CaseIterable, Identifiable {
        case glasses, beard, mustache, headphones
        public var id: String { rawValue }
    }

    public var name: String
    public var head: Head
    public var hair: Hair
    public var eyes: Eyes
    public var body: Body
    public var top: Top
    public var bottom: Bottom
    public var extras: [Extra]
    public var skin: ColorValue
    public var hairColor: ColorValue
    public var topColor: ColorValue
    public var bottomColor: ColorValue
    public var shoeColor: ColorValue
    /// 1 = about 1.7 m.
    public var height: Double

    public init(
        name: String = "Me", head: Head = .round, hair: Hair = .short, eyes: Eyes = .dots, body: Body = .regular, top: Top = .hoodie,
        bottom: Bottom = .jeans, extras: [Extra] = [], skin: ColorValue = .rgba(RGBA.hex("#D9A57E")),
        hairColor: ColorValue = .rgba(RGBA.hex("#231812")), topColor: ColorValue = .rgba(RGBA.hex("#E4572E")),
        bottomColor: ColorValue = .rgba(RGBA.hex("#2F3E5C")), shoeColor: ColorValue = .rgba(RGBA.hex("#F1F1F1")), height: Double = 1
    ) {
        self.name = name
        self.head = head
        self.hair = hair
        self.eyes = eyes
        self.body = body
        self.top = top
        self.bottom = bottom
        self.extras = extras
        self.skin = skin
        self.hairColor = hairColor
        self.topColor = topColor
        self.bottomColor = bottomColor
        self.shoeColor = shoeColor
        self.height = height
    }
}

extension CharacterRecipe {
    private enum CodingKeys: String, CodingKey {
        case name, head, hair, eyes, body, top, bottom, extras, skin, hairColor, topColor, bottomColor, shoeColor, height
    }

    /// Any subset of fields (an AI can say just {"hair": "curly"}); the rest are the defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = CharacterRecipe()
        try self.init(
            name: c.decodeIfPresent(String.self, forKey: .name) ?? base.name,
            head: c.decodeIfPresent(Head.self, forKey: .head) ?? base.head,
            hair: c.decodeIfPresent(Hair.self, forKey: .hair) ?? base.hair,
            eyes: c.decodeIfPresent(Eyes.self, forKey: .eyes) ?? base.eyes,
            body: c.decodeIfPresent(Body.self, forKey: .body) ?? base.body,
            top: c.decodeIfPresent(Top.self, forKey: .top) ?? base.top,
            bottom: c.decodeIfPresent(Bottom.self, forKey: .bottom) ?? base.bottom,
            extras: c.decodeIfPresent([Extra].self, forKey: .extras) ?? base.extras,
            skin: c.decodeIfPresent(ColorValue.self, forKey: .skin) ?? base.skin,
            hairColor: c.decodeIfPresent(ColorValue.self, forKey: .hairColor) ?? base.hairColor,
            topColor: c.decodeIfPresent(ColorValue.self, forKey: .topColor) ?? base.topColor,
            bottomColor: c.decodeIfPresent(ColorValue.self, forKey: .bottomColor) ?? base.bottomColor,
            shoeColor: c.decodeIfPresent(ColorValue.self, forKey: .shoeColor) ?? base.shoeColor,
            height: c.decodeIfPresent(Double.self, forKey: .height) ?? base.height
        )
    }
}

public extension PropertyKey {
    /// The recipe a built character came from (JSON), so it can be re-opened in the builder.
    static let characterRecipe: PropertyKey = "characterRecipe"
}

public enum CharacterBuilder {
    static let dark = ColorValue.rgba(RGBA.hex("#2A1616"))
    static let white = ColorValue.rgba(RGBA.hex("#F7F4EE"))
    static let tongue = ColorValue.rgba(RGBA.hex("#D8616C"))

    /// Builds the character as a fragment (root first). `ids` makes deterministic ids in tests.
    public static func build(_ recipe: CharacterRecipe, ids: inout IDFactory) -> SceneFragment {
        var objects: [SceneObject] = []
        var builder = Assembler(ids: ids)
        let root = builder.group(recipe.name, parent: nil, at: .zero)
        builder.objects[0][.rigStandard] = .enumeration(SkeletonStandard.humanoid.rawValue)
        builder.objects[0][.mouth] = .enumeration(Viseme.X.rawValue)
        builder.objects[0].transform.scale = Vec3(0.85 * recipe.height, 0.85 * recipe.height, 0.85 * recipe.height)
        if let json = try? LoweyJSON.encode(recipe), let text = String(bytes: json, encoding: .utf8) {
            builder.objects[0][.characterRecipe] = .string(text)
        }
        let skin = recipe.skin

        // Hips and legs.
        let hips = builder.joint("hips", parent: root, at: Vec3(0, 0.9, 0))
        legs(&builder, recipe: recipe, hips: hips)

        // Spine, chest, arms.
        let spine = builder.joint("spine", parent: hips, at: Vec3(0, 0.1, 0))
        let chest = builder.joint("chest", parent: spine, at: Vec3(0, 0.2, 0))
        torso(&builder, recipe: recipe, spine: spine, chest: chest)
        arms(&builder, recipe: recipe, chest: chest)

        // Neck and head.
        let neck = builder.joint("neck", parent: chest, at: Vec3(0, 0.27, 0))
        builder.part(.cylinder, "Neck", parent: neck, center: Vec3(0, 0.02, 0), size: Vec3(0.11, 0.12, 0.11), color: skin)
        let head = builder.joint("head", parent: neck, at: Vec3(0, 0.07, 0))
        let r = 0.23
        let headSize: Vec3 = switch recipe.head {
        case .round: Vec3(2 * r, 2 * r, 2 * r)
        case .oval: Vec3(1.8 * r, 2.2 * r, 1.9 * r)
        case .square: Vec3(1.9 * r, 2 * r, 1.9 * r)
        case .bean: Vec3(2.1 * r, 1.8 * r, 1.9 * r)
        }
        builder.part(recipe.head == .square ? .cube : .sphere, "Head", parent: head, center: Vec3(0, r, 0), size: headSize, color: skin)
        let front = headSize.z / 2 - 0.01
        let hairColor = recipe.hairColor
        // Ears.
        for side in [1.0, -1.0] {
            builder.part(.sphere, "Ear", parent: head, center: Vec3(side * headSize.x / 2, r * 0.95, 0), size: Vec3(0.05, 0.09, 0.07), color: skin)
        }
        face(&builder, recipe: recipe, head: head, radius: r, front: front)

        // Hair and extras.
        builder.hair(recipe.hair, parent: head, radius: r, size: headSize, color: hairColor)
        extras(&builder, recipe: recipe, head: head, radius: r, size: headSize, front: front)
        objects = builder.objects
        ids = builder.ids
        return SceneFragment(objects: objects, roots: [root])
    }

    static func legs(_ builder: inout Assembler, recipe: CharacterRecipe, hips: ObjectID) {
        let w = recipe.body.width
        let skin = recipe.skin
        let pantsColor = recipe.bottomColor
        builder.part(.cube, "Pelvis", parent: hips, center: Vec3(0, 0, 0), size: Vec3(w * 0.85, 0.22, 0.24), color: pantsColor)
        if recipe.bottom == .skirt {
            builder.part(.cone, "Skirt", parent: hips, center: Vec3(0, -0.12, 0), size: Vec3(w * 1.25, 0.36, 0.42), color: pantsColor)
        }
        for side in [1.0, -1.0] {
            let prefix = side > 0 ? "left" : "right"
            let upper = builder.joint("\(prefix)UpperLeg", parent: hips, at: Vec3(side * w * 0.26, -0.04, 0))
            let legColor = recipe.bottom == .jeans ? pantsColor : (recipe.bottom == .shorts ? pantsColor : skin)
            builder.part(.cylinder, "Thigh", parent: upper, center: Vec3(0, -0.21, 0), size: Vec3(0.15, 0.44, 0.15), color: legColor)
            let lower = builder.joint("\(prefix)LowerLeg", parent: upper, at: Vec3(0, -0.42, 0))
            builder.part(.cylinder, "Shin", parent: lower, center: Vec3(0, -0.2, 0), size: Vec3(0.13, 0.42, 0.13),
                         color: recipe.bottom == .jeans ? pantsColor : skin)
            let foot = builder.joint("\(prefix)Foot", parent: lower, at: Vec3(0, -0.4, 0))
            builder.part(.cube, "Shoe", parent: foot, center: Vec3(0, -0.035, 0.04), size: Vec3(0.13, 0.09, 0.25), color: recipe.shoeColor)
        }
    }

    static func torso(_ builder: inout Assembler, recipe: CharacterRecipe, spine: ObjectID, chest: ObjectID) {
        let w = recipe.body.width
        let torsoShape: PrimitiveShape = recipe.body == .broad ? .cube : .cylinder
        builder.part(torsoShape, "Torso", parent: spine, center: Vec3(0, 0.22, 0), size: Vec3(w, 0.52, 0.27), color: recipe.topColor)
        switch recipe.top {
        case .hoodie:
            builder.part(.torus, "Hood", parent: chest, center: Vec3(0, 0.25, -0.05), size: Vec3(w * 0.75, 0.12, 0.3), color: recipe.topColor)
            builder.part(.cube, "Pocket", parent: spine, center: Vec3(0, 0.08, 0.135), size: Vec3(w * 0.55, 0.1, 0.01), color: shade(recipe.topColor))
        case .shirt:
            builder.part(.cube, "Collar", parent: chest, center: Vec3(0, 0.25, 0.1), size: Vec3(w * 0.45, 0.05, 0.08), color: white)
            builder.part(.cube, "Buttons", parent: spine, center: Vec3(0, 0.22, 0.136), size: Vec3(0.02, 0.44, 0.01), color: white)
        case .jacket:
            builder.part(.cube, "Shirt", parent: spine, center: Vec3(0, 0.22, 0.13), size: Vec3(w * 0.28, 0.5, 0.02), color: white)
        case .tshirt, .sweater:
            break
        }
    }

    static func arms(_ builder: inout Assembler, recipe: CharacterRecipe, chest: ObjectID) {
        let w = recipe.body.width
        let skin = recipe.skin
        let sleeves = recipe.top == .tshirt ? skin : recipe.topColor
        for side in [1.0, -1.0] {
            let prefix = side > 0 ? "left" : "right"
            let shoulder = builder.joint("\(prefix)Shoulder", parent: chest, at: Vec3(side * (w / 2 - 0.02), 0.22, 0))
            let upper = builder.joint("\(prefix)UpperArm", parent: shoulder, at: Vec3(side * 0.05, 0, 0))
            builder.part(.sphere, "Shoulder", parent: upper, center: Vec3(0, -0.02, 0), size: Vec3(0.13, 0.13, 0.13), color: recipe.topColor)
            builder.part(.cylinder, "Upper arm", parent: upper, center: Vec3(0, -0.15, 0), size: Vec3(0.11, 0.3, 0.11), color: sleeves)
            let lower = builder.joint("\(prefix)LowerArm", parent: upper, at: Vec3(0, -0.3, 0))
            builder.part(.cylinder, "Forearm", parent: lower, center: Vec3(0, -0.14, 0), size: Vec3(0.1, 0.28, 0.1),
                         color: recipe.top == .tshirt ? skin : sleeves)
            let hand = builder.joint("\(prefix)Hand", parent: lower, at: Vec3(0, -0.28, 0))
            builder.part(.sphere, "Hand", parent: hand, center: Vec3(0, -0.05, 0), size: Vec3(0.11, 0.12, 0.09), color: skin)
        }
    }

    /// Eyes (with pupils that look around), brows, nose and the mouth: a group of swappable shapes, one per viseme
    /// (lip sync switches them).
    static func face(_ builder: inout Assembler, recipe: CharacterRecipe, head: ObjectID, radius r: Double, front: Double) {
        let hairColor = recipe.hairColor
        let skin = recipe.skin
        // Eyes (with pupils that look around), brows, nose.
        for side in [1.0, -1.0] {
            let tag = side > 0 ? "L" : "R"
            let eyeCenter = Vec3(side * 0.085, r * 1.12, front * 0.93)
            switch recipe.eyes {
            case .dots:
                let eye = builder.part(.sphere, "Eye", parent: head, center: eyeCenter, size: Vec3(0.055, 0.07, 0.03), color: dark)
                builder.objects[builder.index(eye)][.faceRole] = .string("eye.\(tag)")
                let shine = builder.part(.sphere, "Shine", parent: eye, center: Vec3(0.18, 0.75, 0.45), size: Vec3(0.35, 0.3, 0.3), color: white,
                                         localToParentScale: true)
                builder.objects[builder.index(shine)][.faceRole] = .string("pupil.\(tag)")
            case .round, .sleepy:
                let eye = builder.part(.sphere, "Eye", parent: head, center: eyeCenter,
                                       size: Vec3(0.085, recipe.eyes == .sleepy ? 0.055 : 0.09, 0.04), color: white)
                builder.objects[builder.index(eye)][.faceRole] = .string("eye.\(tag)")
                let pupil = builder.part(.sphere, "Pupil", parent: eye, center: Vec3(0, 0.25, 0.55), size: Vec3(0.5, 0.5, 0.5), color: dark,
                                         localToParentScale: true)
                builder.objects[builder.index(pupil)][.faceRole] = .string("pupil.\(tag)")
            }
            let brow = builder.part(.cube, "Brow", parent: head, center: eyeCenter + Vec3(0, 0.075, 0.005), size: Vec3(0.075, 0.018, 0.02),
                                    color: hairColor)
            builder.objects[builder.index(brow)][.faceRole] = .string("brow.\(tag)")
        }
        builder.part(.sphere, "Nose", parent: head, center: Vec3(0, r * 0.9, front), size: Vec3(0.045, 0.05, 0.05), color: shade(skin))
        // Mouth: a group of swappable shapes, one per viseme (lip sync switches them).
        let mouth = builder.group("Mouth", parent: head, at: Vec3(0, r * 0.52, front * 0.96))
        builder.objects[builder.index(mouth)][.faceRole] = .string("mouth")
        builder.mouthShapes(parent: mouth)
    }

    static func extras(_ builder: inout Assembler, recipe: CharacterRecipe, head: ObjectID, radius r: Double, size headSize: Vec3, front: Double) {
        let hairColor = recipe.hairColor
        for extra in recipe.extras {
            switch extra {
            case .glasses:
                for side in [1.0, -1.0] {
                    let lens = builder.part(.torus, "Lens", parent: head, center: Vec3(side * 0.085, r * 1.12, front + 0.02), size: Vec3(0.11, 0.02, 0.11),
                                            color: dark)
                    builder.objects[builder.index(lens)].transform.rotation = Quat(angle: .pi / 2, axis: .unitX)
                }
                builder.part(.cube, "Bridge", parent: head, center: Vec3(0, r * 1.14, front + 0.02), size: Vec3(0.06, 0.012, 0.012), color: dark)
            case .beard:
                builder.part(.sphere, "Beard", parent: head, center: Vec3(0, r * 0.42, front * 0.55), size: Vec3(headSize.x * 0.8, 0.2, 0.26), color: hairColor)
            case .mustache:
                builder.part(.cube, "Mustache", parent: head, center: Vec3(0, r * 0.7, front + 0.005), size: Vec3(0.12, 0.025, 0.03), color: hairColor)
            case .headphones:
                let band = builder.part(.torus, "Headphones", parent: head, center: Vec3(0, r * 1.2, 0), size: Vec3(headSize.x * 1.12, 0.05, headSize.x * 1.12),
                                        color: dark)
                builder.objects[builder.index(band)].transform.rotation = Quat(angle: .pi / 2, axis: .unitZ)
                for side in [1.0, -1.0] {
                    builder.part(.cylinder, "Ear cup", parent: head, center: Vec3(side * (headSize.x / 2 + 0.02), r, 0), size: Vec3(0.1, 0.06, 0.1),
                                 color: tongue, rotation: Quat(angle: .pi / 2, axis: .unitZ))
                }
            }
        }
    }

    /// A slightly darker variant of a colour (pockets, nose).
    static func shade(_ color: ColorValue) -> ColorValue {
        if case let .rgba(rgba) = color { return .rgba(RGBA(rgba.r * 0.82, rgba.g * 0.78, rgba.b * 0.76, rgba.a)) }
        return color
    }

    /// Collects objects, parents before children.
    struct Assembler {
        var ids: IDFactory
        var objects: [SceneObject] = []
        var positions: [ObjectID: Int] = [:]

        init(ids: IDFactory) {
            self.ids = ids
        }

        func index(_ id: ObjectID) -> Int {
            guard let position = positions[id] else { preconditionFailure("\(id) wasn't made by this assembler") }
            return position
        }

        @discardableResult
        mutating func add(_ object: SceneObject) -> ObjectID {
            var object = object
            if let parent = object.parent {
                objects[index(parent)].children.append(object.id)
            }
            object.children = []
            positions[object.id] = objects.count
            objects.append(object)
            return object.id
        }

        @discardableResult
        mutating func group(_ name: String, parent: ObjectID?, at position: Vec3) -> ObjectID {
            add(SceneObject(id: ids.next(), name: name, kind: .group, parent: parent, transform: Transform(position: position)))
        }

        @discardableResult
        mutating func joint(_ bone: String, parent: ObjectID, at position: Vec3) -> ObjectID {
            let id = group(Self.title(bone), parent: parent, at: position)
            objects[index(id)][.bone] = .string(bone)
            return id
        }

        static func title(_ bone: String) -> String {
            var result = ""
            for character in bone {
                if character.isUppercase { result += " " }
                result += String(character)
            }
            return result.prefix(1).uppercased() + result.dropFirst().lowercased()
        }

        /// A primitive whose *centre* is at `center` with `size` (primitives are unit-sized and base-centred).
        /// With `localToParentScale`, size and centre are fractions of the parent part's size.
        @discardableResult
        mutating func part(_ shape: PrimitiveShape, _ name: String, parent: ObjectID, center: Vec3, size: Vec3, color: ColorValue,
                           rotation: Quat = .identity, localToParentScale: Bool = false) -> ObjectID {
            var position = center - rotation.act(Vec3(0, size.y / 2, 0))
            if localToParentScale {
                // Parent is a unit primitive scaled to its size: its local space spans −0.5…0.5 (x, z) and 0…1 (y).
                position = Vec3(center.x * 0.5, center.y - size.y / 2, center.z * 0.5)
            }
            var object = SceneObject(id: ids.next(), name: name, kind: .primitive(shape), parent: parent,
                                     transform: Transform(position: position, rotation: rotation, scale: size))
            object[.color] = .color(color)
            return add(object)
        }

        /// The Toonsquid-style mouth set: one small shape per viseme; lip sync shows one at a time.
        /// One group per viseme; only the rest shape starts visible.
        mutating func mouthShape(_ viseme: Viseme, parent: ObjectID) -> ObjectID {
            let shapeGroup = group("Mouth \(viseme.rawValue)", parent: parent, at: .zero)
            objects[index(shapeGroup)][.faceRole] = .string("mouth.\(viseme.rawValue)")
            objects[index(shapeGroup)][.visible] = .bool(viseme == .X)
            return shapeGroup
        }

        mutating func mouthShapes(parent: ObjectID) {
            let dark = CharacterBuilder.dark
            let white = CharacterBuilder.white
            let tongue = CharacterBuilder.tongue
            var shape = mouthShape(.X, parent: parent)
            part(.cube, "Rest", parent: shape, center: .zero, size: Vec3(0.09, 0.012, 0.012), color: dark)
            shape = mouthShape(.A, parent: parent)
            part(.cube, "Closed", parent: shape, center: .zero, size: Vec3(0.08, 0.018, 0.014), color: dark)
            shape = mouthShape(.B, parent: parent)
            part(.sphere, "Open", parent: shape, center: .zero, size: Vec3(0.1, 0.035, 0.02), color: dark)
            part(.cube, "Teeth", parent: shape, center: Vec3(0, 0, 0.006), size: Vec3(0.075, 0.018, 0.01), color: white)
            shape = mouthShape(.C, parent: parent)
            part(.sphere, "Open", parent: shape, center: Vec3(0, -0.005, 0), size: Vec3(0.09, 0.055, 0.02), color: dark)
            part(.cube, "Teeth", parent: shape, center: Vec3(0, 0.017, 0.006), size: Vec3(0.06, 0.012, 0.01), color: white)
            shape = mouthShape(.D, parent: parent)
            part(.sphere, "Wide", parent: shape, center: Vec3(0, -0.012, 0), size: Vec3(0.1, 0.085, 0.02), color: dark)
            part(.sphere, "Tongue", parent: shape, center: Vec3(0, -0.04, 0.006), size: Vec3(0.055, 0.025, 0.012), color: tongue)
            part(.cube, "Teeth", parent: shape, center: Vec3(0, 0.024, 0.006), size: Vec3(0.065, 0.014, 0.01), color: white)
            shape = mouthShape(.E, parent: parent)
            part(.sphere, "Round", parent: shape, center: Vec3(0, -0.005, 0), size: Vec3(0.065, 0.06, 0.02), color: dark)
            shape = mouthShape(.F, parent: parent)
            part(.torus, "Pucker", parent: shape, center: .zero, size: Vec3(0.045, 0.02, 0.045), color: tongue, rotation: Quat(angle: .pi / 2, axis: .unitX))
            shape = mouthShape(.G, parent: parent)
            part(.cube, "Lip", parent: shape, center: Vec3(0, -0.006, 0), size: Vec3(0.08, 0.016, 0.014), color: dark)
            part(.cube, "Teeth", parent: shape, center: Vec3(0, 0.008, 0.007), size: Vec3(0.06, 0.014, 0.01), color: white)
            shape = mouthShape(.H, parent: parent)
            part(.sphere, "Open", parent: shape, center: Vec3(0, -0.006, 0), size: Vec3(0.085, 0.055, 0.02), color: dark)
            part(.sphere, "Tongue", parent: shape, center: Vec3(0, 0.008, 0.007), size: Vec3(0.045, 0.02, 0.012), color: tongue)
        }

        mutating func hair(_ style: CharacterRecipe.Hair, parent: ObjectID, radius r: Double, size: Vec3, color: ColorValue) {
            let top = Vec3(0, r * 1.35, -0.01)
            switch style {
            case .none:
                break
            case .short:
                part(.sphere, "Hair", parent: parent, center: top, size: Vec3(size.x * 1.06, size.y * 0.62, size.z * 1.04), color: color)
            case .spiky:
                part(.sphere, "Hair", parent: parent, center: top, size: Vec3(size.x * 1.04, size.y * 0.5, size.z * 1.02), color: color)
                for index in 0 ..< 7 {
                    let angle = Double(index) / 7 * 2 * .pi
                    let tilt = Quat(angle: 0.5, axis: Vec3(cos(angle), 0, -sin(angle)))
                    part(.cone, "Spike", parent: parent, center: top + Vec3(sin(angle) * r * 0.5, r * 0.3, cos(angle) * r * 0.5),
                         size: Vec3(0.1, 0.16, 0.1), color: color, rotation: tilt)
                }
            case .curly:
                for index in 0 ..< 9 {
                    let angle = Double(index) / 9 * 2 * .pi
                    part(.sphere, "Curl", parent: parent, center: top + Vec3(sin(angle) * r * 0.62, r * 0.05 + Double(index % 3) * 0.03, cos(angle) * r * 0.62),
                         size: Vec3(0.16, 0.16, 0.16), color: color)
                }
                part(.sphere, "Curl", parent: parent, center: top + Vec3(0, r * 0.25, 0), size: Vec3(0.26, 0.2, 0.26), color: color)
            case .long:
                part(.sphere, "Hair", parent: parent, center: top, size: Vec3(size.x * 1.08, size.y * 0.66, size.z * 1.06), color: color)
                part(.cube, "Hair back", parent: parent, center: Vec3(0, r * 0.55, -size.z * 0.28), size: Vec3(size.x * 1.02, r * 1.6, 0.16), color: color)
            case .bun:
                part(.sphere, "Hair", parent: parent, center: top, size: Vec3(size.x * 1.05, size.y * 0.6, size.z * 1.03), color: color)
                part(.sphere, "Bun", parent: parent, center: top + Vec3(0, r * 0.55, -r * 0.2), size: Vec3(0.17, 0.17, 0.17), color: color)
            case .cap:
                part(.sphere, "Cap", parent: parent, center: top + Vec3(0, 0.01, 0), size: Vec3(size.x * 1.07, size.y * 0.55, size.z * 1.05), color: color)
                part(.cube, "Visor", parent: parent, center: Vec3(0, r * 1.5, size.z * 0.55), size: Vec3(size.x * 0.7, 0.025, 0.2), color: color)
            case .beanie:
                part(.sphere, "Beanie", parent: parent, center: top + Vec3(0, 0.03, 0), size: Vec3(size.x * 1.08, size.y * 0.7, size.z * 1.06), color: color)
                part(.torus, "Rim", parent: parent, center: Vec3(0, r * 1.38, 0), size: Vec3(size.x * 1.1, 0.07, size.z * 1.08), color: color)
                part(.sphere, "Pompom", parent: parent, center: top + Vec3(0, r * 0.62, 0), size: Vec3(0.1, 0.1, 0.1), color: color)
            }
        }
    }
}
