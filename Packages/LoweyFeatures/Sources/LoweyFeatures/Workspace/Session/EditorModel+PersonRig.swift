import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// "Rig as a person" (CONTEXT §10.5): the stage turns to the model's front, eight taps place the head, chin, a
/// shoulder, elbow, wrist, hip, knee and ankle (the other side is mirrored), any dot can be dragged, and Rig builds a
/// humanoid skeleton through the middle of the limbs, so every built-in clip plays on it.
extension EditorModel {
    /// Starts placing a person's dots on the object.
    func startPersonRig(_ id: ObjectID) {
        guard let object = baseScene.objects[id] else { return }
        if let blocker = rigBlocker(object) {
            app.show(String.LocalizationValue(blocker))
            return
        }
        if case .drawing = object.kind {
            app.show("Draw the bones of a drawing with the Pencil")
            return
        }
        guard let mesh = paintSource(of: object), let bounds = mesh.bounds else {
            app.show("This model hasn't loaded yet")
            return
        }
        rigging.target = id
        rigging.person = PersonRigging(target: id, dots: HumanRig.template(bounds: bounds), placed: [], found: false, bounds: bounds)
        tool = .rig
        openPanel = nil
        lookAtFront(of: id, bounds: bounds)
        promptNextDot()
    }

    /// The stage looks straight at the object's front (its +z), the whole of it in view.
    private func lookAtFront(of id: ObjectID, bounds: Bounds) {
        guard let stage else { return }
        let frame = rigFrame(id)
        let front = frame.applyDirection(.unitZ)
        let centre = frame.apply(to: bounds.center)
        let size = bounds.size.scaled(by: Vec3(abs(frame.scale.x), abs(frame.scale.y), abs(frame.scale.z)))
        var view = stage.viewpoint
        view.target = centre
        view.yaw = atan2(front.x, front.z) * 180 / .pi
        view.pitch = 0
        view.distance = max(size.y, size.x) * 1.6 / max(tan(view.fieldOfView * .pi / 360), 0.05)
        stage.animate(to: view)
    }

    private func promptNextDot() {
        guard let person = rigging.person else { return }
        if let next = person.next {
            app.show("Tap \(String(localized: String.LocalizationValue(next.title)))")
        } else {
            app.show("Drag any dot to where it belongs, then tap Rig")
        }
    }

    /// Where a point on the stage lands on the plane through the model's middle, facing its front (rig space).
    private func personPoint(at point: CGPoint, person: PersonRigging) -> Vec3? {
        let frame = rigFrame(person.target)
        guard let ray = rigRay(at: point, frame: frame) else { return nil }
        return GuideSurface.plane(origin: person.bounds.center, normal: .unitZ).intersect(ray)?.point
    }

    /// A tap places the next dot (and its mirror).
    func personTap(at point: CGPoint) {
        guard var person = rigging.person, let next = person.next, let spot = personPoint(at: point, person: person) else { return }
        person.dots[next] = spot
        person.placed.insert(next)
        person.dots = HumanRig.mirrored(person.dots, from: person.placed, centreX: person.bounds.center.x)
        rigging.person = person
        HmmHaptics.play(.selection)
        promptNextDot()
    }

    /// A dot dragged on the stage (its mirror follows while it hasn't been placed itself).
    func movePersonDot(_ dot: HumanRig.Dot, to point: CGPoint) {
        guard var person = rigging.person, let spot = personPoint(at: point, person: person) else { return }
        person.dots[dot] = spot
        person.placed.insert(dot)
        person.dots = HumanRig.mirrored(person.dots, from: person.placed, centreX: person.bounds.center.x)
        rigging.person = person
    }

    /// The dots on screen.
    func personDotsOnScreen() -> [(dot: HumanRig.Dot, point: CGPoint)] {
        guard let person = rigging.person, let stage else { return [] }
        let frame = rigFrame(person.target)
        return HumanRig.Dot.allCases.compactMap { dot in
            person.dots[dot].flatMap { stage.screenPoint(of: frame.apply(to: $0)) }.map { (dot, $0) }
        }
    }

    /// Builds the person's skeleton from the dots and works out its weights (one undo step, replacing drawn bones).
    func finishPersonRig() {
        guard let person = rigging.person, let object = baseScene.objects[person.target], let mesh = paintSource(of: object) else { return }
        let far = person.bounds.max.z + person.bounds.size.length + 1
        let rays = person.dots.mapValues { Ray(origin: Vec3($0.x, $0.y, far), direction: Vec3(0, 0, -1)) }
        let points = HumanRig.points(rays: rays, surface: TriangleBVH(mesh), bounds: person.bounds)
        guard let rig = HumanRig.rig(from: points, bounds: person.bounds) else {
            app.show("Place every dot first")
            return
        }
        rigging.person = nil
        weigh(rig, on: object, label: "Rig \(object.name) as a person", done: "\(object.name) is rigged. Try a clip, or drag its hands and feet")
        tool = .select
        select(object.id)
    }

    func cancelPersonRig() {
        rigging.person = nil
    }
}
