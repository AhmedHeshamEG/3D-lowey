import Foundation
import HmmBrush

/// Where board units land in a picture's pixels: pixel = unit × scale + offset.
public struct BoardPlacement: Hashable, Sendable {
    public var offset: Vec2
    /// Pixels per board unit.
    public var scale: Double

    public init(offset: Vec2, scale: Double) {
        self.offset = offset
        self.scale = scale
    }

    /// The screen: a view of `size` points at `contentScale` pixels a point.
    public init(viewport: BoardViewport, size: Vec2, contentScale: Double) {
        scale = viewport.scale * contentScale
        offset = (size * 0.5 - viewport.center * viewport.scale) * contentScale
    }

    /// A picture of one part of the board, its top left at the picture's.
    public init(region: BoardRect, pixelsPerUnit: Double) {
        scale = pixelsPerUnit
        offset = Vec2(-region.x * pixelsPerUnit, -region.y * pixelsPerUnit)
    }

    public func apply(_ point: Vec2) -> Vec2 { point * scale + offset }

    public func corners(_ rect: BoardRect) -> [Vec2] {
        // Top left, top right, bottom left, bottom right: a triangle strip.
        [Vec2(rect.minX, rect.minY), Vec2(rect.maxX, rect.minY), Vec2(rect.minX, rect.maxY), Vec2(rect.maxX, rect.maxY)].map(apply)
    }
}

/// Words to draw: a note's text or a frame's title, laid out in a box of board units.
public struct BoardTextSpec: Hashable, Sendable {
    public var text: String
    /// The box, in board units.
    public var width: Double
    public var height: Double
    public var fontSize: Double
    public var color: BoardColor
    public var isTitle: Bool
    /// Pixels per board unit the words are drawn at: a power of two at or above the zoom, so they stay sharp
    /// without being redrawn at every step of a pinch.
    public var resolution: Double

    public static func resolution(for pixelsPerUnit: Double) -> Double {
        pow(2, log2(max(pixelsPerUnit, 1e-6)).rounded(.up)).clamped(1, 8)
    }
}

/// One thing for the renderer to draw, already in pixels (strokes keep their own units: the brush shader places
/// them).
public enum BoardDraw: Hashable, Sendable {
    case stroke(BoardStroke, brush: Brush)
    /// Triangles, three points each, in one colour at an opacity.
    case fill([Vec2], color: BoardColor, opacity: Double)
    /// A picture from the board's assets in a quad (corners as a strip).
    case picture(asset: String, corners: [Vec2])
    case text(BoardTextSpec, corners: [Vec2])
}

/// What a board looks like, as a list of draws. The screen, a pin's picture and a shared image all come from here.
public enum BoardDrawList {
    static let noteRadius = 6.0
    static let notePadding = 12.0
    static let noteFontSize = 17.0
    static let titleFontSize = 13.0

    /// The paper's pattern over `rect` (the paper's own colour is the picture's background).
    public static func paper(_ paper: BoardPaper, over rect: BoardRect, placement: BoardPlacement, viewScale: Double,
                             contentScale: Double) -> [BoardDraw] {
        // The marks are about a point and a half wide on screen whatever the zoom.
        let mark = 1.5 * contentScale / max(placement.scale, 1e-9)
        let triangles = BoardShapes.paper(paper.pattern, over: rect, scale: viewScale, mark: mark).map(placement.apply)
        return triangles.isEmpty ? [] : [.fill(triangles, color: paper.faint, opacity: 1)]
    }

    /// Items back to front. Those wholly outside `clip` (board units) are left out; `editingNote` keeps its slip but
    /// not its words (the text field shows them).
    public static func items(_ items: [BoardItem], on board: Board, placement: BoardPlacement, clip: BoardRect? = nil, editingNote: String? = nil,
                             contentScale: Double = 1) -> [BoardDraw] {
        var draws: [BoardDraw] = []
        for item in items {
            if let clip, !item.bounds.intersects(clip) { continue }
            switch item.content {
            case let .stroke(stroke):
                draws.append(.stroke(stroke, brush: BrushResolver.brush(stroke.brush, in: board.brushes)))
            case let .picture(picture):
                draws.append(.picture(asset: picture.asset, corners: placement.corners(picture.rect)))
            case let .note(note):
                draws += self.note(note, placement: placement, showsText: item.id != editingNote)
            case let .arrow(arrow):
                draws.append(.fill(arrow.triangles.map(placement.apply), color: arrow.color, opacity: 1))
            case let .frame(frame):
                draws += self.frame(frame, paper: board.paper, placement: placement, contentScale: contentScale)
            }
        }
        return draws
    }

    static func note(_ note: BoardNote, placement: BoardPlacement, showsText: Bool) -> [BoardDraw] {
        var draws: [BoardDraw] = [.fill(BoardShapes.roundedRect(note.rect, radius: noteRadius).map(placement.apply), color: note.color, opacity: 1)]
        let inner = note.rect.expanded(by: -notePadding)
        guard showsText, !note.text.isEmpty, inner.width > 4, inner.height > 4 else { return draws }
        // Dark words on a light slip, light on a dark one.
        let ink = note.color.luminance > 0.5 ? BoardColor(red: 0.1, green: 0.1, blue: 0.11) : BoardColor(red: 0.95, green: 0.95, blue: 0.96)
        let spec = BoardTextSpec(text: note.text, width: inner.width, height: inner.height, fontSize: noteFontSize, color: ink, isTitle: false,
                                 resolution: BoardTextSpec.resolution(for: placement.scale))
        draws.append(.text(spec, corners: placement.corners(inner)))
        return draws
    }

    static func frame(_ frame: BoardFrame, paper: BoardPaper, placement: BoardPlacement, contentScale: Double) -> [BoardDraw] {
        let rect = BoardRect(placement.apply(Vec2(frame.rect.minX, frame.rect.minY)), placement.apply(Vec2(frame.rect.maxX, frame.rect.maxY)))
        var draws: [BoardDraw] = [.fill(BoardShapes.outline(rect, thickness: 1.5 * contentScale), color: paper.ink, opacity: 0.35)]
        let title = frame.titleRect.expanded(by: -4)
        guard !frame.title.isEmpty, title.width > 4 else { return draws }
        let spec = BoardTextSpec(text: frame.title, width: title.width, height: title.height, fontSize: titleFontSize, color: paper.ink,
                                 isTitle: true, resolution: BoardTextSpec.resolution(for: placement.scale))
        draws.append(.text(spec, corners: placement.corners(title)))
        return draws
    }

    /// What floats over the board while it is worked on, in the accent colour: the selection's box and handles, the
    /// box being dragged out, the eraser's reach, the Pencil's point when it hovers.
    public struct Overlay: Hashable, Sendable {
        public var selection: BoardRect?
        public var showsHandles = true
        public var marquee: BoardRect?
        /// The eraser's middle (board units) and reach.
        public var eraser: Vec2?
        public var eraserRadius = 0.0
        /// Where the Pencil hovers (board units).
        public var hover: Vec2?
        public var accent: BoardColor
        public var ink: BoardColor

        public init(accent: BoardColor, ink: BoardColor) {
            self.accent = accent
            self.ink = ink
        }
    }

    public static func overlay(_ overlay: Overlay, placement: BoardPlacement, contentScale: Double) -> [BoardDraw] {
        var draws: [BoardDraw] = []
        let line = 1.5 * contentScale
        if let marquee = overlay.marquee {
            let rect = pixels(marquee, placement)
            draws.append(.fill(BoardShapes.quad(rect), color: overlay.accent, opacity: 0.10))
            draws.append(.fill(BoardShapes.outline(rect, thickness: line), color: overlay.accent, opacity: 1))
        }
        if let selection = overlay.selection {
            let rect = pixels(selection, placement)
            draws.append(.fill(BoardShapes.outline(rect, thickness: line), color: overlay.accent, opacity: 1))
            if overlay.showsHandles {
                let handles = BoardShapes.handles(of: rect)
                draws.append(.fill(handles.flatMap { BoardShapes.disc(center: $0, radius: 5.5 * contentScale, segments: 16) }, color: overlay.accent,
                                   opacity: 1))
                draws.append(.fill(handles.flatMap { BoardShapes.disc(center: $0, radius: 3 * contentScale, segments: 12) }, color: overlay.ink,
                                   opacity: 1))
            }
        }
        if let eraser = overlay.eraser {
            let ring = BoardShapes.ring(center: placement.apply(eraser), radius: overlay.eraserRadius * placement.scale, thickness: line)
            draws.append(.fill(ring, color: overlay.ink, opacity: 0.8))
        }
        if let hover = overlay.hover {
            let point = BoardShapes.disc(center: placement.apply(hover), radius: 2.5 * contentScale, segments: 12)
            draws.append(.fill(point, color: overlay.ink, opacity: 1))
        }
        return draws
    }

    private static func pixels(_ rect: BoardRect, _ placement: BoardPlacement) -> BoardRect {
        BoardRect(placement.apply(Vec2(rect.minX, rect.minY)), placement.apply(Vec2(rect.maxX, rect.maxY)))
    }
}
