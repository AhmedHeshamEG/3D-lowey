import Foundation

/// A preset for the job, applied to an empty project (CONTEXT §10.1): the Look and Mood it suggests, where the camera
/// starts, snapping and the grid, whether the timeline shows, and which tools open first. Nothing is placed in the
/// scene; a template only gets the workspace ready.
///
/// Sketch arrives with the Schizzo board; a template that would promise a tool the app doesn't have yet isn't listed.
public struct StarterTemplate: Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case blank, print, room, character, animation

        public var title: String {
            switch self {
            case .blank: "Blank"
            case .print: "Model to print"
            case .room: "Room or building"
            case .character: "Character"
            case .animation: "Animation"
            }
        }

        public var subtitle: String {
            switch self {
            case .blank: "An empty stage, ready for anything."
            case .print: "Millimetres, 5 cm shapes on a 1 cm grid, close up."
            case .room: "Metres, a 25 cm grid, the view from above."
            case .character: "Cast open, the camera at eye level."
            case .animation: "The timeline open from the start."
            }
        }

        public var systemImage: String {
            switch self {
            case .blank: "square.dashed"
            case .print: "cube.transparent"
            case .room: "house"
            case .character: "figure.wave"
            case .animation: "film"
            }
        }
    }

    public var kind: Kind
    public var lookPresetID: String
    public var mood: LightingPreset
    public var viewpoint: Viewpoint
    public var workspace: ProjectWorkspace

    public var id: Kind { kind }
    public var title: String { kind.title }
    public var subtitle: String { kind.subtitle }
    public var systemImage: String { kind.systemImage }

    /// In the order New project shows them.
    public static let all: [StarterTemplate] = [.blank, .print, .room, .character, .animation]

    public static func template(_ kind: Kind) -> StarterTemplate {
        all.first { $0.kind == kind } ?? .blank
    }

    public static let blank = StarterTemplate(
        kind: .blank, lookPresetID: LookPreset.ink.id, mood: .day, viewpoint: .default, workspace: ProjectWorkspace(template: .blank)
    )

    /// Small parts on a fine grid, seen up close in Clay so the form reads.
    public static let print = StarterTemplate(
        kind: .print, lookPresetID: LookPreset.clay.id, mood: .studio,
        viewpoint: Viewpoint(target: Vec3(0, 0.04, 0), yaw: 35, pitch: 30, distance: 0.6, fieldOfView: 40),
        workspace: ProjectWorkspace(template: .print, snap: SnapSettings(grid: true, gridSize: 0.01, rotationStep: 15, objectThreshold: 0.005),
                                    showsGrid: true, shapeSize: 0.05, firstPanel: "model", units: .millimetre,
                                    printBed: PrintBed.standard.id)
    )

    /// Rooms and buildings: a quarter-metre grid, seen from above the floor.
    public static let room = StarterTemplate(
        kind: .room, lookPresetID: LookPreset.ink.id, mood: .day,
        viewpoint: Viewpoint(target: Vec3(0, 0, 0), yaw: 35, pitch: 42, distance: 16),
        workspace: ProjectWorkspace(template: .room, snap: SnapSettings(grid: true, gridSize: 0.25, rotationStep: 45), showsGrid: true,
                                    firstPanel: "model", units: .metre)
    )

    /// A character at eye level with Cast open.
    public static let character = StarterTemplate(
        kind: .character, lookPresetID: LookPreset.ink.id, mood: .studio,
        viewpoint: Viewpoint(target: Vec3(0, 0.9, 0), yaw: 20, pitch: 8, distance: 4.5, fieldOfView: 40),
        workspace: ProjectWorkspace(template: .character, timeline: .transport, showsGrid: false, firstPanel: "cast")
    )

    /// Motion first: the timeline open from the start.
    public static let animation = StarterTemplate(
        kind: .animation, lookPresetID: LookPreset.ink.id, mood: .day, viewpoint: .default,
        workspace: ProjectWorkspace(template: .animation, timeline: .full, showsGrid: true)
    )
}
