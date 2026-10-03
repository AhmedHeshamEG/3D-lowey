import Foundation
import HmmBridge
import LoweyCore
import LoweyEngine
import UIKit

/// MCP v2's endpoints (PROMPT §12.2): the 16 tools of `hmm-bridge` map onto these. Everything that changes the scene
/// goes through `build` (Scene Script v3): one batch = one Proposal = one undo step, and the reply carries an
/// `observe` of the result so the AI sees what it made.
extension BridgeModel {
    func v2Routes() -> [BridgeRoute] {
        [
            v2("GET", "/v2/status") { model, _ in model.v2Status() },
            v2("GET", "/v2/project") { model, _ in model.withOpenEditor { model.readProject($0) } },
            v2("GET", "/v2/transcript") { model, _ in model.withOpenEditor { .json(TranscriptSummary($0.timeline)) } },
            v2("GET", "/v2/actions") { _, _ in .data(Data(ScriptReference.text.utf8), type: "text/markdown; charset=utf-8") },
            v2("GET", "/v2/assets") { model, request in model.findAssets(request) },
            v2("GET", "/v2/thumbnail") { model, request in await model.assetThumbnail(request) },
            v2("POST", "/v2/build") { model, request in await model.build(request) },
            v2("POST", "/v2/observe") { model, request in await model.observeRoute(request) },
            v2("POST", "/v2/contact_sheet") { model, request in await model.contactSheetRoute(request) },
            v2("POST", "/v2/commit") { model, request in await model.commit(request) },
            v2("POST", "/v2/media") { model, request in await model.v2Media(request) },
            // Not one of the sixteen tools: the evals harness starts each brief in a fresh scene.
            v2("POST", "/v2/scenes/new") { model, request in await model.newScene(request) }
        ]
    }

    private func v2(_ method: String, _ path: String,
                    _ handler: @escaping @MainActor (BridgeModel, HTTPRequest) async -> HTTPResponse) -> BridgeRoute {
        BridgeRoute(method, path) { [weak self] request, _ in
            guard let self else { return .error(503, "The app is closing") }
            return await handler(self, request)
        }
    }

    private func withOpenEditor(_ body: (EditorModel) -> HTTPResponse) -> HTTPResponse {
        guard let editor = app.editor else { return .error(409, "Open a project on the iPad first") }
        return body(editor)
    }

    // MARK: Reading

    private func v2Status() -> HTTPResponse {
        let editor = app.editor
        let camera = editor.flatMap { editor in
            (editor.timeline.cutCamera(at: editor.time) ?? editor.baseScene.activeCamera).flatMap { editor.baseScene.objects[$0]?.name }
        }
        return .json(V2Status(app: AppIdentity.displayName, version: AppIdentity.shortVersion, device: UIDevice.current.name, bridge: 2,
                              project: editor?.document.project.name, scene: editor?.baseScene.name, shot: camera, playhead: editor?.time,
                              duration: editor?.timeline.duration, autoApply: autoApplyThisSession, pendingProposals: pendingBuilds.count))
    }

    private func readProject(_ editor: EditorModel) -> HTTPResponse {
        editor.refreshOperationsLibrary()
        let scenes = editor.sceneList.map { line -> (name: String, seconds: Double?, fps: Int?, look: String?) in
            (line.name, nil, nil, nil)
        }
        return .json(ProjectReading(editor.document, scenes: scenes, library: app.library.manifest))
    }

    private func findAssets(_ request: HTTPRequest) -> HTTPResponse {
        let limit = min(max(Int(request.query["limit"] ?? "12") ?? 12, 1), 60)
        return .json(FoundAsset.find(request.query["q"] ?? "", set: request.query["set"], in: app.library.manifest, limit: limit))
    }

    /// A Kit or library model's thumbnail (PNG), rendered in the Ink Look the first time it's asked for.
    private func assetThumbnail(_ request: HTTPRequest) async -> HTTPResponse {
        guard let id = request.query["id"], let asset = app.library.manifest.asset(AssetID(raw: id)) else {
            return .error(404, "No model with that id (find_assets lists them)")
        }
        guard let png = await app.library.thumbnailPNG(for: .asset(asset)) else { return .error(500, "The thumbnail failed") }
        return .data(png, type: "image/png")
    }

    // MARK: Building

    /// `build(actions, dry_run)`: compiles the v3 script. A dry run returns the diff, an observe of the result and a
    /// proposal id for `commit`; otherwise it's proposed on the iPad (with a thumbnail) and applied when Hesham says yes.
    private func build(_ request: HTTPRequest) async -> HTTPResponse {
        guard let editor = app.editor else { return .error(409, "Open a project on the iPad first") }
        guard let body = try? request.json(BuildBody.self), !body.actions.isEmpty else {
            return .error(400, "{\"title\": \"…\", \"actions\": [{\"do\": …}], \"dry_run\": false} — GET /v2/actions for the verbs")
        }
        let script = SceneScript(title: body.title ?? "From \(request.headers["x-lowey-client"] ?? "the AI")", actions: body.actions, version: 3)
        let result: ScriptResult
        do {
            result = try ScriptCompiler.compile(script, document: editor.document, context: editor.scriptContext())
        } catch {
            return .error(422, String(describing: error))
        }
        let preview = ScriptPreview(before: editor.document, after: result.document, report: result.report)
        let views = Set((body.views ?? ["camera"]).compactMap(ObserveView.init(rawValue:)))
        if body.dryRun ?? false {
            let id = UUID().uuidString.lowercased()
            pendingBuilds[id] = script
            let observation = try? await editor.observe(result.document, views: views, subject: body.subject, longSide: 960)
            return .json(BuildReply(proposalId: id, applied: false, diff: preview.lines, report: result.report,
                                    observe: observation.map(ObserveReply.init), message: "Dry run. commit(proposal_id) to propose it on the iPad."))
        }
        return await propose(script, result: result, preview: preview, editor: editor, source: request.headers["x-lowey-client"] ?? "AI",
                             views: views, subject: body.subject)
    }

    /// Shows the proposal (with a thumbnail of the result) and applies it if Hesham says yes; replies with an observe.
    private func propose(_ script: SceneScript, result: ScriptResult, preview: ScriptPreview, editor: EditorModel, source: String,
                         views: Set<ObserveView>, subject: String?) async -> HTTPResponse {
        if !autoApplyThisSession {
            if UIApplication.shared.applicationState != .active { BridgeNotice.proposal(script.title) }
            let thumbnail = await editor.previewThumbnail(of: result.document)
            guard await editor.propose(script, preview: preview, source: source, thumbnail: thumbnail) else {
                return .json(BuildReply(proposalId: nil, applied: false, diff: preview.lines, report: result.report, observe: nil,
                                        message: "Not applied: Hesham said no (or didn't answer). Ask what to change."))
            }
        }
        switch editor.applyScript(script) {
        case let .success(applied):
            notify("scene")
            let observation = try? await editor.observe(views: views, subject: subject, longSide: 960)
            return .json(BuildReply(proposalId: nil, applied: true, diff: preview.lines, report: applied.report,
                                    observe: observation.map(ObserveReply.init), message: "Applied (one undo step)"))
        case let .failure(error):
            return .error(422, String(describing: error))
        }
    }

    /// `commit(proposal_id)` proposes a dry run for real; `undo(steps)` undoes.
    private func commit(_ request: HTTPRequest) async -> HTTPResponse {
        guard let editor = app.editor else { return .error(409, "Open a project on the iPad first") }
        guard let body = try? request.json(CommitBody.self) else { return .error(
            400,
            "{\"action\": \"commit\", \"proposal_id\": …} or {\"action\": \"undo\", \"steps\": 1}"
        ) }
        if body.action == "undo" {
            var undone = 0
            for _ in 0 ..< min(max(body.steps ?? 1, 1), 20) where editor.canUndo {
                editor.undo()
                undone += 1
            }
            notify("scene")
            return .json(["undone": undone])
        }
        guard let id = body.proposalId, let script = pendingBuilds.removeValue(forKey: id) else {
            return .error(404, "No dry run with that proposal_id (they last until the app closes; run build again)")
        }
        let result: ScriptResult
        do {
            // Against the scene as it is now (it may have changed since the dry run).
            result = try ScriptCompiler.compile(script, document: editor.document, context: editor.scriptContext())
        } catch {
            return .error(422, "The scene changed and the script no longer fits: \(error)")
        }
        let preview = ScriptPreview(before: editor.document, after: result.document, report: result.report)
        return await propose(script, result: result, preview: preview, editor: editor, source: request.headers["x-lowey-client"] ?? "AI",
                             views: [.camera], subject: nil)
    }

    private func newScene(_ request: HTTPRequest) async -> HTTPResponse {
        guard let editor = app.editor else { return .error(409, "Open a project on the iPad first") }
        struct Body: Decodable { var name: String? }
        let name = (try? request.json(Body.self))?.name
        guard let id = await editor.newScene(named: name) else { return .error(500, "Couldn't add a scene") }
        notify("scene")
        return .json(["scene": editor.baseScene.name, "id": id.raw])
    }

    // MARK: Seeing

    private func observeRoute(_ request: HTTPRequest) async -> HTTPResponse {
        guard let editor = app.editor else { return .error(409, "Open a project on the iPad first") }
        let body = (try? request.json(ObserveBody.self)) ?? ObserveBody()
        let views = Set((body.views ?? ["camera"]).compactMap(ObserveView.init(rawValue:))).union([.camera])
        do {
            let observation = try await editor.observe(at: body.time, views: views, framing: body.framing.flatMap(Framing.init(rawValue:)),
                                                       subject: body.subject, longSide: body.longSide ?? 1280)
            return .json(ObserveReply(observation))
        } catch {
            return .error(500, "observe failed: \(error)")
        }
    }

    private func contactSheetRoute(_ request: HTTPRequest) async -> HTTPResponse {
        guard let editor = app.editor else { return .error(409, "Open a project on the iPad first") }
        let body = (try? request.json(ContactSheetBody.self)) ?? ContactSheetBody()
        do {
            let sheet = try await editor.contactSheet(from: body.from, to: body.to, frames: body.frames ?? 6, subject: body.subject)
            return .json(ContactSheetReply(summary: sheet.report.summary, report: sheet.report, image: sheet.image?.pngData?.base64EncodedString()))
        } catch {
            return .error(500, "contact_sheet failed: \(error)")
        }
    }

    /// `add_media` (and `render_manim`'s output): a picture or video into the shot as a card or an overlay.
    private func v2Media(_ request: HTTPRequest) async -> HTTPResponse {
        guard let editor = app.editor else { return .error(409, "Open a project on the iPad first") }
        guard let name = request.query["name"], Self.isSafeName(name), !request.body.isEmpty else {
            return .error(400, "POST the file as the body with ?name=graph.mov&at=2.5&as=card|overlay")
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
}

// MARK: - Bodies and replies

struct V2Status: Codable {
    var app: String
    var version: String
    var device: String
    var bridge: Int
    var project: String?
    var scene: String?
    var shot: String?
    var playhead: Double?
    var duration: Double?
    var autoApply: Bool
    var pendingProposals: Int
}

struct BuildBody: Decodable {
    var title: String?
    var actions: [JSONValue]
    var dryRun: Bool?
    var views: [String]?
    var subject: String?

    enum CodingKeys: String, CodingKey {
        case title, actions, views, subject
        case dryRun = "dry_run"
    }
}

struct CommitBody: Decodable {
    var action: String
    var proposalId: String?
    var steps: Int?

    enum CodingKeys: String, CodingKey {
        case action, steps
        case proposalId = "proposal_id"
    }
}

struct ObserveBody: Decodable {
    var time: Double?
    var views: [String]?
    var framing: String?
    var subject: String?
    var longSide: Int?

    init() {}

    enum CodingKeys: String, CodingKey {
        case time, views, framing, subject
        case longSide = "long_side"
    }
}

struct ContactSheetBody: Decodable {
    var from: Double?
    var to: Double?
    var frames: Int?
    var subject: String?

    init() {}
}

/// An observe for the wire: the summary first, the report, and each view as base64 PNG.
struct ObserveReply: Encodable {
    var summary: String
    var report: ShotReport
    var images: [String: String]

    init(_ observation: ShotObservation) {
        summary = observation.report.summary
        report = observation.report
        images = Dictionary(uniqueKeysWithValues: observation.images.compactMap { view, image in
            image.pngData.map { (view.rawValue, $0.base64EncodedString()) }
        })
    }
}

struct BuildReply: Encodable {
    var proposalId: String?
    var applied: Bool
    var diff: [String]
    var report: [String]
    var observe: ObserveReply?
    var message: String

    enum CodingKeys: String, CodingKey {
        case applied, diff, report, observe, message
        case proposalId = "proposal_id"
    }
}

struct ContactSheetReply: Encodable {
    var summary: String
    var report: ContactSheetReport
    var image: String?
}
