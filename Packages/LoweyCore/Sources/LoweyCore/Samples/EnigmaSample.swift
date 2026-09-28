import Foundation

/// The canonical test: the three static sets of the Enigma video (context.md §7.1),
/// built only from blockout, drawing recipes and lights — through the same commands
/// the UI uses. Ships as a sample project and doubles as a round-trip test fixture.
public enum EnigmaSample {
    public static let projectName = "Enigma — sets"

    /// Builds the sample project. Deterministic (sequential ids) so tests can compare output.
    public static func build(ids: IDFactory = .sequential("enigma")) throws -> (ProjectInfo, [Scene]) {
        var ids = ids
        var look = LookPresets.look(for: .night)
        look.palette = Palette(swatches: [
            .init(name: "Paper", color: RGBA(hex: "#EFE4C8")!),
            .init(name: "Desk wood", color: RGBA(hex: "#6B4428")!),
            .init(name: "Lamp", color: RGBA(hex: "#FFB45C")!),
            .init(name: "Wall", color: RGBA(hex: "#2B3148")!),
            .init(name: "Metal", color: RGBA(hex: "#9AA3B2")!),
            .init(name: "Screen", color: RGBA(hex: "#7FD4FF")!),
            .init(name: "Rock", color: RGBA(hex: "#4A4E5A")!),
            .init(name: "Hero", color: RGBA(hex: "#E8EEF5")!),
            .init(name: "Skin", color: RGBA(hex: "#D9A27E")!),
            .init(name: "Shirt", color: RGBA(hex: "#5B6C8F")!)
        ])
        let info = ProjectInfo(id: ids.next(), name: projectName, created: Date(timeIntervalSince1970: 1_790_000_000),
                               modified: Date(timeIntervalSince1970: 1_790_000_000), look: look)
        let desk = try deskScene(ids: &ids, info: info)
        let room = try roomScene(ids: &ids, info: info)
        let cave = try caveScene(ids: &ids, info: info)
        return (info, [desk, room, cave])
    }

    // MARK: Helpers

    struct Builder {
        var session: EditSession
        var factory: ObjectFactory
        var operations: Operations

        init(scene: Scene, info: ProjectInfo, ids: IDFactory) {
            session = EditSession(document: Document(project: info, scene: scene))
            factory = ObjectFactory(ids: ids)
            operations = Operations(ids: ids)
        }

        var ids: IDFactory {
            get { factory.ids }
            set {
                factory.ids = newValue
                operations.ids = newValue
            }
        }

        @discardableResult
        mutating func box(
            _ name: String, _ shape: PrimitiveShape = .cube, at position: Vec3, size: Vec3, color: ColorValue,
            rotation: Vec3 = .zero, parent: ObjectID? = nil, glow: Double = 0
        ) throws -> ObjectID {
            var object = factory.primitive(shape, at: position, color: color)
            operations.ids = factory.ids
            object.name = name
            object.transform = Transform(position: position, rotation: Quat(eulerDegrees: rotation), scale: size)
            if glow > 0 {
                object[.emissive] = .color(color)
                object[.emissiveIntensity] = .float(glow)
            }
            try session.perform(.insert(SceneFragment(object: object), parent: parent, index: nil))
            return object.id
        }

        @discardableResult
        mutating func group(_ name: String, at position: Vec3 = .zero, parent: ObjectID? = nil) throws -> ObjectID {
            var object = factory.group(named: name, at: position)
            operations.ids = factory.ids
            object.name = name
            try session.perform(.insert(SceneFragment(object: object), parent: parent, index: nil))
            return object.id
        }

        @discardableResult
        mutating func light(_ type: LightType, at position: Vec3, color: RGBA, intensity: Double, range: Double, parent: ObjectID? = nil) throws -> ObjectID {
            var object = factory.light(type, at: position, color: color)
            operations.ids = factory.ids
            object[.lightIntensity] = .float(intensity)
            object[.lightRange] = .float(range)
            try session.perform(.insert(SceneFragment(object: object), parent: parent, index: nil))
            return object.id
        }

        @discardableResult
        mutating func drawing(_ name: String, _ recipe: DrawingRecipe, at position: Vec3, color: ColorValue, parent: ObjectID? = nil) throws -> ObjectID {
            var object = factory.drawing(recipe, transform: Transform(position: position), color: color)
            operations.ids = factory.ids
            object.name = name
            try session.perform(.insert(SceneFragment(object: object), parent: parent, index: nil))
            return object.id
        }
    }

    static func deskScene(ids: inout IDFactory, info: ProjectInfo) throws -> Scene {
        var scene = Scene(id: ids.next(), name: "1 · Desk, paper, warm lamp")
        var look = info.look
        look.lighting.sunIntensity = 0.12
        look.lighting.ambientIntensity = 0.45
        look.fog = Fog(enabled: true, color: RGBA(hex: "#0D1020")!, distance: 14)
        look.ground = Ground(visible: false, color: RGBA(hex: "#1A1D2B")!, size: 30)
        scene.look = look
        scene.viewpoint = Viewpoint(target: Vec3(0, 0.85, 0), yaw: 20, pitch: 32, distance: 3.4, fieldOfView: 42)
        var b = Builder(scene: scene, info: info, ids: ids)

        // Room shell.
        try b.box("Floor", at: Vec3(0, -0.02, 0), size: Vec3(8, 0.02, 8), color: .rgba(RGBA(hex: "#23202A")!))
        try b.box("Back wall", at: Vec3(0, 0, -1.6), size: Vec3(8, 3.2, 0.1), color: .palette(3))
        try b.box("Side wall", at: Vec3(-2.6, 0, 0), size: Vec3(0.1, 3.2, 8), color: .palette(3))

        // Desk.
        let desk = try b.group("Desk")
        try b.box("Desk top", at: Vec3(0, 0.72, 0), size: Vec3(1.6, 0.06, 0.8), color: .palette(1), parent: desk)
        for (x, z) in [(-0.74, -0.34), (0.74, -0.34), (-0.74, 0.34), (0.74, 0.34)] {
            try b.box("Leg", .cylinder, at: Vec3(x, 0, z), size: Vec3(0.06, 0.72, 0.06), color: .palette(1), parent: desk)
        }
        try b.box("Drawer", at: Vec3(0.45, 0.5, 0), size: Vec3(0.5, 0.2, 0.74), color: .palette(1), parent: desk)

        // The paper: the hero of shot 1.
        try b.box("Army message", at: Vec3(-0.1, 0.78, 0.08), size: Vec3(0.3, 0.004, 0.42),
                  color: .palette(0), rotation: Vec3(0, -12, 0))
        try b.box("Envelope", at: Vec3(0.28, 0.78, 0.12), size: Vec3(0.24, 0.006, 0.14),
                  color: .rgba(RGBA(hex: "#C9B48A")!), rotation: Vec3(0, 18, 0))

        // Warm desk lamp: base, drawn arm, cone shade, glowing bulb, point light.
        let lamp = try b.group("Desk lamp", at: Vec3(0.55, 0.78, -0.22))
        try b.box("Lamp base", .cylinder, at: Vec3(0, 0, 0), size: Vec3(0.2, 0.03, 0.2), color: .palette(4), parent: lamp)
        let arm = DrawingRecipe(style: .tube, strokes: [
            .init(points: [Vec3(0, 0.02, 0), Vec3(0, 0.3, 0.02), Vec3(-0.12, 0.48, 0.1), Vec3(-0.28, 0.52, 0.16)],
                  widths: [0.014, 0.014, 0.013, 0.012])
        ], segments: 6)
        try b.drawing("Lamp arm", arm, at: .zero, color: .palette(4), parent: lamp)
        // Cone flipped upside down so it opens toward the paper.
        try b.box("Lamp shade", .cone, at: Vec3(-0.3, 0.56, 0.17), size: Vec3(0.24, 0.18, 0.24),
                  color: .palette(4), rotation: Vec3(180, 0, 0), parent: lamp)
        try b.box("Bulb", .sphere, at: Vec3(-0.3, 0.36, 0.17), size: Vec3(0.07, 0.07, 0.07),
                  color: .palette(2), parent: lamp, glow: 3)
        try b.light(.point, at: Vec3(-0.3, 0.33, 0.17), color: RGBA(hex: "#FFB45C")!, intensity: 2.2, range: 4, parent: lamp)

        // Chair blockout.
        let chair = try b.group("Chair", at: Vec3(0, 0, 0.75))
        try b.box("Seat", at: Vec3(0, 0.45, 0), size: Vec3(0.45, 0.05, 0.45), color: .rgba(RGBA(hex: "#3C2A1E")!), parent: chair)
        try b.box("Back", at: Vec3(0, 0.45, 0.2), size: Vec3(0.45, 0.5, 0.04), color: .rgba(RGBA(hex: "#3C2A1E")!), parent: chair)
        for (x, z) in [(-0.2, -0.2), (0.2, -0.2), (-0.2, 0.2), (0.2, 0.2)] {
            try b.box("Chair leg", .cylinder, at: Vec3(x, 0, z), size: Vec3(0.035, 0.45, 0.035),
                      color: .rgba(RGBA(hex: "#3C2A1E")!), parent: chair)
        }
        ids = b.ids
        return b.session.document.scene
    }

    static func roomScene(ids: inout IDFactory, info: ProjectInfo) throws -> Scene {
        var scene = Scene(id: ids.next(), name: "2 · Room of people at PCs")
        var look = info.look
        look.lighting.sunIntensity = 0.3
        look.lighting.ambientIntensity = 0.8
        look.fog = Fog(enabled: true, color: RGBA(hex: "#101528")!, distance: 22)
        look.ground = Ground(visible: false, color: RGBA(hex: "#1A1D2B")!, size: 40)
        scene.look = look
        scene.viewpoint = Viewpoint(target: Vec3(1.8, 0.8, 1.6), yaw: 28, pitch: 30, distance: 9, fieldOfView: 48)
        var b = Builder(scene: scene, info: info, ids: ids)

        try b.box("Floor", at: Vec3(1.8, -0.02, 1.8), size: Vec3(12, 0.02, 10), color: .rgba(RGBA(hex: "#262A38")!))
        try b.box("Back wall", at: Vec3(1.8, 0, -1.4), size: Vec3(12, 3.4, 0.1), color: .palette(3))

        // One workstation: desk, PC, glowing screen, person typing.
        let station = try b.group("Workstation")
        try b.box("Desk", at: Vec3(0, 0.7, 0), size: Vec3(1.2, 0.05, 0.6), color: .palette(1), parent: station)
        try b.box("Desk legs", at: Vec3(0, 0, 0), size: Vec3(1.1, 0.7, 0.5), color: .rgba(RGBA(hex: "#4A3120")!), parent: station)
        try b.box("Monitor", at: Vec3(0, 0.75, -0.18), size: Vec3(0.5, 0.34, 0.05), color: .palette(4), parent: station)
        try b.box("Screen", at: Vec3(0, 0.77, -0.152), size: Vec3(0.45, 0.29, 0.005), color: .palette(5), parent: station, glow: 1.6)
        try b.box("PC tower", at: Vec3(0.45, 0, -0.05), size: Vec3(0.18, 0.42, 0.4), color: .palette(4), parent: station)
        try b.box("Keyboard", at: Vec3(0, 0.725, 0.05), size: Vec3(0.4, 0.02, 0.13), color: .rgba(RGBA(hex: "#30343F")!), parent: station)
        let person = try b.group("Person", at: Vec3(0, 0, 0.55), parent: station)
        try b.box("Legs", .cylinder, at: Vec3(0, 0, 0), size: Vec3(0.3, 0.46, 0.3), color: .rgba(RGBA(hex: "#2E3445")!), parent: person)
        try b.box("Body", .cylinder, at: Vec3(0, 0.46, 0), size: Vec3(0.38, 0.5, 0.3), color: .palette(9), parent: person)
        try b.box("Head", .sphere, at: Vec3(0, 0.98, -0.02), size: Vec3(0.24, 0.26, 0.24), color: .palette(8), parent: person)
        for x in [-0.2, 0.2] {
            try b.box("Arm", .cylinder, at: Vec3(x, 0.72, -0.18), size: Vec3(0.09, 0.3, 0.09), color: .palette(9),
                      rotation: Vec3(-70, 0, 0), parent: person)
        }

        // Fill the room: 4 × 3 grid of workstations, one gesture.
        var ops = b.operations
        ops.ids = b.ids
        if let (command, _) = ops.array(station, layout: .grid(columns: 4, rows: 3, spacingX: 1.6, spacingZ: 1.8), in: b.session.document.scene) {
            try b.session.perform(command)
        }
        b.ids = ops.ids

        // Cold ceiling lights.
        for x in [0.0, 2.4, 4.8] {
            try b.light(.point, at: Vec3(x, 2.8, 1.8), color: RGBA(hex: "#BFD8FF")!, intensity: 3, range: 7)
        }
        ids = b.ids
        return b.session.document.scene
    }

    static func caveScene(ids: inout IDFactory, info: ProjectInfo) throws -> Scene {
        var scene = Scene(id: ids.next(), name: "3 · Hero robot in a cave")
        var look = info.look
        look.shading = .flat
        look.lighting.sunIntensity = 0.25
        look.lighting.ambientIntensity = 0.5
        look.fog = Fog(enabled: true, color: RGBA(hex: "#0B0E18")!, distance: 16)
        look.ground = Ground(visible: true, color: RGBA(hex: "#23262F")!, size: 40)
        scene.look = look
        scene.viewpoint = Viewpoint(target: Vec3(0, 1.4, 0), yaw: 0, pitch: 8, distance: 7.5, fieldOfView: 45)
        var b = Builder(scene: scene, info: info, ids: ids)

        // Cave walls: a ring of big faceted rocks, open toward the camera.
        let cave = try b.group("Cave")
        var random = SeededRandom(seed: 85)
        for index in 0 ..< 16 {
            // Open toward the camera (+Z): rocks cover the back and sides only.
            let angle = Double(index) / 15 * 1.5 * .pi + 0.25 * .pi
            let radius = 4.2 + random.range(-0.4, 0.5)
            let size = random.range(1.8, 3.2)
            try b.box("Rock", .sphere, at: Vec3(sin(angle) * radius, -0.3, cos(angle) * radius),
                      size: Vec3(size * 1.2, size * random.range(1.4, 2.2), size),
                      color: .palette(6), rotation: Vec3(0, random.range(0, 360), random.range(-10, 10)), parent: cave)
        }
        try b.box("Cave roof", .sphere, at: Vec3(0, 3.4, -1), size: Vec3(9, 3, 8), color: .palette(6), parent: cave)
        // Stalagmites drawn as lathe profiles.
        let spike = DrawingRecipe(style: .lathe, strokes: [
            .init(points: [Vec3(0.25, 0, 0), Vec3(0.18, 0.4, 0), Vec3(0.08, 0.9, 0), Vec3(0.0, 1.3, 0)], widths: [0.02, 0.02, 0.02, 0.02])
        ], segments: 7)
        for (x, z) in [(-2.2, -1.2), (2.4, -0.8), (-1.4, 1.8), (1.8, 1.9)] {
            try b.drawing("Stalagmite", spike, at: Vec3(x, 0, z), color: .palette(6), parent: cave)
        }

        // The hero robot.
        let robot = try b.group("Hero robot", at: Vec3(0, 0, -0.6))
        try b.box("Legs L", at: Vec3(-0.25, 0, 0), size: Vec3(0.28, 0.9, 0.34), color: .palette(4), parent: robot)
        try b.box("Legs R", at: Vec3(0.25, 0, 0), size: Vec3(0.28, 0.9, 0.34), color: .palette(4), parent: robot)
        try b.box("Torso", at: Vec3(0, 0.9, 0), size: Vec3(1.0, 0.9, 0.6), color: .palette(7), parent: robot)
        try b.box("Core", .sphere, at: Vec3(0, 1.2, 0.29), size: Vec3(0.22, 0.22, 0.08), color: .palette(5), parent: robot, glow: 4)
        try b.box("Head", at: Vec3(0, 1.85, 0), size: Vec3(0.6, 0.45, 0.5), color: .palette(7), parent: robot)
        try b.box("Eye L", .sphere, at: Vec3(-0.13, 2.0, 0.25), size: Vec3(0.1, 0.1, 0.03), color: .palette(5), parent: robot, glow: 5)
        try b.box("Eye R", .sphere, at: Vec3(0.13, 2.0, 0.25), size: Vec3(0.1, 0.1, 0.03), color: .palette(5), parent: robot, glow: 5)
        try b.box("Arm L", .cylinder, at: Vec3(-0.65, 0.75, 0), size: Vec3(0.22, 0.95, 0.22), color: .palette(4),
                  rotation: Vec3(0, 0, -8), parent: robot)
        try b.box("Arm R", .cylinder, at: Vec3(0.65, 0.75, 0), size: Vec3(0.22, 0.95, 0.22), color: .palette(4),
                  rotation: Vec3(0, 0, 8), parent: robot)
        try b.box("Antenna", .cylinder, at: Vec3(0, 2.3, 0), size: Vec3(0.04, 0.3, 0.04), color: .palette(4), parent: robot)
        try b.box("Antenna tip", .sphere, at: Vec3(0, 2.58, 0), size: Vec3(0.08, 0.08, 0.08), color: .rgba(RGBA(hex: "#FF5A3C")!),
                  parent: robot, glow: 4)

        // Heroic rim light from behind + cold glow from the core.
        try b.light(.spot, at: Vec3(0, 4.5, -3.2), color: RGBA(hex: "#9CC8FF")!, intensity: 6, range: 14)
        try b.light(.point, at: Vec3(0, 1.3, 0.4), color: RGBA(hex: "#7FD4FF")!, intensity: 1.6, range: 3.5, parent: robot)
        ids = b.ids
        return b.session.document.scene
    }
}
