import HmmDesign
import LoweyCore
import LoweyEngine
import SwiftUI

/// What the pick can do, in the Model tool's bar: bevel and round edges; inset and shell (open) faces.
struct PickActions: View {
    let editor: EditorModel
    let mode: MeshSelection.Mode

    var body: some View {
        switch mode {
        case .edge:
            HmmButton("square.bottomhalf.filled", label: "Bevel", size: 36) { editor.bevelPick(.chamfer) }
                .accessibilityIdentifier("bevel")
            HmmButton("app", label: "Round", size: 36) { editor.bevelPick(.round) }
                .accessibilityIdentifier("round")
        case .face:
            HmmButton("square.inset.filled", label: "Inset", size: 36) { editor.insetPick() }
                .accessibilityIdentifier("inset")
            HmmButton("cube.box", label: "Shell, leaving these open", size: 36) { editor.shellPick() }
                .accessibilityIdentifier("shell-open")
        case .vertex:
            EmptyView()
        }
    }
}

/// The bar's controls for measuring and building.
struct ModelToolExtras: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        if editor.modeling.mode == .measure, let detail = editor.measurementDetail {
            Divider().frame(height: 24)
            Text(detail).font(.hmmNumbers(.footnote)).foregroundStyle(theme.text2)
            HmmButton("pin", label: "Keep", size: 36) { editor.keepMeasurement() }
                .accessibilityIdentifier("keep-measurement")
        }
        if let build = editor.modeling.mode.buildTool, build == .walls || build == .floor, !editor.modeling.build.isEmpty {
            Divider().frame(height: 24)
            HmmButton("checkmark", label: "Done", size: 36) { editor.finishBuild() }
                .accessibilityIdentifier("build-done")
        }
    }
}

/// Model ▸ Edit ▸ Mirror & symmetry.
struct MirrorControls: View {
    let editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HStack(spacing: HmmSpacing.xs) {
                Menu {
                    if editor.pickedFace != nil {
                        Button("Across the picked face") { editor.mirrorSelection(nil) }
                    }
                    Button("Across the middle, left to right") { editor.mirrorSelection(.x) }
                    Button("Across the middle, front to back") { editor.mirrorSelection(.z) }
                    Button("Across the ground") { editor.mirrorSelection(.y) }
                } label: {
                    Label("Mirror", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                }
                .accessibilityIdentifier("mirror")
                Menu {
                    Button("Off") { editor.setSymmetry(nil) }
                    Button("Left and right") { editor.setSymmetry(.x) }
                    Button("Front and back") { editor.setSymmetry(.z) }
                    Button("Top and bottom") { editor.setSymmetry(.y) }
                } label: {
                    Label { symmetryTitle } icon: { Image(systemName: "square.split.2x1") }
                }
                .accessibilityIdentifier("symmetry")
            }
            .disabled(editor.modelableSelection.isEmpty && editor.modeling.target == nil)
            Hint("Symmetry keeps both sides alike as you model: whatever you change on one side, the other follows.")
        }
    }

    private var symmetryTitle: Text {
        switch editor.selectionSymmetry {
        case .x: Text("Symmetry: left and right")
        case .y: Text("Symmetry: top and bottom")
        case .z: Text("Symmetry: front and back")
        case nil: Text("Symmetry")
        }
    }
}

/// Model ▸ Edit ▸ 3D print: the printer, the check and the repair.
struct PrintCheckControls: View {
    @Bindable var editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Picker("Printer", selection: Binding(get: { editor.precision.printBed ?? "" }, set: { editor.setPrintBed($0.isEmpty ? nil : $0) })) {
                Text("None").tag("")
                ForEach(PrintBed.presets) { bed in
                    Text(bed.name).tag(bed.id)
                }
            }
            .accessibilityIdentifier("printer")
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton("Check for printing", systemName: "checkmark.seal") { editor.checkForPrinting() }
                    .accessibilityIdentifier("print-check")
                if let report = editor.precision.printReport, !report.isWatertight {
                    HmmPillButton("Repair", systemName: "bandage") { editor.repairForPrinting() }
                        .accessibilityIdentifier("print-repair")
                }
            }
            if let report = editor.precision.printReport {
                VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
                    if report.isReady {
                        Label("Ready to print", systemImage: "checkmark.circle.fill").foregroundStyle(theme.accent)
                    }
                    ForEach(report.problems, id: \.self) { problem in
                        Label { Self.text(problem) } icon: { Image(systemName: "exclamationmark.triangle") }
                    }
                    if let wall = report.thinnestWall {
                        Text("Thinnest wall: \(editor.format(wall))").foregroundStyle(theme.text2)
                    }
                }
                .font(.hmm(.footnote))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("print-report")
            }
            Hint("Export it from Actions ▸ Export ▸ 3D model as STL or 3MF: millimetres, standing on the bed.")
        }
    }

    static func text(_ problem: PrintProblem) -> Text {
        switch problem {
        case let .holes(count): Text("It has holes in its surface (\(count) open edges).")
        case let .tangledEdges(count): Text("Some edges are shared by more than two faces (\(count)).")
        case .insideOut: Text("Some faces point inward.")
        case .thinWalls: Text("Some walls are thinner than this printer can print.")
        case .tooBig: Text("It's bigger than the printer's build volume.")
        }
    }
}
