import Foundation

/// Example scripts shipped with the app (and saved into the library on first use).
public enum ScriptExamples {
    public struct Example: Sendable, Hashable {
        public let name: String
        public let summary: String
        public let source: String
    }

    public static let all: [Example] = [forest, flock, crowd]

    public static let forest = Example(
        name: "Forest grows in",
        summary: "40 trees pop up in a wave from the centre, then sway in the wind.",
        source: """
        // Forest grows in: trees pop up in a wave from the centre, then sway in the wind.
        const rnd = lowey.random(7);
        const center = selection.length ? scene.get(selection[0]).worldPosition : [0, 0, 0];
        const trees = [];
        for (let i = 0; i < 40; i++) {
          const r = 1.5 + Math.sqrt(rnd()) * 9, a = rnd() * Math.PI * 2, s = 0.7 + rnd() * 0.7;
          const tree = lowey.group("Tree", { position: [center[0] + Math.cos(a) * r, 0, center[2] + Math.sin(a) * r], rotation: [0, rnd() * 360, 0] });
          lowey.add("cylinder", { name: "Trunk", parent: tree, scale: [0.16 * s, 0.7 * s, 0.16 * s], color: "#6B4428" });
          lowey.add("cone", { name: "Crown", parent: tree, position: [0, 0.55 * s, 0], scale: [1.0 * s, 1.7 * s, 1.0 * s], color: rnd() > 0.5 ? "#2F7D4A" : "#3E8F52" });
          trees.push(tree);
        }
        lowey.preset(trees, "popIn", time, { delay: 0.05, order: "distance", from: center, randomTiming: 0.6 });
        for (const tree of trees) {
          lowey.behavior(tree, { type: "windSway", angle: 3 + rnd() * 3, frequency: 0.35, direction: 30 }, { start: time + 2.5 });
        }
        lowey.log("Planted " + trees.length + " trees");
        """
    )

    public static let flock = Example(
        name: "Flock of birds",
        summary: "24 birds with flapping wings fly together as a flock (baked to keys).",
        source: """
        // Flock of birds: small birds flap their wings and fly as a flock (boids), baked to editable keys.
        const rnd = lowey.random(11);
        const birds = [];
        for (let i = 0; i < 24; i++) {
          const bird = lowey.group("Bird", { position: [(rnd() - 0.5) * 8, 6 + rnd() * 2, (rnd() - 0.5) * 8] });
          lowey.add("cone", { name: "Body", parent: bird, rotation: [90, 0, 0], position: [0, 0, -0.18], scale: [0.16, 0.36, 0.16], color: "#2B2B33" });
          for (const side of [-1, 1]) {
            const wing = lowey.add("plane", { name: "Wing", parent: bird, position: [side * 0.22, 0, 0], scale: [0.4, 1, 0.2], color: "#3A3A44" });
            lowey.behavior(wing, { type: "noise", position: [0, 0, 0], rotation: [0, 0, 40], frequency: 3 + rnd() });
          }
          birds.push(bird);
        }
        lowey.flock(birds, { duration: Math.max(duration - time, 4), center: [0, 7, 0], extent: [12, 2.5, 12], speed: 4, start: time });
        lowey.log("A flock of " + birds.length + " birds");
        """
    )

    public static let crowd = Example(
        name: "Crowd walks in",
        summary: "16 people walk in from the side and take their places in a grid.",
        source: """
        // Crowd walks in: people enter from the left and walk to their places, bobbing as they walk.
        const people = [];
        for (let i = 0; i < 16; i++) {
          const p = lowey.group("Person", { position: [-9 - (i % 4) * 0.9, 0, (Math.floor(i / 4) - 1.5) * 0.9] });
          lowey.add("cylinder", { name: "Legs", parent: p, scale: [0.3, 0.46, 0.3], color: "#2E3445" });
          lowey.add("cylinder", { name: "Body", parent: p, position: [0, 0.46, 0], scale: [0.38, 0.5, 0.3], color: "#5B6C8F" });
          lowey.add("sphere", { name: "Head", parent: p, position: [0, 0.98, 0], scale: [0.24, 0.26, 0.24], color: "#D9A27E" });
          lowey.behavior(p, { type: "bob", height: 0.04, period: 0.45, tilt: 2 });
          people.push(p);
        }
        const places = people.map((_, i) => [(i % 4) * 1.6, 0, Math.floor(i / 4) * 1.8]);
        lowey.crowdWalk(people, places, { speed: 1.4, start: time });
        lowey.log(people.length + " people walk in");
        """
    )
}
