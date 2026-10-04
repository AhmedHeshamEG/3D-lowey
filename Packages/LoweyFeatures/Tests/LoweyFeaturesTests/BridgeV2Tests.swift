import HmmBridge
import LoweyCore
@testable import LoweyFeatures
import XCTest

/// MCP v2's endpoints through the real router, paired, on an open project: what `hmm-bridge`'s 16 tools call.
@MainActor
final class BridgeV2Tests: XCTestCase {
    /// Kept alive for the whole run (editors hold the app unowned).
    private var app: AppModel?

    private func pairedRouter() async throws -> (BridgeRouter, String, AppModel) {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Bridge \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.ink.id)
        let editor = try XCTUnwrap(app.editor)
        editor.addPrimitive(.cube)
        let authority = PairingAuthority(store: InMemoryClientStore())
        let router = BridgeRouter(authority: authority, routes: app.bridge.routes()) {
            BridgeHello(app: "lowey", appVersion: "test", device: "iPad", pairing: false)
        }
        let code = authority.startPairing()
        let pair = await router.handle(HTTPRequest(method: "POST", path: "/v1/pair", body: Data(#"{"code":"\#(code.digits)","client":"Test"}"#.utf8)),
                                       from: "192.168.1.20")
        let token = try XCTUnwrap(JSONSerialization.jsonObject(with: pair.body) as? [String: String])["token"] ?? ""
        return (router, token, app)
    }

    private func call(_ router: BridgeRouter, _ token: String, _ method: String, _ path: String, query: [String: String] = [:],
                      json: String? = nil) async -> HTTPResponse {
        await router.handle(HTTPRequest(method: method, path: path, query: query, headers: ["authorization": "Bearer \(token)"],
                                        body: Data((json ?? "").utf8)), from: "192.168.1.20")
    }

    private func object(_ response: HTTPResponse) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any], String(decoding: response.body, as: UTF8.self))
    }

    func testReadingStatusProjectAssetsAndActions() async throws {
        let (router, token, _) = try await pairedRouter()
        let status = try await object(call(router, token, "GET", "/v2/status"))
        XCTAssertEqual(status["bridge"] as? Int, 2)
        XCTAssertNotNil(status["project"] as? String)
        let project = try await object(call(router, token, "GET", "/v2/project"))
        XCTAssertTrue((project["summary"] as? String)?.contains("objects") == true)
        XCTAssertEqual(project["look"] as? String, "ink")
        let assets = await call(router, token, "GET", "/v2/assets", query: ["q": "desk", "limit": "3"])
        XCTAssertEqual(assets.status, 200)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: assets.body) as? [Any])
        let missing = await call(router, token, "GET", "/v2/thumbnail", query: ["id": "kit.nothing"])
        XCTAssertEqual(missing.status, 404)
        let actions = await call(router, token, "GET", "/v2/actions")
        XCTAssertTrue(String(decoding: actions.body, as: UTF8.self).contains("Scene Script v3"))
        let transcript = await call(router, token, "GET", "/v2/transcript")
        XCTAssertEqual(transcript.status, 200)
        let unpaired = await router.handle(HTTPRequest(method: "GET", path: "/v2/status"), from: "192.168.1.20")
        XCTAssertEqual(unpaired.status, 401, "v2 is behind pairing too")
    }

    func testADryRunThenCommitIsOneUndoStepWithAnObserve() async throws {
        let (router, token, app) = try await pairedRouter()
        let editor = try XCTUnwrap(app.editor)
        let before = editor.baseScene.objects.count
        let actions = #"[{"do": "add", "shape": "sphere", "name": "Moon", "at": [2, 0, 0]}, "#
            + #"{"do": "place", "target": "Moon", "relation": "beside_left", "reference": "Cube"}]"#
        let dry = try await object(call(
            router,
            token,
            "POST",
            "/v2/build",
            json: #"{"title": "Moon", "dry_run": true, "views": ["camera", "top"], "actions": \#(actions)}"#
        ))
        let proposal = try XCTUnwrap(dry["proposal_id"] as? String)
        XCTAssertEqual(dry["applied"] as? Bool, false)
        XCTAssertEqual(editor.baseScene.objects.count, before, "a dry run changes nothing")
        let observe = try XCTUnwrap(dry["observe"] as? [String: Any])
        XCTAssertNotNil((observe["images"] as? [String: String])?["top"], "the result, seen from above")
        XCTAssertTrue((observe["summary"] as? String)?.isEmpty == false)
        app.bridge.autoApplyThisSession = true
        let committed = try await object(call(router, token, "POST", "/v2/commit", json: #"{"action": "commit", "proposal_id": "\#(proposal)"}"#))
        XCTAssertEqual(committed["applied"] as? Bool, true)
        XCTAssertEqual(editor.baseScene.objects.count, before + 1)
        let again = await call(router, token, "POST", "/v2/commit", json: #"{"action": "commit", "proposal_id": "\#(proposal)"}"#)
        XCTAssertEqual(again.status, 404, "a proposal commits once")
        let undone = try await object(call(router, token, "POST", "/v2/commit", json: #"{"action": "undo", "steps": 1}"#))
        XCTAssertEqual(undone["undone"] as? Int, 1)
        XCTAssertEqual(editor.baseScene.objects.count, before, "the whole batch was one undo step")
        let bad = await call(router, token, "POST", "/v2/build", json: #"{"actions": [{"do": "place", "target": "Cube", "relation": "sideways"}]}"#)
        XCTAssertEqual(bad.status, 422)
        XCTAssertTrue(String(decoding: bad.body, as: UTF8.self).contains("beside_left"), "errors say what would work")
    }

    func testDirectorVerbsApplyThroughBuild() async throws {
        let (router, token, app) = try await pairedRouter()
        app.bridge.autoApplyThisSession = true
        let editor = try XCTUnwrap(app.editor)
        let actions = #"[{"do": "frameShot", "subject": "Cube", "shotType": "medium", "camera": "Shot 1"}, "#
            + #"{"do": "lighting", "recipe": "key-warm-world-cool", "subject": "Cube"}, {"do": "intent", "target": "Cube", "what": "enter", "at": 0.5}]"#
        let reply = try await object(call(router, token, "POST", "/v2/build", json: #"{"title": "Shot", "actions": \#(actions)}"#))
        XCTAssertEqual(reply["applied"] as? Bool, true)
        XCTAssertTrue(editor.baseScene.objects.values.contains { $0.name == "Shot 1" })
        XCTAssertTrue(editor.baseScene.objects.values.contains { $0.name == "Key light" })
        XCTAssertFalse(editor.timeline.tracks.isEmpty, "the cube enters")
        let observe = try XCTUnwrap(reply["observe"] as? [String: Any])
        let report = try XCTUnwrap(observe["report"] as? [String: Any])
        XCTAssertEqual(report["camera"] as? String, "Shot 1")
    }

    func testObserveAndContactSheet() async throws {
        let (router, token, _) = try await pairedRouter()
        let observed = try await object(call(router, token, "POST", "/v2/observe",
                                             json: #"{"views": ["top", "front", "side", "value", "silhouette"], "subject": "Cube", "long_side": 480}"#))
        let images = try XCTUnwrap(observed["images"] as? [String: String])
        XCTAssertEqual(Set(images.keys), ["camera", "top", "front", "side", "value", "silhouette"])
        let report = try XCTUnwrap(observed["report"] as? [String: Any])
        let objects = try XCTUnwrap(report["objects"] as? [[String: Any]])
        XCTAssertTrue(objects.contains { $0["name"] as? String == "Cube" && $0["grounded"] as? Bool == true })
        XCTAssertNotNil((report["frame"] as? [String: Any])?["contrast"], "measured from the render")
        let sheet = try await object(call(router, token, "POST", "/v2/contact_sheet", json: #"{"frames": 4}"#))
        XCTAssertNotNil(sheet["image"] as? String)
        XCTAssertEqual(((sheet["report"] as? [String: Any])?["frames"] as? [Any])?.count, 4)
    }
}
