import Foundation
import LoweyCore
import LoweyRender
import Observation
import UIKit

/// The AI & laptop bridge: settings, pairing, and the endpoints (backed by the open editor).
/// AI proposes, you decide: scripts wait for your OK on the iPad unless you switch on auto-apply.
@Observable
@MainActor
final class BridgeModel {
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored let auth: BridgeAuth
    @ObservationIgnored private var server: BridgeServer?
    var isOn = false
    var status = "Off"
    /// Apply scripts without asking (they're still one undo step each).
    var autoApply = UserDefaults.standard.bool(forKey: "bridge.autoApply") {
        didSet { UserDefaults.standard.set(autoApply, forKey: "bridge.autoApply") }
    }

    var pairedCount: Int { auth.pairedTokens.count }
    var code: String { auth.code }
    var address: String { "\(BridgeServer.localAddress() ?? "this iPad's IP"):\(BridgeServer.httpPort.rawValue)" }

    init(app: AppModel) {
        self.app = app
        let saved = Set(UserDefaults.standard.stringArray(forKey: "bridge.tokens") ?? [])
        auth = BridgeAuth(tokens: saved)
    }

    func toggle(_ on: Bool) {
        if on { start() } else { stop() }
    }

    func start() {
        guard server == nil else { return }
        let server = BridgeServer(router: BridgeRouter(auth: auth, routes: routes()))
        server.onStatus = { [weak self] message in self?.status = message }
        do {
            try server.start()
            self.server = server
            isOn = true
            status = "On — pair from the laptop with the code"
        } catch {
            status = "Couldn't start: \(error.localizedDescription)"
        }
    }

    func stop() {
        server?.stop()
        server = nil
        isOn = false
        status = "Off"
    }

    func forgetDevices() {
        auth.reset()
        saveTokens()
    }

    func saveTokens() {
        UserDefaults.standard.set(Array(auth.pairedTokens), forKey: "bridge.tokens")
    }

    /// Tells connected clients something changed (they re-read what they need).
    func notify(_ type: String, _ extra: [String: String] = [:]) {
        server?.broadcast(extra.merging(["type": type]) { a, _ in a })
    }

    // MARK: Endpoints

    private func routes() -> [BridgeRoute] {
        [
            BridgeRoute("GET", "/v1/status", requiresAuth: false) { [weak self] _ in await self?.statusResponse() ?? .error(500, "gone") },
            BridgeRoute("GET", "/v1/scene") { [weak self] request in await self?.scene(request) ?? .error(500, "gone") },
            BridgeRoute("GET", "/v1/scene/full") { [weak self] _ in await self?.fullScene() ?? .error(500, "gone") },
            BridgeRoute("GET", "/v1/look") { [weak self] _ in await self?.lookResponse() ?? .error(500, "gone") },
            BridgeRoute("GET", "/v1/assets") { [weak self] request in await self?.assets(request) ?? .error(500, "gone") },
            BridgeRoute("GET", "/v1/transcript") { [weak self] _ in await self?.transcriptResponse() ?? .error(500, "gone") },
            BridgeRoute("GET", "/v1/actions") { _ in .data(Data(ScriptReference.text.utf8), type: "text/markdown; charset=utf-8") },
            BridgeRoute("POST", "/v1/script") { [weak self] request in await self?.script(request) ?? .error(500, "gone") },
            BridgeRoute("POST", "/v1/snapshot") { [weak self] request in await self?.snapshot(request) ?? .error(500, "gone") },
            BridgeRoute("POST", "/v1/playhead") { [weak self] request in await self?.playhead(request) ?? .error(500, "gone") },
            BridgeRoute("POST", "/v1/undo") { [weak self] _ in await self?.undoResponse() ?? .error(500, "gone") },
            BridgeRoute("GET", "/v1/renders") { [weak self] _ in await self?.renders() ?? .error(500, "gone") },
            BridgeRoute("GET", "/v1/renders/*") { [weak self] request in await self?.render(request) ?? .error(500, "gone") },
            BridgeRoute("POST", "/v1/library/import") { [weak self] request in await self?.importAsset(request) ?? .error(500, "gone") },
            BridgeRoute("POST", "/v1/audio/import") { [weak self] request in await self?.importAudio(request) ?? .error(500, "gone") },
            BridgeRoute("POST", "/v1/media/import") { [weak self] request in await self?.importMedia(request) ?? .error(500, "gone") }
        ]
    }

    private func withEditor(_ body: (EditorModel) async -> HTTPResponse) async -> HTTPResponse {
        guard let editor = app.editor else { return .error(409, "Open a project on the iPad first") }
        return await body(editor)
    }

    private func lookResponse() async -> HTTPResponse {
        await withEditor { .json($0.look) }
    }

    private func transcriptResponse() async -> HTTPResponse {
        await withEditor { .json(TranscriptSummary($0.timeline)) }
    }

    private func undoResponse() async -> HTTPResponse {
        await withEditor { editor in
            editor.undo()
            notify("scene")
            return .json(["undone": true])
        }
    }

    private func statusResponse() -> HTTPResponse {
        saveTokens()
        let info: [String: String] = [
            "app": Branding.appName,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            "project": app.editor?.document.project.name ?? "",
            "scene": app.editor?.baseScene.name ?? "",
            "autoApply": autoApply ? "true" : "false"
        ]
        return .json(info)
    }

    private func scene(_ request: HTTPRequest) async -> HTTPResponse {
        await withEditor { editor in
            editor.refreshOperationsLibrary()
            let depth = Int(request.query["depth"] ?? "2") ?? 2
            return .json(SceneSummary(editor.document, bounds: editor.operations.bounds, depth: depth))
        }
    }

    private func fullScene() async -> HTTPResponse {
        await withEditor { editor in
            guard let data = try? LoweyJSON.encode(editor.baseScene) else { return .error(500, "couldn't encode") }
            return .data(data, type: "application/json")
        }
    }

    private func assets(_ request: HTTPRequest) -> HTTPResponse {
        .json(AssetSummary.search(request.query["q"] ?? "", in: app.library.manifest, limit: Int(request.query["limit"] ?? "40") ?? 40))
    }

    private func script(_ request: HTTPRequest) async -> HTTPResponse {
        await withEditor { editor in
            guard let script = try? LoweyJSON.decode(SceneScript.self, from: request.body) else {
                return .error(400, "The body must be a Scene Script: {\"title\": …, \"actions\": [{\"do\": …}]} — see GET /v1/actions")
            }
            let dryRun = ["1", "true", "yes"].contains(request.query["dryRun"]?.lowercased() ?? "")
            let preview: ScriptPreview
            do {
                preview = try ScriptCompiler.preview(script, document: editor.document, context: editor.scriptContext())
            } catch {
                return .error(422, String(describing: error))
            }
            if dryRun {
                return .json(ScriptReply(applied: false, preview: preview.lines, report: preview.report, created: [:], message: "dry run"))
            }
            let source = request.headers["x-lowey-client"] ?? "AI"
            if !autoApply {
                let accepted = await editor.propose(script, preview: preview, source: source)
                guard accepted else {
                    return .json(ScriptReply(applied: false, preview: preview.lines, report: preview.report, created: [:],
                                             message: "Hesham said no (or didn't answer) — ask what to change"))
                }
            }
            switch editor.applyScript(script) {
            case let .success(result):
                notify("scene")
                return .json(ScriptReply(applied: true, preview: preview.lines, report: result.report,
                                         created: result.created.mapValues(\.raw), message: "applied (one undo step)"))
            case let .failure(error):
                return .error(422, String(describing: error))
            }
        }
    }

    private func snapshot(_ request: HTTPRequest) async -> HTTPResponse {
        await withEditor { editor in
            struct Options: Decodable {
                var framing: String?
                var longSide: Int?
                var camera: Bool?
                var time: Double?
            }
            let options = (try? request.json(Options.self)) ?? Options()
            if let time = options.time { editor.setTime(time) }
            let framing = Framing(rawValue: options.framing ?? "16:9") ?? .landscape
            guard let url = await editor.exportSnapshot(framing: framing, longSide: min(options.longSide ?? 1280, 2560),
                                                        throughCamera: options.camera ?? true),
                let data = try? Data(contentsOf: url) else { return .error(500, "Snapshot failed") }
            return .data(data, type: "image/png")
        }
    }

    private func playhead(_ request: HTTPRequest) async -> HTTPResponse {
        await withEditor { editor in
            struct Body: Decodable { var time: Double }
            guard let body = try? request.json(Body.self) else { return .error(400, "{\"time\": seconds}") }
            editor.setTime(body.time)
            return .json(["time": editor.time])
        }
    }

    private func renders() async -> HTTPResponse {
        await withEditor { editor in
            let files = (try? FileManager.default.contentsOfDirectory(at: editor.rendersFolder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return .json(files.map(\.lastPathComponent).sorted())
        }
    }

    private func render(_ request: HTTPRequest) async -> HTTPResponse {
        await withEditor { editor in
            let name = String(request.path.dropFirst("/v1/renders/".count))
            guard !name.contains(".."), !name.contains("/") else { return .error(400, "bad name") }
            let url = editor.rendersFolder.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return .error(404, "No render called \(name)") }
            let type = switch url.pathExtension.lowercased() {
            case "mp4": "video/mp4"
            case "mov": "video/quicktime"
            case "png": "image/png"
            case "srt": "application/x-subrip"
            case "glb": "model/gltf-binary"
            case "usdz": "model/vnd.usdz+zip"
            default: "application/octet-stream"
            }
            return .data(data, type: type)
        }
    }

    /// Files from the laptop (models, generator output) land in the library.
    private func importAsset(_ request: HTTPRequest) async -> HTTPResponse {
        guard let name = request.query["name"], !name.contains("/"), !name.contains(".."), !request.body.isEmpty else {
            return .error(400, "POST the file as the body with ?name=model.glb")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            try request.body.write(to: url)
            let count = await app.library.importFiles([url])
            try? FileManager.default.removeItem(at: folder)
            guard count > 0 else { return .error(422, "3D-lowey couldn't import \(name)") }
            app.show("From the laptop: \(name) is in your library")
            notify("library")
            return .json(["imported": name])
        } catch {
            return .error(500, error.localizedDescription)
        }
    }

    /// A picture or video (a clip, a Manim render) into the open scene's frame: ?name=graph.mov&at=seconds
    private func importMedia(_ request: HTTPRequest) async -> HTTPResponse {
        await withEditor { editor in
            guard let name = request.query["name"], !name.contains("/"), !name.contains(".."), !request.body.isEmpty else {
                return .error(400, "POST the file as the body with ?name=graph.mov&at=2.5")
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lowey-media-\(UUID().uuidString)")
            let url = folder.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try request.body.write(to: url)
            } catch {
                return .error(500, error.localizedDescription)
            }
            let at = request.query["at"].flatMap(Double.init)
            guard let id = await editor.importMedia(url, at: at) else { return .error(422, "Couldn't add \(name)") }
            try? FileManager.default.removeItem(at: folder)
            notify("scene")
            return .json(["added": name, "id": id.raw, "name": editor.baseScene.objects[id]?.name ?? name])
        }
    }

    private func importAudio(_ request: HTTPRequest) async -> HTTPResponse {
        await withEditor { editor in
            guard let name = request.query["name"], !name.contains("/"), !name.contains(".."), !request.body.isEmpty else {
                return .error(400, "POST the audio as the body with ?name=voiceover.m4a&role=voiceover")
            }
            let role = AudioRole(rawValue: request.query["role"] ?? "voiceover") ?? .voiceover
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do {
                try request.body.write(to: url)
            } catch {
                return .error(500, error.localizedDescription)
            }
            editor.importAudio([url], role: role)
            return .json(["imported": name, "role": role.rawValue])
        }
    }
}

struct ScriptReply: Codable {
    var applied: Bool
    var preview: [String]
    var report: [String]
    var created: [String: String]
    var message: String
}
