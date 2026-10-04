import HmmBridge
import LoweyCore
import LoweyEngine
@testable import LoweyFeatures
import XCTest

@MainActor
final class BridgeSecurityTests: XCTestCase {
    func testUnpairedRequestsAreRefusedAndAPairedLaptopGetsIn() async throws {
        let app = AppModel()
        let authority = PairingAuthority(store: InMemoryClientStore())
        let router = BridgeRouter(authority: authority, routes: app.bridge.routes()) {
            BridgeHello(app: "lowey", appVersion: "test", device: "iPad", pairing: false)
        }
        let scene = HTTPRequest(method: "GET", path: "/v1/scene")
        let unpaired = await router.handle(scene, from: "192.168.1.20")
        XCTAssertEqual(unpaired.status, 401, "no token, no scene")
        let outside = await router.handle(scene, from: "8.8.8.8")
        XCTAssertEqual(outside.status, 403, "only the local network")
        let guess = await router.handle(HTTPRequest(method: "POST", path: "/v1/pair", body: Data(#"{"code":"000000"}"#.utf8)), from: "192.168.1.20")
        XCTAssertEqual(guess.status, 409, "no permanent code: pairing only while a code is shown")
        let code = authority.startPairing()
        let pair = await router.handle(HTTPRequest(method: "POST", path: "/v1/pair", body: Data(#"{"code":"\#(code.digits)","client":"Laptop"}"#.utf8)),
                                       from: "192.168.1.20")
        XCTAssertEqual(pair.status, 200)
        let token = try XCTUnwrap(JSONSerialization.jsonObject(with: pair.body) as? [String: String])["token"]
        let paired = await router.handle(HTTPRequest(method: "GET", path: "/v1/scene", headers: ["authorization": "Bearer \(token ?? "")"]),
                                         from: "192.168.1.20")
        XCTAssertEqual(paired.status, 409, "in, and told to open a project first")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: BridgeModel.wantsOnKey), "the bridge is off until switched on")
    }

    func testRenderNamesCannotEscapeTheFolder() {
        XCTAssertTrue(BridgeModel.isSafeName("shot.mp4"))
        XCTAssertFalse(BridgeModel.isSafeName("../project.json"))
        XCTAssertFalse(BridgeModel.isSafeName("a/b.png"))
        XCTAssertFalse(BridgeModel.isSafeName(".hidden"))
    }
}

@MainActor
final class EditorFlowTests: XCTestCase {
    /// The app model outlives its editors (the editor holds it unowned), as it does in the app: XCTest keeps each test
    /// case alive for the whole run, so the model is still there when an editor's autosave or thumbnail finishes.
    private var app: AppModel?

    private func makeEditor() throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Test \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.ink.id)
        return try XCTUnwrap(app.editor)
    }

    func testAddUndoRedoAndKeyframeMode() throws {
        let editor = try makeEditor()
        XCTAssertEqual(editor.look.presetID, "ink")
        editor.addPrimitive(.cube)
        XCTAssertEqual(editor.selection.count, 1)
        let cube = try XCTUnwrap(editor.singleSelection)
        XCTAssertNotNil(cube[.bevel], "new primitives are bevelled")
        editor.undo()
        XCTAssertNil(editor.baseScene.objects[cube.id])
        editor.redo()
        XCTAssertNotNil(editor.baseScene.objects[cube.id])
        editor.setSelection([cube.id])
        editor.translateSelection(by: Vec3(1, 0, 0), gesture: "compose")
        editor.endGesture()
        XCTAssertTrue(editor.timeline.tracks.isEmpty, "Compose never creates keys")
        editor.timelineMode = .keyframe
        editor.setTime(1)
        editor.translateSelection(by: Vec3(1, 0, 0), gesture: "keyframe")
        editor.endGesture()
        XCTAssertFalse(editor.timeline.tracks.isEmpty, "Keyframe mode keys the change at the playhead")
    }

    func testLooksMyLookAndOverride() throws {
        let editor = try makeEditor()
        editor.setLookPreset(LookPreset.comic.id)
        XCTAssertEqual(editor.lookPreset.id, "comic")
        editor.duplicateLook(LookPreset.comic)
        let mine = try XCTUnwrap(editor.document.project.customLooks.first)
        XCTAssertEqual(mine.name, "My Comic")
        XCTAssertEqual(editor.look.presetID, mine.id)
        editor.updateCustomLook(mine.id) { $0.lines.width = 4 }
        XCTAssertEqual(editor.document.project.customLooks.first?.lines.width, 4)
        editor.addPrimitive(.sphere)
        editor.setLookOverride(LookPreset.clay.id)
        XCTAssertEqual(editor.singleSelection?.lookOverride, "clay")
        editor.deleteCustomLook(mine.id)
        XCTAssertEqual(editor.look.presetID, "comic", "deleting a My Look falls back to the Look it came from")
    }

    func testShadowBrushStrokesAreOneUndoStep() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.sphere)
        let sphere = try XCTUnwrap(editor.singleSelection)
        let top = editor.scene.worldTransform(of: sphere.id).position + Vec3(0, 1, 0)
        for step in 0 ..< 5 {
            editor.paintShadow(on: sphere.id, at: top + Vec3(Double(step) * 0.1, 0, 0), pressure: 1, gesture: "stroke")
        }
        editor.endGesture()
        XCTAssertFalse(editor.baseScene.objects[sphere.id]?.shadowDabs.isEmpty ?? true)
        XCTAssertLessThan(editor.baseScene.objects[sphere.id]?.shadowDabs.first?.amount ?? 0, 0, "pushes the shadow in")
        editor.undo()
        XCTAssertTrue(editor.baseScene.objects[sphere.id]?.shadowDabs.isEmpty ?? false, "the whole stroke undoes at once")
    }

    func testTheSessionReopensWhereYouLeftIt() async throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        editor.frameShot(.medium, composition: .center)
        editor.setTime(1.5)
        editor.openPanel = .look
        editor.timelineCollapsed = true
        let saved = SessionRestoration(editor)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "restoration-\(UUID().uuidString)"))
        saved.save(to: defaults)
        XCTAssertEqual(SessionRestoration.load(from: defaults), saved)
        XCTAssertEqual(saved.panel, "look")
        XCTAssertTrue(saved.directorView, "framing a shot turns the Director view on")
        editor.setTime(0)
        editor.openPanel = nil
        editor.timelineCollapsed = false
        editor.setDirectorView(false)
        await saved.apply(to: editor)
        XCTAssertEqual(editor.time, 1.5, accuracy: 1e-9)
        XCTAssertEqual(editor.openPanel, .look)
        XCTAssertTrue(editor.timelineCollapsed)
        XCTAssertTrue(editor.directorView)
        SessionRestoration.clear(in: defaults)
        XCTAssertNil(SessionRestoration.load(from: defaults))
    }

    func testTheMonitorDrawsTheShotAsItExports() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        editor.frameShot(.medium, composition: .center)
        let view = try StageView(device: RenderDevice.sharedDevice())
        XCTAssertNil(editor.monitorFrame(for: view), "nothing to draw at zero size")
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        let frame = try XCTUnwrap(editor.monitorFrame(for: view))
        XCTAssertNotNil(frame.shotCamera, "through the shot camera")
        XCTAssertEqual(editor.monitorCaption, try editor.baseScene.objects[XCTUnwrap(editor.shotCamera)]?.name)
    }

    func testFrameShotPlacesACameraOnTheSubject() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        editor.frameShot(.closeUp, composition: .leftThird)
        let camera = try XCTUnwrap(editor.baseScene.cameras.first)
        XCTAssertEqual(editor.baseScene.activeCamera, camera)
        XCTAssertTrue(editor.directorView)
    }
}

final class LayoutMathTests: XCTestCase {
    func testDirectorFrameFitsTheDeliveryShape() {
        let wide = DirectorFrame.rect(in: CGSize(width: 1000, height: 800), aspect: 16.0 / 9)
        XCTAssertEqual(wide.width, 1000)
        XCTAssertEqual(wide.height, 562.5, accuracy: 0.01)
        XCTAssertEqual(wide.midY, 400, accuracy: 0.01)
        let tall = DirectorFrame.rect(in: CGSize(width: 1000, height: 800), aspect: 9.0 / 16)
        XCTAssertEqual(tall.height, 800)
        XCTAssertEqual(tall.width, 450, accuracy: 0.01)
    }

    func testFormatting() {
        XCTAssertEqual(TimeFormat.clock(61.5), "01:01.50")
        XCTAssertEqual(NumberFormat.short(2.0), "2")
        XCTAssertEqual(NumberFormat.short(2.456), "2.46")
        XCTAssertEqual("topHat".spacedTitle, "Top hat")
    }
}
