import LoweyCore
import LoweyRender
import SwiftUI

/// Draw tool options: what you draw on, what the stroke becomes, width, smoothing, mirror.
struct DrawPanel: View {
    @Bindable var editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(DrawingRecipe.Style.allCases, id: \.self) { style in
                    choice(style.title, icon: style.systemImage, selected: editor.draw.style == style) { editor.draw.style = style }
                }
                Divider().frame(height: 30).overlay(Theme.panelStroke)
                IconButton(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Mirror",
                           isOn: editor.draw.mirror, size: 40) { editor.draw.mirror.toggle() }
                IconButton(systemName: editor.draw.pencilOnly ? "applepencil" : "hand.draw", label: "Pencil only",
                           isOn: !editor.draw.pencilOnly, size: 40) { editor.draw.pencilOnly.toggle() }
            }
            HStack(spacing: 6) {
                Text("On").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.secondaryText)
                ForEach(GuideKind.allCases) { kind in
                    choice(kind.title, icon: kind.systemImage, selected: editor.draw.guide == kind) { editor.draw.guide = kind }
                }
            }
            if editor.draw.guide == .plane {
                HStack(spacing: 6) {
                    Text("Plane").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.secondaryText)
                    ForEach(PlaneLock.allCases) { lock in
                        choice(lock.title, icon: nil, selected: editor.draw.planeLock == lock) { editor.draw.planeLock = lock }
                    }
                }
                slider("Plane offset", value: $editor.draw.planeOffset, range: -3 ... 3)
            } else if editor.draw.guide != .object {
                slider("Guide size", value: $editor.draw.guideSize, range: 0.3 ... 6)
            }
            HStack(spacing: 18) {
                slider("Width", value: $editor.draw.width, range: 0.005 ... 0.4)
                slider("Smoothing", value: $editor.draw.smoothing, range: 0 ... 1)
                if editor.draw.style == .extrude {
                    slider("Depth", value: $editor.draw.extrudeDepth, range: 0.02 ... 3)
                }
            }
            Text(editor.draw.style.hint + (editor.draw.pencilOnly ? " · Pencil draws, fingers move the view" : ""))
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: 620)
        .panelStyle()
    }

    private func choice(_ title: String, icon: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .foregroundStyle(selected ? Color.black : Theme.text)
            .background(Capsule().fill(selected ? Theme.accent : Theme.raised))
        }
        .buttonStyle(.plain)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(title) \(NumberFormat.short(value.wrappedValue))").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
            Slider(value: value, in: range)
        }
        .frame(minWidth: 150)
    }
}

/// Scatter tool options.
struct ScatterPanel: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("How many: \(editor.scatter.count)").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                Slider(value: Binding(get: { Double(editor.scatter.count) }, set: { editor.scatter.count = Int($0) }), in: 3 ... 150, step: 1)
            }
            .frame(width: 200)
            VStack(alignment: .leading, spacing: 2) {
                Text("Size variety").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                Slider(value: $editor.scatter.scaleVariation, in: 0 ... 0.6)
            }
            .frame(width: 150)
            VStack(alignment: .leading, spacing: 2) {
                Text("Spacing").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                Slider(value: $editor.scatter.spacing, in: 0 ... 2)
            }
            .frame(width: 150)
            Text(editor.selection.isEmpty ? "Select something to scatter" : "Drag on the ground to paint an area")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(editor.selection.isEmpty ? Theme.danger : Theme.text)
        }
        .padding(14)
        .panelStyle()
    }
}

/// Bottom-right: quick views, ortho toggle, frame, grid, snapping.
struct ViewControls: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(ViewAxis.allCases, id: \.self) { axis in
                    Button(axis.displayName) { editor.stage?.quickView(axis) }
                }
                Divider()
                Button(isOrthographic ? "Perspective" : "Orthographic") { toggleProjection() }
            } label: {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.raised))
            }
            .accessibilityLabel("Views")
            IconButton(systemName: isOrthographic ? "square" : "perspective", label: "Toggle orthographic",
                       isOn: isOrthographic, size: 44) { toggleProjection() }
            IconButton(systemName: "viewfinder", label: "Frame", size: 44) { editor.frameSelection() }
            if editor.mode == .build {
                IconButton(systemName: "grid", label: "Grid", isOn: editor.showGrid, size: 44) { editor.showGrid.toggle() }
                Menu {
                    Toggle("Snap to grid", isOn: $editor.snap.grid)
                    Picker("Grid size", selection: $editor.snap.gridSize) {
                        Text("10 cm").tag(0.1)
                        Text("25 cm").tag(0.25)
                        Text("50 cm").tag(0.5)
                        Text("1 m").tag(1.0)
                    }
                    Toggle("Snap to objects", isOn: $editor.snap.objects)
                    Toggle("Snap to ground", isOn: $editor.snap.ground)
                    Toggle("Rotation steps", isOn: $editor.snap.rotation)
                    Picker("Step", selection: $editor.snap.rotationStep) {
                        Text("15°").tag(15.0)
                        Text("45°").tag(45.0)
                        Text("90°").tag(90.0)
                    }
                } label: {
                    Image(systemName: "grid.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(editor.snap.grid || editor.snap.objects ? Theme.accent : Theme.text)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.raised))
                }
                .accessibilityLabel("Snapping")
            }
        }
        .padding(6)
        .panelStyle(cornerRadius: 30)
    }

    private var isOrthographic: Bool { editor.projection == .orthographic }

    private func toggleProjection() {
        guard let stage = editor.stage else { return }
        var viewpoint = stage.viewpoint
        viewpoint.projection = viewpoint.projection == .orthographic ? .perspective : .orthographic
        stage.setViewpoint(viewpoint)
    }
}

/// Export mode: PNG snapshots in 16:9, 9:16 and 1:1.
struct ExportPanel: View {
    @Bindable var editor: EditorModel
    @State private var longSide = 1920
    @State private var working = false
    @State private var shareURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export").font(.system(size: 22, weight: .bold, design: .rounded))
            SectionHeader(title: "Snapshot")
            Picker("Framing", selection: $editor.snapshotFraming) {
                ForEach(Framing.allCases) { framing in
                    Text(framing.rawValue).tag(framing)
                }
            }
            .pickerStyle(.segmented)
            Picker("Size", selection: $longSide) {
                Text("HD").tag(1920)
                Text("4K").tag(3840)
            }
            .pickerStyle(.segmented)
            let size = editor.snapshotFraming.pixelSize(longSide: longSide)
            Text("\(size.width) × \(size.height) PNG · saved in the project's renders folder")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            PillButton(title: working ? "Rendering…" : "Take snapshot", systemName: "camera.aperture", prominent: true) {
                guard !working else { return }
                working = true
                Task {
                    shareURL = await editor.exportSnapshot(framing: editor.snapshotFraming, longSide: longSide)
                    working = false
                }
            }
            .accessibilityIdentifier("take-snapshot")
            Divider().overlay(Theme.panelStroke)
            SectionHeader(title: "Coming in Phase 2")
            Text("Video export (16:9 and 9:16 in one go), PNG sequences, transparent backgrounds and USDZ/glTF export.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(18)
        .panelStyle()
        .sheet(item: Binding(get: { shareURL.map(IdentifiedURL.init) }, set: { shareURL = $0?.url })) { item in
            ShareSheet(items: [item.url])
        }
    }
}

/// Camera mode shell (Phase 2 fills it). Saving a camera from the view already works.
struct CameraPanel: View {
    let editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Camera").font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Save the current view as a camera. Moves (push-in, orbit, punch-in…), lenses, depth of field and the iPad-as-camera arrive in Phase 2.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
            PillButton(title: "Save camera from view", systemName: "video.badge.plus", prominent: true) { editor.addCamera() }
            let cameras = editor.scene.cameras
            if !cameras.isEmpty {
                SectionHeader(title: "Cameras")
                ForEach(cameras, id: \.self) { id in
                    Button {
                        guard let object = editor.scene.objects[id] else { return }
                        var viewpoint = editor.stage?.viewpoint ?? .default
                        let forward = object.transform.rotation.act(Vec3(0, 0, -1))
                        viewpoint.target = object.transform.position + forward * viewpoint.distance
                        viewpoint.yaw = atan2(-forward.x, -forward.z) * 180 / .pi
                        viewpoint.pitch = -asin(max(-1, min(1, forward.y))) * 180 / .pi
                        viewpoint.fieldOfView = object[.fieldOfView]?.floatValue ?? viewpoint.fieldOfView
                        editor.stage?.animate(to: viewpoint)
                    } label: {
                        Label(editor.scene.objects[id]?.name ?? "Camera", systemImage: id == editor.scene.activeCamera ? "video.fill" : "video")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(18)
        .panelStyle()
    }
}

struct ComingSoonPanel: View {
    let mode: EditorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(mode.title, systemImage: mode.systemImage).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(
                "Coming in Phase 2: a touch-first timeline (Compose · Perform · Keyframe), Perform-mode motion capture by touch, one-tap animation presets with stagger, characters and clips."
            )
            .font(.system(size: 14))
            .foregroundStyle(Theme.secondaryText)
            Text("The timeline engine and easing curves already exist underneath, so everything you build now animates later without changes.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(18)
        .panelStyle()
    }
}
