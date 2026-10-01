import Foundation

// MARK: - Face, hat and hair

extension BlobCharacter {
    /// One layer of the drawn mouth; flat layers (inside, teeth, tongue) sit `raise` off the skin.
    struct MouthLayer {
        let role: String
        let name: String
        let color: ColorValue
        let raise: Double?
    }

    // MARK: Face

    /// The face at rest, drawn with the rig's own shapes (so a still face is never rebuilt). `BlobRig` redraws the
    /// eyes, brows and mouth from their dials as they animate.
    static func face(_ a: inout CharacterBuilder.Assembler, head: ObjectID, recipe: BlobRecipe) {
        for side in [-1.0, 1.0] {
            let tag = side < 0 ? "L" : "R"
            let normal = headNormal(side * eye.x, eye.y)
            let eyeID = a.shape("Eye \(tag)", parent: head, recipe: slab(BlobRig.eyeOutline(open: 1, happy: 0, wide: 0, side: side), depth: 0.008),
                                color: ink)
            a.objects[a.index(eyeID)].transform = Transform(position: onHead(side * eye.x, eye.y, lift: 0.002) - normal * 0.004,
                                                            rotation: .rotation(from: .unitZ, to: normal))
            a.objects[a.index(eyeID)][.faceRole] = .string("eye.\(tag)")
            let look = a.group("Look \(tag)", parent: eyeID, at: Vec3(0, 0, 0.008))
            a.objects[a.index(look)][.faceRole] = .string("pupil.\(tag)")
            let shine = slabs([ellipse(rx: 0.31 * eye.rx, ry: 0.3 * eye.rx, center: Vec2(-0.3 * eye.rx, 0.34 * eye.ry)),
                               ellipse(rx: 0.13 * eye.rx, ry: 0.13 * eye.rx, center: Vec2(0.36 * eye.rx, -0.42 * eye.ry))], depth: 0.003)
            a.shape("Shine", parent: look, recipe: shine, color: white)

            let browCentre = onHead(side * brow.x, brow.y, lift: 0.003)
            let browID = a.shape("Brow \(tag)", parent: head, recipe: BlobRig.browRecipe(side: side, raise: 0, angle: 0, arch: 0, origin: browCentre),
                                 color: ink)
            a.objects[a.index(browID)].transform.position = browCentre
            a.objects[a.index(browID)][.faceRole] = .string("brow.\(tag)")

            if recipe.blush {
                let cheekID = a.shape("Cheek \(tag)", parent: head, recipe: slab(ellipse(rx: 0.036, ry: 0.026), depth: 0.006), color: blushColor)
                a.objects[a.index(cheekID)].transform = Transform(position: onHead(side * cheek.x, cheek.y, lift: -0.002),
                                                                  rotation: .rotation(from: .unitZ, to: headNormal(side * cheek.x, cheek.y)))
            }
        }

        // Mouth: one drawn mouth that morphs (lip sync, smiles, shouts), resting on his smirk and curl.
        let mouthCentre = onHead(0, mouthY, lift: 0)
        let rest = BlobRig.mouthLayers(BlobRig.MouthPose.named("X"), origin: mouthCentre)
        let layers = [
            MouthLayer(role: "mouth.inside", name: "Mouth inside", color: mouthDark, raise: 0.001),
            MouthLayer(role: "mouth.teeth", name: "Teeth", color: white, raise: 0.003),
            MouthLayer(role: "mouth.tongue", name: "Tongue", color: tongue, raise: 0.0035),
            MouthLayer(role: "mouth.lips", name: "Lips", color: ink, raise: nil),
            MouthLayer(role: "mouth.curl", name: "Curl", color: ink, raise: nil)
        ]
        let normal = headNormal(0, mouthY)
        for layer in layers {
            let recipe = rest[layer.role] ?? slab(ellipse(rx: 0.01, ry: 0.01, n: 8), depth: 0.001)
            let id = a.shape(layer.name, parent: head, recipe: recipe, color: layer.color)
            a.objects[a.index(id)].transform = if let raise = layer.raise {
                Transform(position: mouthCentre + normal * (raise - 0.002), rotation: .rotation(from: .unitZ, to: normal))
            } else {
                Transform(position: mouthCentre)
            }
            a.objects[a.index(id)][.faceRole] = .string(layer.role)
            a.objects[a.index(id)][.visible] = .bool(rest[layer.role] != nil)
        }
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
            a.objects[a.index(hat)][.faceRole] = .string("hat")
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
}
