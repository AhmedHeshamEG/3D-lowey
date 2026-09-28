import Foundation

/// 3D text in the world. "Blocky" is meshed here in Core from a built-in 5×7 font (low-poly, exact,
/// exportable); the other styles use the system fonts through RealityKit (smooth outlines, any script).
public struct TextRecipe: Codable, Hashable, Sendable {
    public enum Style: String, Codable, Sendable, CaseIterable, Identifiable {
        case blocky, rounded, bold, serif, mono

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .blocky: "Blocky"
            case .rounded: "Rounded"
            case .bold: "Bold"
            case .serif: "Serif"
            case .mono: "Mono"
            }
        }
    }

    public enum Alignment: String, Codable, Sendable, CaseIterable {
        case left, center, right
    }

    public var text: String
    public var style: Style
    /// Letter height in metres (before the object's scale).
    public var size: Double
    /// Extrusion depth as a fraction of `size`.
    public var depth: Double
    public var alignment: Alignment

    public init(text: String, style: Style = .blocky, size: Double = 1, depth: Double = 0.25, alignment: Alignment = .center) {
        self.text = text
        self.style = style
        self.size = size
        self.depth = depth
        self.alignment = alignment
    }

    /// Whether Core can mesh every character (the blocky font covers Latin letters, digits, punctuation).
    public var coreMeshable: Bool {
        style == .blocky && text.uppercased().allSatisfy { $0 == "\n" || BlockFont.glyphs[$0] != nil }
    }

    /// Approximate bounds (base-centred, standing on the ground like every Lowey object).
    public var estimatedBounds: Bounds {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let longest = Double(lines.map(\.count).max() ?? 1)
        let width = max(longest, 1) * size * 0.72
        let height = Double(max(lines.count, 1)) * size * 1.3
        let halfDepth = size * depth / 2
        let minX: Double = switch alignment {
        case .left: 0
        case .center: -width / 2
        case .right: -width
        }
        return Bounds(min: Vec3(minX, 0, -halfDepth), max: Vec3(minX + width, height, halfDepth))
    }
}

/// A 5×7 pixel font meshed as merged blocks: chunky, readable, Minecraft-friendly, a few dozen triangles a letter.
public enum BlockFont {
    public static let columns = 5
    public static let rows = 7

    /// Glyph bitmaps, top row first ("#" = filled).
    public static let glyphs: [Character: [String]] = {
        var map: [Character: [String]] = [:]
        let table: [(Character, String)] = [
            ("A", ".###.|#...#|#...#|#####|#...#|#...#|#...#"), ("B", "####.|#...#|#...#|####.|#...#|#...#|####."),
            ("C", ".###.|#...#|#....|#....|#....|#...#|.###."), ("D", "####.|#...#|#...#|#...#|#...#|#...#|####."),
            ("E", "#####|#....|#....|####.|#....|#....|#####"), ("F", "#####|#....|#....|####.|#....|#....|#...."),
            ("G", ".###.|#...#|#....|#.###|#...#|#...#|.####"), ("H", "#...#|#...#|#...#|#####|#...#|#...#|#...#"),
            ("I", ".###.|..#..|..#..|..#..|..#..|..#..|.###."), ("J", "..###|...#.|...#.|...#.|...#.|#..#.|.##.."),
            ("K", "#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#"), ("L", "#....|#....|#....|#....|#....|#....|#####"),
            ("M", "#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#"), ("N", "#...#|#...#|##..#|#.#.#|#..##|#...#|#...#"),
            ("O", ".###.|#...#|#...#|#...#|#...#|#...#|.###."), ("P", "####.|#...#|#...#|####.|#....|#....|#...."),
            ("Q", ".###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#"), ("R", "####.|#...#|#...#|####.|#.#..|#..#.|#...#"),
            ("S", ".####|#....|#....|.###.|....#|....#|####."), ("T", "#####|..#..|..#..|..#..|..#..|..#..|..#.."),
            ("U", "#...#|#...#|#...#|#...#|#...#|#...#|.###."), ("V", "#...#|#...#|#...#|#...#|#...#|.#.#.|..#.."),
            ("W", "#...#|#...#|#...#|#.#.#|#.#.#|#.#.#|.#.#."), ("X", "#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#"),
            ("Y", "#...#|#...#|.#.#.|..#..|..#..|..#..|..#.."), ("Z", "#####|....#|...#.|..#..|.#...|#....|#####"),
            ("0", ".###.|#...#|#..##|#.#.#|##..#|#...#|.###."), ("1", "..#..|.##..|..#..|..#..|..#..|..#..|.###."),
            ("2", ".###.|#...#|....#|...#.|..#..|.#...|#####"), ("3", "####.|....#|....#|.###.|....#|....#|####."),
            ("4", "...#.|..##.|.#.#.|#..#.|#####|...#.|...#."), ("5", "#####|#....|####.|....#|....#|#...#|.###."),
            ("6", "..##.|.#...|#....|####.|#...#|#...#|.###."), ("7", "#####|....#|...#.|..#..|.#...|.#...|.#..."),
            ("8", ".###.|#...#|#...#|.###.|#...#|#...#|.###."), ("9", ".###.|#...#|#...#|.####|....#|...#.|.##.."),
            (" ", ".....|.....|.....|.....|.....|.....|....."), (".", ".....|.....|.....|.....|.....|.##..|.##.."),
            (",", ".....|.....|.....|.....|.##..|..#..|.#..."), ("!", "..#..|..#..|..#..|..#..|..#..|.....|..#.."),
            ("?", ".###.|#...#|....#|...#.|..#..|.....|..#.."), ("'", "..#..|..#..|.#...|.....|.....|.....|....."),
            ("\"", ".#.#.|.#.#.|.....|.....|.....|.....|....."), ("-", ".....|.....|.....|#####|.....|.....|....."),
            ("+", ".....|..#..|..#..|#####|..#..|..#..|....."), (":", ".....|.##..|.##..|.....|.##..|.##..|....."),
            (";", ".....|.##..|.##..|.....|.##..|..#..|.#..."), ("(", "...#.|..#..|.#...|.#...|.#...|..#..|...#."),
            (")", ".#...|..#..|...#.|...#.|...#.|..#..|.#..."), ("/", "....#|....#|...#.|..#..|.#...|#....|#...."),
            ("&", ".##..|#..#.|#.#..|.#...|#.#.#|#..#.|.##.#"), ("%", "##..#|##..#|...#.|..#..|.#...|#..##|#..##"),
            ("#", ".#.#.|.#.#.|#####|.#.#.|#####|.#.#.|.#.#."), ("=", ".....|.....|#####|.....|#####|.....|....."),
            ("_", ".....|.....|.....|.....|.....|.....|#####"), ("*", ".....|#.#.#|.###.|#####|.###.|#.#.#|....."),
            ("<", "...#.|..#..|.#...|#....|.#...|..#..|...#."), (">", ".#...|..#..|...#.|....#|...#.|..#..|.#..."),
            ("@", ".###.|#...#|#.###|#.#.#|#.###|#....|.###."), ("$", "..#..|.####|#.#..|.###.|..#.#|####.|..#..")
        ]
        for (character, rows) in table {
            map[character] = rows.split(separator: "|").map(String.init)
        }
        return map
    }()

    /// Mesh of `recipe` (text in the XY plane facing +Z, standing on y = 0).
    public static func mesh(for recipe: TextRecipe) -> MeshData {
        let pixel = Float(recipe.size / Double(rows))
        let depth = Float(max(recipe.size * recipe.depth, 0.001))
        let advance = Float(columns + 1)
        let lines = recipe.text.uppercased().split(separator: "\n", omittingEmptySubsequences: false)
        let lineHeight = Float(rows + 2)
        var mesh = MeshData()
        for (lineIndex, line) in lines.enumerated() {
            let width = (Float(line.count) * advance - 1) * pixel
            let startX: Float = switch recipe.alignment {
            case .left: 0
            case .center: -width / 2
            case .right: -width
            }
            let baseY = Float(lines.count - 1 - lineIndex) * lineHeight * pixel
            for (index, character) in line.enumerated() {
                guard let glyph = glyphs[character] else { continue }
                let originX = startX + Float(index) * advance * pixel
                for (row, bits) in glyph.enumerated() {
                    let y = baseY + Float(rows - 1 - row) * pixel
                    // One block per horizontal run of filled pixels.
                    var column = 0
                    let cells = Array(bits)
                    while column < cells.count {
                        guard cells[column] == "#" else {
                            column += 1
                            continue
                        }
                        var end = column
                        while end + 1 < cells.count, cells[end + 1] == "#" {
                            end += 1
                        }
                        let x0 = originX + Float(column) * pixel
                        let x1 = originX + Float(end + 1) * pixel
                        appendBlock(&mesh, min: SIMD3<Float>(x0, y, -depth / 2), max: SIMD3<Float>(x1, y + pixel, depth / 2))
                        column = end + 1
                    }
                }
            }
        }
        return mesh
    }

    static func appendBlock(_ mesh: inout MeshData, min a: SIMD3<Float>, max b: SIMD3<Float>) {
        let faces: [(SIMD3<Float>, [SIMD3<Float>])] = [
            (SIMD3(0, 0, 1), [SIMD3(a.x, a.y, b.z), SIMD3(b.x, a.y, b.z), SIMD3(b.x, b.y, b.z), SIMD3(a.x, b.y, b.z)]),
            (SIMD3(0, 0, -1), [SIMD3(b.x, a.y, a.z), SIMD3(a.x, a.y, a.z), SIMD3(a.x, b.y, a.z), SIMD3(b.x, b.y, a.z)]),
            (SIMD3(1, 0, 0), [SIMD3(b.x, a.y, b.z), SIMD3(b.x, a.y, a.z), SIMD3(b.x, b.y, a.z), SIMD3(b.x, b.y, b.z)]),
            (SIMD3(-1, 0, 0), [SIMD3(a.x, a.y, a.z), SIMD3(a.x, a.y, b.z), SIMD3(a.x, b.y, b.z), SIMD3(a.x, b.y, a.z)]),
            (SIMD3(0, 1, 0), [SIMD3(a.x, b.y, b.z), SIMD3(b.x, b.y, b.z), SIMD3(b.x, b.y, a.z), SIMD3(a.x, b.y, a.z)]),
            (SIMD3(0, -1, 0), [SIMD3(a.x, a.y, a.z), SIMD3(b.x, a.y, a.z), SIMD3(b.x, a.y, b.z), SIMD3(a.x, a.y, b.z)])
        ]
        for (normal, corners) in faces {
            let i0 = mesh.addVertex(corners[0], normal: normal, uv: SIMD2(0, 0))
            let i1 = mesh.addVertex(corners[1], normal: normal, uv: SIMD2(1, 0))
            let i2 = mesh.addVertex(corners[2], normal: normal, uv: SIMD2(1, 1))
            let i3 = mesh.addVertex(corners[3], normal: normal, uv: SIMD2(0, 1))
            mesh.addTriangle(i0, i1, i2)
            mesh.addTriangle(i0, i2, i3)
        }
    }
}
