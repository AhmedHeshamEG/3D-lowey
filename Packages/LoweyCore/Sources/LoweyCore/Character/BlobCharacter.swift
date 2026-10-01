import Foundation

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

    static let ink = ColorValue.rgba(RGBA.hex("#0B0B10"))
    static let white = ColorValue.rgba(RGBA.hex("#FFFFFF"))
    static let blushColor = ColorValue.rgba(RGBA.hex("#F0303A"))
    static let mouthDark = ColorValue.rgba(RGBA.hex("#2A0A12"))
    static let tongue = ColorValue.rgba(RGBA.hex("#FF6B7A"))
    static let glowColor = ColorValue.rgba(RGBA.hex("#9EB6FF"))
    static let markColor = ColorValue.rgba(RGBA.hex("#E3F6FF"))

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

        // Head: the drawing's onion, turned; the face lives on its front.
        let head = a.group("Head", parent: root, at: Vec3(0, headBottom, 0))
        a.objects[a.index(head)][.faceRole] = .string("head")
        let skull = a.shape("Skull", parent: head, recipe: lathe(headProfile.map { Vec3($0.r, $0.y, 0) }, segments: 48), color: recipe.skin)
        a.objects[a.index(skull)].transform.scale = Vec3(1, 1, headDepth)
        face(&a, head: head, recipe: recipe)
        hat(&a, head: head, recipe: recipe)
        hair(&a, head: head, recipe: recipe)

        // Body: a drop, point up, floating under the head.
        let body = a.group("Body", parent: root, at: Vec3(0, bodyBottom, 0))
        a.shape("Drop", parent: body, recipe: lathe(dropProfile(), segments: 40), color: recipe.skin)
        for side in [-1.0, 1.0] {
            arm(&a, side: side, root: root, body: body, recipe: recipe)
        }
        accessories(&a, head: head, body: body, recipe: recipe)
        if recipe.hover { hoverGlow(&a, root: root) }

        let objects = bendArms(a.objects, root: root)
        ids = a.ids
        let floating = Behavior(id: ids.next(ObjectID.self).raw, target: root, kind: .bob(height: 0.035, period: 2.6, tilt: 1.5))
        return Build(fragment: SceneFragment(objects: objects, roots: [root]), behaviors: [floating])
    }

    /// A rubber-hose arm and a mitten hand (the arm follows the hand); the right hand holds the prop.
    static func arm(_ a: inout CharacterBuilder.Assembler, side: Double, root: ObjectID, body: ObjectID, recipe: BlobRecipe) {
        let skin = recipe.skin
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

    /// A soft pool of light right under the drop (stacked discs fade it out towards the edge). The rig keeps it on
    /// the ground while he floats and tightens it as he rises.
    static func hoverGlow(_ a: inout CharacterBuilder.Assembler, root: ObjectID) {
        let pool = a.group("Hover glow", parent: root, at: Vec3(0, 0.006, 0.02))
        a.objects[a.index(pool)][.faceRole] = .string("hover")
        for (index, radius) in [0.2, 0.155, 0.11, 0.07].enumerated() {
            let disc = a.shape("Glow", parent: pool, recipe: lathe([Vec3(radius, 0, 0), Vec3(0, 0.001, 0)], segments: 40), color: glowColor)
            a.objects[a.index(disc)].transform.position = Vec3(0, 0.0015 * Double(index), 0)
            a.objects[a.index(disc)][.emissiveIntensity] = .float(0.9)
            a.objects[a.index(disc)][.opacity] = .float(0.16)
        }
    }

    /// Arms start bent the way the rig will bend them (so a character at rest never needs rebuilding).
    static func bendArms(_ built: [SceneObject], root: ObjectID) -> [SceneObject] {
        var objects = built
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
        return objects
    }
}
