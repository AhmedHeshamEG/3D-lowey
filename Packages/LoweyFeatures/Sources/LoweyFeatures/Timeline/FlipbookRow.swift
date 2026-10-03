import HmmDesign
import LoweyCore
import SwiftUI

/// A flipbook track: its drawings as cells as long as their holds (a looping track repeats them faded). Tap a cell to
/// go to that drawing and draw into it; drag the cells to move the track in time; touch and hold for its menu.
struct FlipbookRow: View {
    let editor: EditorModel
    let layout: TimelineLayout
    let track: FlipbookTrack
    let width: CGFloat
    @State private var drag: Double?
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Label(track.name, systemImage: track.anchor == .camera ? "book.pages" : "link")
                .font(.hmm(.caption, weight: .semibold)).lineLimit(1)
                .foregroundStyle(isActive ? theme.accent : theme.text2)
                .padding(.leading, 10).frame(width: TimelineLayout.labelWidth, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    editor.flipbook.track = track.id
                    editor.tool = .flipbook
                }
            ZStack(alignment: .leading) {
                ForEach(cells, id: \.offset) { cell in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(fill(for: cell))
                        .overlay(alignment: .leading) {
                            if !cell.repeat, cell.width > 18 {
                                Text("\(cell.index + 1)").font(.hmmNumbers(.caption2)).foregroundStyle(theme.text).padding(.leading, 4)
                            }
                        }
                        .frame(width: max(cell.width - 1, 2), height: TimelineLayout.rowHeight - 8)
                        .offset(x: cell.x + shift)
                        .onTapGesture { editor.showFlipbookDrawing(cell.index, of: track.id) }
                }
            }
            .frame(width: width, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { value in drag = Double(value.translation.width) / layout.pps }
                .onEnded { value in
                    let start = max(0, track.start + Double(value.translation.width) / layout.pps)
                    editor.flipbook.track = track.id
                    editor.updateFlipbook("Move flipbook") { $0.start = editor.timeline.snapped(start) }
                    drag = nil
                })
            .contextMenu {
                Button("Draw into it", systemImage: "pencil.tip") {
                    editor.flipbook.track = track.id
                    editor.tool = .flipbook
                }
                Button(track.visible ? "Hide" : "Show", systemImage: track.visible ? "eye.slash" : "eye") {
                    editor.flipbook.track = track.id
                    editor.updateFlipbook(track.visible ? "Hide flipbook" : "Show flipbook") { $0.visible.toggle() }
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    editor.flipbook.track = track.id
                    editor.deleteFlipbook()
                }
            }
        }
        .frame(height: TimelineLayout.rowHeight)
        .background(isActive ? theme.accent.opacity(0.08) : .clear)
        .opacity(track.visible ? 1 : 0.5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Flipbook \(track.name), \(track.frames.count) drawings")
    }

    private var isActive: Bool { editor.flipbook.track == track.id }

    /// How far the cells follow a drag.
    private var shift: CGFloat {
        CGFloat((drag ?? 0) * layout.pps)
    }

    private func fill(for cell: Cell) -> Color {
        if cell.repeat { return theme.text.opacity(0.08) }
        return cell.index == current ? theme.accent.opacity(0.7) : theme.text.opacity(0.18)
    }

    private var current: Int? {
        isActive ? editor.activeFlipbookFrame : nil
    }

    private struct Cell {
        var offset: Int
        var index: Int
        var x: CGFloat
        var width: CGFloat
        var `repeat`: Bool
    }

    /// One cell per drawing; a looping track's repeats up to its end (at most a few hundred).
    private var cells: [Cell] {
        let fps = Double(editor.timeline.fps)
        let end = track.end(fps: editor.timeline.fps, sceneDuration: editor.timeline.duration)
        var result: [Cell] = []
        var time = track.start
        var pass = 0
        while time < end - 1e-6, result.count < 400 {
            for (index, frame) in track.frames.enumerated() where time < end - 1e-6 {
                let length = min(Double(frame.hold) / fps, end - time)
                result.append(Cell(offset: result.count, index: index, x: layout.x(time), width: CGFloat(length * layout.pps), repeat: pass > 0))
                time += length
            }
            pass += 1
            if !track.loops || track.frames.isEmpty { break }
        }
        return result
    }
}
