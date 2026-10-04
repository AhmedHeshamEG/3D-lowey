import HmmDesign
import LoweyCore
import Observation
import SwiftUI
import UIKit

/// A Mood shown as its sky.
struct MoodCard: View {
    let mood: LightingPreset
    let selected: Bool
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let sky = MoodPresets.sky(for: mood)
        VStack(spacing: HmmSpacing.xs) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [sky.top.color, sky.horizon.color, sky.bottom.color], startPoint: .top, endPoint: .bottom)
                if sky.stars > 0 {
                    Image(systemName: "sparkles").foregroundStyle(.white.opacity(0.8)).padding(HmmSpacing.xs)
                }
            }
            .frame(width: 104, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous)
                .stroke(selected ? theme.accent : theme.line, lineWidth: selected ? 3 : 1))
            Text(mood.displayName)
                .font(.hmm(.footnote, weight: .semibold))
                .foregroundStyle(selected ? theme.accent : theme.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("mood-\(mood.rawValue)")
    }
}

/// A Look shown on a sphere and a cube, rendered once per Look and kept for the session.
struct LookCard: View {
    let preset: LookPreset
    let selected: Bool
    var mood: LightingPreset = .day
    @Environment(\.hmmTheme) private var theme
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: HmmSpacing.xs) {
            ZStack {
                theme.surface2
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "paintpalette").font(.system(size: 22)).foregroundStyle(theme.text3)
                }
            }
            .frame(width: 104, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous)
                .stroke(selected ? theme.accent : theme.line, lineWidth: selected ? 3 : 1))
            Text(LocalizedStringKey(preset.name))
                .font(.hmm(.footnote, weight: .semibold))
                .foregroundStyle(selected ? theme.accent : theme.text)
                .lineLimit(1)
        }
        .frame(width: 108)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("look-\(preset.id)")
        .task(id: "\(preset.hashValue)-\(mood.rawValue)") { image = await LookSwatches.shared.swatch(preset, mood: mood) }
    }
}

/// Rendered Look swatches, made once and reused by every card.
@MainActor
final class LookSwatches {
    static let shared = LookSwatches()
    private var images: [String: UIImage] = [:]
    private let thumbnailer = Thumbnailer()

    func swatch(_ preset: LookPreset, mood: LightingPreset) async -> UIImage? {
        let key = "\(preset.hashValue)-\(mood.rawValue)"
        if let cached = images[key] { return cached }
        var look = MoodPresets.look(for: mood)
        look.presetID = preset.id
        guard let image = try? await thumbnailer.lookSwatch(look, customLooks: preset.isBuiltIn ? [] : [preset], width: 208, height: 136) else {
            return nil
        }
        let made = UIImage(cgImage: image)
        images[key] = made
        return made
    }
}
