import Foundation

/// "Render on your computer": a zip that Blender turns back into the scene. It holds the scene as glTF (objects,
/// materials, cameras, lights, animation), `maquette.json` with what glTF can't carry (the Look, the sun, the sky, the
/// ground, the camera cuts, render settings) and `setup_maquette.py`, which builds a ready-to-render .blend from both.
public enum BlenderPackage {
    public static let scriptName = "setup_maquette.py"
    public static let settingsName = "maquette.json"
    public static let sceneName = "scene.glb"

    public struct Render: Hashable, Sendable {
        public var width: Int
        public var height: Int

        public init(width: Int = 1920, height: Int = 1080) {
            self.width = width
            self.height = height
        }
    }

    /// The package for a scene, as zip data.
    public static func archive(_ scene: Scene, look: Look, preset: LookPreset, render: Render = Render(),
                               parts: @escaping (SceneObject) -> [GLTFScene.LocalPart] = { _ in [] },
                               painted: @escaping (SceneObject) -> PaintedExport? = { _ in nil }) -> Data {
        let glb = GLTFScene.glb(nil, in: scene, look: look, parts: parts, painted: painted)
        let json = (try? JSONSerialization.data(withJSONObject: settings(scene, look: look, preset: preset, render: render),
                                                options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        return ZipWriter.storedArchive([
            (sceneName, glb),
            (settingsName, json),
            (scriptName, Data(BlenderScript.source.utf8)),
            ("README.txt", Data(readme(scene).utf8))
        ])
    }

    /// What the script needs that glTF doesn't hold. Directions are glTF's (Y up); the script turns them.
    static func settings(_ scene: Scene, look: Look, preset: LookPreset, render: Render) -> [String: Any] {
        let fps = max(scene.timeline.fps, 1)
        func hex(_ color: RGBA) -> String { color.hex }
        let sun = look.lighting.sunDirection
        let names = Dictionary(uniqueKeysWithValues: scene.objects.values.map { ($0.id, $0.name.isEmpty ? $0.kind.typeName : $0.name) })
        var renderSettings: [String: Any] = [
            "width": render.width, "height": render.height, "fps": fps,
            "frameStart": 0, "frameEnd": max(Int((scene.timeline.duration * Double(fps)).rounded()) - 1, 0)
        ]
        if let camera = scene.activeCamera.flatMap({ names[$0] }) { renderSettings["camera"] = camera }
        renderSettings["cuts"] = scene.timeline.cuts.compactMap { cut -> [String: Any]? in
            names[cut.camera].map { ["frame": Int((cut.time * Double(fps)).rounded()), "camera": $0] }
        }
        return [
            "version": 1,
            "scene": scene.name,
            "look": [
                "preset": preset.id, "name": preset.name, "model": preset.shading.model.rawValue, "bands": preset.shading.bands,
                "smoothing": preset.shading.smoothing,
                "lines": ["enabled": preset.lines.enabled, "width": preset.lines.width, "color": hex(preset.lines.inkColor),
                          "creaseAngle": preset.lines.creaseAngle]
            ],
            "sun": ["direction": [sun.x, sun.y, sun.z], "color": hex(look.lighting.sunColor), "intensity": look.lighting.sunIntensity,
                    "shadows": look.lighting.sunShadows],
            "ambient": look.lighting.ambientIntensity,
            "exposure": look.lighting.exposure,
            "sky": ["top": hex(look.sky.top), "horizon": hex(look.sky.horizon), "bottom": hex(look.sky.bottom)],
            "ground": ["visible": look.ground.visible, "color": hex(look.ground.color), "size": look.ground.size],
            "render": renderSettings
        ]
    }

    static func readme(_ scene: Scene) -> String {
        """
        \(scene.name) — from Maquette

        To render it on your computer:
        1. Unzip this folder anywhere.
        2. Open Blender (4.2 or newer), go to Scripting, open \(scriptName) and press Run Script.
           Or from a terminal:  blender --python \(scriptName)
        3. It builds \(scene.name).blend next to these files, with the Look, the lights, the cameras, the camera cuts and
           the render settings in place. Render with F12 (a still) or Ctrl+F12 (the animation).

        What carries over: objects and their hierarchy, colours, roughness, metal and glow, cameras, lights, the sun, the
        sky, the ground, the animation, the frame rate and the camera cuts. Ink and Comic outlines become Blender's
        Freestyle lines; the banded shading becomes a toon material. Fog, film grain and the screen effects stay in
        Maquette.
        """
    }
}

/// The Blender script, kept here so the package always matches the app that wrote it.
enum BlenderScript {
    static let source = #"""
    # Builds a ready-to-render Blender scene from a Maquette package (scene.glb + maquette.json).
    #   blender --python setup_maquette.py                 opens Blender with the scene built
    #   blender -b --python setup_maquette.py -- --check   builds, saves and renders a small test frame, then quits
    import json
    import math
    import os
    import sys

    import bpy

    HERE = os.path.dirname(os.path.abspath(__file__))


    def rgb(hex_color):
        hex_color = hex_color.lstrip("#")
        srgb = [int(hex_color[i:i + 2], 16) / 255 for i in (0, 2, 4)]
        return [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]


    def to_blender(v):
        # glTF is Y up; Blender is Z up.
        return (v[0], -v[2], v[1])


    def clear():
        bpy.ops.wm.read_factory_settings(use_empty=True)


    def engine(scene):
        for name in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
            try:
                scene.render.engine = name
                return
            except TypeError:
                continue


    def import_scene(settings):
        scene = bpy.context.scene
        # The importer turns seconds into frames at the scene's rate, so set it first.
        scene.render.fps = settings["render"]["fps"]
        bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, "scene.glb"))


    def toon(material, bands, model):
        if not material.use_nodes:
            return
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        principled = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
        output = next((n for n in nodes if n.type == "OUTPUT_MATERIAL"), None)
        if principled is None or output is None:
            return
        base = principled.inputs["Base Color"].default_value[:]
        # Painted objects: the image under Base Color keeps its colours; the ramp shades it in grey.
        painted = principled.inputs["Base Color"].links[0].from_socket if principled.inputs["Base Color"].links else None
        if painted is not None:
            base = (1, 1, 1, 1)
        diffuse = nodes.new("ShaderNodeBsdfDiffuse")
        diffuse.inputs["Color"].default_value = (1, 1, 1, 1)
        to_rgb = nodes.new("ShaderNodeShaderToRGB")
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        steps = max(2, bands)
        elements = ramp.color_ramp.elements
        while len(elements) < steps:
            elements.new(0.5)
        for i, element in enumerate(elements):
            element.position = i / steps
            shade = 0.35 + 0.65 * (i / (steps - 1))
            element.color = (base[0] * shade, base[1] * shade, base[2] * shade, 1)
        emission = nodes.new("ShaderNodeEmission")
        links.new(diffuse.outputs["BSDF"], to_rgb.inputs["Shader"])
        links.new(to_rgb.outputs["Color"], ramp.inputs["Fac"])
        if painted is not None:
            multiply = nodes.new("ShaderNodeVectorMath")
            multiply.operation = "MULTIPLY"
            links.new(ramp.outputs["Color"], multiply.inputs[0])
            links.new(painted, multiply.inputs[1])
            links.new(multiply.outputs["Vector"], emission.inputs["Color"])
        else:
            links.new(ramp.outputs["Color"], emission.inputs["Color"])
        links.new(emission.outputs["Emission"], output.inputs["Surface"])


    def apply_look(settings):
        scene = bpy.context.scene
        look = settings["look"]
        if look["model"] in ("cel", "banded", "toon", "ink", "comic"):
            for material in bpy.data.materials:
                toon(material, look.get("bands", 3), look["model"])
        if look.get("smoothing", 1) < 0.5:
            for obj in scene.objects:
                if obj.type == "MESH":
                    for polygon in obj.data.polygons:
                        polygon.use_smooth = False
        lines = look["lines"]
        if lines["enabled"]:
            scene.render.use_freestyle = True
            scene.render.line_thickness_mode = "ABSOLUTE"
            scene.render.line_thickness = max(0.5, float(lines["width"]))
            layer = scene.view_layers[0]
            layer.use_freestyle = True
            lineset = layer.freestyle_settings.linesets.new("Maquette lines") if not layer.freestyle_settings.linesets \
                else layer.freestyle_settings.linesets[0]
            lineset.select_by_visibility = True
            lineset.select_silhouette = True
            lineset.select_border = True
            lineset.select_crease = True
            layer.freestyle_settings.crease_angle = math.radians(180 - float(lines.get("creaseAngle", 30)))
            if lineset.linestyle is None:
                lineset.linestyle = bpy.data.linestyles.new("Maquette ink")
            lineset.linestyle.color = rgb(lines["color"])
            lineset.linestyle.thickness = max(0.5, float(lines["width"]))


    def add_sun(settings):
        sun = settings["sun"]
        data = bpy.data.lights.new("Sun", type="SUN")
        data.color = rgb(sun["color"])
        data.energy = 3.0 * float(sun["intensity"])
        if hasattr(data, "use_shadow"):
            data.use_shadow = bool(sun["shadows"])
        obj = bpy.data.objects.new("Sun", data)
        bpy.context.scene.collection.objects.link(obj)
        # The light travels along the direction; a Blender sun shines down its -Z.
        direction = to_blender(sun["direction"])
        length = math.sqrt(sum(c * c for c in direction)) or 1
        dx, dy, dz = (c / length for c in direction)
        obj.rotation_euler = (math.acos(max(-1.0, min(1.0, -dz))), 0, math.atan2(-dx, dy))


    def world(settings):
        scene = bpy.context.scene
        world_data = bpy.data.worlds.new("Maquette sky")
        scene.world = world_data
        world_data.use_nodes = True
        nodes = world_data.node_tree.nodes
        links = world_data.node_tree.links
        background = next(n for n in nodes if n.type == "BACKGROUND")
        coords = nodes.new("ShaderNodeTexCoord")
        separate = nodes.new("ShaderNodeSeparateXYZ")
        ramp = nodes.new("ShaderNodeValToRGB")
        sky = settings["sky"]
        ramp.color_ramp.elements[0].position = 0.45
        ramp.color_ramp.elements[0].color = rgb(sky["bottom"]) + [1]
        ramp.color_ramp.elements[1].position = 1.0
        ramp.color_ramp.elements[1].color = rgb(sky["top"]) + [1]
        middle = ramp.color_ramp.elements.new(0.5)
        middle.color = rgb(sky["horizon"]) + [1]
        mapping = nodes.new("ShaderNodeMapRange")
        mapping.inputs["From Min"].default_value = -1
        links.new(coords.outputs["Generated"], separate.inputs["Vector"])
        links.new(separate.outputs["Z"], mapping.inputs["Value"])
        links.new(mapping.outputs["Result"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], background.inputs["Color"])
        background.inputs["Strength"].default_value = float(settings["ambient"])
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.exposure = float(settings["exposure"])


    def ground(settings):
        g = settings["ground"]
        if not g["visible"]:
            return
        size = float(g["size"])
        bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
        plane = bpy.context.active_object
        plane.name = "Ground"
        material = bpy.data.materials.new("Ground")
        material.use_nodes = True
        principled = material.node_tree.nodes.get("Principled BSDF")
        if principled:
            principled.inputs["Base Color"].default_value = rgb(g["color"]) + [1]
            principled.inputs["Roughness"].default_value = 1.0
        plane.data.materials.append(material)


    def lights_and_cameras(settings):
        scene = bpy.context.scene
        for obj in scene.objects:
            extras = obj.get("maquette")
            if obj.type == "LIGHT" and extras is not None and obj.name != "Sun":
                intensity = float(extras.get("intensity", 1))
                obj.data.energy = intensity * (5.0 if obj.data.type == "SUN" else 100.0)
        render = settings["render"]
        cameras = {obj.name: obj for obj in scene.objects if obj.type == "CAMERA"}
        if render.get("camera") in cameras:
            scene.camera = cameras[render["camera"]]
        elif cameras:
            scene.camera = next(iter(cameras.values()))
        for cut in render.get("cuts", []):
            camera = cameras.get(cut["camera"])
            if camera is not None:
                marker = scene.timeline_markers.new(cut["camera"], frame=int(cut["frame"]))
                marker.camera = camera


    def render_settings(settings):
        scene = bpy.context.scene
        render = settings["render"]
        engine(scene)
        scene.render.resolution_x = render["width"]
        scene.render.resolution_y = render["height"]
        scene.frame_start = render["frameStart"]
        scene.frame_end = render["frameEnd"]
        scene.render.filepath = "//renders/frame_"


    def main():
        check = "--check" in sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else False
        with open(os.path.join(HERE, "maquette.json"), encoding="utf-8") as handle:
            settings = json.load(handle)
        clear()
        import_scene(settings)
        apply_look(settings)
        add_sun(settings)
        world(settings)
        ground(settings)
        lights_and_cameras(settings)
        render_settings(settings)
        name = settings.get("scene") or "Maquette"
        blend = os.path.join(HERE, "".join(c if c.isalnum() or c in " -_" else "_" for c in name) + ".blend")
        bpy.ops.wm.save_as_mainfile(filepath=blend)
        print("MAQUETTE: saved " + blend)
        if check:
            scene = bpy.context.scene
            scene.render.resolution_percentage = 20
            scene.render.filepath = os.path.join(HERE, "renders", "check.png")
            bpy.ops.render.render(write_still=True)
            print("MAQUETTE: rendered " + scene.render.filepath)


    main()
    """#
}
