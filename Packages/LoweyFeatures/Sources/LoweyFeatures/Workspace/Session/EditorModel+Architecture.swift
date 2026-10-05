import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Building (Model ▸ Add ▸ Building): walls along tapped corners, floors under them, doors and windows cut where a
/// wall's side is tapped, and stairs climbing away from you. Corners snap like every Model point; the wall height and
/// thickness float beside the walls being drawn, ready to type.
extension EditorModel {
    func buildTap(at point: CGPoint) {
        guard let tool = modeling.mode.buildTool else { return }
        switch tool {
        case .walls, .floor:
            buildCornerTap(at: point, tool: tool)
        case .door, .window:
            openingTap(at: point, tool: tool)
        case .stairs:
            stairsTap(at: point)
        }
    }

    /// The plane corners land on: the ground, or the height of the first corner.
    private var buildPlane: PlaneFrame {
        let height = modeling.build.first?.y ?? 0
        return PlaneFrame(origin: Vec3(0, height, 0), normal: .unitY, u: .unitX, v: Vec3(0, 0, -1))
    }

    private func buildCornerTap(at point: CGPoint, tool: BuildTool) {
        guard let result = snapPoint(at: point, plane: buildPlane), let stage else { return }
        // Level with the first corner (a wall on a floor stays on it).
        var corner = result.point
        if let first = modeling.build.first { corner.y = first.y }
        if let first = modeling.build.first, modeling.build.count >= 3, let a = stage.screenPoint(of: first),
           hypot(a.x - point.x, a.y - point.y) < 16 {
            finishBuild(closed: true)
            return
        }
        modeling.build.append(corner)
        HmmHaptics.play(.selection)
        viewRevision &+= 1
    }

    /// The bar's Done: walls stay open; a floor closes on its first corner.
    func finishBuild(closed: Bool = false) {
        guard let tool = modeling.mode.buildTool else { return }
        let corners = modeling.build
        modeling.build = []
        var ids = operations.ids
        let id: ObjectID = ids.next()
        operations.ids = ids
        let done: Bool = switch tool {
        case .walls:
            corners.count >= 2 && runModeling {
                try ModelingOperations.addWalls(along: corners, closed: closed && corners.count >= 3, height: precision.wallHeight,
                                                thickness: precision.wallThickness, id: id)
            }
        case .floor:
            corners.count >= 3 && runModeling { try ModelingOperations.addSlab(outline: corners, thickness: 0.2, id: id) }
        default:
            false
        }
        if done {
            setSelection([id])
        } else if corners.count < (tool == .floor ? 3 : 2) {
            app.show(tool == .floor ? "Tap at least three corners for a floor" : "Tap at least two corners for a wall")
        }
    }

    private func openingTap(at point: CGPoint, tool: BuildTool) {
        guard let opening = tool.opening, let stage, let (id, _) = stage.pickObject(at: point), let (mesh, world) = modelMesh(of: id),
              let ray = stage.worldRay(at: point) else {
            app.show(String.LocalizationValue(tool.hint))
            return
        }
        let local = Ray(origin: world.inverseApply(to: ray.origin), direction: world.inverseApplyDirection(ray.direction))
        guard let hit = MeshPicking.face(local, in: mesh) else { return }
        let normal = world.applyDirection(mesh.normal(of: hit.face)).normalized
        if runModeling({ try ModelingOperations.cutOpening(opening, in: id, at: world.apply(to: hit.point), facing: normal, in: baseScene) }) {
            setSelection([id])
        }
    }

    private func stairsTap(at point: CGPoint) {
        guard let result = snapPoint(at: point, plane: Self.groundPlane), let stage else { return }
        // Climbing away from the camera, along the ground.
        let forward = Vec3(stage.camera.forward)
        var ids = operations.ids
        let id: ObjectID = ids.next()
        operations.ids = ids
        if perform(ModelingOperations.addStairs(Architecture.Stairs(), from: result.point, direction: Vec3(forward.x, 0, forward.z), id: id)) {
            HmmHaptics.play(.commit)
            setSelection([id])
        }
    }

    // MARK: On the stage

    /// The corners so far and the walls they'll make.
    func buildOverlays(_ stage: StageView) -> [EditorOverlay] {
        guard let tool = modeling.mode.buildTool, !modeling.build.isEmpty else { return [] }
        var overlays: [EditorOverlay] = []
        var marks = MeshData()
        for corner in modeling.build {
            ModelOverlay.dot(corner, radius: stage.worldPerPoint(at: corner) * 4, into: &marks)
        }
        for (a, b) in zip(modeling.build, modeling.build.dropFirst()) {
            ModelOverlay.line(a, b, width: stage.worldPerPoint(at: a) * 1.5, into: &marks)
        }
        overlays.append(EditorOverlay(mesh: marks, color: Self.modelAccent, onTop: true))
        if tool == .walls, modeling.build.count >= 2,
           let walls = try? Architecture.walls(along: modeling.build, closed: false, height: precision.wallHeight, thickness: precision.wallThickness) {
            overlays.append(EditorOverlay(mesh: walls.renderMesh(), color: Self.modelAccent, opacity: 0.25))
        }
        return overlays
    }

    /// The wall height and thickness beside the last corner, while Walls is on.
    func buildLabels(_ stage: StageView) -> [DimensionLabel] {
        guard modeling.mode.buildTool == .walls, let last = modeling.build.last,
              let top = stage.screenPoint(of: last + Vec3(0, precision.wallHeight, 0)), let foot = stage.screenPoint(of: last) else { return [] }
        return [DimensionLabel(field: .wallHeight, point: CGPoint(x: top.x + 40, y: top.y), text: "↕ " + format(precision.wallHeight)),
                DimensionLabel(field: .wallThickness, point: CGPoint(x: foot.x + 40, y: foot.y + 24), text: "⟷ " + format(precision.wallThickness))]
    }
}
