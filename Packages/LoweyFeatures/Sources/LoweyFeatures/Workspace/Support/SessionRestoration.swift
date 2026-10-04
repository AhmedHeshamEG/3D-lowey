import Foundation
import LoweyCore

/// Where you left off: the open project and scene, the playhead, the open panel, the Director view, the timeline's
/// state. Saved when the app leaves the screen and on every autosave; the next launch reopens it.
struct SessionRestoration: Codable, Equatable {
    /// The project package's file name in the projects folder (the folder itself moves with iCloud).
    var project: String
    var scene: String
    var time: Double
    var panel: String?
    var directorView: Bool
    var timelineCollapsed: Bool

    static let key = "session.restoration"

    @MainActor
    init(_ editor: EditorModel) {
        project = editor.projectURL.lastPathComponent
        scene = editor.baseScene.id.raw
        time = editor.time
        panel = editor.openPanel?.rawValue
        directorView = editor.directorView
        timelineCollapsed = editor.timelineCollapsed
    }

    static func load(from defaults: UserDefaults = .standard) -> SessionRestoration? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(SessionRestoration.self, from: $0) }
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// Puts an opened editor back where it was.
    @MainActor
    func apply(to editor: EditorModel) async {
        if scene != editor.baseScene.id.raw, editor.sceneList.contains(where: { $0.id.raw == scene }) {
            await editor.openScene(SceneID(raw: scene))
        }
        editor.setTime(min(max(time, 0), editor.timeline.duration))
        editor.openPanel = panel.flatMap(ClusterPanel.init(rawValue:))
        if directorView, editor.shotCamera != nil { editor.setDirectorView(true) }
        editor.timelineCollapsed = timelineCollapsed
    }
}

extension AppModel {
    /// Remembers the open editor (or that none is open).
    func rememberSession() {
        if let editor { SessionRestoration(editor).save() } else { SessionRestoration.clear() }
    }

    /// Reopens what was open when the app last left the screen (not in UI tests, unless they ask for it).
    func restoreSession() async {
        guard editor == nil, !AppIdentity.isUITesting || ProcessInfo.processInfo.arguments.contains("-ui-testing-restore"),
              let saved = SessionRestoration.load(),
              let project = projects.first(where: { $0.url.lastPathComponent == saved.project }) else { return }
        open(url: project.url)
        guard let editor else { return }
        await saved.apply(to: editor)
    }
}
