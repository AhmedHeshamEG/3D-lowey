import Foundation

/// One line of the critique rubric (the skill's `critique.md` has the same names and the same fixes).
public struct RubricCheck: Codable, Hashable, Sendable {
    public enum Result: String, Codable, Sendable {
        case pass, fail
        /// Not measurable here (no pixels, no motion).
        case skipped
    }

    public var name: String
    public var result: Result
    public var detail: String
    /// What to do about a fail.
    public var fix: String?

    public init(_ name: String, _ result: Result, _ detail: String, fix: String? = nil) {
        self.name = name
        self.result = result
        self.detail = detail
        self.fix = result == .fail ? fix : nil
    }

    static func check(_ name: String, _ passed: Bool, _ detail: String, fix: String) -> RubricCheck {
        RubricCheck(name, passed ? .pass : .fail, detail, fix: fix)
    }
}

/// The rubric applied to a measured frame: Read, Focus, Frame, Ground, Scale, Light, Clutter (Motion is the contact
/// sheet's). Thresholds are the ones in PROMPT §12.3 and docs/DECISIONS.md R48.
public enum ShotRubric {
    public static let minimumContrast = 25.0
    public static let maximumClutter = 7

    static func evaluate(objects: [ObservedObject], frame: FrameRead, scaleIssues: [String]) -> [RubricCheck] {
        let subject = frame.subject.flatMap { name in objects.first { $0.name == name } }
        return [read(frame), focus(subject, objects: objects), framing(subject, frame: frame), ground(objects),
                RubricCheck.check("Scale", scaleIssues.isEmpty,
                                  scaleIssues.isEmpty ? "Sizes match the Kit's real sizes" : scaleIssues.joined(separator: "; "),
                                  fix: "scaleTo the real size (the Kit knows it), or swap for a model made at that size"),
                light(frame, subjectCoverage: subject?.coverage),
                RubricCheck.check("Clutter", frame.clutter <= maximumClutter, "\(frame.clutter) significant things in frame",
                                  fix: "Remove or push back what doesn't serve the beat; let empty space frame the subject")]
    }

    static func read(_ frame: FrameRead) -> RubricCheck {
        guard let contrast = frame.contrast else { return RubricCheck("Read", .skipped, "No pixels to squint at") }
        return .check("Read", contrast >= minimumContrast, "Subject vs background ΔL* \(Int(contrast.rounded())) (needs \(Int(minimumContrast)))",
                      fix: "Darken the background (mood, fog, a wall colour) or light the subject; change one of their palette slots")
    }

    static func focus(_ subject: ObservedObject?, objects: [ObservedObject]) -> RubricCheck {
        guard let subject else {
            return RubricCheck("Focus", .fail, "No subject in frame", fix: "Frame the subject (frame_shot), or say which one it is")
        }
        let fix = "Move closer to the subject or a longer lens; push the rival back, darker or out of frame; light the subject"
        // An accent (the one thing that keeps its colour) leads however small it is.
        if subject.isAccent { return RubricCheck("Focus", .pass, "“\(subject.name)” is the accent") }
        let others = objects.filter { !$0.isSet && $0.id != subject.id && $0.coverage > 0.5 }
        guard let rival = others.first(where: { $0.coverage > subject.coverage * 1.2 }) else {
            return RubricCheck("Focus", .pass, "“\(subject.name)” is the biggest thing in frame (\(percent(subject.coverage)))")
        }
        // Not the biggest: it can still lead by being the brightest or the most contrasty.
        if let light = subject.lightness, others.allSatisfy({ ($0.lightness ?? 0) <= light + 2 }) {
            return RubricCheck("Focus", .pass, "“\(subject.name)” is the brightest thing in frame (L* \(Int(light)))")
        }
        if let contrast = subject.contrast, others.allSatisfy({ ($0.contrast ?? 0) <= contrast + 2 }) {
            return RubricCheck("Focus", .pass, "“\(subject.name)” stands out most (ΔL* \(Int(contrast)))")
        }
        let bigger = "“\(rival.name)” (\(percent(rival.coverage))) is bigger than the subject “\(subject.name)” (\(percent(subject.coverage)))"
        guard subject.lightness != nil else { return RubricCheck("Focus", .skipped, bigger + "; brightness needs pixels") }
        return RubricCheck("Focus", .fail, bigger + ", and neither brighter nor more contrasty", fix: fix)
    }

    static func framing(_ subject: ObservedObject?, frame: FrameRead) -> RubricCheck {
        var problems: [String] = []
        if let error = frame.thirdsError, error > 0.09 {
            problems.append("the subject is off the thirds (\(frame.thirds ?? "?"))")
        }
        if let headroom = frame.headroom, subject?.isCharacter == true, headroom > 0.3 {
            problems.append("too much headroom (\(percent(headroom * 100)))")
        }
        if let subject, subject.cutByFrame, subject.coverage < 30, frame.headroom ?? 0 >= 0 {
            problems.append("the frame cuts “\(subject.name)”")
        }
        if !frame.tangents.isEmpty {
            problems.append("tangents: \(frame.tangents.prefix(3).joined(separator: ", "))")
        }
        if abs(frame.horizonTilt) > 1.5, abs(frame.horizonTilt) < 8 {
            problems.append("the horizon tilts \(Int(frame.horizonTilt.rounded()))° (a mistake, not a Dutch angle)")
        }
        return .check("Frame", problems.isEmpty, problems.isEmpty ? "Composed: \(frame.thirds ?? "no subject"), no tangents" : problems.joined(separator: "; "),
                      fix: "frame_shot with leftThird / rightThird / center; nudge so edges clear the border; level the camera")
    }

    static func ground(_ objects: [ObservedObject]) -> RubricCheck {
        let floating = objects.filter { !$0.grounded && !$0.airborne && $0.gap > 1 }
        let sunk = objects.filter { !$0.grounded && $0.gap < -2 }
        let crossing = objects.filter { !$0.intersects.isEmpty }
        var problems: [String] = []
        problems += floating.map { "“\($0.name)” floats \(Int($0.gap.rounded())) cm" }
        problems += sunk.map { "“\($0.name)” is sunk \(Int((-$0.gap).rounded())) cm" }
        problems += crossing.prefix(3).map { "“\($0.name)” intersects “\($0.intersects[0])”" }
        return .check("Ground", problems.isEmpty, problems.isEmpty ? "Everything stands on something" : problems.joined(separator: "; "),
                      fix: "place it `on` what it stands on (the solver grounds it), or move it apart")
    }

    static func light(_ frame: FrameRead, subjectCoverage: Double? = nil) -> RubricCheck {
        guard let subject = frame.light.subjectLightness, let world = frame.light.worldLightness else {
            return RubricCheck("Light", .skipped, "Key from \(frame.light.keyFrom); no pixels to read")
        }
        let inShadow = frame.light.subjectInShadow ?? 0
        var problems: [String] = []
        if subject + 3 < world { problems.append("the world (L* \(Int(world))) is brighter than the subject (L* \(Int(subject)))") }
        if inShadow > 75 { problems.append("\(Int(inShadow))% of the subject is in shadow") }
        // Below a few % of the frame the analysis raster can't resolve an outline well enough to judge it.
        if let separation = frame.silhouetteSeparation, separation < 50, (subjectCoverage ?? 100) >= 3 {
            problems.append("the silhouette merges (\(Int(separation))% separated)")
        }
        return .check(
            "Light",
            problems.isEmpty,
            problems.isEmpty ? "Key from \(frame.light.keyFrom); subject brighter than the world" : problems.joined(separator: "; "),
            fix: "light with a recipe (key-warm-world-cool, golden-rim); add a rim; darken the world's mood"
        )
    }

    static func percent(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f%%", value) : "\(Int(value.rounded()))%"
    }
}
