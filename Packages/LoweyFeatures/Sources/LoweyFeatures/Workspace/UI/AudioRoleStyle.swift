import LoweyCore
import SwiftUI

extension AudioRole {
    var systemImage: String {
        switch self {
        case .voiceover: "mic.fill"
        case .sfx: "speaker.wave.2.fill"
        case .music: "music.note"
        }
    }

    var tint: Color {
        switch self {
        case .voiceover: Color(red: 0.45, green: 0.85, blue: 0.65)
        case .sfx: Color(red: 0.95, green: 0.6, blue: 0.35)
        case .music: Color(red: 0.6, green: 0.55, blue: 1)
        }
    }
}
