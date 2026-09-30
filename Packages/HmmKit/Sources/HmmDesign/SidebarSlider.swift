#if canImport(SwiftUI)
    import SwiftUI

    /// Procreate-style vertical slider for the sidebar: a slim glass track filled from the bottom, dragged anywhere
    /// along it (relative, so it never jumps), finer when the finger drifts sideways. Shows the value while dragging.
    public struct HmmSlider: View {
        private let title: String
        @Binding private var value: Double
        private let range: ClosedRange<Double>
        private let format: (Double) -> String
        private let length: Double
        private let onEditingChanged: (Bool) -> Void
        @State private var dragStart: Double?
        @Environment(\.hmmTheme) private var theme

        public init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, length: Double = 180,
                    format: @escaping (Double) -> String = { String(Int(($0 * 100).rounded())) + "%" },
                    onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
            self.title = title
            _value = value
            self.range = range
            self.format = format
            self.length = length
            self.onEditingChanged = onEditingChanged
        }

        public var body: some View {
            let mapping = HmmSliderMapping(range: range, length: length)
            let fraction = mapping.fraction(of: value)
            ZStack(alignment: .bottom) {
                Capsule().fill(theme.surface2.opacity(0.55))
                Capsule()
                    .fill(theme.text.opacity(dragStart == nil ? 0.55 : 0.8))
                    .frame(height: max(12, length * fraction))
            }
            .frame(width: 28, height: length)
            .padding(8)
            .contentShape(Rectangle())
            .hmmGlass(in: Capsule(), interactive: false)
            .overlay(alignment: .trailing) {
                if dragStart != nil {
                    Text(format(value))
                        .font(.hmmNumbers(.footnote))
                        .padding(.horizontal, HmmSpacing.xs)
                        .padding(.vertical, HmmSpacing.xxs)
                        .hmmGlass(in: Capsule(), interactive: false)
                        .fixedSize()
                        .offset(x: 64)
                        .transition(.opacity)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragStart == nil {
                            dragStart = value
                            onEditingChanged(true)
                        }
                        value = mapping.value(start: dragStart ?? value, dy: drag.translation.height, dx: drag.translation.width)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        onEditingChanged(false)
                        HmmHaptics.play(.commit)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityValue(format(value))
            .accessibilityAdjustableAction { direction in
                let step = (range.upperBound - range.lowerBound) / 20
                switch direction {
                case .increment: value = min(value + step, range.upperBound)
                case .decrement: value = max(value - step, range.lowerBound)
                @unknown default: break
                }
            }
            .accessibilityIdentifier(title)
        }
    }
#endif
