import ARKit
import LoweyCore
import LoweyRender
import UIKit

/// The iPad as a virtual camera (Unreal-style): ARKit world tracking with the rear camera reports
/// how the device moved since tracking started; the editor applies that motion to a scene camera
/// (translation scaled up so a small room can film a big world) and records it through Perform.
@MainActor
public final class VirtualCameraController: NSObject, ARSessionDelegate {
    override public init() {
        super.init()
    }

    public static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    private let session = ARSession()
    private var origin: simd_float4x4?
    /// Device axes → camera axes (ARKit reports in the device's landscape-right frame).
    private var roll = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))

    /// Motion since `start()` as a local transform of the camera.
    public var onPose: ((CoreTransform) -> Void)?
    public var onFailure: ((String) -> Void)?

    public func start() {
        let orientation = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.effectiveGeometry.interfaceOrientation ?? .landscapeRight
        let angle: Float = switch orientation {
        case .portrait: .pi / 2
        case .portraitUpsideDown: -.pi / 2
        case .landscapeLeft: .pi
        default: 0
        }
        roll = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 0, 1))
        origin = nil
        session.delegate = self
        session.delegateQueue = .main
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    public func stop() {
        session.pause()
        session.delegate = nil
        origin = nil
    }

    public nonisolated func session(_: ARSession, didUpdate frame: ARFrame) {
        let transform = frame.camera.transform
        let tracking: Bool = if case .normal = frame.camera.trackingState {
            true
        } else {
            false
        }
        MainActor.assumeIsolated {
            self.update(transform, tracking: tracking)
        }
    }

    public nonisolated func session(_: ARSession, didFailWithError error: Error) {
        let message = "Camera tracking stopped: \(error.localizedDescription)"
        MainActor.assumeIsolated {
            self.onFailure?(message)
        }
    }

    private func update(_ transform: simd_float4x4, tracking: Bool) {
        guard tracking else { return }
        guard let origin else {
            origin = transform
            onPose?(.identity)
            return
        }
        let delta = origin.inverse * transform
        let rotation = roll.inverse * simd_quatf(delta) * roll
        let translation = roll.inverse.act(SIMD3<Float>(delta.columns.3.x, delta.columns.3.y, delta.columns.3.z))
        onPose?(CoreTransform(position: Vec3(translation), rotation: Quat(rotation.normalized)))
    }
}
