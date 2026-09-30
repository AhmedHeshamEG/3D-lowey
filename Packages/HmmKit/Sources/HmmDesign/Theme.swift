#if canImport(SwiftUI)
    import SwiftUI

    public extension Color {
        init(hmm rgb: HmmRGB) {
            self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: rgb.alpha)
        }
    }

    /// The user's appearance choice (Settings ▸ Appearance). "System" follows the device.
    public enum HmmThemeMode: String, CaseIterable, Identifiable, Sendable {
        case system, dark, light

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .system: "Automatic"
            case .dark: "Dark"
            case .light: "Light"
            }
        }

        public var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .dark: .dark
            case .light: .light
            }
        }

        /// The key the choice is stored under (`@AppStorage(HmmThemeMode.storageKey)`).
        public static let storageKey = "hmm.theme"
    }

    /// Resolved colours for one appearance and one app accent. Read it from the environment: `@Environment(\.hmmTheme)`.
    public struct HmmTheme: Sendable, Equatable {
        public var appearance: HmmAppearance
        public var accentToken: HmmAccent
        public var neutrals: HmmNeutrals

        public init(appearance: HmmAppearance, accent: HmmAccent) {
            self.appearance = appearance
            accentToken = accent
            neutrals = HmmNeutrals.for(appearance)
        }

        public var background: Color { Color(hmm: neutrals.background) }
        public var surface: Color { Color(hmm: neutrals.surface) }
        public var surface2: Color { Color(hmm: neutrals.surface2) }
        public var line: Color { Color(hmm: neutrals.line) }
        public var text: Color { Color(hmm: neutrals.text) }
        public var text2: Color { Color(hmm: neutrals.text2) }
        public var text3: Color { Color(hmm: neutrals.text3) }
        /// Active / selected / primary only.
        public var accent: Color { Color(hmm: accentToken.rgb) }
        /// Text or icons drawn on the accent.
        public var onAccent: Color { Color(hmm: HmmRGB(hex: 0x1A1305)) }
        public var record: Color { Color(hmm: HmmSemantic.record) }
        public var success: Color { Color(hmm: HmmSemantic.success) }
        public var warning: Color { Color(hmm: HmmSemantic.warning) }
        public var danger: Color { Color(hmm: HmmSemantic.danger) }

        public static let loweyDark = HmmTheme(appearance: .dark, accent: .lowey)
    }

    private struct HmmThemeKey: EnvironmentKey {
        static let defaultValue = HmmTheme.loweyDark
    }

    private struct HmmAccentKey: EnvironmentKey {
        static let defaultValue = HmmAccent.lowey
    }

    public extension EnvironmentValues {
        var hmmTheme: HmmTheme {
            get { self[HmmThemeKey.self] }
            set { self[HmmThemeKey.self] = newValue }
        }

        var hmmAccent: HmmAccent {
            get { self[HmmAccentKey.self] }
            set { self[HmmAccentKey.self] = newValue }
        }
    }

    /// Resolves the theme from the colour scheme and the app accent and puts it into the environment.
    private struct HmmThemeProvider: ViewModifier {
        @Environment(\.colorScheme) private var colorScheme
        let accent: HmmAccent

        func body(content: Content) -> some View {
            let theme = HmmTheme(appearance: colorScheme == .light ? .light : .dark, accent: accent)
            content
                .environment(\.hmmTheme, theme)
                .environment(\.hmmAccent, accent)
                .tint(theme.accent)
        }
    }

    public extension View {
        /// Applies the hmm. theme for an app: appearance from `mode` (or the device), the app's accent as tint.
        func hmmThemed(_ accent: HmmAccent, mode: HmmThemeMode = .system) -> some View {
            modifier(HmmThemeProvider(accent: accent))
                .preferredColorScheme(mode.colorScheme)
        }
    }

    public extension Font {
        /// The hmm. type scale on SF Pro, scaling with Dynamic Type.
        static func hmm(_ size: HmmTypeScale, weight: Font.Weight = .regular) -> Font {
            let style: Font.TextStyle = switch size {
            case .caption: .caption
            case .footnote: .footnote
            case .body: .subheadline
            case .headline: .headline
            case .title3: .title3
            case .title2: .title2
            case .title1: .largeTitle
            }
            return .system(style, design: .default, weight: weight)
        }

        /// Timecodes and counters: monospaced digits.
        static func hmmNumbers(_ size: HmmTypeScale = .footnote, weight: Font.Weight = .semibold) -> Font {
            .system(size: size.rawValue, weight: weight, design: .default).monospacedDigit()
        }
    }
#endif
