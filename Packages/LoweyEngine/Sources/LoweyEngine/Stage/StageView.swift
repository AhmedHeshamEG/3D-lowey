import Foundation
import HmmDiagnostics
import LoweyCore
import MetalKit
import UIKit

/// What the stage shows this frame, supplied by its host (the editor).
public struct StageFrame {
    public var request: FrameRequest
    /// The shot camera when looking through a camera (else the stage's orbit camera is used).
    public var shotCamera: RenderCamera?

    public init(request: FrameRequest, shotCamera: RenderCamera? = nil) {
        self.request = request
        self.shotCamera = shotCamera
    }
}

/// The 3D stage: a Metal view drawing with LoweyRender 2 (the same renderer as snapshots and export), an orbit
/// camera, the editor layer (grid, gizmo, helpers, guide, stroke preview), exact picking from the ID buffer, and
/// dynamic render scale to hold 120 fps. Gestures live in the app; this view answers picking and projection.
@MainActor
public final class StageView: MTKView {
    public let renderer: LoweyRenderer
    private let renderDevice: RenderDevice
    /// Called at every frame for what to draw (nil draws nothing).
    public var frameSource: ((StageView) -> StageFrame?)?
    public private(set) var viewpoint = Viewpoint.default
    /// Looking through a scene camera (Director view): the stage shows that camera instead of the orbit view.
    public private(set) var lookThrough: RenderCamera?
    public var onCameraChanged: ((Viewpoint) -> Void)?
    /// Frame statistics for the Performance HUD (every frame, on the main actor).
    public var onFrameTime: ((_ gpu: Double, _ total: Double, _ scale: Float) -> Void)?
    public var dynamicScale = DynamicScale()
    public var gizmoMode: GizmoMode = .move
    private var gizmoPivot: Vec3?
    public var showsGrid = true
    public private(set) var guide: GuideSurface?
    private var strokePreview: (MeshData, RGBA)?
    /// The hovering Pencil, drawn in this view's own render pass.
    public private(set) var pointer: PencilPointer?
    private var lastFrameStart: CFTimeInterval = 0
    public private(set) var lastReport: FrameReport?

    public init(device: RenderDevice) throws {
        renderDevice = device
        renderer = try LoweyRenderer(device: device)
        super.init(frame: .zero, device: device.device)
        colorPixelFormat = RenderDevice.outputFormat
        depthStencilPixelFormat = .invalid
        framebufferOnly = false
        preferredFramesPerSecond = 120
        autoResizeDrawable = true
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        delegate = self
        isPaused = true
        enableSetNeedsDisplay = true
        isMultipleTouchEnabled = true
        setViewpoint(.default)
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Continuous drawing (playback, Perform, a moving camera) or on-demand (editing: a frame per change).
    public var isContinuous: Bool {
        get { !isPaused }
        set {
            isPaused = !newValue
            enableSetNeedsDisplay = !newValue
            if !newValue { setNeedsDisplay() }
        }
    }

    public func redraw() {
        if isPaused { setNeedsDisplay() }
    }

    // MARK: Camera

    /// The camera the stage draws with now.
    public var camera: RenderCamera { lookThrough ?? RenderCamera(viewpoint: viewpoint) }

    public func setLookThrough(_ camera: RenderCamera?) {
        lookThrough = camera
        redraw()
    }

    public func setViewpoint(_ newValue: Viewpoint, notify: Bool = true) {
        var value = newValue
        value.pitch = min(max(value.pitch, -89.9), 89.9)
        value.distance = min(max(value.distance, 0.2), 400)
        viewpoint = value
        if notify { onCameraChanged?(value) }
        redraw()
    }

    /// Smoothly moves the orbit camera to a viewpoint (spring-eased, Reduce Motion → instant).
    public func animate(to target: Viewpoint, duration: TimeInterval = 0.35) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            setViewpoint(target)
            return
        }
        let start = viewpoint
        let startDate = Date()
        let link = CADisplayLink(target: DisplayLinkProxy { [weak self] link in
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
        link.add(to: .main, forMode: .common)
    }

    /// Frames world bounds (double-tap frames the selection).
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

    // MARK: Projection & picking

    public var viewSize: CGSize { bounds.size }

    public func worldRay(at point: CGPoint) -> Ray? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        return camera.ray(through: point, in: bounds.size)
    }

    public func screenPoint(of world: Vec3) -> CGPoint? {
        camera.project(world, in: bounds.size)
    }

    public func groundPoint(at point: CGPoint, height: Double = 0) -> Vec3? {
        guard let ray = worldRay(at: point) else { return nil }
        return GuideSurface.plane(origin: Vec3(0, height, 0), normal: .unitY).intersect(ray)?.point
    }

    /// The scene object under a point: helpers (lights, cameras, emitters) by their spheres first, then the ID buffer.
    public func pickObject(at point: CGPoint) -> (ObjectID, SurfaceHit)? {
        if let ray = worldRay(at: point) {
            var best: (ObjectID, SurfaceHit)?
            for helper in renderer.helpers {
                let center = helper.transform.position
                let toCenter = center - ray.origin
                let along = toCenter.dot(ray.direction)
                guard along > 0 else { continue }
                let miss = (toCenter - ray.direction * along).length
                let radius = max(helper.radius * 1.5, 0.12)
                if miss < radius, along < (best?.1.distance ?? .infinity) {
                    best = (helper.object, SurfaceHit(point: ray.point(at: along), normal: .unitY, distance: along))
                }
            }
            if let best { return best }
        }
        let scale = contentScaleFactor
        let pixel = SIMD2<Int>(Int(point.x * scale), Int(point.y * scale))
        guard let hit = renderer.pick(at: pixel, radius: Int(6 * scale)) else { return nil }
        return (hit.object, SurfaceHit(point: hit.point, normal: hit.normal, distance: hit.distance))
    }

    public func visualBounds(of ids: [ObjectID]) -> Bounds? {
        renderer.visualBounds(of: Set(ids))
    }

    public func worldMesh(of id: ObjectID) -> MeshData? {
        renderer.worldMesh(of: id)
    }

    // MARK: Editor layer

    public func showSelection(pivot: Vec3?, gizmoVisible: Bool) {
        gizmoPivot = gizmoVisible ? pivot : nil
        redraw()
    }

    public func showGuide(_ surface: GuideSurface?) {
        guard surface != guide else { return }
        guide = surface
        redraw()
    }

    /// Shows (or hides) the point under the hovering Pencil. Drawn by the next frame, in the same pass as the scene.
    public func showPointer(_ newValue: PencilPointer?) {
        guard newValue != pointer else { return }
        pointer = newValue
        redraw()
    }

    public func showStrokePreview(_ mesh: MeshData?, color: RGBA) {
        strokePreview = mesh.flatMap { $0.isEmpty ? nil : ($0, color) }
        redraw()
    }

    /// The gizmo's size in world units (a constant size on screen).
    public var gizmoScale: Double {
        guard let pivot = gizmoPivot else { return 1 }
        let pose = camera
        let distance = (Vec3(pose.position) - pivot).length
        return max(distance * tan(Double(pose.fieldOfView) * .pi / 360) * 0.24, 0.05)
    }

    public var gizmoCenter: Vec3? { gizmoPivot }

    public func editorScene(showsSelection: Bool) -> EditorScene {
        var scene = EditorScene()
        scene.showsGrid = showsGrid && lookThrough == nil
        scene.showsSelection = showsSelection
        if let pivot = gizmoPivot { scene.gizmo = (gizmoMode, pivot, gizmoScale) }
        scene.guide = guide
        scene.strokePreview = strokePreview
        scene.pointer = pointer
        let pixels = Double(bounds.height * contentScaleFactor)
        if pixels > 1 { scene.pixelAngle = Float(2 * tan(Double(camera.fieldOfView) * .pi / 360) / pixels) }
        return scene
    }
}

extension StageView: MTKViewDelegate {
    public func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {
        redraw()
    }

    public func draw(in _: MTKView) {
        let start = CACurrentMediaTime()
        let total = lastFrameStart > 0 ? start - lastFrameStart : 0
        lastFrameStart = start
        guard var frame = frameSource?(self), let drawable = currentDrawable,
              let commandBuffer = renderDevice.queue.makeCommandBuffer() else { return }
        commandBuffer.label = "Stage"
        frame.request.camera = frame.shotCamera ?? camera
        frame.request.renderScale = dynamicScale.scale
        if frame.request.editor == nil { frame.request.editor = editorScene(showsSelection: true) }
        do {
            lastReport = try renderer.encode(frame.request, to: drawable.texture, commandBuffer: commandBuffer)
        } catch {
            return
        }
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] buffer in
            let gpu = buffer.gpuEndTime - buffer.gpuStartTime
            Task { @MainActor in
                guard let self else { return }
                let scale = self.dynamicScale.update(gpuTime: gpu, thermal: .current)
                self.onFrameTime?(gpu, total, scale)
            }
        }
        commandBuffer.commit()
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
