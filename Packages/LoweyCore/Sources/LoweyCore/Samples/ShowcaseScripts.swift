import Foundation

/// The showcase samples as Scene Script v3 actions: Kit models placed by relation, so the sets read the way a
/// set dresser would describe them ("the lamp on the desk, the books beside it").
enum ShowcaseScripts {
    static func number(_ value: Double) -> String { String(format: "%.2f", value) }

    // MARK: Welcome island (Ink, golden hour)

    static let island = """
    {"do": "add", "shape": "cylinder", "name": "Sea", "at": [0, -0.3, 0], "size": [140, 0.3, 140], "color": "#3F7FA6", "onGround": false},
    {"do": "add", "shape": "cylinder", "name": "Beach", "at": [0, -0.05, 0], "size": [16, 0.3, 14], "color": "#E8D39B", "onGround": false},
    {"do": "add", "shape": "cylinder", "name": "Grass", "at": [0, 0, 0], "size": [13, 0.35, 11], "color": "#7FA65A", "onGround": false},
    {"do": "add", "asset": "kit.nature-tent-detailedclosed", "name": "Tent", "at": [2.4, 0.35, -1.6]},
    {"do": "add", "asset": "kit.nature-campfire-stones", "name": "Campfire", "relation": "in_front_of", "reference": "Tent", "offset": [0, 0, 0.6]},
    {"do": "add", "asset": "kit.nature-log", "name": "Log seat", "relation": "beside_left", "reference": "Campfire"},
    {"do": "add", "asset": "kit.nature-tree-pinetalla", "name": "Pine 1", "at": [-3.5, 0.35, -2.5]},
    {"do": "add", "asset": "kit.nature-tree-pinerounda", "name": "Pine 2", "at": [-1.8, 0.35, -3.6]},
    {"do": "add", "asset": "kit.nature-tree-oak", "name": "Oak", "at": [-5, 0.35, -0.6]},
    {"do": "add", "asset": "kit.nature-tree-palmtall", "name": "Palm", "at": [5.4, 0.35, 2.2]},
    {"do": "add", "asset": "kit.nature-rock-largea", "name": "Big rock", "at": [-2.8, 0.35, 2.8]},
    {"do": "add", "asset": "kit.nature-plant-bushlarge", "name": "Bush", "relation": "beside_right", "reference": "Big rock"},
    {"do": "add", "asset": "kit.nature-canoe", "name": "Canoe", "at": [7.6, -0.05, 6], "rotation": [0, -35, 0]},
    {"do": "particles", "preset": "fire", "name": "Fire", "at": "Campfire", "amount": 0.8},
    {"do": "light", "type": "point", "name": "Fire light", "at": "Campfire", "color": "#FF9A3C", "intensity": 2.4, "range": 6},
    {"do": "blob", "likeness": "hesham", "name": "Hesham", "at": [0.6, 0.35, 1.4], "facing": 15},
    {"do": "clip", "character": "Hesham", "clip": "Wave", "at": 2.4},
    {"do": "camera", "name": "Fly camera", "from": [0, 9, 22], "lookAt": [0, 0.8, 0], "focalLength": 32},
    {"do": "cameraMove", "camera": "Fly camera", "move": "crane", "subject": "Hesham", "at": 0, "duration": 4},
    {"do": "cameraMove", "camera": "Fly camera", "move": "orbit", "subject": [0, 0.6, 0], "at": 4, "duration": 6},
    {"do": "overlay", "shape": "title", "name": "Title", "text": "Welcome to 3D-lowey", "at": [0, 0.62], "size": 0.8},
    {"do": "preset", "target": "Title", "preset": "typewriter", "at": 0.6, "duration": 1.6},
    {"do": "preset", "target": "Title", "preset": "fadeOut", "at": 4.5, "duration": 0.6},
    {"do": "flipbook", "fx": "sparkle", "anchor": "Hesham", "at": 2.4, "until": 4.2},
    {"do": "cut", "camera": "Fly camera", "at": 0}
    """

    // MARK: 1 · The message (Ink, night)

    static func desk(at x: Double, animated: Bool) -> String {
        let ox = number(x)
        var actions = """
        {"do": "add", "shape": "cube", "name": "Study floor", "at": [\(ox), -0.02, 0], "size": [7, 0.02, 6], "color": "palette:3", "onGround": false},
        {"do": "add", "shape": "cube", "name": "Study wall", "at": [\(ox), 0, -1.4], "size": [7, 3.2, 0.1], "color": "palette:1"},
        {"do": "add", "asset": "kit.office-desk", "name": "Desk", "at": [\(ox), 0, -0.55]},
        {"do": "add", "asset": "kit.room-lamproundtable", "name": "Lamp", "relation": "on", "reference": "Desk", "offset": [-0.5, 0, -0.15]},
        {"do": "add", "asset": "kit.props-chest", "name": "Enigma", "relation": "on", "reference": "Desk", "offset": [0.25, 0, -0.1]},
        {"do": "scaleTo", "target": "Enigma", "meters": 0.18},
        {"do": "add", "asset": "kit.room-books", "name": "Books", "relation": "on", "reference": "Desk", "offset": [0.58, 0, -0.12]},
        {"do": "add", "shape": "cube", "name": "Army message", "size": [0.3, 0.006, 0.21], "color": "palette:0", "at": [\(ox), 0, 1.5]},
        {"do": "place", "target": "Army message", "relation": "on", "reference": "Desk", "offset": [-0.08, 0, 0.18]},
        {"do": "add", "asset": "kit.room-bookcaseopen", "name": "Bookcase", "relation": "beside_left", "reference": "Desk"},
        {"do": "add", "asset": "kit.office-chairdesk", "name": "Chair", "relation": "in_front_of", "reference": "Desk"},
        {"do": "light", "type": "point", "name": "Lamp light", "at": "Lamp", "color": "#FFB45C", "intensity": 2.6, "range": 4},
        {"do": "camera", "name": "Desk camera", "from": [\(number(x + 1.1)), 1.45, 2.3], "lookAt": "Army message", "focalLength": 42}
        """
        if animated {
            actions += """
            ,
            {"do": "cameraMove", "camera": "Desk camera", "move": "pushIn", "subject": "Army message", "at": 0.4, "duration": 4},
            {"do": "flipbook", "fx": "sparkle", "anchor": "Enigma", "at": 2, "until": 4, "color": "#FFE7A8"},
            {"do": "cut", "camera": "Desk camera", "at": 0}
            """
        }
        return actions
    }

    // MARK: 2 · Nobody could (Comic, dusk, on twos)

    static func room(at x: Double, animated: Bool) -> String {
        var actions = [
            ##"{"do": "add", "shape": "cube", "name": "Office floor", "at": [\##(number(x)), -0.02, 0], "size": [14, 0.02, 11], "##
                + ##""color": "palette:3", "onGround": false}"##,
            ##"{"do": "add", "shape": "cube", "name": "Office wall", "at": [\##(number(x)), 0, -4.4], "size": [14, 3.4, 0.1], "color": "palette:1"}"##
        ]
        var index = 0
        for z in [-3.0, -0.8, 1.4] {
            for dx in [-2.6, 0.0, 2.6] {
                index += 1
                let at = "[\(number(x + dx)), 0, \(number(z))]"
                actions.append(##"{"do": "add", "asset": "kit.office-desk", "name": "Desk \##(index)", "at": \##(at)}"##)
                actions.append(##"{"do": "add", "asset": "kit.office-computerscreen", "name": "Screen \##(index)", "##
                    + ##""relation": "on", "reference": "Desk \##(index)"}"##)
            }
        }
        actions += [
            ##"{"do": "set", "target": "Screen 5", "property": "emissive", "value": "#7FD4FF"}"##,
            ##"{"do": "set", "target": "Screen 5", "property": "emissiveIntensity", "value": 3}"##,
            ##"{"do": "set", "target": "Screen 5", "property": "accent", "value": true}"##,
            ##"{"do": "light", "type": "point", "name": "Screen light", "at": "Screen 5", "color": "#7FD4FF", "intensity": 2.2, "range": 5}"##,
            ##"{"do": "blob", "likeness": "hesham", "name": "Hesham", "at": [\##(number(x + 1.2)), 0, 0.4]}"##,
            ##"{"do": "place", "target": "Hesham", "relation": "in_front_of", "reference": "Desk 5"}"##,
            ##"{"do": "place", "target": "Hesham", "relation": "facing", "reference": "Screen 5"}"##,
            ##"{"do": "camera", "name": "Room camera", "from": [\##(number(x + 0.4)), 3.4, 7.2], "lookAt": "Desk 5", "focalLength": 30}"##
        ]
        if animated {
            actions += [
                ##"{"do": "clip", "character": "Hesham", "clip": "Type", "at": 0}"##,
                ##"{"do": "cameraMove", "camera": "Room camera", "move": "pushIn", "subject": "Screen 5", "at": 1, "duration": 3}"##,
                ##"{"do": "flipbook", "fx": "impactBurst", "anchor": "Screen 5", "at": 3.2, "color": "#FFFFFF"}"##,
                ##"{"do": "cut", "camera": "Room camera", "at": 0}"##
            ]
        }
        return actions.joined(separator: ",\n")
    }

    // MARK: 3 · The secret (Sketch, night, one accent)

    static func cave(at x: Double, animated: Bool) -> String {
        let ox = number(x)
        var actions = """
        {"do": "add", "shape": "cube", "name": "Cave floor", "at": [\(ox), -0.02, 0], "size": [14, 0.02, 14], "color": "palette:6", "onGround": false},
        {"do": "add", "asset": "kit.lab-enemy-eyedrone", "name": "Robot", "at": [\(ox), 0, 0]},
        {"do": "transform", "target": "Robot", "position": [\(ox), 0.8, 0]},
        {"do": "set", "target": "Robot", "property": "accent", "value": true},
        {"do": "add", "asset": "kit.nature-rock-talla", "name": "Rock 1", "at": [\(number(x + 3)), 0, 0]},
        {"do": "add", "asset": "kit.nature-rock-largea", "name": "Rock 2", "at": [\(number(x + 3)), 0, 3]},
        {"do": "add", "asset": "kit.nature-stone-talla", "name": "Rock 3", "at": [\(number(x - 3)), 0, 3]},
        {"do": "add", "asset": "kit.nature-rock-largeb", "name": "Rock 4", "at": [\(number(x - 3)), 0, 0]},
        {"do": "add", "asset": "kit.nature-stone-largea", "name": "Rock 5", "at": [\(number(x - 3)), 0, -3]},
        {"do": "add", "asset": "kit.nature-rock-talla", "name": "Rock 6", "at": [\(number(x + 3)), 0, -3]},
        {"do": "scaleTo", "target": ["Rock 1", "Rock 6"], "meters": 2.8},
        {"do": "place", "target": ["Rock 1", "Rock 2", "Rock 3", "Rock 4", "Rock 5", "Rock 6"], "relation": "around", "reference": "Robot", "radius": 3.6},
        {"do": "text", "name": "Question", "text": "?", "at": [\(ox), 1.7, 0], "size": 0.55, "color": "#FFC46B", "glow": 2},
        {"do": "light", "type": "point", "name": "Question light", "at": "Question", "color": "#FFC46B", "intensity": 2, "range": 5},
        {"do": "camera", "name": "Cave camera", "from": [\(number(x + 1.4)), 0.45, 3.4], "lookAt": "Robot", "focalLength": 35}
        """
        if animated {
            actions += """
            ,
            {"do": "preset", "target": "Robot", "preset": "float", "at": 0, "duration": 6, "strength": 0.6},
            {"do": "preset", "target": "Question", "preset": "popIn", "at": 1.2, "duration": 0.5},
            {"do": "flipbook", "fx": "sparkle", "anchor": "Question", "at": 1.4, "until": 5, "color": "#FFE7A8"},
            {"do": "cut", "camera": "Cave camera", "at": 0}
            """
        }
        return actions
    }

    // MARK: 4 · The story (narrated, cut on the words)

    static let story = """
    {"do": "cut", "camera": "Desk camera", "at": 0},
    {"do": "cameraMove", "camera": "Desk camera", "move": "pushIn", "subject": "Army message", "at": 0.3, "duration": 2.8},
    {"do": "overlay", "shape": "label", "name": "1941 label", "text": "BERLIN · 1941", "follow": "Army message", "at": [0, 0.18], "size": 0.9},
    {"do": "preset", "target": "1941 label", "preset": "typewriter", "at": {"word": "1941,", "offset": -0.3}, "duration": 0.8},
    {"do": "preset", "target": "1941 label", "preset": "fadeOut", "at": {"word": "encrypted", "edge": "end"}, "duration": 0.3},
    {"do": "effect", "kind": "glitch", "at": {"word": "Enigma."}, "duration": 0.5, "strength": 0.8},
    {"do": "flipbook", "fx": "sparkle", "anchor": "Enigma", "at": {"word": "Enigma."}, "until": 3.2, "color": "#FFE7A8"},
    {"do": "cut", "camera": "Room camera", "at": {"word": "People"}},
    {"do": "clip", "character": "Hesham", "clip": "Type", "at": 0},
    {"do": "cameraMove", "camera": "Room camera", "move": "pushIn", "subject": "Screen 5", "at": {"word": "People"}, "duration": 3.4},
    {"do": "overlay", "shape": "title", "name": "2005", "text": "2005 → today", "at": [0, 0.7], "size": 0.8},
    {"do": "preset", "target": "2005", "preset": "typewriter", "at": {"word": "2005."}, "duration": 0.5},
    {"do": "preset", "target": "2005", "preset": "fadeOut", "at": {"word": "Nobody", "offset": -0.3}, "duration": 0.25},
    {"do": "effect", "kind": "flash", "at": {"word": "Nobody"}, "strength": 0.6, "color": "#FFFFFF"},
    {"do": "flipbook", "fx": "impactBurst", "anchor": "Screen 5", "at": {"word": "Nobody"}, "color": "#FFFFFF"},
    {"do": "cut", "camera": "Cave camera", "at": {"word": "Last"}, "transition": "dipToBlack", "duration": 0.5},
    {"do": "preset", "target": "Robot", "preset": "float", "at": {"word": "Last"}, "duration": 4.5, "strength": 0.6},
    {"do": "preset", "target": "Question", "preset": "popIn", "at": {"word": "secret"}, "duration": 0.4},
    {"do": "flipbook", "fx": "sparkle", "anchor": "Question", "at": {"word": "secret"}, "until": 12.6, "color": "#FFE7A8"},
    {"do": "captions", "style": "punchy", "position": "bottom"}
    """
}
