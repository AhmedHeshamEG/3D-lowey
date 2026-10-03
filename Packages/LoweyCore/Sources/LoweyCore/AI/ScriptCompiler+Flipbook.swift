import Foundation

extension ScriptState {
    /// `{"do": "flipbook", "fx": "impactBurst", "anchor": "Screen 5", "at": {"word": "Nobody"}, "size": 0.6, "color": "#FFFFFF"}`:
    /// a drawn effect from the library, on an object (it follows it) or on the camera, starting at a moment.
    mutating func flipbook(_ action: JSONValue) throws {
        let fxName = string(action, "fx") ?? string(action, "kind") ?? ""
        guard let fx = FlipbookFX(rawValue: fxName) else {
            throw fail("unknown drawn effect “\(fxName)” (\(FlipbookFX.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        let anchor: FlipbookAnchor = try {
            guard let value = action["anchor"], value.stringValue != "camera" else { return .camera }
            return try .object(target(value))
        }()
        let start = try time(action["at"], default: context.now)
        let size = number(action, "size") ?? {
            guard case let .object(id) = anchor, let box = SceneBounds(library: context.library).worldBounds(of: id, in: scene) else { return 0.45 }
            return max(box.size.maxComponent * 1.4, 0.3)
        }()
        let color = try color(action["color"]) ?? .rgba(.white)
        let frameCount = number(action, "frames").map { max(Int($0), 1) }
        var track = FlipbookTrack(id: context.ids.next(TrackID.self).raw, name: name(action, fallback: fx.title), anchor: anchor, start: start)
        track.frames = fx.frames(count: frameCount, size: size, color: color, seed: UInt64(number(action, "seed") ?? 1),
                                 hold: Int(number(action, "hold") ?? 2), ids: &context.ids)
        track.loops = bool(action, "loop") ?? fx.loops
        if track.loops { track.end = try action["until"].map { try time($0) } ?? start + 2 }
        if let blend = string(action, "blend").flatMap(FlipbookBlend.init(rawValue:)) { track.blend = blend }
        if let offset = vec3(action["offset"]) { track.offset = Vec2(offset.x, offset.y) }
        try run(.setFlipbooks([FlipbookEdit(track)]), label: "\(fx.title) at \(format(start))")
    }
}
