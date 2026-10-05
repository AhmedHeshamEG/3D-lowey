import LoweyEngine

/// How the gizmo's modes are named and drawn wherever they're offered (the inspector, the joystick, the menu bar).
extension GizmoMode {
    var title: String {
        switch self {
        case .move: "Move"
        case .rotate: "Turn"
        case .scale: "Size"
        }
    }

    var systemImage: String {
        switch self {
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .rotate: "arrow.triangle.2.circlepath"
        case .scale: "arrow.up.left.and.arrow.down.right"
        }
    }
}
