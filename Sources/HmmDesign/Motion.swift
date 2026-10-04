#if canImport(SwiftUI)
    import SwiftUI
    #if canImport(UIKit)
        import UIKit
    #endif

    /// The three motion tokens. Springs only, never linear; with Reduce Motion they become a 0.2 s cross-fade.
    public enum HmmMotion: Sendable {
        case snappy, standard, gentle

        public var spring: HmmSpring {
            switch self {
            case .snappy: .snappy
            case .standard: .standard
            case .gentle: .gentle
            }
        }

        public func animation(reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeInOut(duration: HmmSpring.reducedMotionFade)
                : .spring(response: spring.response, dampingFraction: spring.damping)
        }
    }

    public extension Animation {
        static let hmmSnappy = Animation.spring(response: HmmSpring.snappy.response, dampingFraction: HmmSpring.snappy.damping)
        static let hmmStandard = Animation.spring(response: HmmSpring.standard.response, dampingFraction: HmmSpring.standard.damping)
        static let hmmGentle = Animation.spring(response: HmmSpring.gentle.response, dampingFraction: HmmSpring.gentle.damping)
    }

    private struct HmmAnimationModifier<Value: Equatable>: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let motion: HmmMotion
        let value: Value

        func body(content: Content) -> some View {
            content.animation(motion.animation(reduceMotion: reduceMotion), value: value)
        }
    }

    public extension View {
        /// Animates changes of `value` with a motion token (respecting Reduce Motion).
        func hmmAnimation(_ motion: HmmMotion, value: some Equatable) -> some View {
            modifier(HmmAnimationModifier(motion: motion, value: value))
        }

        /// Panels appear the way they are opened: scaling out of their anchor and fading (a fade with Reduce Motion).
        func hmmPanelTransition(from anchor: UnitPoint) -> some View {
            transition(.asymmetric(insertion: .scale(scale: 0.92, anchor: anchor).combined(with: .opacity),
                                   removal: .scale(scale: 0.96, anchor: anchor).combined(with: .opacity)))
        }
    }

    /// `withAnimation` with a motion token.
    @MainActor
    public func withHmmAnimation<Result>(_ motion: HmmMotion, reduceMotion: Bool = HmmAccessibility.reduceMotion,
                                         _ body: () throws -> Result) rethrows -> Result {
        try withAnimation(motion.animation(reduceMotion: reduceMotion), body)
    }

    /// Accessibility settings readable outside a view.
    @MainActor
    public enum HmmAccessibility {
        public static var reduceMotion: Bool {
            #if canImport(UIKit)
                UIAccessibility.isReduceMotionEnabled
            #else
                false
            #endif
        }

        public static var reduceTransparency: Bool {
            #if canImport(UIKit)
                UIAccessibility.isReduceTransparencyEnabled
            #else
                false
            #endif
        }
    }
#endif
