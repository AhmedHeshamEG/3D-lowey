import Foundation

/// The 1.x welcome island, built from primitives: kept as a regression fixture for the renderer and the package format
/// (the Theater ships `Showcase.island`, built from the Kit).
public enum IslandSample {
    public static let projectName = "Welcome island"

    public static func build(ids: IDFactory = .sequential("island")) throws -> (ProjectInfo, [Scene]) {
        var look = Look.default.applying(.goldenHour)
        look.post = PostSettings.Preset.cinematic.settings
        look.ground.visible = false
        look.fog = Fog(enabled: true, color: RGBA.hex("#F6C48E"), distance: 80)
        let info = ProjectInfo(id: ids.isSequential ? "island-project" : .make(), name: projectName, look: look)
        var scene = Scene(id: ids.isSequential ? "island-scene" : .make(), name: "Fly-through")
        scene.timeline = Timeline(fps: 30, duration: 10)
        let script = try LoweyJSON.decode(SceneScript.self, from: Data(IslandSample.script.utf8))
        let result = try ScriptCompiler.compile(script, document: Document(project: info, scene: scene), context: ScriptContext(ids: ids))
        scene = result.document.scene
        scene.viewpoint = Viewpoint(target: Vec3(0, 0.5, 0), yaw: 30, pitch: 32, distance: 24)
        return (info, [scene])
    }

    static let script = """
    {"version": 2, "title": "Welcome island", "actions": [
      {"do": "add", "shape": "cylinder", "name": "Sea", "at": [0, -0.3, 0], "size": [120, 0.3, 120], "color": "#3F7FA6", "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Beach", "at": [0, -0.05, 0], "size": [16, 0.3, 14], "color": "#E8D39B", "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Grass", "at": [0, 0, 0], "size": [13, 0.35, 11], "color": "#7FA65A"},
      {"do": "add", "shape": "cone", "name": "Hill", "at": [-3, 0.2, -2], "size": [6, 2.2, 5], "color": "#6E9A4E", "onGround": false},
      {"do": "add", "shape": "group", "name": "Pine", "at": [4, 0.35, -3], "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Trunk", "parent": "Pine", "at": [0, 0, 0], "size": [0.25, 0.8, 0.25], "color": "#7A4E2D", "onGround": false},
      {"do": "add", "shape": "cone", "name": "Needles", "parent": "Pine", "at": [0, 0.6, 0], "size": [1.4, 1.8, 1.4], "color": "#2F6B3F", "onGround": false},
      {"do": "add", "shape": "cone", "name": "Needles top", "parent": "Pine", "at": [0, 1.6, 0], "size": [1, 1.3, 1], "color": "#357A47", "onGround": false},
      {"do": "scatter", "target": "Pine", "name": "Forest", "count": 16, "radius": 4.5, "at": [-1, 0.35, -1], "seed": 4},
      {"do": "add", "shape": "cube", "name": "Cabin", "at": [3, 0.35, 2], "size": [2.2, 1.4, 1.8], "color": "#B5533C", "onGround": false},
      {"do": "add", "shape": "ramp", "name": "Roof", "at": [3, 1.75, 2.45], "size": [2.4, 0.8, 0.95], "color": "#4A3B35", "onGround": false},
      {"do": "add", "shape": "ramp", "name": "Roof back", "at": [3, 1.75, 1.55], "size": [2.4, 0.8, 0.95], "rotation": [0, 180, 0], "color": "#4A3B35", "onGround": false},
      {"do": "add", "shape": "cube", "name": "Window", "at": [3, 0.8, 2.91], "size": [0.5, 0.45, 0.04], "color": "#FFC46B", "glow": 3, "onGround": false},
      {"do": "add", "shape": "cube", "name": "Dock", "at": [6.8, 0.05, 4.2], "size": [3.4, 0.12, 0.9], "rotation": [0, -30, 0], "color": "#8A5A3B", "onGround": false},
      {"do": "add", "shape": "cube", "name": "Boat", "at": [8.8, -0.05, 5.8], "size": [1.6, 0.35, 0.6], "rotation": [0, -30, 0], "color": "#E4572E", "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Fire pit", "at": [1, 0.35, 3.6], "size": [0.7, 0.12, 0.7], "color": "#555555", "onGround": false},
      {"do": "particles", "preset": "fire", "name": "Campfire", "at": [1, 0.45, 3.6], "amount": 0.8},
      {"do": "particles", "preset": "embers", "name": "Embers", "at": [1, 0.5, 3.6]},
      {"do": "light", "type": "point", "name": "Fire light", "at": [1, 1, 3.6], "color": "#FF9A3C", "intensity": 2.5, "range": 6},
      {"do": "text", "name": "Welcome", "text": "HELLO", "at": [-3.5, 2.4, 2.5], "size": 0.8, "color": "#F2E8D5"},
      {"do": "camera", "name": "Fly camera", "from": [0, 9, 22], "lookAt": [0, 0.5, 0], "focalLength": 32, "active": true},
      {"do": "cameraMove", "camera": "Fly camera", "move": "crane", "subject": [0, 0.5, 0], "at": 0, "duration": 4},
      {"do": "cameraMove", "camera": "Fly camera", "move": "orbit", "subject": [0, 0.5, 0], "at": 4, "duration": 6},
      {"do": "preset", "target": "Forest", "preset": "wiggle", "at": 1, "duration": 2, "strength": 0.3},
      {"do": "preset", "target": "Welcome", "preset": "dropIn", "at": 2.5, "duration": 1},
      {"do": "overlay", "shape": "title", "name": "Title", "text": "Welcome to 3D-lowey", "at": [0, 0.62], "size": 0.8},
      {"do": "preset", "target": "Title", "preset": "typewriter", "at": 0.6, "duration": 1.6},
      {"do": "preset", "target": "Title", "preset": "fadeOut", "at": 4.5, "duration": 0.6},
      {"do": "cut", "camera": "Fly camera", "at": 0}
    ]}
    """
}
