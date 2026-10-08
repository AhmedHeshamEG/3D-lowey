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

/// A picture pinned from the Schizzo board, floating over the stage beside the model: something to look at while
/// making. It is how the project is seen, not what it is (the same picture as a plane in the scene is an object).
public struct ReferenceCard: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// The picture's file in the project's assets (`references/<name>.png`), like any media file.
    public var image: String
    /// The frame's name or the first words of what was pinned.
    public var title: String
    /// The card's middle, as fractions of the stage's width and height.
    public var x: Double
    public var y: Double
    /// Its width in points; the height follows the picture's shape.
    public var width: Double
    /// The picture's height over its width.
    public var aspect: Double

    public static let widthRange = 120.0 ... 900.0
    public static let defaultWidth = 260.0

    public init(id: String, image: String, title: String = "", x: Double = 0.78, y: Double = 0.3, width: Double = Self.defaultWidth,
                aspect: Double = 1) {
        self.id = id
        self.image = image
        self.title = title
        self.x = x
        self.y = y
        self.width = width
        self.aspect = aspect
        self = clamped
    }

    /// Inside the stage and a size a hand can hold, whatever a file says.
    public var clamped: ReferenceCard {
        var card = self
        card.x = x.isFinite ? min(max(x, 0), 1) : 0.5
        card.y = y.isFinite ? min(max(y, 0), 1) : 0.5
        card.width = width.isFinite ? min(max(width, Self.widthRange.lowerBound), Self.widthRange.upperBound) : Self.defaultWidth
        card.aspect = aspect.isFinite && aspect > 0 ? min(max(aspect, 0.1), 10) : 1
        return card
    }

    /// Where the next card goes so it doesn't hide the ones already there: a step down and left from the last.
    public static func place(after cards: [ReferenceCard]) -> (x: Double, y: Double) {
        let step = Double(cards.count % 5)
        return (0.78 - step * 0.04, 0.3 + step * 0.06)
    }
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
    /// The unit lengths are shown and typed in (the scene is always in metres).
    public var units: LengthUnit
    /// The 3D printer whose build volume the stage outlines (`PrintBed.presets`), nil for none.
    public var printBed: String?
    /// The section view's cut, nil when it's off.
    public var section: SectionPlane?
    /// Kept dimensions show on the stage.
    public var showsDimensions: Bool
    /// The drawing guide over the frame for flipbooks (grid, isometric, perspective, symmetry), nil when off.
    public var frameGuide: DrawingGuide?
    /// The drawing guide on the 3D guide plane for ink and solid shapes (grid, isometric, symmetry), nil when off.
    public var planeGuide: DrawingGuide?
    /// Pictures pinned from the Schizzo board, floating over the stage.
    public var references: [ReferenceCard]

    /// `firstPanel` for a project that opens on its Schizzo board.
    public static let boardPanel = "board"
    public static let defaultTimelineHeight = 260.0
    public static let timelineHeightRange = 150.0 ... 900.0

    public init(template: StarterTemplate.Kind? = nil, timeline: TimelinePresence = .hidden, timelineHeight: Double = Self.defaultTimelineHeight,
                snap: SnapSettings = SnapSettings(), showsGrid: Bool = true, shapeSize: Double = 1, firstPanel: String? = nil,
                units: LengthUnit = .centimetre, printBed: String? = nil, section: SectionPlane? = nil, showsDimensions: Bool = true,
                frameGuide: DrawingGuide? = nil, planeGuide: DrawingGuide? = nil, references: [ReferenceCard] = []) {
        schemaVersion = Self.schemaVersion
        self.template = template
        self.timeline = timeline
        self.timelineHeight = timelineHeight
        self.snap = snap
        self.showsGrid = showsGrid
        self.shapeSize = shapeSize
        self.firstPanel = firstPanel
        self.units = units
        self.printBed = printBed
        self.section = section
        self.showsDimensions = showsDimensions
        self.frameGuide = frameGuide
        self.planeGuide = planeGuide
        self.references = references
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, template, timeline, timelineHeight, snap, showsGrid, shapeSize, firstPanel, units, printBed, section, showsDimensions
        case frameGuide, planeGuide, references
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
        units = (try? container.decodeIfPresent(LengthUnit.self, forKey: .units)) ?? defaults.units
        printBed = (try? container.decodeIfPresent(String.self, forKey: .printBed)).flatMap { PrintBed.preset($0)?.id }
        section = try? container.decodeIfPresent(SectionPlane.self, forKey: .section)
        showsDimensions = (try? container.decodeIfPresent(Bool.self, forKey: .showsDimensions)) ?? defaults.showsDimensions
        frameGuide = try? container.decodeIfPresent(DrawingGuide.self, forKey: .frameGuide)
        planeGuide = try? container.decodeIfPresent(DrawingGuide.self, forKey: .planeGuide)
        references = ((try? container.decodeIfPresent([ReferenceCard].self, forKey: .references)) ?? []).map(\.clamped)
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
