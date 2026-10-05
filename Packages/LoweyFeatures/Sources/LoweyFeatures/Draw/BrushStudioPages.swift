import HmmDesign
import LoweyCore
import SwiftUI

/// One page of Brush Studio's settings. Every control writes the brush straight back to the library.
struct BrushStudioPageView: View {
    let page: BrushStudioPage
    let brush: Brush
    let brushes: BrushModel
    let importPicture: (BrushPictureSlot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            switch page {
            case .stroke: stroke
            case .shape: shape
            case .grain: grain
            case .dynamics: dynamics
            case .pencil: pencil
            case .rendering: rendering
            case .about: BrushAboutPage(brush: brush, brushes: brushes)
            }
        }
        .font(.hmm(.body))
    }

    private func edit(_ change: (inout Brush) -> Void) {
        var edited = brush
        change(&edited)
        brushes.update(edited)
    }

    private func slider(_ title: String, _ value: Double, _ range: ClosedRange<Double> = 0 ... 1, percent: Bool = true,
                        _ set: @escaping (inout Brush, Double) -> Void) -> some View {
        LabeledSlider(title: title, value: value, range: range, format: { percent ? "\(Int(($0 * 100).rounded())) %" : NumberFormat.short($0) }) { value in
            edit { set(&$0, value) }
        }
    }

    // MARK: Pages

    @ViewBuilder private var stroke: some View {
        slider("Spacing", brush.stroke.spacing, 0.02 ... 2) { $0.stroke.spacing = $1 }
        slider("StreamLine", brush.stroke.streamline) { $0.stroke.streamline = $1 }
        slider("Jitter", brush.stroke.jitter, 0 ... 2) { $0.stroke.jitter = $1 }
        slider("Fall-off", brush.stroke.falloff) { $0.stroke.falloff = $1 }
        PanelSection("Taper") {
            slider("Start", brush.stroke.taperStart) { $0.stroke.taperStart = $1 }
            slider("End", brush.stroke.taperEnd) { $0.stroke.taperEnd = $1 }
            slider("Tip size", brush.stroke.taperSize) { $0.stroke.taperSize = $1 }
            slider("Tip opacity", brush.stroke.taperOpacity) { $0.stroke.taperOpacity = $1 }
        }
    }

    @ViewBuilder private var shape: some View {
        PanelSection("Tip") {
            pictureChoices(BuiltInBrushImage.allCases.filter { !$0.isGrain }, current: brush.shape.source, none: false) { source in
                edit { $0.shape.source = source ?? .builtIn(.hardRound) }
            }
            HmmPillButton("Use a picture…", systemName: "photo") { importPicture(.tip) }
            Hint("White paints, black leaves the paper. Pictures with see-through parts paint where they're solid.")
        }
        slider("Roundness", brush.shape.roundness, 0.05 ... 1) { $0.shape.roundness = $1 }
        slider("Angle", brush.shape.angle, 0 ... 360, percent: false) { $0.shape.angle = $1 }
        Toggle("Turns with the stroke", isOn: Binding(get: { brush.shape.followsStroke }, set: { value in edit { $0.shape.followsStroke = value } }))
        slider("Rotation jitter", brush.shape.rotationJitter) { $0.shape.rotationJitter = $1 }
        Stepper(value: Binding(get: { brush.shape.count }, set: { value in edit { $0.shape.count = value } }), in: 1 ... 16) {
            Text("Stamps per step: \(brush.shape.count)")
        }
        Toggle("Flip across at random", isOn: Binding(get: { brush.shape.flipXJitter }, set: { value in edit { $0.shape.flipXJitter = value } }))
        Toggle("Flip upside down at random", isOn: Binding(get: { brush.shape.flipYJitter }, set: { value in edit { $0.shape.flipYJitter = value } }))
        Toggle("Invert the tip", isOn: Binding(get: { brush.shape.inverted }, set: { value in edit { $0.shape.inverted = value } }))
    }

    @ViewBuilder private var grain: some View {
        PanelSection("Grain") {
            pictureChoices(BuiltInBrushImage.allCases.filter(\.isGrain), current: brush.grain.source, none: true) { source in
                edit { $0.grain.source = source }
            }
            HmmPillButton("Use a picture…", systemName: "photo") { importPicture(.grain) }
        }
        if brush.grain.source != nil {
            Picker("Movement", selection: Binding(get: { brush.grain.movement }, set: { value in edit { $0.grain.movement = value } })) {
                Text("Rolling").tag(BrushGrain.Movement.rolling)
                Text("Texturized").tag(BrushGrain.Movement.texturized)
            }
            .pickerStyle(.segmented)
            Hint(brush.grain.movement == .rolling ? "The grain moves with each stamp, like a sponge." : "The grain stays put, like the paper under a pencil.")
            slider("Scale", brush.grain.scale, 0.1 ... 4, percent: false) { $0.grain.scale = $1 }
            slider("Depth", brush.grain.depth) { $0.grain.depth = $1 }
            Toggle("Invert the grain", isOn: Binding(get: { brush.grain.inverted }, set: { value in edit { $0.grain.inverted = value } }))
        }
    }

    @ViewBuilder private var dynamics: some View {
        PanelSection("Pressure") {
            slider("Size", brush.dynamics.pressureSize) { $0.dynamics.pressureSize = $1 }
            slider("Opacity", brush.dynamics.pressureOpacity) { $0.dynamics.pressureOpacity = $1 }
            Picker("Response", selection: Binding(get: { BrushResponse(brush.dynamics.pressureCurve) },
                                                  set: { value in edit { $0.dynamics.pressureCurve = value.curve } })) {
                ForEach(BrushResponse.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            .pickerStyle(.segmented)
            slider("Smallest size", brush.dynamics.minimumSize) { $0.dynamics.minimumSize = $1 }
            slider("Lightest opacity", brush.dynamics.minimumOpacity) { $0.dynamics.minimumOpacity = $1 }
        }
        PanelSection("Speed") {
            slider("Size", brush.dynamics.speedSize, -1 ... 1) { $0.dynamics.speedSize = $1 }
            slider("Opacity", brush.dynamics.speedOpacity, -1 ... 1) { $0.dynamics.speedOpacity = $1 }
        }
        PanelSection("Jitter") {
            slider("Size", brush.dynamics.sizeJitter) { $0.dynamics.sizeJitter = $1 }
            slider("Opacity", brush.dynamics.opacityJitter) { $0.dynamics.opacityJitter = $1 }
        }
    }

    private var pencil: some View {
        PanelSection("Tilt") {
            slider("Size", brush.dynamics.tiltSize) { $0.dynamics.tiltSize = $1 }
            slider("Opacity", brush.dynamics.tiltOpacity) { $0.dynamics.tiltOpacity = $1 }
            Hint("Lay the Pencil over to shade with its side: the stamp grows or fades as it tilts.")
        }
    }

    @ViewBuilder private var rendering: some View {
        slider("Flow", brush.rendering.flow, 0.01 ... 1) { $0.rendering.flow = $1 }
        Hint("Low flow builds up where you go over the same place, like an airbrush.")
        slider("Wet edges", brush.rendering.wetEdges) { $0.rendering.wetEdges = $1 }
        slider("Soft edge", brush.rendering.softness) { $0.rendering.softness = $1 }
    }

    /// Built-in pictures (and "None" for grain), with the brush's own picture when it has one.
    private func pictureChoices(_ images: [BuiltInBrushImage], current: BrushImageSource?, none: Bool,
                                choose: @escaping (BrushImageSource?) -> Void) -> some View {
        var items: [(String, String)] = none ? [("none", "None")] : []
        items += images.map { ($0.rawValue, $0.title) }
        if let key = current?.imageKey { items.append((key, "Picture")) }
        return FlowChips(items: items, isOn: { key in
            switch current {
            case .none: key == "none"
            case let .builtIn(image): key == image.rawValue
            case let .image(picture): key == picture
            }
        }, toggle: { key in
            if key == "none" { choose(nil) } else if let image = BuiltInBrushImage(rawValue: key) { choose(.builtIn(image)) }
        })
    }
}

/// The pressure curve's three shapes.
enum BrushResponse: String, CaseIterable, Identifiable {
    case soft, linear, firm

    init(_ curve: BrushCurve) {
        self = curve == .soft ? .soft : curve == .firm ? .firm : .linear
    }

    var id: String { rawValue }
    var curve: BrushCurve { self == .soft ? .soft : self == .firm ? .firm : .linear }

    var title: String {
        switch self {
        case .soft: "Light touch"
        case .linear: "Even"
        case .firm: "Firm press"
        }
    }
}

extension BuiltInBrushImage {
    var title: String {
        switch self {
        case .hardRound: "Hard round"
        case .softRound: "Soft round"
        case .pencilTip: "Pencil"
        case .chalkTip: "Chalk"
        case .bristleTip: "Bristles"
        case .flatTip: "Flat"
        case .splatterTip: "Splatter"
        case .paper: "Paper"
        case .canvas: "Canvas"
        case .noise: "Noise"
        case .charcoal: "Charcoal"
        }
    }
}

/// About: the name, where the brush came from, reset and duplicate.
struct BrushAboutPage: View {
    let brush: Brush
    let brushes: BrushModel
    @State private var name = ""
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        TextField("Name", text: $name)
            .textFieldStyle(.roundedBorder)
            .onAppear { name = brush.name }
            .onSubmit { brushes.rename(brush.id, to: name) }
        Text(LocalizedStringKey(caption)).font(.hmm(.footnote)).foregroundStyle(theme.text2)
        if let author = brush.about.author {
            Text("Made by \(author)").font(.hmm(.footnote)).foregroundStyle(theme.text2)
        }
        HStack(spacing: HmmSpacing.xs) {
            HmmPillButton("Duplicate", systemName: "plus.square.on.square") { brushes.duplicate(brush.id) }
            if brushes.library.resetTarget(brush.id) != nil {
                HmmPillButton("Reset brush", systemName: "arrow.counterclockwise") { brushes.reset(brush.id) }
            }
        }
    }

    /// Where the brush came from.
    private var caption: String {
        switch brush.about.origin {
        case .builtIn: "Comes with Maquette"
        case .made: "Made here"
        case .procreate: "Imported from Procreate"
        case .photoshop: "Imported from Photoshop"
        case .shared: "Shared with you"
        }
    }
}
