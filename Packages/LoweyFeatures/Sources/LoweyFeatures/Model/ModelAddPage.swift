import HmmDesign
import LoweyCore
import SwiftUI
import UniformTypeIdentifiers

/// Model ▸ Add: shapes (bevelled), lights and cameras, words in the world and on the frame, effects. One tap each;
/// things land in the middle of the view, and the panel closes so the inspector shows what was added (as Procreate
/// Dreams' insert menu does). Screen effects keep it open: they add no object.
struct ModelAddPage: View {
    let editor: EditorModel
    @State private var importingMedia = false

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            PanelSection("Shapes") {
                TileGrid {
                    ForEach(PrimitiveShape.allCases, id: \.self) { shape in
                        TileButton(title: shape.displayName, systemName: Self.icon(for: shape), identifier: "add-\(shape.rawValue)",
                                   glyph: shape == .sphere ? AnyView(SphereGlyph()) : nil) {
                            place { editor.addPrimitive(shape) }
                        }
                    }
                }
            }
            PanelSection("Building") {
                TileGrid {
                    ForEach(BuildTool.allCases) { build in
                        TileButton(title: build.title, systemName: build.systemImage, identifier: "build-\(build.rawValue)") {
                            editor.startModeling(.build(build))
                            editor.openPanel = nil
                        }
                    }
                }
                Hint("Walls follow the corners you tap; doors and windows go where you tap a wall.")
            }
            PanelSection("Light & camera") {
                TileGrid {
                    TileButton(title: "Lamp", systemName: "lightbulb.fill", identifier: "add-lamp") { place { editor.addLight(.point) } }
                    TileButton(title: "Spot", systemName: "light.overhead.right.fill", identifier: "add-spot") { place { editor.addLight(.spot) } }
                    TileButton(title: "Sun", systemName: "sun.max.fill", identifier: "add-sun") { place { editor.addLight(.directional) } }
                    TileButton(title: "Camera", systemName: "video.fill", identifier: "add-camera") { place { editor.addCamera() } }
                }
            }
            PanelSection("Words & pictures") {
                TileGrid {
                    TileButton(title: "3D text", systemName: "textformat", identifier: "add-text3d") { place { editor.addText3D() } }
                    TileButton(title: "Title", systemName: "textformat.size", identifier: "add-title") { place { editor.addOverlay(.title) } }
                    TileButton(title: "Label", systemName: "tag", identifier: "add-label") { place { editor.addOverlay(.label) } }
                    TileButton(title: "Photo or video", systemName: "photo.on.rectangle", identifier: "add-media") { importingMedia = true }
                }
            }
            PanelSection("On the frame") {
                TileGrid {
                    ForEach([OverlayRecipe.Shape.cross, .question, .arrow, .highlight, .exclamation, .check, .circle, .star], id: \.self) { shape in
                        TileButton(title: shape.title, systemName: shape.systemImage, identifier: "add-overlay-\(shape.rawValue)") {
                            place { editor.addOverlay(shape) }
                        }
                    }
                }
            }
            PanelSection("Effects") {
                TileGrid {
                    ForEach(ParticleRecipe.Preset.allCases) { preset in
                        TileButton(title: preset.title, systemName: preset.systemImage, identifier: "add-fx-\(preset.rawValue)") {
                            place { editor.addParticles(preset) }
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
        }
        .fileImporter(isPresented: $importingMedia, allowedContentTypes: [.image, .movie]) { result in
            if case let .success(url) = result {
                editor.openPanel = nil
                Task { await editor.importMedia(url) }
            }
        }
    }

    private func place(_ add: () -> Void) {
        add()
        editor.openPanel = nil
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
