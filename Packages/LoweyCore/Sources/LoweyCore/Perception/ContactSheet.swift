import Foundation

/// How one thing moves on screen over a stretch of the shot.
public struct MotionStats: Codable, Hashable, Sendable {
    public var name: String
    /// Distance travelled on screen, in frame heights.
    public var pathLength: Double
    /// Fastest screen speed, frame heights per second.
    public var peakSpeed: Double
    /// Turns sharper than 75° while moving.
    public var directionChanges: Int
    /// Stillnesses of 0.2 s or more between or after moves.
    public var holds: Int
    /// It goes out of frame (or comes in) during the stretch.
    public var leavesFrame: Bool
    /// Straight distance ÷ path while moving (1: a ruler line; lower: an arc or a wander).
    public var straightness: Double
    /// Spread of its speed while moving (standard deviation ÷ mean; near 0 is a constant-speed glide).
    public var speedVariation: Double
    /// When it peaks (seconds).
    public var peaks: [Double]
    /// Starts, stops and peaks within 0.25 s of a word, of all of them (nil without a transcript).
    public var onWords: Int?
    public var events: Int
}

/// The camera's own move over the stretch.
public struct CameraMotion: Codable, Hashable, Sendable {
    /// Metres travelled and degrees turned.
    public var pathLength: Double
    public var turn: Double
    /// Metres per second at its fastest.
    public var peakSpeed: Double
    public var speedVariation: Double
    public var easesIn: Bool
    public var easesOut: Bool
    /// Moving most of the time at nearly one speed (the "constant-speed orbit" the rubric rejects).
    public var constantSpeed: Bool
}

/// One frame of a contact sheet, in a line.
public struct ContactFrame: Codable, Hashable, Sendable {
    public var time: Double
    public var timecode: String
    public var subject: String?
    public var thirds: String?
    public var subjectCoverage: Double?
    public var clutter: Int
    public var word: String?
    /// The caption under the frame.
    public var note: String
}

/// `contact_sheet`: N frames with mini reports, and how everything moves between them.
public struct ContactSheetReport: Codable, Hashable, Sendable {
    public var scene: String
    public var start: Double
    public var end: Double
    public var frames: [ContactFrame]
    public var motion: [MotionStats]
    public var camera: CameraMotion?
    public var checks: [RubricCheck]
    public var summary: String
}

extension ShotObserver {
    /// Evenly spread frame times over a stretch, first and last frames included.
    public static func frameTimes(from start: Double, to end: Double, count: Int) -> [Double] {
        guard count > 1, end > start else { return [start] }
        return (0 ..< count).map { start + (end - start) * Double($0) / Double(count - 1) }
    }

    /// The contact sheet's numbers for `start…end`: `frames` frames and motion sampled `sampleRate` times a second.
    public func contactSheet(from start: Double, to end: Double, frames count: Int = 6, aspect: Double = 16.0 / 9.0, subject: String? = nil,
                             sampleRate: Double = 24) -> ContactSheetReport {
        let words = document.scene.timeline.words
        let frames = Self.frameTimes(from: start, to: end, count: max(count, 1)).map { time -> ContactFrame in
            let report = observe(at: time, aspect: aspect, subject: subject)
            let word = WordSnap.word(at: time, in: words, lookback: 0.3)?.text
            let coverage = report.frame.subject.flatMap { report.object(named: $0)?.coverage }
            var note = report.frame.subject.map { "\($0) · \(report.frame.thirds ?? "?") · \(ShotRubric.percent(coverage ?? 0))" } ?? "no subject"
            note += " · \(report.frame.clutter) in frame"
            if let word { note += " · “\(word)”" }
            return ContactFrame(time: time, timecode: Self.timecode(time, fps: document.scene.timeline.fps), subject: report.frame.subject,
                                thirds: report.frame.thirds, subjectCoverage: coverage, clutter: report.frame.clutter, word: word, note: note)
        }
        let samples = sampleMotion(from: start, to: end, aspect: aspect, rate: sampleRate)
        let motion = samples.tracks.compactMap { MotionAnalysis.stats(name: $0.name, points: $0.points, times: samples.times, words: words) }
        let camera = MotionAnalysis.camera(samples.camera, times: samples.times)
        let checks = [MotionAnalysis.check(motion, camera: camera, duration: end - start, hasWords: !words.isEmpty)]
        let moving = motion.map(\.name)
        let summary = "\(frames.count) frames over \(String(format: "%.1f", end - start)) s. "
            + (moving.isEmpty ? "Nothing moves on its own" : "Moving: \(moving.prefix(6).joined(separator: ", "))")
            + (camera.map(Self.cameraWords) ?? "")
            + ". " + (checks[0].result == .fail ? "Motion: \(checks[0].detail)." : "Motion passes.")
        return ContactSheetReport(scene: document.scene.name, start: start, end: end, frames: frames, motion: motion, camera: camera,
                                  checks: checks, summary: summary)
    }

    static func cameraWords(_ camera: CameraMotion) -> String {
        camera.pathLength > 0.05 || camera.turn > 2 ? "; the camera travels \(String(format: "%.1f", camera.pathLength)) m" : "; the camera holds"
    }

    static func timecode(_ time: Double, fps: Int) -> String {
        let frame = Int((time * Double(max(fps, 1))).rounded())
        let seconds = frame / max(fps, 1)
        return String(format: "%d:%02d.%02d", seconds / 60, seconds % 60, frame % max(fps, 1))
    }

    struct MotionSamples {
        var times: [Double] = []
        /// Screen positions (x in frame heights from the left, y in frame heights from the top; nil behind the camera).
        var tracks: [(name: String, points: [(x: Double, y: Double, inFrame: Bool)?])] = []
        var camera: [(position: Vec3, forward: Vec3)] = []
    }

    /// Screen paths of the things that move in the world, and the camera's path.
    func sampleMotion(from start: Double, to end: Double, aspect: Double, rate: Double) -> MotionSamples {
        let bounds = SceneBounds(library: library)
        let units = Self.units(in: document.scene)
        let step = 1 / max(rate, 1)
        var samples = MotionSamples()
        var worlds: [[Vec3?]] = Array(repeating: [], count: units.count)
        var screens: [[(x: Double, y: Double, inFrame: Bool)?]] = Array(repeating: [], count: units.count)
        var time = start
        while time <= end + 1e-9 {
            let animated = Animator.evaluate(document, at: time, rigs: rigs)
            let camera = ObserveCamera.shot(animated, fallback: document.scene.viewpoint, aspect: aspect)
            samples.times.append(time)
            samples.camera.append((camera.position, camera.forward))
            for (index, unit) in units.enumerated() {
                let center = bounds.worldBounds(of: unit, in: animated.scene)?.center
                worlds[index].append(center)
                screens[index].append(center.flatMap { camera.project($0) }.map { point in
                    (point.x * aspect, point.y, point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1)
                })
            }
            time += step
        }
        for (index, unit) in units.enumerated() {
            let positions = worlds[index].compactMap(\.self)
            guard let first = positions.first, positions.contains(where: { ($0 - first).length > 0.02 }) else { continue }
            samples.tracks.append((document.scene.objects[unit]?.name ?? unit.raw, screens[index]))
        }
        return samples
    }
}
