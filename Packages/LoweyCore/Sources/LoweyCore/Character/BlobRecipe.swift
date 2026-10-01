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
        name: String = "Blob", skin: ColorValue = .rgba(RGBA.hex("#FFFFFF")), hat: Hat = .none,
        hatColor: ColorValue = .rgba(RGBA.hex("#5D69FF")), hatLabel: String = "", mark: Mark = .none, hair: Hair = .none,
        hairColor: ColorValue = .rgba(RGBA.hex("#2B2118")), accessories: [Accessory] = [],
        accessoryColor: ColorValue = .rgba(RGBA.hex("#1B1B22")), prop: Prop = .none, blush: Bool = true, hover: Bool = true,
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
    private static func hex(_ value: StaticString) -> ColorValue { .rgba(RGBA.hex(value)) }

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
