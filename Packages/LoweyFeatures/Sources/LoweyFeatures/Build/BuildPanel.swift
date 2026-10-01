import HmmDesign
import LoweyCore
import SwiftUI

/// Build: shapes (bevelled), lights and cameras, characters, words in the world and on the frame, effects. One tap
/// each; things land in the middle of the view.
struct BuildPanel: View {
    let editor: EditorModel

    var body: some View {
        HmmPanel("Build", width: 360, close: { editor.openPanel = nil }) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                PanelSection("Shapes") {
                    TileGrid {
                        ForEach(PrimitiveShape.allCases, id: \.self) { shape in
                            TileButton(title: shape.displayName, systemName: Self.icon(for: shape), identifier: "add-\(shape.rawValue)") {
                                editor.addPrimitive(shape)
                            }
                        }
                    }
                }
                PanelSection("Light & camera") {
                    TileGrid {
                        TileButton(title: "Lamp", systemName: "lightbulb.fill") { editor.addLight(.point) }
                        TileButton(title: "Spot", systemName: "light.overhead.right.fill") { editor.addLight(.spot) }
                        TileButton(title: "Sun", systemName: "sun.max.fill") { editor.addLight(.directional) }
                        TileButton(title: "Camera", systemName: "video.fill", identifier: "add-camera") { editor.addCamera() }
                    }
                }
                PanelSection("Words") {
                    TileGrid {
                        TileButton(title: "3D text", systemName: "textformat", identifier: "add-text3d") { editor.addText3D() }
                        TileButton(title: "Title", systemName: "textformat.size") { editor.addOverlay(.title) }
                        TileButton(title: "Label", systemName: "tag") { editor.addOverlay(.label) }
                    }
                }
                PanelSection("On the frame") {
                    TileGrid {
                        ForEach([OverlayRecipe.Shape.cross, .question, .arrow, .highlight, .exclamation, .check, .circle, .star], id: \.self) { shape in
                            TileButton(title: shape.title, systemName: shape.systemImage, identifier: "add-overlay-\(shape.rawValue)") {
                                editor.addOverlay(shape)
                            }
                        }
                    }
                }
                PanelSection("Effects") {
                    TileGrid {
                        ForEach(ParticleRecipe.Preset.allCases) { preset in
                            TileButton(title: preset.title, systemName: preset.systemImage, identifier: "add-fx-\(preset.rawValue)") {
                                editor.addParticles(preset)
                            }
                        }
                    }
                }
                PanelSection("Screen effects at the playhead") {
                    TileGrid {
                        ForEach(ScreenEffect.Kind.allCases) { kind in
                            TileButton(title: kind.title, systemName: kind.systemImage, identifier: "effect-\(kind.rawValue)") {
                                editor.addScreenEffect(kind)
                            }
                        }
                    }
                }
                HmmPillButton("Open the library", systemName: "books.vertical") { editor.openPanel = .library }
            }
        }
    }

    static func icon(for shape: PrimitiveShape) -> String {
        switch shape {
        case .cube: "cube.fill"
        case .sphere: "circle.fill"
        case .cylinder: "cylinder.fill"
        case .cone: "cone.fill"
        case .plane: "square.fill"
        case .torus: "circle.circle"
        case .ramp: "triangle.fill"
        }
    }
}

/// Scatter options while the Scatter tool is on.
struct ScatterOptionsBar: View {
    @Bindable var editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: HmmSpacing.m) {
            LabeledSlider(title: "How many", value: Double(editor.scatter.count), range: 3 ... 150, format: { "\(Int($0))" }) {
                editor.scatter.count = Int($0)
            }
            .frame(width: 180)
            LabeledSlider(title: "Size variety", value: editor.scatter.scaleVariation, range: 0 ... 0.6, format: NumberFormat.percent) {
                editor.scatter.scaleVariation = $0
            }
            .frame(width: 150)
            LabeledSlider(title: "Spacing", value: editor.scatter.spacing, range: 0 ... 2) { editor.scatter.spacing = $0 }
                .frame(width: 150)
            HmmButton("xmark", label: "Done scattering", size: 36) { editor.tool = .select }
        }
        .padding(HmmSpacing.s)
        .hmmPanelBackground()
        .overlay(alignment: .top) {
            Text(editor.selection.isEmpty ? "Select something to scatter" : "Drag on the ground to paint an area")
                .font(.hmm(.caption, weight: .semibold))
                .foregroundStyle(editor.selection.isEmpty ? theme.danger : theme.text2)
                .offset(y: -18)
        }
    }
}
