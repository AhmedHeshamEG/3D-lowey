import Foundation

/// Upgrades older Scene Scripts to v3 where the meaning is certain: aliases become the canonical verbs, and v2's
/// `place` (find a library model) becomes `add` with `asset` (v3's `place` is a relation). Everything v3 can't infer
/// (which coordinates meant "on the desk") is left as it was: v3 still runs it.
public enum ScriptMigration {
    static let canonical = ["animate": "preset", "move": "cameraMove", "person": "blob", "duration": "length", "keys": "key",
                            "scale_to": "scaleTo", "remove": "delete"]

    public static func upgraded(_ script: SceneScript) -> SceneScript {
        guard script.version < SceneScript.relationsVersion else { return script }
        var result = script
        result.version = SceneScript.relationsVersion
        result.actions = script.actions.map(upgraded)
        return result
    }

    static func upgraded(_ action: JSONValue) -> JSONValue {
        guard var fields = action.objectValue, let verb = (fields["do"] ?? fields["action"])?.stringValue else { return action }
        fields["action"] = nil
        if verb == "place", fields["relation"] == nil {
            fields["do"] = .string("add")
            if fields["asset"] == nil, let query = fields["query"] {
                fields["asset"] = query
                fields["query"] = nil
            }
        } else {
            fields["do"] = .string(canonical[verb] ?? verb)
        }
        return .object(fields)
    }
}
