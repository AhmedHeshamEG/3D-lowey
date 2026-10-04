#if canImport(SwiftUI)
    import SwiftUI

    public extension EnvironmentValues {
        /// Inside a glass panel, controls draw no glass of their own (glass on glass is muddy, and every glass layer
        /// over a live canvas is re-blurred every frame).
        @Entry var hmmInsideGlass = false
    }

    /// Floating chrome material: Liquid Glass with a dark tint so text stays legible over any content, or a solid
    /// surface at 96 % with Reduce Transparency (opaque, with a stronger outline, with Increase Contrast).
    private struct HmmGlassModifier<S: Shape>: ViewModifier {
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.hmmTheme) private var theme
        let shape: S
        let interactive: Bool
        let tint: Color?

        func body(content: Content) -> some View {
            if reduceTransparency || contrast == .increased {
                content
                    .background(theme.surface.opacity(contrast == .increased ? 1 : 0.96), in: shape)
                    .overlay(shape.stroke(contrast == .increased ? theme.text2 : theme.line, lineWidth: contrast == .increased ? 1.5 : 1))
            } else {
                let glassTint = tint ?? (theme.appearance == .dark ? Color.black.opacity(0.32) : Color.white.opacity(0.28))
                content.glassEffect(interactive ? .regular.tint(glassTint).interactive() : .regular.tint(glassTint), in: shape)
            }
        }
    }

    public extension View {
        /// A floating control on glass (round buttons, pills over the canvas).
        func hmmGlass(in shape: some Shape = Capsule(), interactive: Bool = true, tint: Color? = nil) -> some View {
            modifier(HmmGlassModifier(shape: shape, interactive: interactive, tint: tint))
        }

        /// A floating panel: glass in the panel radius; controls inside draw no glass of their own.
        func hmmPanelBackground(cornerRadius: Double = HmmRadius.panel) -> some View {
            environment(\.hmmInsideGlass, true)
                .modifier(HmmGlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                                           interactive: false, tint: nil))
        }
    }
#endif
