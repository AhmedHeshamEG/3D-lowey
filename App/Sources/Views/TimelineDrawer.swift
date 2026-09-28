import LoweyCore
import LoweyRender
import SwiftUI

/// Bottom timeline drawer (Procreate Dreams-style): transport, ruler with markers and loop,
/// one row per animated object (expandable into property rows), camera cuts, and the three
/// modes — Compose (slide whole animations), Perform (record by touch), Keyframe (edit keys).
struct TimelineDrawer: View {
    @Bindable var editor: EditorModel
    /// Visible window: first second shown and zoom (points per second).
    @State private var visibleStart: Double = 0
    /// Live offset of the selected keys while they're dragged.
    @State private var keyDrag: Double?
    @State private var composeDrag: (ids: Set<ObjectID>, delta: Double)?
    @State private var laneDrag: LaneDrag?
    /// Selection box in the lanes' coordinate space, and the keys it would pick.
    @State private var marquee: CGRect?
    @State private var marqueeKeys: Set<KeyRef> = []
    /// A long press on the lanes arms the selection box for the drag that follows.
    @State private var marqueeArmed = false
    /// Live position of a dragged end of the selection band (stretching the selected keys).
    @State private var stretch: (edge: StretchEdge, time: Double)?
    @State private var zoomStart: Double?
    @State private var showSettings = false
    @State private var renamingMarker: Marker?
    @State private var markerName = ""

    static let labelWidth: CGFloat = 150
    static let rowHeight: CGFloat = 30
    static let rulerHeight: CGFloat = 30
    static let audioRowHeight: CGFloat = 38
    static let wordsRowHeight: CGFloat = 24

    private var timeline: Timeline { editor.timeline }
    private var pps: Double { editor.timelineZoom }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider().overlay(Theme.panelStroke)
            GeometryReader { geometry in
                let width = max(geometry.size.width - Self.labelWidth, 50)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        rulerLabel
                        ruler(width: width)
                    }
                    .frame(height: Self.rulerHeight)
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 1) {
                            if showsCutRow {
                                cutRow(width: width)
                            }
                            ForEach(rows, id: \.self) { row in
                                rowView(row, width: width)
                            }
                            if rows.isEmpty {
                                Text(emptyHint)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.secondaryText)
                                    .frame(maxWidth: .infinity, minHeight: 60)
                            }
                        }
                        .coordinateSpace(name: Self.lanesSpace)
                        .overlay(alignment: .topLeading) { marqueeView }
                        .simultaneousGesture(laneTap, including: editor.timelineMode == .compose ? .subviews : .all)
                        .simultaneousGesture(laneDragGesture, including: editor.timelineMode == .compose ? .subviews : .all)
                        .simultaneousGesture(marqueeLongPress, including: editor.timelineMode == .compose ? .subviews : .all)
                    }
                    .scrollDisabled(marqueeArmed || marquee != nil)
                }
                .overlay(alignment: .topLeading) { playhead(width: width, height: geometry.size.height) }
                .gesture(zoomGesture(width: width))
                .onAppear { fit(width: width) }
            }
        }
        .panelStyle()
        .sheet(item: Binding(get: { editor.graphKey.map { IdentifiedKey(key: $0) } }, set: { editor.graphKey = $0?.key })) { item in
            EasingEditor(editor: editor, key: item.key)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSettings) { TimelineSettingsSheet(editor: editor).presentationDetents([.medium]) }
        .sheet(isPresented: $editor.showAudio) { AudioSheet(editor: editor).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $editor.showTranscript) { TranscriptPanel(editor: editor).presentationDetents([.medium, .large]) }
        .alert("Marker", isPresented: Binding(get: { renamingMarker != nil }, set: { if !$0 { renamingMarker = nil } })) {
            TextField("Name (a word from the script)", text: $markerName)
            Button("Save") {
                if let marker = renamingMarker { editor.renameMarker(marker.id, to: markerName) }
                renamingMarker = nil
            }
            Button("Delete", role: .destructive) {
                if let marker = renamingMarker { editor.removeMarker(marker.id) }
                renamingMarker = nil
            }
            Button("Cancel", role: .cancel) { renamingMarker = nil }
        }
    }

    private var emptyHint: String {
        switch editor.timelineMode {
        case .perform: "Select something, press record, and move it while the timeline plays."
        case .keyframe: "Select something and move it: each change becomes a key at the playhead. Or tap a preset."
        case .compose: "Animated objects appear here as bars you can slide in time."
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            transport
            Text(Self.format(editor.time))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.text)
                .frame(minWidth: 70, alignment: .leading)
                .accessibilityIdentifier("timeline-time")
            Picker("Mode", selection: $editor.timelineMode) {
                ForEach(TimelineMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 270)
            .accessibilityIdentifier("timeline-mode")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    switch editor.timelineMode {
                    case .perform: performControls
                    case .keyframe: keyControls
                    case .compose: composeControls
                    }
                }
            }
            IconButton(systemName: "waveform", label: "Audio and words", isOn: editor.showAudio, size: 36) { editor.showAudio = true }
            IconButton(systemName: "flag", label: "Add marker", size: 36) { editor.addMarker() }
            Menu {
                Button("Loop starts here", systemImage: "arrow.right.to.line") { editor.setLoopStart() }
                Button("Loop ends here", systemImage: "arrow.left.to.line") { editor.setLoopEnd() }
                if timeline.loop != nil { Button("No loop", systemImage: "xmark") { editor.clearLoop() } }
            } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(timeline.loop != nil ? Color.black : Theme.text)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(timeline.loop != nil ? Theme.accent : Theme.raised))
            }
            .accessibilityLabel("Loop")
            IconButton(systemName: "slider.horizontal.3", label: "Timeline settings", size: 36) { showSettings = true }
        }
    }

    private var transport: some View {
        HStack(spacing: 6) {
            IconButton(systemName: "backward.end.fill", label: "To start", size: 34) {
                editor.pause()
                editor.setTime(editor.playRange.start)
            }
            IconButton(systemName: "chevron.left", label: "Previous frame", size: 34) { editor.step(frames: -1) }
            IconButton(systemName: editor.isPlaying ? "pause.fill" : "play.fill", label: editor.isPlaying ? "Pause" : "Play",
                       isOn: editor.isPlaying, size: 42) { editor.togglePlay() }
            IconButton(systemName: "chevron.right", label: "Next frame", size: 34) { editor.step(frames: 1) }
        }
    }

    @ViewBuilder private var keyControls: some View {
        PillButton(title: "Key", systemName: "diamond.fill", prominent: !editor.selection.isEmpty) { editor.keySelection() }
            .disabled(editor.selection.isEmpty)
        Toggle(isOn: $editor.autoKey) { Text("Auto-key").font(.system(size: 13, weight: .semibold)) }
            .toggleStyle(.button)
            .accessibilityIdentifier("auto-key")
        selectControls
        if !editor.selectedKeys.isEmpty {
            Menu {
                ForEach(EasingChoice.allCases) { choice in
                    Button(choice.title) { editor.setEasing(choice.easing) }
                }
                Divider()
                Button("Edit curve…", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                    editor.graphKey = editor.selectedKeys.min { $0.time < $1.time }
                }
            } label: {
                Label("Easing", systemImage: "point.topleft.down.to.point.bottomright.curvepath").pillLabel()
            }
            Menu {
                Button("Copy", systemImage: "doc.on.doc") { editor.copyKeys() }
                Button("Mirror (there and back)", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") { editor.mirrorKeys() }
                Button("Reverse", systemImage: "arrow.uturn.backward") { editor.reverseKeys() }
                Button("Twice as fast", systemImage: "hare") { editor.retimeKeys(0.5) }
                Button("Twice as slow", systemImage: "tortoise") { editor.retimeKeys(2) }
                Button("One frame earlier", systemImage: "chevron.left") { editor.nudgeSelectedKeys(frames: -1) }
                Button("One frame later", systemImage: "chevron.right") { editor.nudgeSelectedKeys(frames: 1) }
                Divider()
                Button("Delete keys", systemImage: "trash", role: .destructive) { editor.deleteSelectedKeys() }
            } label: {
                Label("\(editor.selectedKeys.count) key\(editor.selectedKeys.count == 1 ? "" : "s")", systemImage: "diamond").pillLabel()
            }
        }
        if editor.keyClipboard != nil {
            PillButton(title: "Paste", systemName: "doc.on.clipboard") { editor.pasteKeys() }
        }
    }

    /// Select mode (box select, taps add) and the Select menu — Procreate Dreams-style multi-select.
    @ViewBuilder private var selectControls: some View {
        Toggle(isOn: $editor.keyBoxSelect) {
            Label("Select", systemImage: "rectangle.dashed").font(.system(size: 13, weight: .semibold))
        }
        .toggleStyle(.button)
        .accessibilityIdentifier("key-select-mode")
        Menu {
            ForEach(KeyQuery.allCases) { query in
                if query != .loop || timeline.loop != nil {
                    Button(query.title, systemImage: query.systemImage) { editor.selectKeys(query) }
                }
            }
        } label: {
            Label(editor.selection.isEmpty ? "Pick" : "Pick in selection", systemImage: "checklist").pillLabel()
        }
        .accessibilityIdentifier("key-select-menu")
    }

    @ViewBuilder private var composeControls: some View {
        Text(editor.keyBoxSelect ? "Tap bars to pick several, then drag one to move them together" : "Drag a bar to move that animation in time")
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondaryText)
        Toggle(isOn: $editor.keyBoxSelect) {
            Label("Select", systemImage: "rectangle.dashed").font(.system(size: 13, weight: .semibold))
        }
        .toggleStyle(.button)
        if !editor.selection.isEmpty, editor.selectionHasAnimation {
            PillButton(title: "Clear animation", systemName: "xmark.bin", destructive: true) { editor.clearAnimation() }
        }
    }

    @ViewBuilder private var performControls: some View {
        Button {
            if editor.performPhase == .recording {
                editor.pause()
            } else {
                editor.armPerform()
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 14, height: 14)
                Text(recordTitle).font(.system(size: 14, weight: .bold))
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .foregroundStyle(Theme.text)
            .background(Capsule().fill(editor.performPhase == .idle ? Theme.raised : Color.red.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("perform-record")
        VStack(alignment: .leading, spacing: 0) {
            Text("Smoothing \(Int(editor.performSettings.smoothing * 100))%")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            Slider(value: $editor.performSettings.smoothing, in: 0 ... 1)
                .frame(width: 130)
        }
        Toggle(isOn: $editor.performSettings.barrelRoll) {
            Label("Pencil roll", systemImage: "applepencil.and.scribble").font(.system(size: 13, weight: .semibold))
        }
        .toggleStyle(.button)
        PerformValueSlider(editor: editor)
    }

    private var recordTitle: String {
        switch editor.performPhase {
        case .idle: "Record"
        case let .countdown(count): "Ready… \(count)"
        case .recording: "Stop"
        }
    }

    // MARK: Ruler

    private var rulerLabel: some View {
        HStack {
            Text(editor.timelineMode == .compose ? "Animations" : "Tracks")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: Self.labelWidth)
    }

    private func ruler(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                if let loop = timeline.loop {
                    let rect = CGRect(x: x(loop.start), y: 0, width: CGFloat(loop.duration * pps), height: size.height)
                    context.fill(Path(rect), with: .color(Theme.accent.opacity(0.18)))
                }
                let end = CGRect(x: x(timeline.duration), y: 0, width: max(size.width - x(timeline.duration), 0), height: size.height)
                context.fill(Path(end), with: .color(.black.opacity(0.35)))
                let step = Self.tickStep(pps: pps)
                var t = (visibleStart / step).rounded(.down) * step
                while x(t) < size.width {
                    let px = x(t)
                    if px >= 0 {
                        let major = abs((t / (step * 5)).rounded() * step * 5 - t) < 1e-6
                        var tick = Path()
                        tick.move(to: CGPoint(x: px, y: size.height))
                        tick.addLine(to: CGPoint(x: px, y: size.height - (major ? 12 : 6)))
                        context.stroke(tick, with: .color(.white.opacity(major ? 0.5 : 0.25)), lineWidth: 1)
                        if major {
                            context.draw(Text(Self.shortFormat(t)).font(.system(size: 10, weight: .medium)).foregroundColor(.white.opacity(0.6)),
                                         at: CGPoint(x: px + 3, y: 9), anchor: .leading)
                        }
                    }
                    t += step
                }
            }
            selectionBand(width: width)
            ForEach(timeline.markers) { marker in
                if x(marker.time) >= -4, x(marker.time) <= width {
                    MarkerFlag(marker: marker)
                        .offset(x: x(marker.time) - 2, y: 0)
                        .onTapGesture { editor.setTime(marker.time) }
                        .onLongPressGesture {
                            markerName = marker.name
                            renamingMarker = marker
                        }
                }
            }
        }
        .frame(width: width, height: Self.rulerHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    editor.pause()
                    let before = editor.time
                    editor.setTime(editor.wordSnapped(time(at: value.location.x), tolerance: 8 / pps))
                    if editor.time != before { editor.audioPlayback.scrub(timeline.audio, at: editor.time) }
                }
        )
        .accessibilityIdentifier("timeline-ruler")
    }

    private func playhead(width: CGFloat, height: CGFloat) -> some View {
        let px = x(editor.time)
        return Rectangle()
            .fill(Theme.accent)
            .frame(width: 2, height: height)
            .offset(x: Self.labelWidth + px - 1)
            .opacity(px >= 0 && px <= width ? 1 : 0)
            .allowsHitTesting(false)
    }

    // MARK: Rows

    /// Object rows (and expanded property rows) in outliner order.
    enum Row: Hashable {
        case object(ObjectID)
        case track(TrackID)
        /// An audio clip (waveform).
        case audio(String)
        /// Spoken words of the voiceover, as chips you can tap.
        case words
    }

    private var rows: [Row] {
        let animated = timeline.animatedObjects
        let wanted = animated.union(editor.selection)
        var result: [Row] = timeline.audio.map { .audio($0.id) }
        if !timeline.transcripts.isEmpty { result.append(.words) }
        for id in editor.baseScene.orderedIDs() where wanted.contains(id) {
            result.append(.object(id))
            if editor.expandedObjects.contains(id) {
                result += timeline.tracks.filter { $0.target == id }.map { .track($0.id) }
            }
        }
        return result
    }

    @ViewBuilder
    private func rowView(_ row: Row, width: CGFloat) -> some View {
        switch row {
        case let .object(id):
            HStack(spacing: 0) {
                objectLabel(id)
                objectLane(id, width: width)
            }
            .frame(height: Self.rowHeight)
            .background(editor.selection.contains(id) ? Theme.accent.opacity(0.08) : Color.clear)
        case let .audio(id):
            if let clip = editor.audioClip(id) {
                AudioRow(editor: editor, clip: clip, width: width, x: x, pps: pps)
                    .frame(height: Self.audioRowHeight)
            }
        case .words:
            wordsRow(width: width)
                .frame(height: Self.wordsRowHeight)
        case let .track(trackID):
            if let track = timeline.track(trackID) {
                HStack(spacing: 0) {
                    Text(track.property.spec?.label ?? track.property.rawValue)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .padding(.leading, 30)
                        .frame(width: Self.labelWidth, alignment: .leading)
                    keyLane([track], width: width, color: Self.color(for: track.property))
                }
                .frame(height: Self.rowHeight - 4)
            }
        }
    }

    private func objectLabel(_ id: ObjectID) -> some View {
        let object = editor.baseScene.objects[id]
        let hasTracks = timeline.tracks.contains { $0.target == id }
        return HStack(spacing: 4) {
            Button {
                if editor.expandedObjects.contains(id) {
                    editor.expandedObjects.remove(id)
                } else {
                    editor.expandedObjects.insert(id)
                }
            } label: {
                Image(systemName: editor.expandedObjects.contains(id) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 24)
                    .foregroundStyle(hasTracks ? Theme.secondaryText : Color.clear)
            }
            .buttonStyle(.plain)
            .disabled(!hasTracks)
            Text(object?.name ?? "?")
                .font(.system(size: 13, weight: editor.selection.contains(id) ? .bold : .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .frame(width: Self.labelWidth, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { editor.select(id) }
    }

    @ViewBuilder
    private func objectLane(_ id: ObjectID, width: CGFloat) -> some View {
        let tracks = timeline.tracks.filter { $0.target == id }
        if editor.timelineMode == .compose {
            composeBar(id, tracks: tracks, width: width)
        } else {
            ZStack(alignment: .leading) {
                spans(id, width: width)
                keyLane(tracks, width: width, color: Theme.accent)
            }
        }
    }

    /// Behaviour spans (lines) and clip segments (capsules) under the keys.
    private func spans(_ id: ObjectID, width: CGFloat) -> some View {
        Canvas { context, size in
            for behavior in timeline.behaviors where behavior.target == id {
                let start = x(behavior.start)
                let end = x(behavior.end ?? timeline.duration)
                let rect = CGRect(x: start, y: size.height - 6, width: max(end - start, 2), height: 3)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Color.purple.opacity(behavior.enabled ? 0.8 : 0.3)))
            }
            for track in timeline.clipTracks where track.target == id {
                for segment in track.segments {
                    let rect = CGRect(x: x(segment.start), y: 3, width: max(CGFloat(segment.duration * pps), 4), height: size.height - 10)
                    context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(Color.teal.opacity(0.3)))
                    context.draw(Text(segment.clip.name).font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.8)),
                                 at: CGPoint(x: rect.minX + 6, y: rect.midY), anchor: .leading)
                }
            }
        }
        .frame(width: width)
        .allowsHitTesting(false)
    }

    private func keyLane(_ tracks: [Track], width: CGFloat, color: Color) -> some View {
        let keys = tracks.flatMap { track in track.keyframes.map { KeyRef(track: track.id, time: $0.time) } }
        let selected = editor.selectedKeys.union(marqueeKeys)
        let preview = previewTime
        return Canvas { context, size in
            let y = size.height / 2
            for key in keys {
                let isSelected = selected.contains(key)
                let px = x(isSelected ? preview(key.time) : key.time)
                guard px > -8, px < size.width + 8 else { continue }
                var diamond = Path()
                diamond.move(to: CGPoint(x: px, y: y - 6))
                diamond.addLine(to: CGPoint(x: px + 6, y: y))
                diamond.addLine(to: CGPoint(x: px, y: y + 6))
                diamond.addLine(to: CGPoint(x: px - 6, y: y))
                diamond.closeSubpath()
                context.fill(diamond, with: .color(isSelected ? .white : color))
                context.stroke(diamond, with: .color(.black.opacity(0.5)), lineWidth: 1)
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
    }

    private func composeBar(_ id: ObjectID, tracks: [Track], width: CGFloat) -> some View {
        let times = tracks.flatMap { $0.keyframes.map(\.time) }
        let start = times.min()
        let end = times.max()
        let delta = composeDrag?.ids.contains(id) == true ? composeDrag?.delta ?? 0 : 0
        return ZStack(alignment: .leading) {
            spans(id, width: width)
            if let start, let end {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.accent.opacity(editor.selection.contains(id) ? 0.85 : 0.5))
                    .frame(width: max(CGFloat((end - start) * pps), 10), height: Self.rowHeight - 10)
                    .offset(x: x(start + delta))
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in composeDrag = (composeGroup(for: id), Double(value.translation.width) / pps) }
                            .onEnded { value in
                                editor.shiftAnimation(of: composeGroup(for: id), by: Double(value.translation.width) / pps)
                                composeDrag = nil
                            }
                    )
                    .onTapGesture { editor.select(id, additive: editor.keyBoxSelect) }
            }
        }
        .frame(width: width, alignment: .leading)
        .clipped()
    }

    /// Dragging a selected bar moves every selected animated object together.
    private func composeGroup(for id: ObjectID) -> Set<ObjectID> {
        guard editor.selection.contains(id), editor.selection.count > 1 else { return [id] }
        let animated = timeline.animatedObjects
        return Set(editor.selection.filter { animated.contains($0) }).union([id])
    }

    // MARK: Multi-select (one gesture layer over every lane)

    static let lanesSpace = "timeline-lanes"

    enum LaneDrag {
        case moveKeys
        case pan(start: Double)
        case marquee(origin: CGPoint)
        case ignore
    }

    enum StretchEdge {
        case start, end
    }

    private var showsCutRow: Bool { !timeline.cuts.isEmpty || editor.mode == .camera }

    /// Vertical layout of the rows inside the lanes (mirrors the VStack: fixed heights, 1 pt spacing).
    private var slots: [(row: Row?, minY: CGFloat, height: CGFloat)] {
        var result: [(row: Row?, minY: CGFloat, height: CGFloat)] = []
        var y: CGFloat = 0
        if showsCutRow {
            result.append((nil, y, Self.rowHeight))
            y += Self.rowHeight + 1
        }
        for row in rows {
            let height: CGFloat = switch row {
            case .track: Self.rowHeight - 4
            case .audio: Self.audioRowHeight
            case .words: Self.wordsRowHeight
            case .object: Self.rowHeight
            }
            result.append((row, y, height))
            y += height + 1
        }
        return result
    }

    private func trackIDs(for row: Row) -> [TrackID] {
        switch row {
        case let .object(id): timeline.tracks.filter { $0.target == id }.map(\.id)
        case let .track(id): [id]
        case .audio, .words: []
        }
    }

    private func row(at y: CGFloat) -> Row? {
        slots.first { y >= $0.minY && y < $0.minY + $0.height + 1 }?.row
    }

    /// The key under a point in the lanes' space (within 14 pt).
    private func key(at point: CGPoint) -> KeyRef? {
        guard point.x >= Self.labelWidth, let row = row(at: point.y) else { return nil }
        let keys = KeySelection.all(in: timeline, tracks: Set(trackIDs(for: row)))
        return nearestKey(Array(keys), at: point.x - Self.labelWidth)
    }

    /// Audio and word rows handle their own touches.
    private func isOwnGestureRow(at y: CGFloat) -> Bool {
        switch row(at: y) {
        case .audio, .words: true
        default: false
        }
    }

    private var laneTap: some Gesture {
        SpatialTapGesture(coordinateSpace: .named(Self.lanesSpace)).onEnded { value in
            guard value.location.x >= Self.labelWidth, !isOwnGestureRow(at: value.location.y) else { return }
            if let hit = key(at: value.location) {
                if editor.keyBoxSelect {
                    editor.selectedKeys = editor.selectedKeys.contains(hit) ? editor.selectedKeys.subtracting([hit]) : editor.selectedKeys.union([hit])
                } else {
                    editor.selectedKeys = [hit]
                }
                editor.setTime(hit.time)
            } else {
                if !editor.keyBoxSelect { editor.selectedKeys = [] }
                editor.setTime(max(0, time(at: value.location.x - Self.labelWidth)))
            }
        }
    }

    private var laneDragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.lanesSpace))
            .onChanged { value in
                if laneDrag == nil {
                    laneDrag = beginLaneDrag(at: value.startLocation)
                }
                switch laneDrag {
                case .moveKeys:
                    let earliest = editor.selectedKeys.map(\.time).min() ?? 0
                    keyDrag = max(Double(value.translation.width) / pps, -earliest)
                case let .pan(start):
                    visibleStart = max(0, start - Double(value.translation.width) / pps)
                case let .marquee(origin):
                    updateMarquee(from: origin, to: value.location)
                case .ignore, nil:
                    break
                }
            }
            .onEnded { _ in
                switch laneDrag {
                case .moveKeys:
                    if let delta = keyDrag { editor.moveSelectedKeys(by: delta) }
                case .marquee:
                    commitMarquee()
                default:
                    break
                }
                keyDrag = nil
                laneDrag = nil
            }
    }

    /// Long press, then drag: a selection box even outside Select mode.
    private var marqueeLongPress: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.lanesSpace)))
            .onChanged { value in
                guard case let .second(true, drag) = value else { return }
                if !marqueeArmed, laneDrag == nil {
                    marqueeArmed = true
                    Haptics.select()
                }
                if marqueeArmed, let drag {
                    updateMarquee(from: drag.startLocation, to: drag.location)
                }
            }
            .onEnded { _ in
                if marqueeArmed { commitMarquee() }
                marqueeArmed = false
            }
    }

    private func beginLaneDrag(at start: CGPoint) -> LaneDrag {
        if marqueeArmed { return .ignore }
        guard start.x >= Self.labelWidth, !isOwnGestureRow(at: start.y) else { return .ignore }
        if let hit = key(at: start) {
            if !editor.selectedKeys.contains(hit) {
                editor.selectedKeys = editor.keyBoxSelect ? editor.selectedKeys.union([hit]) : [hit]
            }
            keyDrag = 0
            return .moveKeys
        }
        if editor.keyBoxSelect { return .marquee(origin: start) }
        return .pan(start: visibleStart)
    }

    private func updateMarquee(from origin: CGPoint, to location: CGPoint) {
        let rect = CGRect(x: min(origin.x, location.x), y: min(origin.y, location.y),
                          width: abs(location.x - origin.x), height: abs(location.y - origin.y))
        marquee = rect
        let start = time(at: max(rect.minX, Self.labelWidth) - Self.labelWidth)
        let end = time(at: max(rect.maxX, Self.labelWidth) - Self.labelWidth)
        var tracks = Set<TrackID>()
        for slot in slots {
            guard let row = slot.row, slot.minY + slot.height >= rect.minY, slot.minY <= rect.maxY else { continue }
            tracks.formUnion(trackIDs(for: row))
        }
        marqueeKeys = tracks.isEmpty ? [] : KeySelection.keys(in: TimeRange(start: start, end: end), tracks: tracks, timeline: timeline)
    }

    private func commitMarquee() {
        if marquee != nil {
            editor.selectKeys(marqueeKeys, additive: editor.keyBoxSelect)
        }
        marquee = nil
        marqueeKeys = []
    }

    @ViewBuilder private var marqueeView: some View {
        if let marquee {
            Rectangle()
                .fill(Theme.accent.opacity(0.12))
                .overlay(Rectangle().stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                .frame(width: marquee.width, height: marquee.height)
                .offset(x: marquee.minX, y: marquee.minY)
                .allowsHitTesting(false)
        }
    }

    /// Where a selected key is drawn while the selection is dragged or stretched.
    private var previewTime: (Double) -> Double {
        if let keyDrag {
            return { $0 + keyDrag }
        }
        if let stretch, let span = KeySelection.span(of: editor.selectedKeys) {
            let target = stretchTarget(span: span, stretch: stretch)
            return { KeySelection.stretchedTime($0, from: span, to: target) }
        }
        return { $0 }
    }

    private func stretchTarget(span: TimeRange, stretch: (edge: StretchEdge, time: Double)) -> TimeRange {
        switch stretch.edge {
        case .start: TimeRange(start: max(0, min(stretch.time, span.end)), end: span.end)
        case .end: TimeRange(start: span.start, end: max(stretch.time, span.start))
        }
    }

    /// A band on the ruler over the selected keys; drag either end to stretch or squash their timing.
    @ViewBuilder
    private func selectionBand(width: CGFloat) -> some View {
        if editor.timelineMode != .compose, editor.selectedKeys.count > 1, let span = KeySelection.span(of: editor.selectedKeys), span.duration > 0 {
            let shown = stretch.map { stretchTarget(span: span, stretch: $0) } ?? TimeRange(start: previewTime(span.start), end: previewTime(span.end))
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: max(CGFloat(shown.duration * pps), 4), height: 5)
                    .offset(x: x(shown.start), y: Self.rulerHeight - 7)
                    .allowsHitTesting(false)
                stretchHandle(.start, at: shown.start, span: span)
                stretchHandle(.end, at: shown.end, span: span)
            }
            .frame(width: width, height: Self.rulerHeight, alignment: .topLeading)
        }
    }

    private func stretchHandle(_ edge: StretchEdge, at handleTime: Double, span: TimeRange) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
            .frame(width: 16, height: 16)
            .frame(width: 34, height: Self.rulerHeight)
            .contentShape(Rectangle())
            .offset(x: x(handleTime) - 17, y: 4)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let base = edge == .start ? span.start : span.end
                        stretch = (edge, editor.timeline.snapped(base + Double(value.translation.width) / pps))
                    }
                    .onEnded { _ in
                        if let stretch { editor.stretchSelectedKeys(to: stretchTarget(span: span, stretch: stretch)) }
                        stretch = nil
                    }
            )
            .accessibilityLabel(edge == .start ? "Stretch selected keys from the start" : "Stretch selected keys from the end")
    }

    // MARK: Words

    private func wordsRow(width: CGFloat) -> some View {
        let words = editor.words
        let current = WordSnap.word(at: editor.time, in: words)?.id
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble").font(.system(size: 11))
                Text("Words").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Theme.secondaryText)
            .padding(.leading, 10)
            .frame(width: Self.labelWidth)
            .contentShape(Rectangle())
            .onTapGesture { editor.showTranscript = true }
            Canvas { context, size in
                var lastEnd: CGFloat = -1000
                for word in words {
                    let start = x(word.start)
                    let end = x(word.end)
                    guard end > 0, start < size.width else { continue }
                    let rect = CGRect(x: start, y: 3, width: max(end - start - 1, 2), height: size.height - 6)
                    let isCurrent = word.id == current
                    context.fill(Path(roundedRect: rect, cornerRadius: 4),
                                 with: .color(isCurrent ? Theme.accent.opacity(0.9) : Color.yellow.opacity(0.22)))
                    // Labels only where there's room (zoom in to read every word).
                    if start > lastEnd + 2 {
                        let label = context.resolve(Text(word.text).font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isCurrent ? .black : .white.opacity(0.85)))
                        let labelSize = label.measure(in: CGSize(width: 200, height: size.height))
                        context.draw(label, at: CGPoint(x: start + 3, y: size.height / 2), anchor: .leading)
                        lastEnd = start + labelSize.width + 3
                    }
                }
            }
            .frame(width: width)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                let tapped = time(at: value.location.x)
                if let word = words.min(by: { abs(($0.start + $0.end) / 2 - tapped) < abs(($1.start + $1.end) / 2 - tapped) }) {
                    editor.jump(to: word)
                }
            })
            .accessibilityIdentifier("words-lane")
        }
    }

    // MARK: Camera cuts

    private func cutRow(width: CGFloat) -> some View {
        let cuts = timeline.cuts.sorted { $0.time < $1.time }
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "video").font(.system(size: 11))
                Text("Camera").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Theme.text)
            .padding(.leading, 10)
            .frame(width: Self.labelWidth)
            ZStack(alignment: .leading) {
                ForEach(Array(cuts.enumerated()), id: \.offset) { index, cut in
                    let end = index + 1 < cuts.count ? cuts[index + 1].time : timeline.duration
                    let name = editor.baseScene.objects[cut.camera]?.name ?? "Camera"
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .frame(width: max(CGFloat((end - cut.time) * pps) - 2, 8), height: Self.rowHeight - 8, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Self.cameraColor(index)))
                        .offset(x: x(cut.time))
                        .onTapGesture {
                            editor.setTime(cut.time)
                            editor.selectCamera(cut.camera)
                        }
                        .contextMenu {
                            Button("Remove this cut", systemImage: "scissors", role: .destructive) { editor.removeCut(at: cut.time) }
                        }
                }
            }
            .frame(width: width, height: Self.rowHeight, alignment: .leading)
            .clipped()
        }
    }

    // MARK: Zoom & geometry

    private func zoomGesture(width: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomStart == nil { zoomStart = editor.timelineZoom }
                let minimum = Double(width) / max(timeline.duration, 1) * 0.5
                editor.timelineZoom = min(max((zoomStart ?? pps) * value.magnification, minimum), 1200)
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func fit(width: CGFloat) {
        editor.timelineZoom = max(Double(width - 20) / max(timeline.duration, 1), 10)
        visibleStart = 0
    }

    private func x(_ time: Double) -> CGFloat { CGFloat((time - visibleStart) * pps) }

    private func time(at x: CGFloat) -> Double { visibleStart + Double(x) / pps }

    private func nearestKey(_ keys: [KeyRef], at location: CGFloat) -> KeyRef? {
        let best = keys.min { abs(x($0.time) - location) < abs(x($1.time) - location) }
        guard let best, abs(x(best.time) - location) < 14 else { return nil }
        return best
    }

    static func tickStep(pps: Double) -> Double {
        for step in [1.0 / 30, 1.0 / 10, 0.2, 0.5, 1, 2, 5, 10, 30] where step * pps >= 12 {
            return step
        }
        return 60
    }

    static func format(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = time - Double(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, seconds)
    }

    static func shortFormat(_ time: Double) -> String {
        time == time.rounded() ? "\(Int(time))s" : String(format: "%.1fs", time)
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

private struct IdentifiedKey: Identifiable {
    let key: KeyRef
    var id: String { "\(key.track.raw)@\(key.time)" }
}

private struct MarkerFlag: View {
    let marker: Marker

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            Rectangle().fill(Color.yellow).frame(width: 2, height: TimelineDrawer.rulerHeight)
            Text(marker.name)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.yellow))
                .frame(maxWidth: 120, alignment: .leading)
        }
        .accessibilityLabel("Marker \(marker.name)")
    }
}

/// Easing presets offered for selected keys.
enum EasingChoice: String, CaseIterable, Identifiable {
    case linear, easeIn, easeOut, easeInOut, backOut, bounce, elastic, step

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linear: "Linear"
        case .easeIn: "Ease in"
        case .easeOut: "Ease out"
        case .easeInOut: "Ease in & out"
        case .backOut: "Overshoot"
        case .bounce: "Bounce"
        case .elastic: "Elastic"
        case .step: "Step (hold)"
        }
    }

    var easing: Easing {
        switch self {
        case .linear: .linear
        case .easeIn: .easeIn
        case .easeOut: .easeOut
        case .easeInOut: .easeInOut
        case .backOut: .backOut
        case .bounce: .bounce
        case .elastic: .elastic
        case .step: .step
        }
    }

    /// Bezier handles that approximate a preset (the starting point for custom curves).
    var bezier: (Double, Double, Double, Double) {
        switch self {
        case .linear, .step: (0.25, 0.25, 0.75, 0.75)
        case .easeIn: (0.55, 0, 1, 0.45)
        case .easeOut: (0, 0.55, 0.45, 1)
        case .easeInOut: (0.65, 0, 0.35, 1)
        case .backOut: (0.34, 1.56, 0.64, 1)
        case .bounce, .elastic: (0.2, 1.4, 0.4, 0.9)
        }
    }
}

/// Graph editor: the curve of the segment leaving a key, with two draggable handles.
struct EasingEditor: View {
    @Bindable var editor: EditorModel
    let key: KeyRef
    @State private var handles: (Double, Double, Double, Double) = (0.42, 0, 0.58, 1)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Curve").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                PillButton(title: "Done", prominent: true) { dismiss() }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(EasingChoice.allCases) { choice in
                        PillButton(title: choice.title) {
                            editor.setEasing(choice.easing)
                            handles = choice.bezier
                        }
                    }
                }
            }
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                let box = CGRect(x: (geometry.size.width - side) / 2 + 20, y: 20, width: side - 40, height: side - 40)
                ZStack(alignment: .topLeading) {
                    Path { path in path.addRect(box) }.stroke(Theme.panelStroke, lineWidth: 1)
                    Path { path in
                        let easing = currentEasing
                        for index in 0 ... 60 {
                            let t = Double(index) / 60
                            let point = CGPoint(x: box.minX + CGFloat(t) * box.width, y: box.maxY - CGFloat(easing.apply(t)) * box.height)
                            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                    }
                    .stroke(Theme.accent, lineWidth: 3)
                    handle(box: box, first: true)
                    handle(box: box, first: false)
                }
            }
            .frame(minHeight: 240)
            Text("Drag the dots to shape how the motion speeds up and slows down between this key and the next.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(22)
        .onAppear {
            if case let .cubicBezier(a, b, c, d) = keyEasing { handles = (a, b, c, d) }
        }
    }

    private var keyEasing: Easing {
        editor.timeline.track(key.track)?.key(at: key.time)?.easing ?? .easeInOut
    }

    private var currentEasing: Easing {
        if case .cubicBezier = keyEasing { return .cubicBezier(handles.0, handles.1, handles.2, handles.3) }
        return keyEasing
    }

    private func handle(box: CGRect, first: Bool) -> some View {
        let hx = first ? handles.0 : handles.2
        let hy = first ? handles.1 : handles.3
        let anchor = first ? CGPoint(x: box.minX, y: box.maxY) : CGPoint(x: box.maxX, y: box.minY)
        let point = CGPoint(x: box.minX + CGFloat(hx) * box.width, y: box.maxY - CGFloat(hy) * box.height)
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: anchor)
                path.addLine(to: point)
            }
            .stroke(Color.white.opacity(0.5), lineWidth: 1)
            Circle()
                .fill(Color.white)
                .frame(width: 26, height: 26)
                .position(point)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let nx = min(max(Double((value.location.x - box.minX) / box.width), 0), 1)
                            let ny = min(max(Double((box.maxY - value.location.y) / box.height), -0.5), 1.5)
                            if first { handles = (nx, ny, handles.2, handles.3) } else { handles = (handles.0, handles.1, nx, ny) }
                        }
                        .onEnded { _ in
                            editor.selectedKeys = editor.selectedKeys.isEmpty ? [key] : editor.selectedKeys
                            editor.setEasing(.cubicBezier(handles.0, handles.1, handles.2, handles.3))
                        }
                )
        }
    }
}

/// Frame rate, length, project stepping.
struct TimelineSettingsSheet: View {
    @Bindable var editor: EditorModel
    @State private var length: Double = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Timeline").font(.system(size: 22, weight: .bold, design: .rounded))
            SectionHeader(title: "Frame rate")
            Picker("Frame rate", selection: Binding(get: { editor.timeline.fps }, set: { editor.setFrameRate($0) })) {
                ForEach(Timeline.frameRates, id: \.self) { fps in
                    Text("\(fps) fps").tag(fps)
                }
            }
            .pickerStyle(.segmented)
            SectionHeader(title: "Length: \(NumberFormat.short(length)) s")
            HStack {
                Slider(value: $length, in: 1 ... 120, step: 0.5) { editing in
                    if !editing { editor.setDuration(length) }
                }
                PillButton(title: "Fit to animation") {
                    editor.fitDurationToContent()
                    length = editor.timeline.duration
                }
            }
            SectionHeader(title: "Stepping (the whole project)")
            Picker("Stepping", selection: Binding(get: { editor.timeline.stepping }, set: { editor.setProjectStepping($0) })) {
                Text("On ones").tag(Stepping.onOnes)
                Text("On twos").tag(Stepping.onTwos)
                Text("On threes").tag(Stepping.onThrees)
            }
            .pickerStyle(.segmented)
            Text("On twos looks hand-animated (Spider-Verse). Cameras stay smooth; any object can override it in the Animate panel.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
        }
        .padding(22)
        .onAppear { length = editor.timeline.duration }
    }
}

/// Perform any number while the timeline records (glow, light strength, focal length, opacity…).
struct PerformValueSlider: View {
    @Bindable var editor: EditorModel
    @State private var value: Double = 0

    struct Option: Identifiable {
        let key: PropertyKey
        let title: String
        let range: ClosedRange<Double>
        var id: String { key.rawValue }
    }

    private var options: [Option] {
        guard let object = editor.singleSelection else { return [] }
        if object.kind == .camera {
            return [Option(key: .fieldOfView, title: "Zoom (field of view)", range: 10 ... 100),
                    Option(key: .focusDistance, title: "Focus", range: 0.2 ... 40)]
        }
        var result = [Option(key: .opacity, title: "Opacity", range: 0 ... 1)]
        if object.kind.hasSurface { result.append(Option(key: .emissiveIntensity, title: "Glow", range: 0 ... 8)) }
        if case .light = object.kind { result.append(Option(key: .lightIntensity, title: "Light", range: 0 ... 6)) }
        return result
    }

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Button("Move / scale / turn (touch)") { editor.performSliderKey = nil }
                ForEach(options) { option in
                    Button(option.title) {
                        editor.performSliderKey = option.key
                        value = editor.singleSelection?[option.key]?.floatValue ?? option.range.lowerBound
                    }
                }
            } label: {
                Label(currentTitle, systemImage: "hand.draw").pillLabel()
            }
            if let key = editor.performSliderKey, let option = options.first(where: { $0.key == key }) {
                Slider(value: $value, in: option.range) { editing in
                    if !editing { editor.performValue(key, value, touching: false) }
                }
                .frame(width: 160)
                .onChange(of: value) { _, newValue in editor.performValue(key, newValue, touching: true) }
            }
        }
    }

    private var currentTitle: String {
        guard let key = editor.performSliderKey else { return "Perform: touch" }
        return "Perform: \(options.first { $0.key == key }?.title ?? key.rawValue)"
    }
}
