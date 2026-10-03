import Foundation
import LoweyCore
import Observation
import SwiftUI

/// The timeline's view state and geometry: rows in outliner order, their heights, time ↔ x, and what a drag on the
/// lanes is doing. One per timeline pane.
@Observable
@MainActor
final class TimelineLayout {
    static let labelWidth: CGFloat = 150
    static let rowHeight: CGFloat = 30
    static let rulerHeight: CGFloat = 30
    static let audioRowHeight: CGFloat = 38
    static let wordsRowHeight: CGFloat = 24
    static let lanesSpace = "timeline-lanes"

    /// A row of the lanes.
    enum Row: Hashable {
        case object(ObjectID)
        case track(TrackID)
        case audio(String)
        case words
        case effects
        case flipbook(String)
    }

    /// What a drag on the lanes does, decided once as it starts.
    enum LaneDrag {
        case moveKeys
        case pan(start: Double)
        case scrollRows(start: CGFloat)
        case marquee(origin: CGPoint)
        case ignore
    }

    enum StretchEdge { case start, end }

    @ObservationIgnored let editor: EditorModel
    var rowScroll: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var laneWidth: CGFloat = 0
    /// Live offset of the selected keys while dragged.
    var keyDrag: Double?
    var composeDrag: (ids: Set<ObjectID>, delta: Double)?
    var marquee: CGRect?
    var marqueeKeys: Set<KeyRef> = []
    var marqueeArmed = false
    var stretch: (edge: StretchEdge, time: Double)?
    @ObservationIgnored var laneDrag: LaneDrag?
    @ObservationIgnored var zoomStart: Double?
    @ObservationIgnored var zoomAnchor: (time: Double, x: CGFloat)?
    @ObservationIgnored let momentum = TimelineMomentum()
    @ObservationIgnored let rowMomentum = TimelineMomentum()

    init(editor: EditorModel) {
        self.editor = editor
    }

    var timeline: Timeline { editor.timeline }
    var pps: Double { editor.timelineZoom }
    var visibleStart: Double { editor.timelineStart }

    func x(_ time: Double) -> CGFloat { CGFloat((time - editor.timelineStart) * editor.timelineZoom) }
    func time(at x: CGFloat) -> Double { editor.timelineStart + Double(x) / editor.timelineZoom }

    func fit(width: CGFloat) {
        editor.timelineZoom = max(Double(width - 20) / max(timeline.duration, 1), 10)
        editor.timelineStart = 0
    }

    // MARK: Rows

    var showsCutRow: Bool { !timeline.cuts.isEmpty || !editor.cameras.isEmpty }

    /// Animated (and selected) objects under the groups they live in.
    var outline: [TimelineOutline.Entry] {
        TimelineOutline.entries(scene: editor.baseScene, include: timeline.animatedObjects.union(editor.selection), collapsed: editor.collapsedGroups)
    }

    var rows: [Row] {
        var result: [Row] = timeline.audio.map { .audio($0.id) }
        if !timeline.transcripts.isEmpty { result.append(.words) }
        if !timeline.effects.isEmpty { result.append(.effects) }
        result += timeline.flipbooks.map { .flipbook($0.id) }
        for entry in outline {
            result.append(.object(entry.id))
            if editor.expandedObjects.contains(entry.id) {
                result += timeline.tracks.filter { $0.target == entry.id }.map { .track($0.id) }
            }
        }
        return result
    }

    func entry(_ id: ObjectID) -> TimelineOutline.Entry? { outline.first { $0.id == id } }

    /// A group row stands for everything animated inside it; any other row for its object.
    func members(of id: ObjectID) -> Set<ObjectID> {
        guard entry(id)?.isGroup == true else { return [id] }
        return Set(TimelineOutline.members(of: id, scene: editor.baseScene, animated: timeline.animatedObjects))
    }

    static func height(of row: Row) -> CGFloat {
        switch row {
        case .track: rowHeight - 4
        case .audio: audioRowHeight
        case .words, .effects: wordsRowHeight
        case .object, .flipbook: rowHeight
        }
    }

    /// Vertical layout of the rows (fixed heights, 1 pt apart), the cut row first.
    var slots: [(row: Row?, minY: CGFloat, height: CGFloat)] {
        var result: [(row: Row?, minY: CGFloat, height: CGFloat)] = []
        var y: CGFloat = 0
        if showsCutRow {
            result.append((nil, y, Self.rowHeight))
            y += Self.rowHeight + 1
        }
        for row in rows {
            let height = Self.height(of: row)
            result.append((row, y, height))
            y += height + 1
        }
        return result
    }

    func trackIDs(for row: Row) -> [TrackID] {
        switch row {
        case let .object(id):
            let ids = members(of: id)
            return timeline.tracks.filter { ids.contains($0.target) }.map(\.id)
        case let .track(id): return [id]
        case .audio, .words, .effects, .flipbook: return []
        }
    }

    func row(at y: CGFloat) -> Row? {
        slots.first { y >= $0.minY && y < $0.minY + $0.height + 1 }?.row
    }

    /// The key under a point in the lanes' space (within 14 pt).
    func key(at point: CGPoint) -> KeyRef? {
        guard point.x >= Self.labelWidth, let row = row(at: point.y) else { return nil }
        let keys = KeySelection.all(in: timeline, tracks: Set(trackIDs(for: row)))
        let location = point.x - Self.labelWidth
        guard let best = keys.min(by: { abs(x($0.time) - location) < abs(x($1.time) - location) }), abs(x(best.time) - location) < 14 else { return nil }
        return best
    }

    /// Audio, word and effect rows handle their own touches.
    func isOwnGestureRow(at y: CGFloat) -> Bool {
        switch row(at: y) {
        case .audio, .words, .effects, .flipbook: true
        default: false
        }
    }

    // MARK: Scrolling rows

    var contentHeight: CGFloat {
        if rows.isEmpty { return (showsCutRow ? Self.rowHeight + 1 : 0) + 60 }
        return slots.last.map { $0.minY + $0.height + 1 } ?? 0
    }

    var maxScroll: CGFloat { max(contentHeight - viewportHeight, 0) }
    var scrollOffset: CGFloat { min(max(rowScroll, 0), maxScroll) }

    /// A point in the lanes' viewport as the same point in the rows' own space.
    func toContent(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: point.y + scrollOffset) }

    // MARK: Previews while dragging

    /// Where a selected key is drawn while the selection is dragged or stretched.
    var previewTime: (Double) -> Double {
        if let keyDrag { return { $0 + keyDrag } }
        if let stretch, let span = KeySelection.span(of: editor.selectedKeys) {
            let target = stretchTarget(span: span, stretch: stretch)
            return { KeySelection.stretchedTime($0, from: span, to: target) }
        }
        return { $0 }
    }

    func stretchTarget(span: TimeRange, stretch: (edge: StretchEdge, time: Double)) -> TimeRange {
        switch stretch.edge {
        case .start: TimeRange(start: max(0, min(stretch.time, span.end)), end: span.end)
        case .end: TimeRange(start: span.start, end: max(stretch.time, span.start))
        }
    }

    static func color(for property: PropertyKey) -> Color {
        switch property {
        case .position: Color(red: 0.96, green: 0.45, blue: 0.4)
        case .rotation: Color(red: 0.45, green: 0.8, blue: 0.45)
        case .scale: Color(red: 0.4, green: 0.6, blue: 1)
        case .opacity, .visible: .white
        case .fieldOfView, .focusDistance, .aperture: .teal
        default: .orange
        }
    }

    static func cameraColor(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .teal, .indigo, .pink, .orange]
        return colors[index % colors.count].opacity(0.55)
    }
}

/// A flick keeps the timeline gliding, slowing like a scroll view.
@MainActor
final class TimelineMomentum {
    private var clock = PlaybackClock()
    private var velocity: Double = 0
    private var step: ((Double) -> Bool)?
    private var stopBelow: Double = 0

    /// `step` applies an offset and returns false when it hit an end (the glide stops there).
    func start(velocity: Double, pointsPerSecond: Double, step: @escaping (Double) -> Bool) {
        stop()
        guard abs(velocity * pointsPerSecond) > 60 else { return }
        self.velocity = velocity
        self.step = step
        stopBelow = 12 / max(pointsPerSecond, 1e-6)
        clock.onTick = { [weak self] dt in self?.tick(dt) }
        clock.start()
    }

    func stop() {
        clock.stop()
        step = nil
    }

    private func tick(_ dt: Double) {
        guard let step, dt > 0 else { return }
        guard step(velocity * dt) else {
            stop()
            return
        }
        velocity *= pow(0.998, dt * 1000)
        if abs(velocity) < stopBelow { stop() }
    }
}
