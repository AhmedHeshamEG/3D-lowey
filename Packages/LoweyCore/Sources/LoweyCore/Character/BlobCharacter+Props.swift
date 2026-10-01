import Foundation

// MARK: - Accessories and props

extension BlobCharacter {
    static func accessories(_ a: inout CharacterBuilder.Assembler, head: ObjectID, body: ObjectID, recipe: BlobRecipe) {
        let color = recipe.accessoryColor
        for accessory in recipe.accessories {
            switch accessory {
            case .glasses, .roundGlasses, .monocle:
                glasses(&a, accessory, head: head, color: color)
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
                headphones(&a, head: head, color: color)
            }
        }
    }

    static func glasses(_ a: inout CharacterBuilder.Assembler, _ accessory: BlobRecipe.Accessory, head: ObjectID, color: ColorValue) {
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
    }

    static func headphones(_ a: inout CharacterBuilder.Assembler, head: ObjectID, color: ColorValue) {
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

    static func prop(_ a: inout CharacterBuilder.Assembler, hand: ObjectID, _ prop: BlobRecipe.Prop) {
        let holder = a.group("Holding", parent: hand, at: Vec3(0, -0.1, 0.06))
        a.objects[a.index(holder)].transform.rotation = Quat(angle: -0.78, axis: .unitZ)
        @discardableResult
        func ball(_ name: String, _ radius: Vec3, _ at: Vec3, _ color: StaticString) -> ObjectID {
            let id = a.shape(name, parent: holder, recipe: lathe(ellipseProfile(radius: 1, height: 1), segments: 16), color: .rgba(RGBA.hex(color)))
            a.objects[a.index(id)].transform = Transform(position: at, scale: radius)
            return id
        }
        func box(_ name: String, _ size: Vec3, _ at: Vec3, _ color: StaticString) {
            a.part(.cube, name, parent: holder, center: at, size: size, color: .rgba(RGBA.hex(color)))
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
            )], segments: 6), color: .rgba(RGBA.hex("#3B3B3B")))
            box("Handle", Vec3(0.02, 0.1, 0.02), .zero, "#5B3A1E")
        case .flask:
            let id = a.shape("Flask", parent: holder, recipe: lathe([Vec3(0, 0, 0), Vec3(0.07, 0, 0), Vec3(0.02, 0.1, 0), Vec3(0.02, 0.14, 0),
                                                                     Vec3(0, 0.14, 0)], segments: 20), color: .rgba(RGBA.hex("#7EE0B5")))
            a.objects[a.index(id)][.emissiveIntensity] = .float(0.8)
        case .envelope:
            box("Envelope", Vec3(0.18, 0.12, 0.01), .zero, "#F1E7D0")
            let flap = a.shape("Flap", parent: holder, recipe: slab([Vec2(-0.09, 0.06), Vec2(0.09, 0.06), Vec2(0, 0.0)], depth: 0.003),
                               color: .rgba(RGBA.hex("#D9CBAA")))
            a.objects[a.index(flap)].transform.position = Vec3(0, 0, 0.006)
        case .gear:
            let teeth = (0 ..< 24).map { index -> Vec2 in
                let angle = Double(index) / 24 * 2 * .pi
                let r = index.isMultiple(of: 2) ? 0.075 : 0.058
                return Vec2(cos(angle) * r, sin(angle) * r)
            }
            a.shape("Gear", parent: holder, recipe: slab(teeth, depth: 0.02), color: .rgba(RGBA.hex("#B08D57")))
        }
    }
}
