import HmmDesign
import LoweyCore
import SwiftUI

/// One row of the lanes.
struct TimelineRowView: View {
    let editor: EditorModel
    let layout: TimelineLayout
    let row: TimelineLayout.Row
    let width: CGFloat
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        switch row {
        case let .object(id):
            let entry = layout.entry(id)
            HStack(spacing: 0) {
                ObjectLabel(editor: editor, id: id, entry: entry)
                if editor.timelineMode == .compose {
                    ComposeBar(editor: editor, layout: layout, id: id, width: width)
                } else {
                    ZStack(alignment: .leading) {
                        Spans(editor: editor, layout: layout, ids: layout.members(of: id), width: width)
                        KeyLane(editor: editor, layout: layout, tracks: editor.timeline.tracks.filter { layout.members(of: id).contains($0.target) },
                                width: width, color: entry?.isGroup == true ? theme.accent.opacity(0.6) : theme.accent)
                    }
                }
            }
            .frame(height: TimelineLayout.rowHeight)
            .background(editor.selection.contains(id) ? theme.accent.opacity(0.08) : (entry?.isGroup == true ? theme.text.opacity(0.03) : .clear))
        case let .track(trackID):
            if let track = editor.timeline.track(trackID) {
                HStack(spacing: 0) {
                    Text(track.property.spec?.label ?? track.property.rawValue)
                        .font(.hmm(.caption)).foregroundStyle(theme.text2).lineLimit(1)
                        .padding(.leading, 30)
                        .frame(width: TimelineLayout.labelWidth, alignment: .leading)
                    KeyLane(editor: editor, layout: layout, tracks: [track], width: width, color: TimelineLayout.color(for: track.property))
                }
                .frame(height: TimelineLayout.rowHeight - 4)
            }
        case let .audio(id):
            if let clip = editor.audioClip(id) {
                AudioRow(editor: editor, layout: layout, clip: clip, width: width).frame(height: TimelineLayout.audioRowHeight)
            }
        case .words:
            WordsRow(editor: editor, layout: layout, width: width).frame(height: TimelineLayout.wordsRowHeight)
        case .effects:
            EffectsRow(editor: editor, layout: layout, width: width).frame(height: TimelineLayout.wordsRowHeight)
        case let .flipbook(id):
            if let track = editor.timeline.flipbook(id) {
                FlipbookRow(editor: editor, layout: layout, track: track, width: width)
            }
        }
    }
}

private struct ObjectLabel: View {
    let editor: EditorModel
    let id: ObjectID
    let entry: TimelineOutline.Entry?
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let object = editor.baseScene.objects[id]
        let hasTracks = editor.timeline.tracks.contains { $0.target == id }
        let isGroup = entry?.isGroup == true
        let isOpen = isGroup ? entry?.isCollapsed != true : editor.expandedObjects.contains(id)
        HStack(spacing: 4) {
            Button {
                if isGroup {
                    editor.collapsedGroups.formSymmetricDifference([id])
                } else {
                    editor.expandedObjects.formSymmetricDifference([id])
                }
            } label: {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 28)
                    .foregroundStyle(isGroup || hasTracks ? theme.text2 : .clear)
            }
            .buttonStyle(.plain)
            .disabled(!(isGroup || hasTracks))
            .accessibilityLabel(isOpen ? "Fold \(object?.name ?? "")" : "Unfold \(object?.name ?? "")")
            if isGroup { Image(systemName: "folder.fill").font(.system(size: 11)).foregroundStyle(theme.accent.opacity(0.85)) }
            Text(object?.name ?? "?").font(.hmm(.footnote, weight: editor.selection.contains(id) ? .semibold : .regular)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 6 + CGFloat(entry?.depth ?? 0) * 12)
        .frame(width: TimelineLayout.labelWidth, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { editor.select(id) }
        .accessibilityAddTraits(.isButton)
        .hmmHoldMenu(editor.holdMenu(for: [id], extras: isGroup ? [
            HmmHoldMenu.Item("Select everything inside", systemName: "square.stack.3d.up") { editor.setSelection(editor.baseScene.subtree(of: id)) }
        ] : nil))
    }
}

/// Behaviour spans (lines) and clip segments (capsules) under the keys.
private struct Spans: View {
    let editor: EditorModel
    let layout: TimelineLayout
    let ids: Set<ObjectID>
    let width: CGFloat

    var body: some View {
        Canvas { context, size in
            for behavior in editor.timeline.behaviors where ids.contains(behavior.target) {
                let start = layout.x(behavior.start)
                let end = layout.x(behavior.end ?? editor.timeline.duration)
                context.fill(Path(roundedRect: CGRect(x: start, y: size.height - 6, width: max(end - start, 2), height: 3), cornerRadius: 1.5),
                             with: .color(Color.purple.opacity(behavior.enabled ? 0.8 : 0.3)))
            }
            for track in editor.timeline.clipTracks where ids.contains(track.target) {
                for segment in track.segments {
                    let picked = editor.selectedClips.contains(segment.id)
                    let shift = picked ? layout.keyDrag ?? 0 : 0
                    let rect = CGRect(x: layout.x(segment.start + shift), y: 3, width: max(CGFloat(segment.duration * layout.pps), 4),
                                      height: size.height - 10)
                    context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(Color.teal.opacity(picked ? 0.6 : 0.3)))
                    if picked { context.stroke(Path(roundedRect: rect, cornerRadius: 5), with: .color(.white.opacity(0.9)), lineWidth: 1.5) }
                    context.draw(Text(segment.clip.name).font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.8)),
                                 at: CGPoint(x: rect.minX + 6, y: rect.midY), anchor: .leading)
                }
            }
        }
        .frame(width: width)
        .allowsHitTesting(false)
    }
}

/// Keys as diamonds (selected ones white, drawn where they'll land while dragged).
struct KeyLane: View {
    let editor: EditorModel
    let layout: TimelineLayout
    let tracks: [Track]
    let width: CGFloat
    let color: Color

    var body: some View {
        let keys = tracks.flatMap { track in track.keyframes.map { KeyRef(track: track.id, time: $0.time) } }
        let selected = editor.selectedKeys.union(layout.marqueeKeys)
        let preview = layout.previewTime
        Canvas { context, size in
            let y = size.height / 2
            for key in keys {
                let isSelected = selected.contains(key)
                let x = layout.x(isSelected ? preview(key.time) : key.time)
                guard x > -8, x < size.width + 8 else { continue }
                var diamond = Path()
                diamond.move(to: CGPoint(x: x, y: y - 6))
                diamond.addLine(to: CGPoint(x: x + 6, y: y))
                diamond.addLine(to: CGPoint(x: x, y: y + 6))
                diamond.addLine(to: CGPoint(x: x - 6, y: y))
                diamond.closeSubpath()
                context.fill(diamond, with: .color(isSelected ? .white : color))
                context.stroke(diamond, with: .color(.black.opacity(0.5)), lineWidth: 1)
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
    }
}

/// Compose: an object's whole animation as a bar; a selected bar slides in time (with the rest of the selection).
private struct ComposeBar: View {
    let editor: EditorModel
    let layout: TimelineLayout
    let id: ObjectID
    let width: CGFloat
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let ids = layout.members(of: id)
        let times = editor.timeline.tracks.filter { ids.contains($0.target) }.flatMap { $0.keyframes.map(\.time) }
        let selected = editor.selection.contains(id)
        let moving = layout.composeDrag.map { !$0.ids.isDisjoint(with: ids) } ?? false
        let delta = moving ? layout.composeDrag?.delta ?? 0 : 0
        ZStack(alignment: .leading) {
            Spans(editor: editor, layout: layout, ids: ids, width: width)
            if let start = times.min(), let end = times.max() {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.accent.opacity(selected ? 0.85 : 0.45))
                    .frame(width: max(CGFloat((end - start) * layout.pps), 10), height: TimelineLayout.rowHeight - 10)
                    .offset(x: layout.x(start + delta))
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in layout.composeDrag = (group(ids), Double(value.translation.width) / layout.pps) }
                            .onEnded { value in
                                editor.shiftAnimation(of: group(ids), by: Double(value.translation.width) / layout.pps)
                                layout.composeDrag = nil
                            },
                        including: selected ? .all : .subviews
                    )
                    .onTapGesture { editor.select(id, additive: editor.keyBoxSelect) }
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(width: width, alignment: .leading)
        .clipped()
    }

    /// A selected bar moves what it stands for and every other selected animated thing.
    private func group(_ ids: Set<ObjectID>) -> Set<ObjectID> {
        guard editor.selection.contains(id), editor.selection.count > 1 else { return ids }
        return Set(editor.selection.filter { editor.timeline.animatedObjects.contains($0) }).union(ids)
    }
}

/// The camera's shots: one block per cut; tap to jump and select the camera, touch and hold to remove the cut.
struct CutRow: View {
    let editor: EditorModel
    let layout: TimelineLayout
    let width: CGFloat
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let cuts = editor.timeline.cuts.sorted { $0.time < $1.time }
        HStack(spacing: 0) {
            Label("Camera", systemImage: "video").font(.hmm(.footnote, weight: .semibold)).padding(.leading, 10)
                .frame(width: TimelineLayout.labelWidth, alignment: .leading)
            ZStack(alignment: .leading) {
                ForEach(Array(cuts.enumerated()), id: \.offset) { index, cut in
                    let end = index + 1 < cuts.count ? cuts[index + 1].time : editor.timeline.duration
                    Text(editor.baseScene.objects[cut.camera]?.name ?? "Camera")
                        .font(.system(size: 11, weight: .semibold)).lineLimit(1).padding(.horizontal, 6)
                        .frame(width: max(CGFloat((end - cut.time) * layout.pps) - 2, 8), height: TimelineLayout.rowHeight - 8, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 5).fill(TimelineLayout.cameraColor(index)))
                        .offset(x: layout.x(cut.time))
                        .onTapGesture {
                            editor.setTime(cut.time)
                            editor.selectCamera(cut.camera)
                        }
                        .accessibilityAddTraits(.isButton)
                        .hmmHoldMenu(HmmHoldMenu(delete: { editor.removeCut(at: cut.time) }))
                }
                if cuts.isEmpty { Text("Select a camera and tap Cut here").font(.hmm(.caption)).foregroundStyle(theme.text3).padding(.leading, 8) }
            }
            .frame(width: width, height: TimelineLayout.rowHeight, alignment: .leading)
            .clipped()
        }
    }
}
