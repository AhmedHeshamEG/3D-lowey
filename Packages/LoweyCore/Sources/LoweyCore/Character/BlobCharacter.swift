import Foundation

/// The house character style: Hesham's avatar, drawn by him and turned into 3D (assets/avatar). An onion-shaped head
/// with a painted-on face, a floating drop for a body, rubber-hose arms with mitten hands, no legs (it hovers), and a
/// hat that can carry a name. Anyone can be one: a recipe picks the hat, hair, accessories and a prop, and the
/// `Likeness` table knows the clues that make a famous person recognisable.
///
/// Everything is ordinary scene objects, so the face rig (blinks, brows, looks, lip sync), keys, Perform and
/// Scene Scripts all work on it unchanged. Units: metres, about 1.8 m to the top of a beret; faces +Z.
public struct BlobRecipe: Codable, Hashable, Sendable {
    public enum Hat: String, Codable, Sendable, CaseIterable, Identifiable {
        case none, beret, topHat, cap, beanie, crown, wizard
        public var id: String { rawValue }
    }

    public enum Hair: String, Codable, Sendable, CaseIterable, Identifiable {
        /// Bare (the house look).
        case none
        /// A little tuft on top.
        case tuft
        /// White and everywhere (Einstein).
        case wild
        /// A long curly wig down to the shoulders (Newton).
        case curlyWig
        /// Short, parted, neat (Turing).
        case parted
        /// Pulled up into a bun (Curie).
        case bun
        case spiky
        /// Chin-length on both sides (Lovelace).
        case bob
        public var id: String { rawValue }
    }

    public enum Accessory: String, Codable, Sendable, CaseIterable, Identifiable {
        case glasses, roundGlasses, monocle, mustache, bigMustache, beard, bowTie, tie, scarf, headphones
        public var id: String { rawValue }
    }

    /// Something held in the right hand: the fastest clue there is.
    public enum Prop: String, Codable, Sendable, CaseIterable, Identifiable {
        case none, apple, book, lightbulb, pencil, magnifier, flask, envelope, gear
        public var id: String { rawValue }
    }

    /// A symbol painted on the beret.
    public enum Mark: String, Codable, Sendable, CaseIterable, Identifiable {
        case none
        /// ♓ (Hesham's).
        case pisces
        public var id: String { rawValue }
    }

    public var name: String
    public var skin: ColorValue
    public var hat: Hat
    public var hatColor: ColorValue
    /// Text across the front of the hat ("" = none): the name clue.
    public var hatLabel: String
    public var mark: Mark
    public var hair: Hair
    public var hairColor: ColorValue
    public var accessories: [Accessory]
    public var accessoryColor: ColorValue
    public var prop: Prop
    public var blush: Bool
    /// The soft light it hovers on.
    public var hover: Bool
    /// 1 = about 1.8 m to the top of a beret.
    public var height: Double

    public init(
        name: String = "Blob", skin: ColorValue = .rgba(RGBA(hex: "#FFFFFF")!), hat: Hat = .none,
        hatColor: ColorValue = .rgba(RGBA(hex: "#5D69FF")!), hatLabel: String = "", mark: Mark = .none, hair: Hair = .none,
        hairColor: ColorValue = .rgba(RGBA(hex: "#2B2118")!), accessories: [Accessory] = [],
        accessoryColor: ColorValue = .rgba(RGBA(hex: "#1B1B22")!), prop: Prop = .none, blush: Bool = true, hover: Bool = true,
        height: Double = 1
    ) {
        self.name = name
        self.skin = skin
        self.hat = hat
        self.hatColor = hatColor
        self.hatLabel = hatLabel
        self.mark = mark
        self.hair = hair
        self.hairColor = hairColor
        self.accessories = accessories
        self.accessoryColor = accessoryColor
        self.prop = prop
        self.blush = blush
        self.hover = hover
        self.height = height
    }

    /// Hesham, as he drew himself.
    public static let hesham = BlobRecipe(name: "Hesham", hat: .beret, mark: .pisces)
}

extension BlobRecipe {
    private enum CodingKeys: String, CodingKey {
        case name, skin, hat, hatColor, hatLabel, mark, hair, hairColor, accessories, accessoryColor, prop, blush, hover, height
    }

    /// Any subset of fields (an AI can say just {"hat": "topHat"}); the rest are the defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = BlobRecipe()
        try self.init(
            name: c.decodeIfPresent(String.self, forKey: .name) ?? base.name,
            skin: c.decodeIfPresent(ColorValue.self, forKey: .skin) ?? base.skin,
            hat: c.decodeIfPresent(Hat.self, forKey: .hat) ?? base.hat,
            hatColor: c.decodeIfPresent(ColorValue.self, forKey: .hatColor) ?? base.hatColor,
            hatLabel: c.decodeIfPresent(String.self, forKey: .hatLabel) ?? base.hatLabel,
            mark: c.decodeIfPresent(Mark.self, forKey: .mark) ?? base.mark,
            hair: c.decodeIfPresent(Hair.self, forKey: .hair) ?? base.hair,
            hairColor: c.decodeIfPresent(ColorValue.self, forKey: .hairColor) ?? base.hairColor,
            accessories: c.decodeIfPresent([Accessory].self, forKey: .accessories) ?? base.accessories,
            accessoryColor: c.decodeIfPresent(ColorValue.self, forKey: .accessoryColor) ?? base.accessoryColor,
            prop: c.decodeIfPresent(Prop.self, forKey: .prop) ?? base.prop,
            blush: c.decodeIfPresent(Bool.self, forKey: .blush) ?? base.blush,
            hover: c.decodeIfPresent(Bool.self, forKey: .hover) ?? base.hover,
            height: c.decodeIfPresent(Double.self, forKey: .height) ?? base.height
        )
    }
}

/// Who's who: two or three clues each (hair, one accessory, a prop), the way a cartoonist would draw them.
public enum Likeness {
    private static func hex(_ value: String) -> ColorValue { .rgba(RGBA(hex: value)!) }

    public static let people: [String: BlobRecipe] = [
        "hesham": .hesham,
        "newton": BlobRecipe(name: "Newton", hair: .curlyWig, hairColor: hex("#EDE6D8"), accessories: [.scarf], accessoryColor: hex("#7A1F2B"),
                             prop: .apple),
        "einstein": BlobRecipe(name: "Einstein", hair: .wild, hairColor: hex("#F4F4F2"), accessories: [.bigMustache], accessoryColor: hex("#E6E6E2"),
                               prop: .none),
        "turing": BlobRecipe(name: "Turing", hair: .parted, hairColor: hex("#3A2A1E"), accessories: [.tie], accessoryColor: hex("#2E3F6E"),
                             prop: .envelope),
        "curie": BlobRecipe(name: "Curie", hair: .bun, hairColor: hex("#6B5A4E"), prop: .flask),
        "darwin": BlobRecipe(name: "Darwin", hair: .none, accessories: [.beard], accessoryColor: hex("#EDEDEA"), prop: .book),
        "tesla": BlobRecipe(name: "Tesla", hair: .parted, hairColor: hex("#15110E"), accessories: [.mustache], accessoryColor: hex("#15110E"),
                            prop: .lightbulb),
        "lovelace": BlobRecipe(name: "Lovelace", hair: .bob, hairColor: hex("#2A1C16"), prop: .gear),
        "edison": BlobRecipe(name: "Edison", hair: .parted, hairColor: hex("#9C9A94"), accessories: [.bowTie], prop: .lightbulb),
        "sherlock": BlobRecipe(name: "Sherlock", hat: .cap, hatColor: hex("#8A6B45"), accessories: [.scarf], accessoryColor: hex("#5A1E1E"),
                               prop: .magnifier),
        "wizard": BlobRecipe(name: "Wizard", hat: .wizard, hatColor: hex("#3C2F8F"), accessories: [.beard], accessoryColor: hex("#F2F2EE"))
    ]

    /// Aliases people actually type.
    private static let aliases: [String: String] = [
        "isaac newton": "newton", "albert einstein": "einstein", "alan turing": "turing", "marie curie": "curie",
        "charles darwin": "darwin", "nikola tesla": "tesla", "ada lovelace": "lovelace", "thomas edison": "edison",
        "sherlock holmes": "sherlock", "me": "hesham", "ahmed hesham": "hesham"
    ]

    /// The recipe for a person by name ("Isaac Newton", "newton", "sir isaac newton"), or nil if unknown.
    public static func recipe(for name: String) -> BlobRecipe? {
        var key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["sir ", "dr ", "dr. ", "lady ", "professor "] where key.hasPrefix(prefix) {
            key = String(key.dropFirst(prefix.count))
        }
        if let known = people[key] { return known }
        if let alias = aliases[key], let known = people[alias] { return known }
        // "isaac newton" → "newton": the last word is usually the surname.
        if let last = key.split(separator: " ").last, let known = people[String(last)] { return known }
        return nil
    }
}

public extension PropertyKey {
    /// The recipe a blob character came from (JSON), so it can be rebuilt.
    static let blobRecipe: PropertyKey = "blobRecipe"
    /// How far a face part moves when the rig drives it (a blob's parts are true size, so their scale can't say).
    static let faceRange: PropertyKey = "faceRange"
}

/// Builds `BlobRecipe`s into scene fragments.
public enum BlobCharacter {
    /// The fragment (root first) plus the behaviour that keeps it floating.
    public struct Build: Sendable {
        public var fragment: SceneFragment
        public var behaviors: [Behavior]
    }

    // MARK: Measurements (from Hesham's drawing, assets/avatar/trace.json; metres)

    /// Head silhouette (radius, height above the head's bottom), bottom to peak.
    static let headProfile: [(r: Double, y: Double)] = [
        (0.0, 0.0), (0.0818, 0.0004), (0.2373, 0.0253), (0.3532, 0.0605), (0.4292, 0.0956), (0.4863, 0.1307), (0.5299, 0.1659),
        (0.5647, 0.2010), (0.5915, 0.2362), (0.6120, 0.2713), (0.6270, 0.3064), (0.6371, 0.3416), (0.6423, 0.3767), (0.6435, 0.4119),
        (0.6409, 0.4470), (0.6340, 0.4821), (0.6231, 0.5173), (0.6077, 0.5524), (0.5889, 0.5876), (0.5665, 0.6227), (0.5408, 0.6578),
        (0.5116, 0.6930), (0.4802, 0.7281), (0.4458, 0.7633), (0.4078, 0.7984), (0.3669, 0.8335), (0.3219, 0.8687), (0.2714, 0.9038),
        (0.2138, 0.9389), (0.1503, 0.9741), (0.0212, 1.0092), (0.0137, 1.0110), (0.0066, 1.0120), (0.0, 1.0124)
    ]
    /// Front-to-back depth of the head relative to its width.
    static let headDepth = 0.92
    /// Where things sit: the head's bottom, the body (a drop) under it, the hover height.
    static let hover = 0.08
    static let headBottom = 0.5993 + hover
    static let bodyLength = 0.559
    static let bodyRadius = 0.1987
    static let bodyBottom = headBottom - 0.05 - bodyLength
    /// Face placement (x from the centre line, y above the head's bottom).
    static let eye = (x: 0.2238, y: 0.5901, rx: 0.0979, ry: 0.1063)
    static let brow = (x: 0.2361, y: 0.7615)
    static let cheek = (x: 0.333, y: 0.3816)
    static let mouthY = 0.3069
    /// The smirk with its curl (the rest mouth), as strokes: centre lines and half-widths, around the mouth's centre.
    static let smirkLine: [(x: Double, y: Double)] = [
        (-0.160, -0.008), (-0.120, -0.007), (-0.080, 0.000), (-0.040, -0.002), (0.000, -0.006), (0.050, -0.012), (0.100, -0.019),
        (0.150, -0.022), (0.200, -0.023), (0.235, -0.017), (0.245, -0.010)
    ]
    static let smirkCurl: [(x: Double, y: Double)] = [
        (-0.098, 0.002), (-0.100, 0.020), (-0.098, 0.036), (-0.104, 0.052), (-0.116, 0.063), (-0.128, 0.066), (-0.133, 0.060)
    ]
    /// Shift so the rest mouth sits where the drawing has it relative to the eyes.
    static let smirkShift = -0.03

    static let ink = ColorValue.rgba(RGBA(hex: "#0B0B10")!)
    static let white = ColorValue.rgba(RGBA(hex: "#FFFFFF")!)
    static let blushColor = ColorValue.rgba(RGBA(hex: "#F0303A")!)
    static let mouthDark = ColorValue.rgba(RGBA(hex: "#2A0A12")!)
    static let tongue = ColorValue.rgba(RGBA(hex: "#FF6B7A")!)
    static let glowColor = ColorValue.rgba(RGBA(hex: "#9EB6FF")!)
    static let markColor = ColorValue.rgba(RGBA(hex: "#E3F6FF")!)

    // MARK: Surface of the head

    /// The head's radius at a height above its bottom (linear between measured rings).
    static func headRadius(at y: Double) -> Double {
        let profile = headProfile
        guard let first = profile.first, let last = profile.last else { return 0 }
        if y <= first.y { return first.r }
        if y >= last.y { return 0 }
        for index in 1 ..< profile.count where profile[index].y >= y {
            let a = profile[index - 1]
            let b = profile[index]
            let t = (y - a.y) / max(b.y - a.y, 1e-9)
            return a.r + (b.r - a.r) * t
        }
        return 0
    }

    /// The front of the head at (x, y) in head space (z forward), or nil off the silhouette.
    static func headFront(x: Double, y: Double) -> Double? {
        let r = headRadius(at: y)
        guard abs(x) < r else { return nil }
        return (r * r - x * x).squareRoot() * headDepth
    }

    /// A point on the front of the head, lifted `lift` along the surface.
    static func onHead(_ x: Double, _ y: Double, lift: Double) -> Vec3 {
        let z = headFront(x: x, y: y) ?? 0
        return Vec3(x, y, z) + headNormal(x, y) * lift
    }

    /// Outward normal of the head's front at (x, y).
    static func headNormal(_ x: Double, _ y: Double) -> Vec3 {
        let h = 0.004
        let z = headFront(x: x, y: y) ?? 0
        let dzdx = ((headFront(x: x + h, y: y) ?? z) - (headFront(x: x - h, y: y) ?? z)) / (2 * h)
        let dzdy = ((headFront(x: x, y: y + h) ?? z) - (headFront(x: x, y: y - h) ?? z)) / (2 * h)
        return Vec3(-dzdx, -dzdy, 1).normalized
    }

    // MARK: Build

    public static func build(_ recipe: BlobRecipe, ids: inout IDFactory) -> Build {
        var a = CharacterBuilder.Assembler(ids: ids)
        let root = a.group(recipe.name, parent: nil, at: .zero)
        a.objects[0][.rigStandard] = .enumeration("blob")
        a.objects[0][.mouth] = .enumeration(Viseme.X.rawValue)
        a.objects[0].transform.scale = Vec3(recipe.height, recipe.height, recipe.height)
        if let json = try? LoweyJSON.encode(recipe), let text = String(bytes: json, encoding: .utf8) {
            a.objects[0][.blobRecipe] = .string(text)
        }
        let skin = recipe.skin

        // Head: the drawing's onion, turned; the face lives on its front.
        let head = a.group("Head", parent: root, at: Vec3(0, headBottom, 0))
        a.objects[a.index(head)][.faceRole] = .string("head")
        let skull = a.shape("Skull", parent: head, recipe: lathe(headProfile.map { Vec3($0.r, $0.y, 0) }, segments: 48), color: skin)
        a.objects[a.index(skull)].transform.scale = Vec3(1, 1, headDepth)
        face(&a, head: head, recipe: recipe)
        hat(&a, head: head, recipe: recipe)
        hair(&a, head: head, recipe: recipe)

        // Body: a drop, point up, floating under the head.
        let body = a.group("Body", parent: root, at: Vec3(0, bodyBottom, 0))
        a.shape("Drop", parent: body, recipe: lathe(dropProfile(), segments: 40), color: skin)

        // Arms (rubber hose) and mitten hands. The arm follows the hand.
        for side in [-1.0, 1.0] {
            let tag = side < 0 ? "L" : "R"
            let shoulderHeight = 0.7 * bodyLength
            let shoulderX = side * (dropRadius(at: 0.7) - 0.03)
            let shoulder = a.group("Shoulder \(tag)", parent: body, at: Vec3(shoulderX, shoulderHeight, 0))
            let handPosition = Vec3(shoulderX + side * 0.17, bodyBottom + shoulderHeight - 0.07, 0.05)
            let hand = a.group("Hand \(tag)", parent: root, at: handPosition)
            a.objects[a.index(hand)].transform.rotation = Quat(angle: side * 0.78, axis: .unitZ)
            a.objects[a.index(hand)][.faceRole] = .string("hand.\(tag)")
            let palm = a.shape("Palm", parent: hand, recipe: lathe(ellipseProfile(radius: 1, height: 1), segments: 20), color: skin)
            a.objects[a.index(palm)].transform = Transform(position: Vec3(0, -0.058, 0), scale: Vec3(0.032, 0.058, 0.05))
            let thumb = a.shape("Thumb", parent: hand, recipe: lathe(ellipseProfile(radius: 1, height: 1), segments: 14), color: skin)
            a.objects[a.index(thumb)].transform = Transform(position: Vec3(side * -0.004, -0.045, 0.045),
                                                            rotation: Quat(angle: 0.6, axis: .unitX), scale: Vec3(0.017, 0.028, 0.017))
            var arm = SceneObject(id: a.ids.next(), name: "Arm \(tag)", kind: .drawing(DrawingRecipe(style: .tube, strokes: [], segments: 8)),
                                  parent: root, transform: Transform())
            arm[.color] = .color(skin)
            arm[.shading] = .enumeration(ShadingMode.smooth.rawValue)
            arm[.hoseFrom] = .string(shoulder.raw)
            arm[.hoseTo] = .string(hand.raw)
            arm[.hoseWrist] = .vec3(Vec3(0, 0, 0))
            arm[.hoseRadius] = .float(0.017)
            a.add(arm)
            if side > 0, recipe.prop != .none { prop(&a, hand: hand, recipe.prop) }
        }

        accessories(&a, head: head, body: body, recipe: recipe)

        if recipe.hover {
            let glow = a.shape("Hover glow", parent: root, recipe: lathe([Vec3(0.3, 0, 0), Vec3(0.2, 0.004, 0), Vec3(0, 0.005, 0)], segments: 40),
                               color: glowColor)
            a.objects[a.index(glow)].transform.position = Vec3(0, 0.005, 0)
            a.objects[a.index(glow)][.emissiveIntensity] = .float(1.3)
            a.objects[a.index(glow)][.opacity] = .float(0.45)
            a.objects[a.index(glow)][.faceRole] = .string("hover")
        }

        var objects = a.objects
        // Arms start bent the way the rig will bend them (so a character at rest never needs rebuilding).
        var scene = Scene(id: "blob-build", name: "Build")
        for object in objects {
            scene.objects[object.id] = object
        }
        scene.roots = [root]
        for index in objects.indices where objects[index][.hoseFrom] != nil {
            if let stroke = RubberHose.stroke(for: objects[index].id, in: scene) {
                objects[index].kind = .drawing(DrawingRecipe(style: .tube, strokes: [stroke], segments: 8))
            }
        }
        ids = a.ids
        let floating = Behavior(id: ids.next(ObjectID.self).raw, target: root, kind: .bob(height: 0.035, period: 2.6, tilt: 1.5))
        return Build(fragment: SceneFragment(objects: objects, roots: [root]), behaviors: [floating])
    }

    // MARK: Face

    static func face(_ a: inout CharacterBuilder.Assembler, head: ObjectID, recipe: BlobRecipe) {
        for side in [-1.0, 1.0] {
            let tag = side < 0 ? "L" : "R"
            // Eye: a black oval, tilted a touch, with two shines that slide when it looks around.
            let centre = onHead(side * eye.x, eye.y, lift: 0.002)
            let eyeID = a.shape("Eye \(tag)", parent: head, recipe: slab(ellipse(rx: eye.rx, ry: eye.ry, rotation: side * -0.07), depth: 0.008),
                                color: ink)
            a.objects[a.index(eyeID)].transform = Transform(position: centre - headNormal(side * eye.x, eye.y) * 0.004,
                                                            rotation: .rotation(from: .unitZ, to: headNormal(side * eye.x, eye.y)))
            a.objects[a.index(eyeID)][.faceRole] = .string("eye.\(tag)")
            let look = a.group("Look \(tag)", parent: eyeID, at: Vec3(0, 0, 0.008))
            a.objects[a.index(look)][.faceRole] = .string("pupil.\(tag)")
            a.objects[a.index(look)][.faceRange] = .float(0.23)
            let shine = slabs([ellipse(rx: 0.31 * eye.rx, ry: 0.3 * eye.rx, center: Vec2(-0.3 * eye.rx, 0.34 * eye.ry)),
                               ellipse(rx: 0.13 * eye.rx, ry: 0.13 * eye.rx, center: Vec2(0.36 * eye.rx, -0.42 * eye.ry))], depth: 0.003)
            a.shape("Shine", parent: look, recipe: shine, color: white)

            // Brow: a thick soft arc, outer end lower (his hopeful look). Painted along the head's curve.
            let browPoints: [(Double, Double)] = [(-0.1, 0.004), (-0.045, 0.034), (0.03, 0.036), (0.105, -0.018)].map { (side * $0.0, $0.1) }
            let browCentre = onHead(side * brow.x, brow.y, lift: 0.003)
            let browStroke = surfaceStroke(browPoints.map { (side * brow.x + $0.0, brow.y + $0.1) }, halfWidths: [0.021, 0.029, 0.028, 0.022],
                                           origin: browCentre, lift: 0.003)
            let browID = a.shape("Brow \(tag)", parent: head, recipe: DrawingRecipe(style: .ribbon, strokes: [browStroke], normal: .unitZ),
                                 color: ink)
            a.objects[a.index(browID)].transform.position = browCentre
            a.objects[a.index(browID)][.faceRole] = .string("brow.\(tag)")
            a.objects[a.index(browID)][.faceRange] = .float(0.05)

            if recipe.blush {
                let cheekID = a.shape("Cheek \(tag)", parent: head, recipe: slab(ellipse(rx: 0.036, ry: 0.026), depth: 0.006), color: blushColor)
                let normal = headNormal(side * cheek.x, cheek.y)
                a.objects[a.index(cheekID)].transform = Transform(position: onHead(side * cheek.x, cheek.y, lift: -0.002),
                                                                  rotation: .rotation(from: .unitZ, to: normal))
            }
        }

        // Mouth: one shape shown at a time (lip sync, expressions). X, the rest, is his smirk.
        let mouthCentre = onHead(0, mouthY, lift: 0)
        let mouth = a.group("Mouth", parent: head, at: mouthCentre)
        a.objects[a.index(mouth)][.faceRole] = .string("mouth")
        for (name, layers) in mouthShapes() {
            let shape = a.group("Mouth \(name)", parent: mouth, at: .zero)
            a.objects[a.index(shape)][.faceRole] = .string("mouth.\(name)")
            a.objects[a.index(shape)][.visible] = .bool(name == Viseme.X.rawValue)
            for layer in layers {
                switch layer {
                case let .line(points, halfWidth):
                    let stroke = surfaceStroke(points.map { ($0.0, mouthY + $0.1) }, halfWidths: Array(repeating: halfWidth, count: points.count),
                                               origin: mouthCentre, lift: 0.003, taper: true)
                    a.shape("Line", parent: shape, recipe: DrawingRecipe(style: .ribbon, strokes: [stroke], normal: .unitZ), color: ink)
                case let .fill(outline, color, raise):
                    let id = a.shape("Fill", parent: shape, recipe: slab(outline, depth: 0.004), color: color)
                    a.objects[a.index(id)].transform = Transform(position: Vec3(0, 0, raise - 0.002),
                                                                 rotation: .rotation(from: .unitZ, to: headNormal(0, mouthY)))
                }
            }
        }
    }

    enum MouthLayer {
        /// A painted line (centre line around the mouth's centre, half-width).
        case line([(Double, Double)], Double)
        /// A filled shape (outline in the mouth's plane), its colour and how far it sits above the skin.
        case fill([Vec2], ColorValue, Double)
    }

    /// The Rhubarb lip-sync set (A–H, X) plus expressions (smile, grin, frown), drawn in his style.
    static func mouthShapes() -> [(String, [MouthLayer])] {
        let w = 0.085
        func lens(_ top: Double, _ bottom: Double) -> [Vec2] {
            let n = 30
            let upper = (0 ... n).map { Vec2(-w + 2 * w * Double($0) / Double(n), top * sin(.pi * Double($0) / Double(n))) }
            let lower = (1 ..< n).map { Vec2(w - 2 * w * Double($0) / Double(n), -bottom * sin(.pi * Double($0) / Double(n))) }
            return upper + lower
        }
        func band(_ left: Double, _ right: Double, _ top: Double, _ bottom: Double) -> [Vec2] {
            [Vec2(left, top), Vec2(right, top), Vec2(right * 0.86, bottom), Vec2(left * 0.86, bottom)]
        }
        let smirk = smirkLine.map { ($0.x + smirkShift, $0.y) }
        let curl = smirkCurl.map { ($0.x + smirkShift, $0.y) }
        let grinOutline = [Vec2(-w * 1.15, 0.018), Vec2(w * 1.15, 0.018)]
            + (1 ..< 30).map { Vec2(w * 1.15 * cos(.pi * Double($0) / 30), 0.018 - 0.085 * sin(.pi * Double($0) / 30)) }
        return [
            ("X", [.line(smirk, 0.0085), .line(curl, 0.0065)]),
            ("A", [.line([(-w * 0.85, 0.002), (0, -0.004), (w * 0.85, 0.002)], 0.0095)]),
            ("B", [.fill(lens(0.012, 0.026), mouthDark, 0.001), .fill(band(-w * 0.72, w * 0.72, 0.004, -0.012), white, 0.003)]),
            ("C", [.fill(ellipse(rx: w * 0.9, ry: 0.042, center: Vec2(0, -0.012)), mouthDark, 0.001),
                   .fill(band(-w * 0.62, w * 0.62, 0.02, 0.006), white, 0.003),
                   .fill(ellipse(rx: w * 0.45, ry: 0.014, center: Vec2(0, -0.04)), tongue, 0.003)]),
            ("D", [.fill(ellipse(rx: w, ry: 0.064, center: Vec2(0, -0.028), squareness: 2.4), mouthDark, 0.001),
                   .fill(band(-w * 0.7, w * 0.7, 0.028, 0.012), white, 0.003),
                   .fill(ellipse(rx: w * 0.55, ry: 0.02, center: Vec2(0, -0.068)), tongue, 0.003)]),
            ("E", [.fill(ellipse(rx: w * 0.62, ry: 0.05, center: Vec2(0, -0.016)), mouthDark, 0.001),
                   .fill(ellipse(rx: w * 0.34, ry: 0.012, center: Vec2(0, -0.046)), tongue, 0.003)]),
            ("F", [.fill(ellipse(rx: w * 0.34, ry: 0.03, center: Vec2(0, -0.006)), mouthDark, 0.001)]),
            ("G", [.fill(lens(0.01, 0.022), mouthDark, 0.001), .fill(band(-w * 0.55, w * 0.55, 0.012, -0.016), white, 0.003)]),
            ("H", [.fill(ellipse(rx: w * 0.85, ry: 0.045, center: Vec2(0, -0.014)), mouthDark, 0.001),
                   .fill(ellipse(rx: w * 0.42, ry: 0.016, center: Vec2(0, 0.004)), tongue, 0.003)]),
            ("smile", [.line([(-w * 1.2, 0.02), (-w * 0.6, -0.012), (0, -0.02), (w * 0.6, -0.012), (w * 1.2, 0.02)], 0.009)]),
            ("grin", [.fill(grinOutline, mouthDark, 0.001), .fill(ellipse(rx: w * 0.55, ry: 0.02, center: Vec2(0, -0.045)), tongue, 0.003),
                      .fill(band(-w * 0.95, w * 0.95, 0.014, -0.004), white, 0.003)]),
            ("frown", [.line([(-w * 0.9, -0.018), (-w * 0.4, 0.004), (w * 0.4, 0.004), (w * 0.9, -0.018)], 0.0085)])
        ]
    }

    // MARK: Hat

    static func hat(_ a: inout CharacterBuilder.Assembler, head: ObjectID, recipe: BlobRecipe) {
        let top = headProfile.last?.y ?? 1
        let color = recipe.hatColor
        switch recipe.hat {
        case .none:
            return
        case .beret:
            // A soft pancake, wider than deep, tipped forward and to one side, with its little stalk.
            let hat = a.group("Beret", parent: head, at: Vec3(0.075, top - 0.035, 0))
            a.objects[a.index(hat)].transform.rotation = (Quat(angle: 0.17, axis: .unitX) * Quat(angle: -0.05, axis: .unitZ)).normalized
            let profile = [Vec3(0, 0, 0), Vec3(0.3, 0.012, 0), Vec3(0.39, 0.045, 0), Vec3(0.41, 0.08, 0), Vec3(0.37, 0.115, 0),
                           Vec3(0.24, 0.145, 0), Vec3(0.1, 0.158, 0), Vec3(0, 0.16, 0)]
            let pancake = a.shape("Crown", parent: hat, recipe: lathe(profile, segments: 48), color: color)
            a.objects[a.index(pancake)].transform.scale = Vec3(1, 1, 0.74)
            let stalk = a.shape("Stalk", parent: hat, recipe: lathe([Vec3(0.016, 0, 0), Vec3(0.012, 0.03, 0), Vec3(0.006, 0.05, 0), Vec3(0, 0.056, 0)],
                                                                    segments: 12), color: color)
            a.objects[a.index(stalk)].transform = Transform(position: Vec3(-0.24, 0.135, 0), rotation: Quat(angle: 0.45, axis: .unitZ))
            hatFront(&a, hat: hat, recipe: recipe, frontZ: 0.41 * 0.74, height: 0.08)
        case .topHat:
            let hat = a.group("Top hat", parent: head, at: Vec3(0, top - 0.06, 0))
            a.shape("Brim", parent: hat, recipe: lathe([Vec3(0, 0, 0), Vec3(0.36, 0, 0), Vec3(0.36, 0.02, 0), Vec3(0, 0.02, 0)], segments: 40), color: color)
            a.shape("Crown", parent: hat, recipe: lathe([Vec3(0, 0.02, 0), Vec3(0.2, 0.02, 0), Vec3(0.21, 0.38, 0), Vec3(0, 0.38, 0)], segments: 40),
                    color: color)
            hatFront(&a, hat: hat, recipe: recipe, frontZ: 0.205, height: 0.12)
        case .cap:
            let hat = a.group("Cap", parent: head, at: Vec3(0, top - 0.2, 0))
            a.shape("Crown", parent: hat, recipe: lathe(ellipseProfile(radius: 0.36, height: 0.26).filter { $0.y >= 0 }, segments: 40), color: color)
            let brim = a.shape("Visor", parent: hat, recipe: slab(ellipse(rx: 0.2, ry: 0.13), depth: 0.02), color: color)
            a.objects[a.index(brim)].transform = Transform(position: Vec3(0, 0.02, 0.3), rotation: Quat(angle: -.pi / 2 + 0.25, axis: .unitX))
            hatFront(&a, hat: hat, recipe: recipe, frontZ: 0.33, height: 0.12)
        case .beanie:
            let hat = a.group("Beanie", parent: head, at: Vec3(0, top - 0.28, 0))
            a.shape("Crown", parent: hat, recipe: lathe(ellipseProfile(radius: 0.4, height: 0.34).filter { $0.y >= 0 }, segments: 40), color: color)
            let pompom = a.shape("Pompom", parent: hat, recipe: lathe(ellipseProfile(radius: 0.07, height: 0.07), segments: 16), color: color)
            a.objects[a.index(pompom)].transform.position = Vec3(0, 0.36, 0)
            hatFront(&a, hat: hat, recipe: recipe, frontZ: 0.37, height: 0.12)
        case .crown:
            let hat = a.group("Crown", parent: head, at: Vec3(0, top - 0.08, 0))
            a.shape("Band", parent: hat, recipe: lathe([Vec3(0.2, 0, 0), Vec3(0.22, 0.12, 0), Vec3(0.2, 0.12, 0), Vec3(0.18, 0, 0)], segments: 32),
                    color: color)
            for index in 0 ..< 5 {
                let angle = Double(index) / 5 * 2 * .pi
                let spike = a.shape("Point", parent: hat, recipe: lathe([Vec3(0.035, 0, 0), Vec3(0, 0.09, 0)], segments: 8), color: color)
                a.objects[a.index(spike)].transform.position = Vec3(sin(angle) * 0.21, 0.12, cos(angle) * 0.21)
            }
        case .wizard:
            let hat = a.group("Wizard hat", parent: head, at: Vec3(0, top - 0.1, 0))
            a.shape("Brim", parent: hat, recipe: lathe([Vec3(0, 0, 0), Vec3(0.42, 0, 0), Vec3(0.42, 0.015, 0), Vec3(0, 0.015, 0)], segments: 40),
                    color: color)
            let cone = a.shape("Cone", parent: hat, recipe: lathe([Vec3(0.26, 0.015, 0), Vec3(0.14, 0.3, 0), Vec3(0.04, 0.55, 0), Vec3(0, 0.62, 0)],
                                                                  segments: 32), color: color)
            a.objects[a.index(cone)].transform.rotation = Quat(angle: -0.18, axis: .unitZ)
            hatFront(&a, hat: hat, recipe: recipe, frontZ: 0.22, height: 0.1)
        }
    }

    /// The mark or the name across the hat's front.
    static func hatFront(_ a: inout CharacterBuilder.Assembler, hat: ObjectID, recipe: BlobRecipe, frontZ: Double, height: Double) {
        if !recipe.hatLabel.isEmpty {
            var label = SceneObject(id: a.ids.next(), name: "Label", kind: .text(TextRecipe(text: recipe.hatLabel, style: .rounded, size: 0.07,
                                                                                            depth: 0.004)),
                                    parent: hat, transform: Transform(position: Vec3(0, height, frontZ + 0.004)))
            label[.color] = .color(markColor)
            a.add(label)
        } else if recipe.mark == .pisces {
            // ♓ as he drew it: )—(
            let y = height
            let strokes = [
                [(-0.058, y + 0.024), (-0.046, y + 0.012), (-0.043, y), (-0.046, y - 0.012), (-0.058, y - 0.024)],
                [(0.058, y + 0.024), (0.046, y + 0.012), (0.043, y), (0.046, y - 0.012), (0.058, y - 0.024)],
                [(-0.043, y), (0.043, y)]
            ].map { points in
                DrawingRecipe.Stroke(points: points.map { Vec3($0.0, $0.1, frontZ + 0.006) }, widths: Array(repeating: 0.0045, count: points.count))
            }
            a.shape("Mark", parent: hat, recipe: DrawingRecipe(style: .ribbon, strokes: strokes, normal: .unitZ), color: markColor)
        }
    }

    // MARK: Hair

    static func hair(_ a: inout CharacterBuilder.Assembler, head: ObjectID, recipe: BlobRecipe) {
        let color = recipe.hairColor
        func blob(_ name: String, _ at: Vec3, _ size: Vec3) {
            let id = a.shape(name, parent: head, recipe: lathe(ellipseProfile(radius: 1, height: 1), segments: 16), color: color)
            a.objects[a.index(id)].transform = Transform(position: at, scale: size)
        }
        /// A cap of hair over the top of the head, above the brows (it never covers the face).
        func shell(from height: Double, thickness: Double) {
            let rings = headProfile.filter { $0.y >= height }.map { Vec3($0.r + thickness, $0.y, 0) }
            guard let first = rings.first else { return }
            let id = a.shape("Hair", parent: head, recipe: lathe([Vec3(0, first.y, 0)] + rings, segments: 40), color: color)
            a.objects[a.index(id)].transform.scale = Vec3(1, 1, headDepth)
        }
        switch recipe.hair {
        case .none:
            break
        case .tuft:
            for (index, dx) in [-0.04, 0.0, 0.045].enumerated() {
                blob("Tuft", Vec3(dx, 1.0 + (index == 1 ? 0.04 : 0.02), 0.05), Vec3(0.04, 0.07, 0.04))
            }
        case .wild:
            // Einstein: white clouds around the sides and back, none on the face.
            let spots: [(Double, Double, Double, Double)] = [
                (-0.55, 0.62, -0.1, 0.16), (0.55, 0.62, -0.1, 0.16), (-0.48, 0.82, -0.18, 0.15), (0.48, 0.82, -0.18, 0.15),
                (-0.3, 0.96, -0.2, 0.14), (0.3, 0.96, -0.2, 0.14), (0, 1.0, -0.32, 0.16), (-0.62, 0.45, -0.05, 0.12), (0.62, 0.45, -0.05, 0.12),
                (0, 0.8, -0.5, 0.18), (-0.35, 0.7, -0.45, 0.15), (0.35, 0.7, -0.45, 0.15)
            ]
            for spot in spots {
                blob("Hair", Vec3(spot.0, spot.1, spot.2), Vec3(spot.3, spot.3 * 0.85, spot.3))
            }
        case .curlyWig:
            // Newton: a wig on top and long curls falling past the cheeks.
            shell(from: 0.8, thickness: 0.03)
            for side in [-1.0, 1.0] {
                for index in 0 ..< 6 {
                    let t = Double(index) / 5
                    blob("Curl", Vec3(side * (0.6 - t * 0.06), 0.72 - t * 0.62, -0.05 - t * 0.04), Vec3(0.1, 0.085, 0.1))
                }
            }
        case .parted:
            shell(from: 0.82, thickness: 0.025)
        case .bun:
            shell(from: 0.84, thickness: 0.02)
            blob("Bun", Vec3(0, 1.02, -0.18), Vec3(0.13, 0.11, 0.13))
        case .spiky:
            for index in 0 ..< 7 {
                let angle = (Double(index) / 6 - 0.5) * 1.6
                let spike = a.shape("Spike", parent: head, recipe: lathe([Vec3(0.06, 0, 0), Vec3(0, 0.16, 0)], segments: 8), color: color)
                a.objects[a.index(spike)].transform = Transform(position: Vec3(sin(angle) * 0.22, 0.93, cos(angle) * -0.05),
                                                                rotation: Quat(angle: -angle * 0.5, axis: .unitZ))
            }
        case .bob:
            shell(from: 0.8, thickness: 0.03)
            for side in [-1.0, 1.0] {
                blob("Side", Vec3(side * 0.6, 0.5, -0.1), Vec3(0.12, 0.3, 0.3))
            }
        }
    }

    // MARK: Accessories and props

    static func accessories(_ a: inout CharacterBuilder.Assembler, head: ObjectID, body: ObjectID, recipe: BlobRecipe) {
        let color = recipe.accessoryColor
        for accessory in recipe.accessories {
            switch accessory {
            case .glasses, .roundGlasses, .monocle:
                let sides: [Double] = accessory == .monocle ? [1] : [-1, 1]
                for side in sides {
                    let rim = a.shape("Lens rim", parent: head,
                                      recipe: DrawingRecipe(style: .tube, strokes: [DrawingRecipe.Stroke(
                                          points: ellipse(rx: eye.rx * 1.35, ry: eye.ry * (accessory == .glasses ? 1.05 : 1.3), n: 32)
                                              .map { Vec3($0.x, $0.y, 0) }
                                              + [Vec3(eye.rx * 1.35, 0, 0)],
                                          widths: [0.008]
                                      )], segments: 6), color: color)
                    a.objects[a.index(rim)].transform = Transform(position: onHead(side * eye.x, eye.y, lift: 0.03),
                                                                  rotation: .rotation(from: .unitZ, to: headNormal(side * eye.x, eye.y)))
                }
                if accessory != .monocle {
                    let bridge = surfaceStroke([(-eye.x + eye.rx * 1.3, eye.y + 0.02), (0, eye.y + 0.035), (eye.x - eye.rx * 1.3, eye.y + 0.02)],
                                               halfWidths: [0.006, 0.006, 0.006], origin: onHead(0, eye.y, lift: 0.03), lift: 0.03)
                    let id = a.shape("Bridge", parent: head, recipe: DrawingRecipe(style: .tube, strokes: [bridge], segments: 6), color: color)
                    a.objects[a.index(id)].transform.position = onHead(0, eye.y, lift: 0.03)
                }
            case .mustache, .bigMustache:
                let big = accessory == .bigMustache
                for side in [-1.0, 1.0] {
                    let x = side * (big ? 0.075 : 0.055)
                    let y = mouthY + (big ? 0.075 : 0.06)
                    let id = a.shape("Mustache", parent: head, recipe: slab(ellipse(rx: big ? 0.09 : 0.06, ry: big ? 0.042 : 0.026,
                                                                                    rotation: side * -0.25), depth: big ? 0.03 : 0.012), color: color)
                    a.objects[a.index(id)].transform = Transform(position: onHead(x, y, lift: -0.004), rotation: .rotation(from: .unitZ, to: headNormal(x, y)))
                }
            case .beard:
                let id = a.shape("Beard", parent: head, recipe: lathe(dropProfile(length: 0.42, radius: 0.24).map { Vec3($0.x, -$0.y, 0) }, segments: 32),
                                 color: color)
                a.objects[a.index(id)].transform = Transform(position: Vec3(0, 0.2, 0.3), scale: Vec3(1, 1, 0.6))
            case .bowTie:
                for side in [-1.0, 1.0] {
                    let wing = a.shape("Bow tie", parent: body, recipe: slab([Vec2(0, 0), Vec2(side * 0.07, 0.035), Vec2(side * 0.07, -0.035)], depth: 0.02),
                                       color: color)
                    a.objects[a.index(wing)].transform.position = Vec3(0, bodyLength * 0.86, dropRadius(at: 0.86) * 0.9)
                }
            case .tie:
                let id = a.shape("Tie", parent: body, recipe: slab([Vec2(0, 0), Vec2(0.03, -0.03), Vec2(0.022, -0.2), Vec2(0, -0.24), Vec2(-0.022, -0.2),
                                                                    Vec2(-0.03, -0.03)], depth: 0.015), color: color)
                a.objects[a.index(id)].transform.position = Vec3(0, bodyLength * 0.88, dropRadius(at: 0.7) * 0.92)
            case .scarf:
                let id = a.shape("Scarf", parent: body, recipe: lathe([Vec3(0.13, 0, 0), Vec3(0.17, 0.03, 0), Vec3(0.16, 0.07, 0), Vec3(0.11, 0.09, 0)],
                                                                      segments: 32), color: color)
                a.objects[a.index(id)].transform.position = Vec3(0, bodyLength * 0.8, 0)
            case .headphones:
                a.shape("Headphones", parent: head, recipe: DrawingRecipe(style: .tube, strokes: [DrawingRecipe.Stroke(
                    points: (0 ... 20).map { index -> Vec3 in
                        let t = Double(index) / 20 * .pi
                        return Vec3(-cos(t) * 0.66, 0.55 + sin(t) * 0.5, 0)
                    }, widths: [0.025]
                )], segments: 8), color: color)
                for side in [-1.0, 1.0] {
                    let cup = a.shape("Ear cup", parent: head, recipe: lathe(ellipseProfile(radius: 1, height: 1), segments: 16), color: color)
                    a.objects[a.index(cup)].transform = Transform(position: Vec3(side * 0.64, 0.5, 0), scale: Vec3(0.05, 0.1, 0.1))
                }
            }
        }
    }

    static func prop(_ a: inout CharacterBuilder.Assembler, hand: ObjectID, _ prop: BlobRecipe.Prop) {
        let holder = a.group("Holding", parent: hand, at: Vec3(0, -0.1, 0.06))
        a.objects[a.index(holder)].transform.rotation = Quat(angle: -0.78, axis: .unitZ)
        @discardableResult
        func ball(_ name: String, _ radius: Vec3, _ at: Vec3, _ color: String) -> ObjectID {
            let id = a.shape(name, parent: holder, recipe: lathe(ellipseProfile(radius: 1, height: 1), segments: 16), color: .rgba(RGBA(hex: color)!))
            a.objects[a.index(id)].transform = Transform(position: at, scale: radius)
            return id
        }
        func box(_ name: String, _ size: Vec3, _ at: Vec3, _ color: String) {
            a.part(.cube, name, parent: holder, center: at, size: size, color: .rgba(RGBA(hex: color)!))
        }
        switch prop {
        case .none:
            return
        case .apple:
            ball("Apple", Vec3(0.07, 0.065, 0.07), .zero, "#D7263D")
            box("Stem", Vec3(0.01, 0.04, 0.01), Vec3(0, 0.07, 0), "#5B3A1E")
            ball("Leaf", Vec3(0.025, 0.008, 0.014), Vec3(0.022, 0.08, 0), "#4CAF50")
        case .book:
            box("Book", Vec3(0.16, 0.2, 0.04), .zero, "#8E3B46")
            box("Pages", Vec3(0.15, 0.19, 0.03), Vec3(0.006, 0, 0.004), "#F4EEDC")
        case .lightbulb:
            let bulb = ball("Bulb", Vec3(0.06, 0.07, 0.06), Vec3(0, 0.05, 0), "#FFE066")
            a.objects[a.index(bulb)][.emissiveIntensity] = .float(2)
            box("Base", Vec3(0.045, 0.05, 0.045), .zero, "#9A9A9A")
        case .pencil:
            box("Pencil", Vec3(0.018, 0.2, 0.018), .zero, "#F2B632")
        case .magnifier:
            a.shape("Magnifier", parent: holder, recipe: DrawingRecipe(style: .tube, strokes: [DrawingRecipe.Stroke(
                points: ellipse(rx: 0.06, ry: 0.06, n: 28).map { Vec3($0.x, $0.y + 0.1, 0) } + [Vec3(0.06, 0.1, 0)], widths: [0.008]
            )], segments: 6), color: .rgba(RGBA(hex: "#3B3B3B")!))
            box("Handle", Vec3(0.02, 0.1, 0.02), .zero, "#5B3A1E")
        case .flask:
            let id = a.shape("Flask", parent: holder, recipe: lathe([Vec3(0, 0, 0), Vec3(0.07, 0, 0), Vec3(0.02, 0.1, 0), Vec3(0.02, 0.14, 0),
                                                                     Vec3(0, 0.14, 0)], segments: 20), color: .rgba(RGBA(hex: "#7EE0B5")!))
            a.objects[a.index(id)][.emissiveIntensity] = .float(0.8)
        case .envelope:
            box("Envelope", Vec3(0.18, 0.12, 0.01), .zero, "#F1E7D0")
            let flap = a.shape("Flap", parent: holder, recipe: slab([Vec2(-0.09, 0.06), Vec2(0.09, 0.06), Vec2(0, 0.0)], depth: 0.003),
                               color: .rgba(RGBA(hex: "#D9CBAA")!))
            a.objects[a.index(flap)].transform.position = Vec3(0, 0, 0.006)
        case .gear:
            let teeth = (0 ..< 24).map { index -> Vec2 in
                let angle = Double(index) / 24 * 2 * .pi
                let r = index.isMultiple(of: 2) ? 0.075 : 0.058
                return Vec2(cos(angle) * r, sin(angle) * r)
            }
            a.shape("Gear", parent: holder, recipe: slab(teeth, depth: 0.02), color: .rgba(RGBA(hex: "#B08D57")!))
        }
    }

    // MARK: Geometry helpers

    /// Radius of the body drop at a fraction of its height.
    static func dropRadius(at fraction: Double) -> Double {
        let profile = dropProfile()
        let y = fraction * bodyLength
        for index in 1 ..< profile.count where profile[index].y >= y {
            let a = profile[index - 1]
            let b = profile[index]
            let t = (y - a.y) / max(b.y - a.y, 1e-9)
            return a.x + (b.x - a.x) * t
        }
        return 0
    }

    /// A drop: round below its widest ring, tapering to a soft point above.
    static func dropProfile(length: Double = bodyLength, radius: Double = bodyRadius) -> [Vec3] {
        let n = 28
        let widest = 0.36
        return (0 ... n).map { index in
            let t = (1 - cos(.pi * Double(index) / Double(n))) / 2
            let r: Double
            if t <= widest {
                let u = (widest - t) / widest
                r = radius * pow(max(0, 1 - pow(u, 2.2)), 1 / 2.2)
            } else {
                let u = (t - widest) / (1 - widest)
                r = radius * pow(max(0, 1 - pow(u, 1.25)), 0.9)
            }
            return Vec3(r, t * length, 0)
        }
    }

    /// Half an ellipse, bottom to top (a sphere or ellipsoid when turned, centred on the origin).
    static func ellipseProfile(radius: Double, height: Double, n: Int = 14) -> [Vec3] {
        (0 ... n).map { index in
            let angle = -.pi / 2 + .pi * Double(index) / Double(n)
            return Vec3(cos(angle) * radius, sin(angle) * height, 0)
        }
    }

    static func lathe(_ profile: [Vec3], segments: Int) -> DrawingRecipe {
        DrawingRecipe(style: .lathe, strokes: [DrawingRecipe.Stroke(points: profile, widths: [0])], segments: segments)
    }

    /// A flat shape extruded towards +Z (the face's parts; thin enough to hug the head).
    static func slab(_ outline: [Vec2], depth: Double) -> DrawingRecipe {
        slabs([outline], depth: depth)
    }

    /// Several flat shapes in one object.
    static func slabs(_ outlines: [[Vec2]], depth: Double) -> DrawingRecipe {
        DrawingRecipe(style: .extrude, strokes: outlines.map { outline in
            DrawingRecipe.Stroke(points: outline.map { Vec3($0.x, $0.y, 0) }, widths: [0])
        }, normal: .unitZ, depth: depth)
    }

    static func ellipse(rx: Double, ry: Double, center: Vec2 = Vec2(0, 0), rotation: Double = 0, squareness: Double = 2, n: Int = 40) -> [Vec2] {
        (0 ..< n).map { index in
            let t = 2 * .pi * Double(index) / Double(n)
            let c = cos(t)
            let s = sin(t)
            let r = 1 / pow(pow(abs(c), squareness) + pow(abs(s), squareness), 1 / squareness)
            let x = c * r * rx
            let y = s * r * ry
            return center + Vec2(x * cos(rotation) - y * sin(rotation), x * sin(rotation) + y * cos(rotation))
        }
    }

    /// A painted line on the head: points (head x, y) put on the surface, relative to `origin`, smoothed (Catmull-Rom).
    static func surfaceStroke(_ points: [(Double, Double)], halfWidths: [Double], origin: Vec3, lift: Double, taper: Bool = false) -> DrawingRecipe.Stroke {
        let samples = max(points.count * 6, 12)
        var out: [Vec3] = []
        var widths: [Double] = []
        for index in 0 ... samples {
            let f = Double(index) / Double(samples) * Double(points.count - 1)
            let k = min(Int(f), points.count - 2)
            let t = f - Double(k)
            func pick(_ i: Int) -> (Double, Double) { points[min(max(i, 0), points.count - 1)] }
            let p0 = pick(k - 1), p1 = pick(k), p2 = pick(k + 1), p3 = pick(k + 2)
            func spline(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t * t * t)
            }
            let x = spline(p0.0, p1.0, p2.0, p3.0)
            let y = spline(p0.1, p1.1, p2.1, p3.1)
            out.append(onHead(x, y, lift: lift) - origin)
            let w0 = halfWidths[min(k, halfWidths.count - 1)]
            let w1 = halfWidths[min(k + 1, halfWidths.count - 1)]
            var width = w0 + (w1 - w0) * t
            if taper {
                // Soft ends, like a brush.
                let edge = min(Double(index), Double(samples - index)) / Double(samples)
                width *= min(1, 0.45 + edge * 4)
            }
            widths.append(width)
        }
        return DrawingRecipe.Stroke(points: out, widths: widths)
    }
}

extension CharacterBuilder.Assembler {
    /// A shape from a drawing recipe (lathes, slabs, painted lines), smooth-shaded, in `color`.
    @discardableResult
    mutating func shape(_ name: String, parent: ObjectID, recipe: DrawingRecipe, color: ColorValue) -> ObjectID {
        var object = SceneObject(id: ids.next(), name: name, kind: .drawing(recipe), parent: parent, transform: Transform())
        object[.color] = .color(color)
        object[.shading] = .enumeration(ShadingMode.smooth.rawValue)
        return add(object)
    }
}
