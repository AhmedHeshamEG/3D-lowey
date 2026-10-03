import Foundation
import LoweyCore

/// The built-in foley on the sound-effects track: placed so its hit lands on the playhead or on a spoken word.
extension EditorModel {
    /// Adds `sound` with its hit at `time` (the playhead when nil). One undo step.
    @discardableResult
    func addFoley(_ sound: Foley, hitting time: Double? = nil) -> AudioClip? {
        let file = "foley-\(sound.rawValue).wav"
        let url = audioFolder.appendingPathComponent(file)
        do {
            try FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)
            // The same sound is the same file: written once per project.
            if !FileManager.default.fileExists(atPath: url.path) { try sound.wav().write(to: url, options: .atomic) }
        } catch {
            app.show("Couldn't add the sound: \(error.localizedDescription)", kind: .error)
            return nil
        }
        let hit = time ?? self.time
        let clip = AudioClip(id: UUID().uuidString.lowercased(), role: .sfx, name: sound.title, file: file, start: max(hit - sound.hit, 0),
                             duration: sound.duration, sourceDuration: sound.duration)
        addAudioClips([clip], label: "Add \(sound.title)")
        return clip
    }

    /// Attach to word: the sound hits on the first picked word.
    func addFoleyOnWords(_ sound: Foley) {
        guard let range = selectedWordRange else { return }
        addFoley(sound, hitting: range.start)
    }
}
