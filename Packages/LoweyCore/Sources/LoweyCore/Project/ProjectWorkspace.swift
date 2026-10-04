import Foundation
import HmmDocuments

/// How much of the timeline shows under the stage. It's called, never in the way: hidden until asked for.
public enum TimelinePresence: String, Codable, Sendable, CaseIterable {
    /// Only the corner control.
    case hidden
    /// The slim transport: play, the time, the scrubber.
    case transport
    /// The whole timeline at its remembered height.
    case full
}

/// How a project is shown when it opens: the timeline, snapping and the grid, the starter template it came from.
/// It's how you see the project, not what the project is, so it lives in `workspace.json` beside `project.json`,
/// outside the history journal and undo, written whenever it changes.
public struct ProjectWorkspace: Codable, Hashable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    /// The starter template the project began from (nil: made before templates, or Blank).
    public var template: StarterTemplate.Kind?
    public var timeline: TimelinePresence
    /// The full timeline's height in points.
    public var timelineHeight: Double
    public var snap: SnapSettings
    public var showsGrid: Bool
    /// How big a new shape is, in metres (1 m by default; small parts for printing).
    public var shapeSize: Double
    /// The tool panel to open the first time the project opens (then cleared).
    public var firstPanel: String?

    public static let defaultTimelineHeight = 260.0
    public static let timelineHeightRange = 150.0 ... 900.0

    public init(template: StarterTemplate.Kind? = nil, timeline: TimelinePresence = .hidden, timelineHeight: Double = Self.defaultTimelineHeight,
                snap: SnapSettings = SnapSettings(), showsGrid: Bool = true, shapeSize: Double = 1, firstPanel: String? = nil) {
        schemaVersion = Self.schemaVersion
        self.template = template
        self.timeline = timeline
        self.timelineHeight = timelineHeight
        self.snap = snap
        self.showsGrid = showsGrid
        self.shapeSize = shapeSize
        self.firstPanel = firstPanel
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, template, timeline, timelineHeight, snap, showsGrid, shapeSize, firstPanel
    }

    /// Unknown or missing values fall back to the defaults: a damaged or future workspace never stops a project opening.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ProjectWorkspace()
        schemaVersion = (try? container.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? Self.schemaVersion
        template = try? container.decodeIfPresent(StarterTemplate.Kind.self, forKey: .template)
        timeline = (try? container.decodeIfPresent(TimelinePresence.self, forKey: .timeline)) ?? defaults.timeline
        let height = (try? container.decodeIfPresent(Double.self, forKey: .timelineHeight)) ?? defaults.timelineHeight
        timelineHeight = min(max(height, Self.timelineHeightRange.lowerBound), Self.timelineHeightRange.upperBound)
        snap = (try? container.decodeIfPresent(SnapSettings.self, forKey: .snap)) ?? defaults.snap
        showsGrid = (try? container.decodeIfPresent(Bool.self, forKey: .showsGrid)) ?? defaults.showsGrid
        let size = (try? container.decodeIfPresent(Double.self, forKey: .shapeSize)) ?? defaults.shapeSize
        shapeSize = size.isFinite && size > 0 ? min(size, 100) : defaults.shapeSize
        firstPanel = try? container.decodeIfPresent(String.self, forKey: .firstPanel)
    }
}

public extension ProjectStore {
    static func workspaceURL(in project: URL) -> URL {
        project.appendingPathComponent(ProjectLayout.workspaceFile)
    }

    /// The project's workspace; the defaults when it has none (projects from before Maquette 0.2) or it can't be read.
    func loadWorkspace(at project: URL) -> ProjectWorkspace {
        let decode = { (data: Data) in try JSONDecoder().decode(ProjectWorkspace.self, from: data) }
        guard let (data, _) = try? SafeFileWriter.read(Self.workspaceURL(in: project), validate: { _ = try decode($0) }),
              let workspace = try? decode(data) else { return ProjectWorkspace() }
        return workspace
    }

    func saveWorkspace(_ workspace: ProjectWorkspace, at project: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try SafeFileWriter.write(encoder.encode(workspace), to: Self.workspaceURL(in: project))
    }
}
