import HmmDesign
import LoweyCore
import LoweyEngine
import SwiftUI
import UniformTypeIdentifiers

/// Brush Studio (Procreate's): every setting of a brush, with a pad to try it on as it changes. Edits go to the
/// library at once; strokes already drawn keep the brush they were drawn with.
struct BrushStudioView: View {
    let brushes: BrushModel
    let brushID: String
    let color: RGBA
    @State private var page: BrushStudioPage = .stroke
    @State private var padStrokes: [[BrushInput<Vec2>]] = []
    @State private var padLive: [BrushInput<Vec2>] = []
    @State private var padSize: Double = 10
    @State private var importingPicture: BrushPictureSlot?
    @Environment(\.hmmTheme) private var theme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    private var brush: Brush { brushes.library.brush(brushID) ?? BuiltInBrushes.inkPen }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                pad
                Picker("Settings", selection: $page) {
                    ForEach(BrushStudioPage.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("brush-studio-pages")
                BrushStudioPageView(page: page, brush: brush, brushes: brushes) { slot in importingPicture = slot }
            }
            .padding(HmmSpacing.l)
        }
        .navigationTitle(Text(brush.name))
        .accessibilityIdentifier("brush-studio")
        .fileImporter(isPresented: Binding(get: { importingPicture != nil }, set: { if !$0 { importingPicture = nil } }),
                      allowedContentTypes: [.image]) { result in
            guard case let .success(url) = result, let slot = importingPicture else { return }
            importPicture(url, into: slot)
        }
    }

    // MARK: The pad

    private var pad: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous).fill(theme.surface)
                    if let image = padImage(size: proxy.size) {
                        Image(decorative: image, scale: displayScale).allowsHitTesting(false)
                    }
                    if padStrokes.isEmpty, padLive.isEmpty {
                        Text("Draw here to try the brush").font(.hmm(.body)).foregroundStyle(theme.text3).allowsHitTesting(false)
                    }
                    BrushPadSurface { samples, finished in
                        if finished {
                            padStrokes.append(samples)
                            padLive = []
                        } else {
                            padLive = samples
                        }
                    }
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
            .accessibilityIdentifier("brush-pad")
            HStack(spacing: HmmSpacing.s) {
                LabeledSlider(title: "Size", value: padSize, range: 1 ... 60, format: { "\(Int($0.rounded())) pt" }) { padSize = $0 }
                HmmButton("trash", label: "Clear the pad", size: 40) { padStrokes = [] }
            }
        }
    }

    private func padImage(size: CGSize) -> CGImage? {
        let strokes = (padStrokes + (padLive.isEmpty ? [] : [padLive])).enumerated().map { index, samples in
            let pixels = samples.map { sample in
                BrushInput(point: sample.point * displayScale, pressure: sample.pressure, altitude: sample.altitude, time: sample.time)
            }
            let path = BrushStroker.path(pixels, brush: brush, size: padSize * displayScale)
            return BrushPreviewStroke(path: path, brush: brush, color: inkColor, seed: UInt64(index + 1))
        }
        guard !strokes.isEmpty else { return nil }
        // Reading the revision redraws the pad when a setting changes.
        _ = brushes.revision
        return brushes.padImage(strokes, width: Int(size.width * displayScale), height: Int(size.height * displayScale))
    }

    private var inkColor: RGBA {
        let luminance = 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
        let dark = colorScheme == .dark
        // A colour that would vanish on the pad draws in the text colour instead.
        if dark, luminance < 0.15 { return RGBA(0.93, 0.93, 0.94) }
        if !dark, luminance > 0.9 { return RGBA(0.11, 0.11, 0.12) }
        return color
    }

    private func importPicture(_ url: URL, into slot: BrushPictureSlot) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let key = brushes.storePicture(data) else { return }
        var edited = brush
        switch slot {
        case .tip: edited.shape.source = .image(key)
        case .grain: edited.grain.source = .image(key)
        }
        brushes.update(edited)
    }
}

/// Which picture of the brush a chosen image becomes.
enum BrushPictureSlot: Identifiable {
    case tip, grain
    var id: Self { self }
}

/// Brush Studio's pages.
enum BrushStudioPage: String, CaseIterable, Identifiable {
    case stroke, shape, grain, dynamics, pencil, rendering, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stroke: "Stroke"
        case .shape: "Shape"
        case .grain: "Grain"
        case .dynamics: "Dynamics"
        case .pencil: "Pencil"
        case .rendering: "Rendering"
        case .about: "About"
        }
    }
}

/// The pad's touch surface: Pencil and finger samples with pressure, tilt and time, in points.
struct BrushPadSurface: UIViewRepresentable {
    let onStroke: ([BrushInput<Vec2>], Bool) -> Void

    func makeUIView(context _: Context) -> PadView {
        let view = PadView()
        view.onStroke = onStroke
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        return view
    }

    func updateUIView(_ view: PadView, context _: Context) {
        view.onStroke = onStroke
    }

    final class PadView: UIView {
        var onStroke: (([BrushInput<Vec2>], Bool) -> Void)?
        private var samples: [BrushInput<Vec2>] = []

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            samples = []
            add(touches, event: event)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            add(touches, event: event)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            add(touches, event: event)
            onStroke?(samples, true)
            samples = []
        }

        override func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
            onStroke?(samples, true)
            samples = []
        }

        private func add(_ touches: Set<UITouch>, event: UIEvent?) {
            guard let touch = touches.first else { return }
            for item in event?.coalescedTouches(for: touch) ?? [touch] {
                let point = item.preciseLocation(in: self)
                let pressure = item.type == .pencil && item.maximumPossibleForce > 0 ? Double(item.force / item.maximumPossibleForce) : 0.6
                samples.append(BrushInput(point: Vec2(Double(point.x), Double(point.y)), pressure: pressure,
                                          altitude: item.type == .pencil ? Double(item.altitudeAngle) : nil, time: item.timestamp))
            }
            onStroke?(samples, false)
        }
    }
}
