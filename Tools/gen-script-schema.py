"""Writes schemas/scene-script.v3.schema.json: every Scene Script v3 verb with its fields.

The shared definitions (commands, times, targets…) come from the v2 schema. Run it after adding a verb;
`--check` (CI) fails when the file on disk is out of date. A Core test checks the verbs match the compiler's.
"""
import copy
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "schemas"
old = json.load(open(ROOT / "scene-script.schema.json", encoding="utf-8"))
defs = copy.deepcopy(old['$defs'])

def ref(name):
    return {"$ref": f"#/$defs/{name}"}

s = {"type": "string"}
n = {"type": "number"}
b = {"type": "boolean"}
tgt = ref("target")
time = ref("time")
point = ref("point")
color = ref("color")
v3 = ref("vec3")

relations = ["on", "beside_left", "beside_right", "in_front_of", "behind", "above", "under", "inside", "facing",
             "around", "row", "grid", "scatter_in", "stack"]
shot_types = ["extremeWide", "wide", "full", "medium", "closeUp", "extremeCloseUp", "overTheShoulder", "twoShot", "insert"]
compositions = ["center", "leftThird", "rightThird", "lowAngle", "highAngle"]
recipes = ["key-warm-world-cool", "noir-single-source", "golden-rim", "monitor-glow", "moonlit", "studio-soft"]
intents = ["enter", "exit", "emphasise", "react", "walk_to", "look_at", "talk", "idle"]
looks = ["ink", "comic", "sketch", "clay", "lowpoly"]
fx = ["speedLines", "impactBurst", "sweatDrop", "sparkle", "smear"]
expressions = ["neutral", "happy", "laugh", "smug", "surprised", "shocked", "scared", "sad", "angry", "sleepy", "wink", "thinking"]
presets = ["popIn", "popOut", "grow", "shrink", "bounce", "wiggle", "float", "spin", "shake", "pulse", "fadeIn", "fadeOut",
           "slideIn", "dropIn", "typewriter"]
moves = ["pushIn", "pullOut", "punchIn", "snapZoom", "orbit", "dolly", "truck", "crane", "whipPan", "shake", "reveal"]
clips = ["Idle", "Walk", "Run", "Talk", "Wave", "Point", "Type", "Nod", "Shrug", "Celebrate"]

verbs = {
    "add": ("A Kit/library model (\"asset\": an id like kit.office-desk, or words), a shape, or a group; optionally placed by relation.",
            {"asset": s, "shape": {"enum": ["cube", "sphere", "cylinder", "cone", "plane", "torus", "ramp", "group"]}, "name": s,
             "at": point, "size": {"anyOf": [n, v3]}, "color": color, "rotation": v3, "glow": n, "parent": tgt, "onGround": b,
             "look": {"enum": looks}, "relation": {"enum": relations}, "reference": tgt, "offset": v3}, []),
    "place": ("Place by relation (grounded, apart from what's there; left/right as seen from the reference's front).",
              {"target": tgt, "relation": {"enum": relations}, "reference": tgt, "offset": v3, "radius": n, "spacing": n,
               "columns": n, "seed": n}, ["target", "relation"]),
    "scaleTo": ("Real-world size in metres.", {"target": tgt, "meters": n, "axis": {"enum": ["height", "width", "depth", "longest"]}},
                ["target", "meters"]),
    "recolor": ("Tint with a palette slot.", {"target": tgt, "slot": n}, ["target", "slot"]),
    "remove": ("Delete.", {"target": tgt}, ["target"]),
    "group": ("Group under a new parent.", {"target": tgt, "name": s}, ["target"]),
    "rename": ("Rename.", {"target": tgt, "name": s}, ["target", "name"]),
    "transform": ("Absolute transform (edge cases).", {"target": tgt, "position": v3, "rotation": v3, "scale": {"anyOf": [n, v3]},
                                                       "relative": b, "at": time, "easing": s}, ["target"]),
    "text": ("3D words.", {"text": s, "name": s, "at": point, "size": n, "style": s, "color": color, "glow": n}, ["text"]),
    "blob": ("A Blob character (a likeness or a recipe).", {"name": s, "likeness": s, "at": point, "facing": n, "label": s,
                                                           "recipe": {"type": "object"}}, []),
    "character": ("A humanoid character.", {"name": s, "at": point, "facing": n, "recipe": {"type": "object"}}, []),
    "particles": ("An emitter.", {"preset": s, "name": s, "at": point, "amount": n, "time": time}, ["preset"]),
    "light": ("A lamp.", {"type": {"enum": ["point", "spot", "sun"]}, "name": s, "at": point, "color": color, "intensity": n, "range": n}, []),
    "camera": ("A camera.", {"name": s, "from": point, "lookAt": point, "focalLength": n, "fov": n, "aperture": n, "active": b}, []),
    "frameShot": ("The camera solver: shot type and composition on a subject (a new camera when \"camera\" doesn't exist).",
                  {"subject": tgt, "shotType": {"enum": shot_types}, "composition": {"enum": compositions}, "lens": n, "other": tgt,
                   "side": {"enum": ["left", "right"]}, "camera": s, "at": time, "aspect": n, "active": b}, ["subject"]),
    "lighting": ("A lighting recipe placed for the shot camera (replaces the recipe's earlier lamps).",
                 {"recipe": {"enum": recipes}, "subject": tgt, "intensity": n, "warmth": n}, ["recipe"]),
    "look": ("The Look, mood and post; per-object Looks.", {"look": {"enum": looks}, "mood": s, "post": s, "shading": s,
                                                            "fog": {"anyOf": [b, n]}, "palette": {"type": "array", "items": color},
                                                            "bloom": n, "grain": n, "sceneOnly": b,
                                                            "perObject": {"type": "object", "additionalProperties": {"enum": looks}}}, []),
    "intent": ("Say what it should do; the app picks the animation.", {"target": tgt, "what": {"enum": intents},
               "how": {"enum": expressions}, "to": {"anyOf": [tgt, v3]}, "at": time, "on_word": s, "duration": n, "strength": n,
               "frameRate": {"enum": ["ones", "twos", "threes", "fours"]}, "words": s}, ["target", "what"]),
    "preset": ("A motion preset.", {"target": tgt, "preset": {"enum": presets}, "at": time, "duration": n, "strength": n,
                                    "stagger": n, "order": {"enum": ["selection", "leftToRight", "rightToLeft", "wave"]}, "from": point},
               ["target", "preset"]),
    "keys": ("Keyframes.", {"target": tgt, "property": s, "keys": {"type": "array", "items": {"type": "object", "required": ["value"],
             "properties": {"t": time, "at": time, "value": {}, "easing": s}}}}, ["target", "property", "keys"]),
    "set": ("A property (keyed when \"at\" is given).", {"target": tgt, "property": s, "value": {}, "at": time}, ["target", "property"]),
    "expression": ("A face, from a moment on.", {"target": tgt, "character": tgt, "name": {"enum": expressions}, "at": time}, ["name"]),
    "clip": ("A built-in clip.", {"character": tgt, "target": tgt, "clip": {"enum": clips}, "at": time, "duration": n, "loop": b,
                                  "from": s}, ["clip"]),
    "transcript": ("Words with known timings on a voiceover clip (a script, a laptop TTS).", {"clip": s, "text": s, "from": n, "to": n,
                   "language": s, "words": {"type": "array", "items": {"type": "object", "required": ["w", "t"],
                   "properties": {"w": s, "t": n, "e": n}}}}, []),
    "lipSync": ("Mouth shapes from the transcript.", {"character": tgt, "target": tgt, "words": s}, []),
    "cameraMove": ("A camera move.", {"camera": tgt, "move": {"enum": moves}, "subject": {"anyOf": [tgt, v3]}, "at": time,
                                      "duration": n, "strength": n}, ["move"]),
    "cut": ("Cut to a camera.", {"camera": tgt, "at": time, "transition": {"enum": ["cut", "fade", "dipToBlack", "wipe", "zoomThrough"]},
                                 "duration": n}, ["camera"]),
    "overlay": ("A 2D overlay in frame space.", {"shape": s, "name": s, "text": s, "at": {"type": "array", "items": n}, "size": n,
                                                 "follow": tgt, "color": color}, ["shape"]),
    "flipbook": ("Drawn FX from the library.", {"fx": {"enum": fx}, "anchor": {"anyOf": [tgt, v3]}, "at": time, "until": time,
                                               "color": color, "frames": n, "name": s}, ["fx"]),
    "effect": ("A screen effect.", {"kind": {"enum": ["flash", "shake", "speedLines", "zoomBlur", "glitch"]}, "at": time,
                                    "duration": n, "strength": n, "color": color}, ["kind"]),
    "marker": ("A timeline marker.", {"name": s, "at": time}, ["at"]),
    "captions": ("Captions on/off and style.", {"enabled": b, "style": s, "position": s}, []),
    "array": ("Copies in a line or ring.", {"target": tgt, "count": n, "step": v3, "radius": n, "faceCenter": b, "name": s}, ["target"]),
    "scatter": ("Copies scattered.", {"target": tgt, "count": n, "radius": n, "at": point, "name": s}, ["target"]),
    "length": ("The timeline's length.", {"seconds": n, "fps": n}, []),
    "command": ("A raw EditCommand.", {"command": ref("command")}, ["command"]),
}

action = {
    "type": "object",
    "required": ["do"],
    "properties": {"do": {"enum": sorted(verbs)}},
    "allOf": [],
    "additionalProperties": True,
}
for verb, (description, props, required) in sorted(verbs.items()):
    then = {"description": description, "properties": props}
    if required:
        then["required"] = required
    action["allOf"].append({"if": {"properties": {"do": {"const": verb}}}, "then": then})
defs["action"] = action

schema = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$id": "https://github.com/AhmedHeshamEG/3D-lowey/schemas/scene-script.v3.schema.json",
    "title": "3D-lowey Scene Script v3",
    "description": "Actions that speak relations, not coordinates: add from the Kit, place by relation (grounded, apart), "
                   "frame shots, light by recipe, animate by intent. One script = one Proposal = one undo step. v1/v2 scripts "
                   "upgrade on the way in. Short reference: GET /v2/actions (LoweyCore ScriptReference).",
    "type": "object",
    "required": ["title"],
    "properties": {
        "version": {"enum": [1, 2, 3]},
        "title": s,
        "commands": {"type": "array", "items": ref("command")},
        "actions": {"type": "array", "items": ref("action")},
    },
    "$defs": defs,
}
text = json.dumps(schema, indent=2, ensure_ascii=False) + "\n"
target = ROOT / "scene-script.v3.schema.json"
if "--check" in sys.argv:
    if target.read_text(encoding="utf-8") != text:
        sys.exit("schemas/scene-script.v3.schema.json is out of date: run python Tools/gen-script-schema.py")
    print(f"Scene Script v3 schema is up to date ({len(verbs)} verbs).")
else:
    target.write_text(text, encoding="utf-8", newline="\n")
    print(f"Wrote {target.name} ({len(verbs)} verbs).")
