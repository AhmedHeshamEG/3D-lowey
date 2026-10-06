import HmmDesign
import LoweyCore
import SwiftUI

/// The left sidebar: two sliders that change with the context (drawing: width and smoothing; Shadow Brush: size and
/// strength; Perform: filtering and sensitivity; otherwise snapping and navigation speed), Pick, undo and redo.
struct EditorSidebar: View {
    @Bindable var editor: EditorModel
    @AppStorage(AppSettings.navigationSpeed) private var navigationSpeed = 1.0

    var body: some View {
        let (top, bottom) = sliders
        HmmSidebar(top: top, bottom: bottom, pickActive: editor.pickActive, pick: {
            editor.pickActive.toggle()
            if editor.pickActive { editor.app.show("Tap an object to take its colour into palette slot \(editor.pickSlot + 1)") }
        }, canUndo: editor.canUndo, canRedo: editor.canRedo, undo: editor.undo, redo: editor.redo)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sidebar")
    }

    private var sliders: (HmmSidebarSlider, HmmSidebarSlider) {
        if editor.flying {
            return (HmmSidebarSlider("Fly speed", value: Binding(get: { editor.flyer.flight.speed }, set: { editor.flyer.flight.speed = $0 }),
                                     in: 0.3 ... 20, format: { String(format: "%.2g m/s", $0) }),
                    HmmSidebarSlider("Ease", value: Binding(get: { editor.flyer.flight.response }, set: { editor.flyer.flight.response = $0 }),
                                     in: 0.05 ... 1.2, format: { String(format: "%.2g s", $0) }))
        }
        if editor.timelineMode == .perform, editor.performPhase != .idle || editor.tool == .select {
            return (HmmSidebarSlider("Filtering", value: $editor.performSettings.smoothing, in: 0 ... 1),
                    HmmSidebarSlider("Sensitivity", value: $editor.performSettings.sensitivity, in: 0.25 ... 3,
                                     format: { String(format: "%.2g×", $0) }))
        }
        switch editor.tool {
        case .flipbook:
            return (HmmSidebarSlider("Width", value: $editor.flipbook.width, in: 0.5 ... 24, format: { "\(Int(($0 * 2).rounded())) pt" },
                                     onEditingChanged: editor.setBrushResizing),
                    HmmSidebarSlider("Opacity", value: $editor.flipbook.opacity, in: 0.05 ... 1, format: { "\(Int(($0 * 100).rounded())) %" }))
        case .ink:
            return (HmmSidebarSlider("Width", value: $editor.ink.width, in: 0.001 ... 0.05, format: { "\(Int(($0 * 2000).rounded())) mm" },
                                     onEditingChanged: editor.setBrushResizing),
                    HmmSidebarSlider("Opacity", value: inkOpacity, in: 0.05 ... 1, format: { "\(Int(($0 * 100).rounded())) %" },
                                     onEditingChanged: { if !$0 { editor.endGesture() } }))
        case .draw:
            return (HmmSidebarSlider("Width", value: $editor.draw.width, in: 0.005 ... 0.4, format: { "\(Int(($0 * 100).rounded())) cm" },
                                     onEditingChanged: editor.setBrushResizing),
                    HmmSidebarSlider("Smoothing", value: $editor.draw.smoothing, in: 0 ... 1))
        case .paint:
            return (HmmSidebarSlider("Size", value: $editor.colourPaint.size, in: 1 ... 120, format: { "\(Int($0.rounded())) pt" },
                                     onEditingChanged: editor.setBrushResizing),
                    HmmSidebarSlider("Opacity", value: $editor.colourPaint.opacity, in: 0.05 ... 1, format: { "\(Int(($0 * 100).rounded())) %" }))
        case .shadowBrush:
            return (HmmSidebarSlider("Brush size", value: $editor.shadowBrush.radius, in: 0.02 ... 1, format: { "\(Int(($0 * 100).rounded())) cm" },
                                     onEditingChanged: editor.setBrushResizing),
                    HmmSidebarSlider("Strength", value: $editor.shadowBrush.strength, in: 0.05 ... 1))
        default:
            return (HmmSidebarSlider("Snapping", value: $editor.snap.objectThreshold, in: 0 ... 0.5, format: { "\(Int(($0 * 100).rounded())) cm" }),
                    HmmSidebarSlider("Speed", value: $navigationSpeed, in: AppSettings.navigationSpeedRange, format: { String(format: "%.2g×", $0) }))
        }
    }
}

extension EditorSidebar {
    /// New strokes' opacity, and the selected ink drawing's.
    var inkOpacity: Binding<Double> {
        Binding(get: { editor.activeInk?.opacity ?? editor.ink.opacity }, set: { value in
            editor.ink.opacity = value
            editor.setInkOpacity(value)
        })
    }
}

/// Bottom centre of the stage: the options of the tool in use.
struct ToolOptionsBar: View {
    let editor: EditorModel

    var body: some View {
        switch editor.tool {
        case .ink: InkOptionsBar(editor: editor)
        case .flipbook: FlipbookOptionsBar(editor: editor)
        case .draw: DrawOptionsBar(editor: editor)
        case .shadowBrush: ShadowBrushOptionsBar(editor: editor)
        case .paint: PaintOptionsBar(editor: editor)
        case .scatter: ScatterOptionsBar(editor: editor)
        case .model: ModelOptionsBar(editor: editor)
        case .select, .lasso: EmptyView()
        }
    }
}
