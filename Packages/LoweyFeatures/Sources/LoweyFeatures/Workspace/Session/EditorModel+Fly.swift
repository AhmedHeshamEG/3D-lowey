import Foundation
import HmmDesign
import LoweyCore

/// Fly: the shot camera flown like a drone (on-screen sticks or a game controller). Outside Perform each flight is
/// one undo step; recording in Perform turns the flight into the camera's keys.
extension EditorModel {
    func startFlying() {
        if editedCamera == nil { addCamera() }
        guard editedCamera != nil else {
            app.show("Add a camera first (Build ▸ Camera saves this view)")
            return
        }
        setDirectorView(true)
        if let camera = editedCamera { setSelection([camera]) }
        flying = true
        let step: @MainActor (Flight.Input, Double) -> Void = { [weak self] input, dt in self?.flyStep(input, dt: dt) }
        flyer.start(step) { [weak self] record, stop in
            self?.flyButtons(record: record, stop: stop)
        }
        app.show(FlyPerformer.controller == nil ? "Fly: left stick moves, right stick looks. Record in Perform to keep the move"
            : "Fly with the controller: left stick moves, right stick looks, triggers lift, A records")
    }

    /// A on the controller records a take (or finishes one), B stops flying.
    private func flyButtons(record: Bool, stop: Bool) {
        if record {
            if performPhase == .recording { finishPerform() } else { armPerform() }
        }
        if stop { stopFlying() }
    }

    func stopFlying() {
        guard flying else { return }
        flyer.stop()
        flying = false
        endGesture()
    }

    func flyStep(_ input: Flight.Input, dt: Double) {
        guard let world = editedCameraWorld else { return }
        if input.isIdle, flyer.flight.isResting {
            if flyer.isMoving {
                flyer.isMoving = false
                endGesture()
            }
            return
        }
        flyer.isMoving = true
        setCameraWorld(flyer.flight.step(world, input: input, dt: min(dt, 0.05)), gesture: "fly")
    }
}
