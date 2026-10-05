import Foundation
import HmmDesign
import HmmDocuments
import LoweyCore
import LoweyEngine
import Observation
import os
import UIKit

/// App-wide state: where projects live (iCloud Drive or this iPad), the project list, the library, the bridge, the
/// open editor and the toast. Theater and every editor feature read it through the environment.
@Observable
@MainActor
public final class AppModel {
    private(set) var projectStore: ProjectStore
    private(set) var storage: DocumentStorage
    let library: LibraryModel
    private(set) var projects: [ProjectSummary] = []
    private(set) var archived: [ProjectSummary] = []
    /// Bumped when a project's card is drawn again, so its still and turntable reload. Cards load their own pictures
    /// when they come on screen (`cardImage`), and read the turntable a frame at a time while they're visible.
    var cardRevisions: [ProjectID: Int] = [:]
    @ObservationIgnored let cardImages = CardImageCache()
    /// How the gallery is arranged: stacks and the sort (`gallery.json` beside the projects).
    var gallery = GalleryArrangement()
    var editor: EditorModel?
    var toast: HmmToastMessage?
    /// The 60-second tour (first launch, or Settings ▸ Take the tour).
    var showTour = false
    /// Settings from the Theater (the editor opens them as one of its sheets).
    var showsSettings = false
    /// A project changed on two devices: which version to keep.
    var pendingConflict: ProjectConflict?
    /// The window that edits (Stage Manager can open more; the others offer to take over or become monitors).
    var primaryWindow: UUID?
    @ObservationIgnored private(set) lazy var bridge = BridgeModel(app: self)
    /// Shows exports outside the app (Live Activity, notification); set by the app target.
    @ObservationIgnored public weak var exportReporter: (any ExportProgressReporting)?
    @ObservationIgnored let diagnostics = DiagnosticsCenter.shared
    @ObservationIgnored let thumbnailer = Thumbnailer()
    @ObservationIgnored private var started = false
    @ObservationIgnored let logger = Logger(subsystem: AppIdentity.subsystem, category: "app")

    public convenience init() {
        let documents = DocumentLocator.defaultLocalRoot
        let base = AppIdentity.isUITesting ? documents.appendingPathComponent("UITest-\(UUID().uuidString)") : documents
        let locator = DocumentLocator(containerIdentifier: nil, subfolder: "Projects", localRoot: base)
        self.init(projects: locator.localFolder, library: base.appendingPathComponent("Lowey Library"))
    }

    /// Projects and library in the given folders, on this device (the app's own, or the Home benchmark's scratch ones).
    init(projects: URL, library libraryRoot: URL) {
        try? FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        storage = .local(projects)
        projectStore = ProjectStore(root: projects)
        try? FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        library = LibraryModel(store: LibraryStore(root: libraryRoot))
    }

    /// Launch: diagnostics, storage, library, projects, first-run samples and tour.
    public func start() async {
        guard !started else { return }
        started = true
        diagnostics.start()
        if diagnostics.previousSessionCrashed, !AppIdentity.isUITesting {
            show("Maquette quit unexpectedly last time. Your work was autosaved.", kind: .error)
        }
        library.load()
        refreshProjects()
        if !AppIdentity.isUITesting { await resolveStorage() }
        let wantsSamples = !AppIdentity.isUITesting || ProcessInfo.processInfo.arguments.contains("-ui-testing-sample")
        if projects.isEmpty, wantsSamples {
            createIslandSample(open: false)
            createEnigmaSample(open: false)
            showTour = !AppIdentity.isUITesting || AppIdentity.isTestingTour
        }
        refreshArchived()
        if !showTour { await restoreSession() }
        if !AppIdentity.isUITesting, !AppIdentity.isHostingTests { bridge.restoreIfWanted() }
    }

    /// iCloud Drive when this build is entitled, the user is signed in and didn't choose "On this iPad". Projects made
    /// on this iPad before move into iCloud Drive once.
    func resolveStorage() async {
        let wantsICloud = UserDefaults.standard.object(forKey: AppSettings.storeInICloud) as? Bool ?? true
        let locator = DocumentLocator(containerIdentifier: AppIdentity.iCloudContainer, subfolder: "Projects")
        let resolved = await locator.resolve(preferICloud: wantsICloud)
        guard resolved != storage else { return }
        let previous = storage
        storage = resolved
        projectStore = ProjectStore(root: resolved.folder)
        if resolved.isICloud { await moveProjects(from: previous.folder, to: resolved) }
        refreshProjects()
        refreshArchived()
    }

    private func moveProjects(from folder: URL, to storage: DocumentStorage) async {
        let local = ProjectStore(root: folder).listProjects()
        guard !local.isEmpty else { return }
        let moved = await Task.detached(priority: .utility) {
            local.reduce(0) { count, project in (try? DocumentLocator.move(project.url, to: storage)) == nil ? count : count + 1 }
        }.value
        if moved > 0 { show(moved == 1 ? "Your project is in iCloud Drive now" : "Your \(moved) projects are in iCloud Drive now") }
    }

    /// Switches between iCloud Drive and this iPad (Settings), moving every project.
    func setStoresInICloud(_ on: Bool) async {
        UserDefaults.standard.set(on, forKey: AppSettings.storeInICloud)
        let before = storage
        await resolveStorage()
        guard !on, before.isICloud, !storage.isICloud else { return }
        let projects = ProjectStore(root: before.folder).listProjects()
        let target = storage
        _ = await Task.detached(priority: .utility) { projects.map { try? DocumentLocator.move($0.url, to: target) } }.value
        refreshProjects()
    }

    // MARK: Scene phase

    /// Back in front: the bridge restarts its listeners if iOS tore them down, the crash marker is set again.
    public func sceneDidBecomeActive() {
        diagnostics.markRunning()
        bridge.resume()
        editor?.resumeFromBackground()
    }

    /// Leaving the screen: save now, keep the bridge reachable if it's on, and mark a clean exit.
    public func sceneDidEnterBackground() {
        diagnostics.markClean()
        rememberSession()
        bridge.enterBackground()
        if let editor { Task { await editor.saveNow(thumbnail: false) } }
    }

    // MARK: Toast

    /// A toast, in the user's language (the message is a String Catalog key; interpolations fill its placeholders).
    func show(_ message: String.LocalizationValue, kind: HmmToastMessage.Kind = .info) {
        let text = String(localized: message)
        logger.info("\(text)")
        diagnostics.log(text)
        toast = HmmToastMessage(text, kind: kind)
    }

    // MARK: Opening and closing

    func open(url: URL) {
        if ConflictResolver.hasConflicts(at: url) {
            pendingConflict = ProjectConflict(url: url, versions: ConflictResolver.conflicts(at: url))
            return
        }
        do {
            let opened = try ProjectHistory.open(url, store: projectStore, onError: journalErrorHandler)
            editor = EditorModel(app: self, projectURL: url, opened: opened)
            diagnostics.log("Opened \(opened.session.document.project.name) (\(opened.replayed) changes replayed, \(opened.skipped) skipped)")
            if opened.skipped > 0 { show("The very last change couldn't be read back. Everything before it is here.", kind: .error) }
        } catch {
            show("Couldn't open the project: \(error.localizedDescription)", kind: .error)
        }
    }

    /// A journal write that failed (shown once it reaches the main actor; the next checkpoint tries again).
    var journalErrorHandler: @Sendable (Error) -> Void {
        { [weak self] error in
            Task { @MainActor in self?.show("Couldn't record your last change: \(error.localizedDescription)", kind: .error) }
        }
    }

    /// Settles a sync conflict, then opens the project.
    func resolveConflict(_ choice: ConflictChoice) {
        guard let conflict = pendingConflict else { return }
        pendingConflict = nil
        do {
            let copy = try ConflictResolver.resolve(conflict.url, choice: choice)
            refreshProjects()
            if copy != nil { show("The other version is saved as a copy") }
            open(url: conflict.url)
        } catch {
            show("Couldn't settle the conflict: \(error.localizedDescription)", kind: .error)
        }
    }

    /// Back home: the project is saved, the editor closes (shrinking into its card), then the card is drawn again.
    func closeEditor() {
        guard let editor else { return }
        Task {
            await editor.saveNow(thumbnail: false)
            let card = editor.cardJob
            editor.tearDown()
            self.editor = nil
            SessionRestoration.clear()
            refreshProjects()
            await drawCard(card)
        }
    }

    // MARK: Thumbnails

    func setThumbnail(_ image: UIImage, for id: ProjectID) {
        cardImages.set(image, for: id)
        cardRevisions[id, default: 0] += 1
    }

    /// A project's still for its card, decoded off the main thread and kept in a small cache.
    func cardImage(for project: ProjectSummary) async -> UIImage? {
        if let cached = cardImages.image(for: project.id) { return cached }
        let url = project.thumbnailURL
        let image = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 640, height: 360))
        }.value
        if let image { cardImages.set(image, for: project.id) }
        return image
    }

    func refreshProjects() {
        projects = projectStore.listProjects()
        gallery = GalleryArrangement.load(from: projectStore.root)
        let ids = Set(projects.map(\.id.raw))
        let before = gallery
        gallery.prune(keeping: ids)
        if gallery != before { saveGallery() }
    }

    /// Writes the gallery's arrangement (a failure only costs the arrangement, never a project).
    func saveGallery() {
        do {
            try gallery.save(to: projectStore.root)
        } catch {
            logger.error("Couldn't save the gallery: \(error.localizedDescription)")
        }
    }

    func refreshArchived() {
        archived = projectStore.listArchived()
    }
}

/// A project with versions from two devices.
struct ProjectConflict: Identifiable, Sendable {
    var url: URL
    var versions: [ConflictVersion]
    var id: String { url.path }

    var name: String { url.deletingPathExtension().lastPathComponent }

    /// This device's version (the file as it is here).
    @MainActor var thisVersion: ConflictVersion {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return ConflictVersion(id: "current", deviceName: UIDevice.current.name, modified: modified)
    }
}

/// The Home cards' stills: a bounded cache, so a gallery of hundreds of projects keeps only what's near the screen.
@MainActor
final class CardImageCache {
    private let cache = NSCache<NSString, UIImage>()

    init(limit: Int = 80) {
        cache.countLimit = limit
    }

    func image(for id: ProjectID) -> UIImage? {
        cache.object(forKey: id.raw as NSString)
    }

    func set(_ image: UIImage, for id: ProjectID) {
        cache.setObject(image, forKey: id.raw as NSString)
    }

    func remove(_ id: ProjectID) {
        cache.removeObject(forKey: id.raw as NSString)
    }
}
