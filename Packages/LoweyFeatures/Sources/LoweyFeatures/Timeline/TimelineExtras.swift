import HmmDesign
import LoweyCore
import SwiftUI

/// The curve leaving a key: presets, or drag the two handles.
struct EasingEditor: View {
    let editor: EditorModel
    let key: KeyRef
    @State private var handles: (Double, Double, Double, Double) = (0.42, 0, 0.58, 1)
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HmmSheet("Curve", subtitle: "How the motion speeds up and slows down between this key and the next.") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.xs) {
                    ForEach(EasingChoice.allCases) { choice in
                        ChoiceChip(title: choice.title, isOn: false) {
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
                    Path { $0.addRect(box) }.stroke(theme.line, lineWidth: 1)
                    Path { path in
                        let easing = currentEasing
                        for index in 0 ... 60 {
                            let t = Double(index) / 60
                            let point = CGPoint(x: box.minX + CGFloat(t) * box.width, y: box.maxY - CGFloat(easing.apply(t)) * box.height)
                            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                    }
                    .stroke(theme.accent, lineWidth: 3)
                    handle(box: box, first: true)
                    handle(box: box, first: false)
                }
            }
            .frame(minHeight: 260)
        }
        .onAppear { if case let .cubicBezier(a, b, c, d) = keyEasing { handles = (a, b, c, d) } }
    }

    private var keyEasing: Easing { editor.timeline.track(key.track)?.key(at: key.time)?.easing ?? .easeInOut }

    private var currentEasing: Easing {
        if case .cubicBezier = keyEasing { return .cubicBezier(handles.0, handles.1, handles.2, handles.3) }
        return keyEasing
    }

    private func handle(box: CGRect, first: Bool) -> some View {
        let anchor = first ? CGPoint(x: box.minX, y: box.maxY) : CGPoint(x: box.maxX, y: box.minY)
        let point = CGPoint(x: box.minX + CGFloat(first ? handles.0 : handles.2) * box.width, y: box.maxY - CGFloat(first ? handles.1 : handles.3) * box.height)
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: anchor)
                path.addLine(to: point)
            }
            .stroke(theme.text.opacity(0.5), lineWidth: 1)
            Circle()
                .fill(theme.text)
                .frame(width: 28, height: 28)
                .position(point)
                .gesture(DragGesture()
                    .onChanged { value in
                        let x = min(max(Double((value.location.x - box.minX) / box.width), 0), 1)
                        let y = min(max(Double((box.maxY - value.location.y) / box.height), -0.5), 1.5)
                        handles = first ? (x, y, handles.2, handles.3) : (handles.0, handles.1, x, y)
                    }
                    .onEnded { _ in
                        if editor.selectedKeys.isEmpty { editor.selectedKeys = [key] }
                        editor.setEasing(.cubicBezier(handles.0, handles.1, handles.2, handles.3))
                    })
                .accessibilityLabel(first ? "First handle" : "Second handle")
        }
    }
}

/// Frame rate, length, the project's stepping.
struct TimelineSettingsSheet: View {
    let editor: EditorModel
    @State private var length: Double = 10

    var body: some View {
        HmmSheet("Timeline") {
            HmmSectionHeader("Frame rate")
            Picker("Frame rate", selection: Binding(get: { editor.timeline.fps }, set: { editor.setFrameRate($0) })) {
                ForEach(Timeline.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledSlider(title: "Length", value: length, range: 1 ... 120, format: { "\(NumberFormat.short($0)) s" }, set: { length = $0 },
                          done: { editor.setDuration(length) })
            HmmPillButton("Fit to the animation") {
                editor.fitDurationToContent()
                length = editor.timeline.duration
            }
            HmmSectionHeader("Stepping (the whole project)")
            Picker("Stepping", selection: Binding(get: { editor.timeline.stepping }, set: { editor.setProjectStepping($0) })) {
                Text("On ones").tag(Stepping.onOnes)
                Text("On twos").tag(Stepping.onTwos)
                Text("On threes").tag(Stepping.onThrees)
            }
            .pickerStyle(.segmented)
            Hint("On twos looks hand-animated. Cameras stay smooth; any object can choose its own in the inspector.")
        }
        .onAppear { length = editor.timeline.duration }
    }
}

/// Perform any number while the timeline records (glow, light strength, focal length, opacity…).
struct PerformValueSlider: View {
    @Bindable var editor: EditorModel
    @State private var value: Double = 0

    private struct Option: Identifiable {
        let key: PropertyKey
        let title: String
        let range: ClosedRange<Double>
        var id: String { key.rawValue }
    }

    private var options: [Option] {
        guard let object = editor.singleSelection else { return [] }
        if object.kind == .camera {
            return [Option(key: .fieldOfView, title: "Zoom", range: 10 ... 100), Option(key: .focusDistance, title: "Focus", range: 0.2 ... 40)]
        }
        var result = [Option(key: .opacity, title: "Opacity", range: 0 ... 1)]
        if object.kind.hasSurface { result.append(Option(key: .emissiveIntensity, title: "Glow", range: 0 ... 8)) }
        if case .light = object.kind { result.append(Option(key: .lightIntensity, title: "Light", range: 0 ... 6)) }
        return result
    }

    var body: some View {
        HStack(spacing: HmmSpacing.xs) {
            Menu {
                Button("Move, size and turn (touch)") { editor.performSliderKey = nil }
                ForEach(options) { option in
                    Button(option.title) {
                        editor.performSliderKey = option.key
                        value = editor.singleSelection?[option.key]?.floatValue ?? option.range.lowerBound
                    }
                }
            } label: {
                Label(currentTitle, systemImage: "hand.draw").font(.hmm(.footnote, weight: .semibold))
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

/// "Ready 3-2-1" and the recording badge.
struct PerformCountdown: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        ZStack {
            switch editor.performPhase {
            case let .countdown(count):
                VStack(spacing: HmmSpacing.xs) {
                    Text("Ready").font(.hmm(.title3, weight: .semibold))
                    Text("\(count)").font(.system(size: 96, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text(editor.virtualCameraActive ? "Move the iPad when it plays" : "Touch and move when it plays").font(.hmm(.body))
                        .foregroundStyle(theme.text2)
                }
                .padding(HmmSpacing.xl)
                .hmmPanelBackground(cornerRadius: 30)
                .transition(.scale.combined(with: .opacity))
                .accessibilityIdentifier("perform-countdown")
            case .recording:
                HStack(spacing: HmmSpacing.xs) {
                    Circle().fill(theme.record).frame(width: 12, height: 12)
                    Text("REC").font(.hmm(.body, weight: .semibold))
                    Text(editor.performTouching ? "recording" : "lift = paused").font(.hmm(.footnote)).foregroundStyle(theme.text2)
                }
                .padding(.horizontal, HmmSpacing.m)
                .padding(.vertical, HmmSpacing.xs)
                .hmmGlass(in: Capsule(), interactive: false)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 70)
                .accessibilityIdentifier("perform-recording")
            case .idle:
                EmptyView()
            }
        }
        .allowsHitTesting(false)
        .animation(.hmmStandard, value: editor.performPhase)
    }
}
