import Foundation
import HmmBridge
import LoweyCore
import LoweyEngine
import UIKit

/// The bridge's endpoints (all behind pairing): read the scene, the look, the transcript and the library; propose a
/// Scene Script; snapshots; the playhead; undo; renders; files from the laptop into the library or the shot.
extension BridgeModel {
    func routes() -> [BridgeRoute] {
        [
            route("GET", "/v1/status") { model, _ in model.statusResponse() },
            route("GET", "/v1/scene") { model, request in model.withEditor { model.scene($0, request) } },
            route("GET", "/v1/scene/full") { model, _ in model.withEditor { model.fullScene($0) } },
            route("GET", "/v1/look") { model, _ in model.withEditor { .json($0.look) } },
            route("GET", "/v1/assets") { model, request in model.assets(request) },
            route("GET", "/v1/transcript") { model, _ in model.withEditor { .json(TranscriptSummary($0.timeline)) } },
            route("GET", "/v1/actions") { _, _ in .data(Data(ScriptReference.text.utf8), type: "text/markdown; charset=utf-8") },
            route("POST", "/v1/script") { model, request in await model.script(request) },
            route("POST", "/v1/snapshot") { model, request in await model.snapshot(request) },
            route("POST", "/v1/playhead") { model, request in model.withEditor { model.playhead($0, request) } },
            route("POST", "/v1/undo") { model, _ in model.withEditor { model.undo($0) } },
            route("GET", "/v1/renders") { model, _ in model.withEditor { model.renders($0) } },
            route("GET", "/v1/renders/*") { model, request in model.withEditor { model.render($0, request) } },
            route("POST", "/v1/library/import") { model, request in await model.importAsset(request) },
            route("POST", "/v1/audio/import") { model, request in model.withEditor { model.importAudio($0, request) } },
            route("POST", "/v1/media/import") { model, request in await model.importMedia(request) }
        ]
    }

    private func route(_ method: String, _ path: String,
                       _ handler: @escaping @MainActor (BridgeModel, HTTPRequest) async -> HTTPResponse) -> BridgeRoute {
        BridgeRoute(method, path) { [weak self] request, _ in
            guard let self else { return .error(503, "The app is closing") }
            return await handler(self, request)
        }
    }

    private func withEditor(_ body: (EditorModel) -> HTTPResponse) -> HTTPResponse {
        guard let editor = app.editor else { return .error(409, "Open a project on the iPad first") }
        return body(editor)
    }

    private func statusResponse() -> HTTPResponse {
        .json([
            "app": AppIdentity.displayName,
            "version": AppIdentity.shortVersion,
            "project": app.editor?.document.project.name ?? "",
            "scene": app.editor?.baseScene.name ?? "",
            "autoApply": autoApplyThisSession ? "true" : "false"
        ])
    }

    private func scene(_ editor: EditorModel, _ request: HTTPRequest) -> HTTPResponse {
        editor.refreshOperationsLibrary()
        return .json(SceneSummary(editor.document, bounds: editor.operations.bounds, depth: Int(request.query["depth"] ?? "2") ?? 2))
    }

    private func fullScene(_ editor: EditorModel) -> HTTPResponse {
        guard let data = try? LoweyJSON.encode(editor.baseScene) else { return .error(500, "Couldn't encode the scene") }
        return .data(data, type: "application/json")
    }

    private func assets(_ request: HTTPRequest) -> HTTPResponse {
        .json(AssetSummary.search(request.query["q"] ?? "", in: app.library.manifest, limit: Int(request.query["limit"] ?? "40") ?? 40))
    }

    private func script(_ request: HTTPRequest) async -> HTTPResponse {
        guard let editor = app.editor else { return .error(409, "Open a project on the iPad first") }
        guard let script = try? LoweyJSON.decode(SceneScript.self, from: request.body) else {
            return .error(400, "The body must be a Scene Script: {\"title\": …, \"actions\": [{\"do\": …}]}. See GET /v1/actions")
        }
        let preview: ScriptPreview
        do {
            preview = try ScriptCompiler.preview(script, document: editor.document, context: editor.scriptContext())
        } catch {
            return .error(422, String(describing: error))
        }
        if ["1", "true", "yes"].contains(request.query["dryRun"]?.lowercased() ?? "") {
            return .json(ScriptReply(applied: false, preview: preview.lines, report: preview.report, created: [:], message: "dry run"))
        }
        if !autoApplyThisSession {
            if UIApplication.shared.applicationState != .active { BridgeNotice.proposal(script.title) }
            guard await editor.propose(script, preview: preview, source: request.headers["x-lowey-client"] ?? "AI") else {
                return .json(ScriptReply(applied: false, preview: preview.lines, report: preview.report, created: [:],
                                         message: "Not applied: Hesham said no (or didn't answer). Ask what to change."))
            }
        }
        switch editor.applyScript(script) {
        case let .success(result):
            notify("scene")
            return .json(ScriptReply(applied: true, preview: preview.lines, report: result.report, created: result.created.mapValues(\.raw),
                                     message: "Applied (one undo step)"))
        case let .failure(error):
            return .error(422, String(describing: error))
        }
    }

    private func snapshot(_ request: HTTPRequest) async -> HTTPResponse {
        struct Options: Decodable {
            var framing: String?
            var longSide: Int?
            var time: Double?
        }
        guard let editor = app.editor else { return .error(409, "Open a project on the iPad first") }
        let options = (try? request.json(Options.self)) ?? Options()
        let framing = Framing(rawValue: options.framing ?? "16:9") ?? .landscape
        guard let png = await editor.snapshotPNG(framing: framing, longSide: min(options.longSide ?? 1280, 2560), at: options.time) else {
            return .error(500, "The snapshot failed")
        }
        return .data(png, type: "image/png")
    }

    private func playhead(_ editor: EditorModel, _ request: HTTPRequest) -> HTTPResponse {
        struct Body: Decodable { var time: Double }
        guard let body = try? request.json(Body.self) else { return .error(400, "{\"time\": seconds}") }
        editor.setTime(body.time)
        return .json(["time": editor.time])
    }

    private func undo(_ editor: EditorModel) -> HTTPResponse {
        editor.undo()
        notify("scene")
        return .json(["undone": true])
    }

    private func renders(_ editor: EditorModel) -> HTTPResponse {
        let files = (try? FileManager.default.contentsOfDirectory(at: editor.rendersFolder, includingPropertiesForKeys: nil)) ?? []
        return .json(files.map(\.lastPathComponent).sorted())
    }

    private func render(_ editor: EditorModel, _ request: HTTPRequest) -> HTTPResponse {
        let name = String(request.path.dropFirst("/v1/renders/".count))
        guard Self.isSafeName(name) else { return .error(400, "That isn't a file name") }
        guard let data = try? Data(contentsOf: editor.rendersFolder.appendingPathComponent(name)) else { return .error(404, "No render called \(name)") }
        return .data(data, type: Self.mimeType(for: (name as NSString).pathExtension))
    }

    /// Files from the laptop (models, generator output) land in the library.
    private func importAsset(_ request: HTTPRequest) async -> HTTPResponse {
        guard let name = request.query["name"], Self.isSafeName(name), !request.body.isEmpty else {
            return .error(400, "POST the file as the body with ?name=model.glb")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            try request.body.write(to: url)
            guard await app.library.importFiles([url]) > 0 else { return .error(422, "\(AppIdentity.displayName) couldn't import \(name)") }
            app.show("From the laptop: \(name) is in your library")
            notify("library")
            return .json(["imported": name])
        } catch {
            return .error(500, error.localizedDescription)
        }
    }

    /// A picture or video into the open scene: ?name=graph.mov&at=seconds&as=card|overlay.
    private func importMedia(_ request: HTTPRequest) async -> HTTPResponse {
        guard let editor = app.editor else { return .error(409, "Open a project on the iPad first") }
        guard let name = request.query["name"], Self.isSafeName(name), !request.body.isEmpty else {
            return .error(400, "POST the file as the body with ?name=graph.mov&at=2.5")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lowey-media-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try request.body.write(to: url)
        } catch {
            return .error(500, error.localizedDescription)
        }
        let placement = MediaPlacement(rawValue: request.query["as"] ?? "card") ?? .card
        guard let id = await editor.importMedia(url, at: request.query["at"].flatMap(Double.init), as: placement) else {
            return .error(422, "Couldn't add \(name)")
        }
        notify("scene")
        return .json(["added": name, "id": id.raw, "name": editor.baseScene.objects[id]?.name ?? name])
    }

    private func importAudio(_ editor: EditorModel, _ request: HTTPRequest) -> HTTPResponse {
        guard let name = request.query["name"], Self.isSafeName(name), !request.body.isEmpty else {
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

    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("..") && !name.hasPrefix(".")
    }

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "mp4": "video/mp4"
        case "mov": "video/quicktime"
        case "png": "image/png"
        case "gif": "image/gif"
        case "srt": "application/x-subrip"
        case "glb": "model/gltf-binary"
        case "usdz": "model/vnd.usdz+zip"
        default: "application/octet-stream"
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
