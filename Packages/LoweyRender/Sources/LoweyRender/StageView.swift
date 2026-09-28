import Combine
import Foundation
import LoweyCore
import RealityKit
import UIKit

/// The 3D stage: a non-AR RealityKit view with an orbit camera, grid, selection box,
/// gizmo, guide surface and live stroke preview. Input handling lives in the app; this
/// view offers the picking and projection queries it needs.
@MainActor
public final class StageView: ARView {
    public let renderer: SceneRenderer
    public let anchor = AnchorEntity(world: .zero)
    public let cameraEntity = Entity()
    public let grid = GridEntity()
    public let selectionBox = SelectionBoxEntity()
    public let gizmo = GizmoEntity()
    public let guide = GuideEntity()
    public let strokePreview = ModelEntity()
    private let helpers = Entity()

    public private(set) var viewpoint = Viewpoint.default
    /// Called whenever the camera moves (to refresh screen-space overlays, save the viewpoint…).
    public var onCameraChanged: ((Viewpoint) -> Void)?

    private lazy var postProcessor = StagePostProcessor(library: MaterialFactory.shared.shaderLibrary)
    /// Made outside the main actor so the closure isn't main-actor isolated (RealityKit calls it on its render thread).
    private nonisolated static func renderThreadCallback(_ processor: StagePostProcessor) -> (ARView.PostProcessContext) -> Void {
        { context in processor.process(context) }
    }

    /// Post-processing, overlays and captions for the live view (nil or empty = the plain render, no extra pass).
    public var post: StagePost? {
        didSet {
            var snapshot = post
            let range = depthRange
            snapshot?.viewSize = bounds.size
            snapshot?.near = range.near
            snapshot?.far = range.far
            postProcessor.update(snapshot)
            updatePostCallback()
        }
    }

    /// Whether the post-processing pass is installed (it waits for the view to be on screen).
    public var isPostProcessing: Bool { renderCallbacks.postProcess != nil }

    /// RealityKit traps (EXC_BREAKPOINT in the `renderCallbacks` setter) when render callbacks are installed before the
    /// view has rendered. Opening a scene with a look straight into a new stage did exactly that (the welcome island
    /// on first launch), so the pass waits until the scene has updated a couple of times.
    private var renderReady = false
    private var updatesSeen = 0
    private var readiness: (any Cancellable)?

    private func watchForFirstFrames() {
        guard readiness == nil, !renderReady else { return }
        readiness = scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.sceneUpdated() }
        }
    }

    private func sceneUpdated() {
        updatesSeen += 1
        guard updatesSeen >= 2, !renderReady else { return }
        readiness?.cancel()
        readiness = nil
        renderReady = true
        // Outside RealityKit's own update pass.
        Task { @MainActor [weak self] in self?.updatePostCallback() }
    }

    /// Installs or removes the post-processing pass (once the view renders; see `renderReady`).
    private func updatePostCallback() {
        guard window != nil, renderReady else {
            watchForFirstFrames()
            return
        }
        let active = post.map { !$0.isEmpty } ?? false
        if active, renderCallbacks.postProcess == nil {
            // Runs on RealityKit's render thread: capture only the thread-safe processor.
            renderCallbacks.postProcess = Self.renderThreadCallback(postProcessor)
        } else if !active, renderCallbacks.postProcess != nil {
            renderCallbacks.postProcess = nil
        }
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()
        updatePostCallback()
    }

    public init(renderer: SceneRenderer) {
        self.renderer = renderer
        super.init(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableCameraGrain]
        environment.background = .color(.black)
        scene.addAnchor(anchor)
        anchor.addChild(renderer.root)
        helpers.name = "Helpers"
        helpers.components.set(LoweyHelperComponent())
        anchor.addChild(helpers)
        helpers.addChild(grid)
        helpers.addChild(selectionBox)
        helpers.addChild(gizmo)
        helpers.addChild(guide)
        helpers.addChild(strokePreview)
        selectionBox.show(nil)
        gizmo.isEnabled = false
        guide.show(nil)
        cameraEntity.name = "EditorCamera"
        anchor.addChild(cameraEntity)
        renderer.environment.onEnvironmentChanged = { [weak self] resource, exponent in
            guard let self, let resource else { return }
            environment.lighting.resource = resource
            environment.lighting.intensityExponent = exponent
        }
        setViewpoint(.default)
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @available(*, unavailable)
    @MainActor required init(frame _: CGRect) {
        fatalError("init(frame:) is not supported")
    }

    // MARK: Camera

    /// Orthographic views are rendered as an extreme telephoto (2° field of view from far away).
    /// It looks orthographic, works identically in ARView and the offscreen renderer, and keeps
    /// picking/projection on one code path. See DECISIONS.md.
    public static let orthographicFieldOfView = 2.0

    /// Camera position and field of view actually used for a viewpoint.
    public static func cameraPose(for viewpoint: Viewpoint) -> (eye: Vec3, rotation: Quat, fieldOfView: Double) {
        guard viewpoint.projection == .orthographic else {
            return (viewpoint.eye, viewpoint.rotation, viewpoint.fieldOfView)
        }
        let visibleHeight = 2 * viewpoint.distance * tan(viewpoint.fieldOfView * .pi / 360)
        let distance = visibleHeight / (2 * tan(orthographicFieldOfView * .pi / 360))
        var far = viewpoint
        far.distance = distance
        return (far.eye, viewpoint.rotation, orthographicFieldOfView)
    }

    /// When set, the stage shows the scene through a scene camera (Camera mode) instead of the orbit view.
    public private(set) var lookThrough: OffscreenRenderer.Camera?

    public func setLookThrough(_ camera: OffscreenRenderer.Camera?) {
        lookThrough = camera
        if let camera {
            cameraEntity.transform = RealityKit.Transform(scale: .one, rotation: camera.orientation, translation: camera.position)
            cameraEntity.components.set(PerspectiveCameraComponent(near: 0.02, far: 3000, fieldOfViewInDegrees: camera.fieldOfView))
            renderer.environment.follow(camera: Vec3(camera.position))
        } else {
            setViewpoint(viewpoint, notify: false)
        }
    }

    public func setViewpoint(_ newValue: Viewpoint, notify: Bool = true) {
        var value = newValue
        value.pitch = min(max(value.pitch, -89.9), 89.9)
        value.distance = min(max(value.distance, 0.2), 400)
        viewpoint = value
        if lookThrough != nil {
            if notify { onCameraChanged?(value) }
            return
        }
        let pose = Self.cameraPose(for: value)
        cameraEntity.transform = RealityKit.Transform(scale: .one, rotation: pose.rotation.simd, translation: pose.eye.simd)
        let far: Float = value.projection == .orthographic ? 60000 : 3000
        cameraEntity.components.set(PerspectiveCameraComponent(near: value.projection == .orthographic ? 1 : 0.02,
                                                               far: far, fieldOfViewInDegrees: Float(pose.fieldOfView)))
        renderer.environment.follow(camera: pose.eye)
        updateGizmoScale()
        if notify { onCameraChanged?(value) }
    }

    /// Smoothly moves the camera to a viewpoint.
    public func animate(to target: Viewpoint, duration: TimeInterval = 0.35) {
        let start = viewpoint
        let startDate = Date()
        let displayLink = CADisplayLink(target: DisplayLinkProxy { [weak self] link in
            guard let self else {
                link.invalidate()
                return
            }
            let t = min(Date().timeIntervalSince(startDate) / duration, 1)
            let eased = Easing.easeInOut.apply(t)
            var current = target
            current.target = start.target.lerp(to: target.target, eased)
            var yawDelta = target.yaw - start.yaw
            yawDelta = (yawDelta + 540).truncatingRemainder(dividingBy: 360) - 180
            current.yaw = start.yaw + yawDelta * eased
            current.pitch = start.pitch + (target.pitch - start.pitch) * eased
            current.distance = start.distance + (target.distance - start.distance) * eased
            current.fieldOfView = start.fieldOfView + (target.fieldOfView - start.fieldOfView) * eased
            setViewpoint(current, notify: t >= 1)
            if t >= 1 { link.invalidate() }
        }, selector: #selector(DisplayLinkProxy.tick(_:)))
        displayLink.add(to: .main, forMode: .common)
    }

    /// Frames world bounds (double-tap to frame selection).
    public func frame(_ bounds: Bounds?, animated: Bool = true) {
        var target = viewpoint
        if let bounds {
            target.target = bounds.center
            let radius = max(bounds.size.length / 2, 0.25)
            target.distance = radius / sin(viewpoint.fieldOfView * .pi / 360) * 1.1
        } else {
            target.target = Vec3(0, 0.5, 0)
            target.distance = 9
        }
        if animated { animate(to: target) } else { setViewpoint(target) }
    }

    /// Quick views: top / front / side / perspective.
    public func quickView(_ axis: ViewAxis) {
        var target = viewpoint
        let angles = axis.angles
        target.yaw = angles.yaw
        target.pitch = angles.pitch
        target.projection = axis == .perspective ? .perspective : target.projection
        animate(to: target)
    }

    // MARK: Picking & projection

    /// World-space ray through a screen point.
    public func worldRay(at point: CGPoint) -> Ray? {
        guard let ray = ray(through: point) else { return nil }
        return Ray(origin: Vec3(ray.origin), direction: Vec3(ray.direction))
    }

    /// The scene object under a screen point.
    public func pickObject(at point: CGPoint) -> (ObjectID, SurfaceHit)? {
        guard let ray = worldRay(at: point) else { return nil }
        let hits = scene.raycast(origin: ray.origin.simd, direction: ray.direction.simd, length: 2000,
                                 query: .all, mask: PickGroup.objects, relativeTo: nil)
        let sorted = hits.sorted { $0.distance < $1.distance }
        for hit in sorted {
            if !hit.entity.isEnabledInHierarchy { continue }
            if let id = renderer.objectID(for: hit.entity) {
                return (id, SurfaceHit(point: Vec3(hit.position), normal: Vec3(hit.normal), distance: Double(hit.distance)))
            }
        }
        return nil
    }

    /// The gizmo handle under a screen point.
    public func pickGizmo(at point: CGPoint) -> GizmoHandle? {
        guard gizmo.isEnabled, let ray = worldRay(at: point) else { return nil }
        let hits = scene.raycast(origin: ray.origin.simd, direction: ray.direction.simd, length: 2000,
                                 query: .nearest, mask: PickGroup.gizmo, relativeTo: nil)
        guard let hit = hits.first else { return nil }
        return GizmoEntity.handle(for: hit.entity)
    }

    /// Screen position of a world point (nil if behind the camera).
    public func screenPoint(of world: Vec3) -> CGPoint? {
        project(world.simd)
    }

    /// Where a ray meets the ground plane (y = height).
    public func groundPoint(at point: CGPoint, height: Double = 0) -> Vec3? {
        guard let ray = worldRay(at: point) else { return nil }
        return GuideSurface.plane(origin: Vec3(0, height, 0), normal: .unitY).intersect(ray)?.point
    }

    // MARK: Overlays

    /// Shows the selection box and gizmo around world bounds.
    public func showSelection(_ bounds: Bounds?, pivot: Vec3?, gizmoVisible: Bool) {
        selectionBox.show(bounds)
        if let pivot, gizmoVisible {
            gizmo.isEnabled = true
            gizmo.position = pivot.simd
            updateGizmoScale()
        } else {
            gizmo.isEnabled = false
        }
    }

    private func updateGizmoScale() {
        guard gizmo.isEnabled else { return }
        let pose = Self.cameraPose(for: viewpoint)
        let distance = Float((pose.eye - Vec3(gizmo.position)).length)
        let size = distance * Float(tan(pose.fieldOfView * .pi / 360)) * 0.24
        gizmo.scale = SIMD3<Float>(repeating: max(size, 0.05))
    }

    /// Live preview while a stroke is being drawn.
    public func showStrokePreview(_ mesh: MeshData?, color: UIColor) {
        guard let mesh, !mesh.isEmpty, let resource = try? MeshUpload.resource(from: mesh, name: "preview") else {
            strokePreview.isEnabled = false
            return
        }
        strokePreview.isEnabled = true
        strokePreview.model = ModelComponent(mesh: resource, materials: [SimpleMaterial(color: color, roughness: 0.7, isMetallic: false)])
    }

    public var showsGrid: Bool {
        get { grid.isEnabled }
        set { grid.isEnabled = newValue }
    }

    public var showsStatistics: Bool {
        get { debugOptions.contains(.showStatistics) }
        set {
            if newValue {
                debugOptions.insert(.showStatistics)
            } else {
                debugOptions.remove(.showStatistics)
            }
        }
    }
}

/// Lets a CADisplayLink call a closure (Swift 6 friendly target).
final class DisplayLinkProxy: NSObject {
    private let body: @MainActor (CADisplayLink) -> Void

    init(_ body: @escaping @MainActor (CADisplayLink) -> Void) {
        self.body = body
    }

    @MainActor @objc func tick(_ link: CADisplayLink) {
        body(link)
    }
}
