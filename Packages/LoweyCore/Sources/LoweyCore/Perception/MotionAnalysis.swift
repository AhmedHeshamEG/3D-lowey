import Foundation

/// The numbers behind the Motion line of the rubric: arcs, holds, speed changes, peaks on words.
enum MotionAnalysis {
    /// Below this screen speed (frame heights per second) a thing is holding.
    static let still = 0.05
    /// Velocities are measured over this window (seconds), so animation on twos or fours doesn't read as stop-start.
    static let window = 0.17

    /// Smoothed speeds and velocities of a sampled path.
    static func velocities(_ points: [(x: Double, y: Double)?], times: [Double]) -> [(dx: Double, dy: Double, speed: Double)?] {
        guard times.count > 1, let first = times.first, let last = times.last else { return points.map { _ in nil } }
        let step = (last - first) / Double(times.count - 1)
        let reach = max(Int((window / 2 / max(step, 1e-6)).rounded()), 1)
        return points.indices.map { index in
            let low = max(index - reach, 0)
            let high = min(index + reach, points.count - 1)
            guard high > low, let a = points[low], let b = points[high] else { return nil }
            let span = times[high] - times[low]
            let dx = (b.x - a.x) / span
            let dy = (b.y - a.y) / span
            return (dx, dy, (dx * dx + dy * dy).squareRoot())
        }
    }

    static func stats(name: String, points: [(x: Double, y: Double, inFrame: Bool)?], times: [Double], words: [TimelineWord]) -> MotionStats? {
        let flat = points.map { $0.map { (x: $0.x, y: $0.y) } }
        let velocity = velocities(flat, times: times)
        let speeds = velocity.map { $0?.speed ?? 0 }
        guard let peak = speeds.max(), peak > still else { return nil }
        var path = 0.0
        var movingPoints: [(x: Double, y: Double)] = []
        for index in points.indices.dropFirst() {
            guard let a = flat[index - 1], let b = flat[index] else { continue }
            path += ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
            if speeds[index] > still { movingPoints.append(b) }
        }
        var chord = 0.0
        if let from = movingPoints.first, let to = movingPoints.last {
            chord = ((to.x - from.x) * (to.x - from.x) + (to.y - from.y) * (to.y - from.y)).squareRoot()
        }
        // Speed variation over the body of the moves (above half the peak), so the ramp in and out of a key doesn't count.
        let moving = speeds.filter { $0 > max(still, peak * 0.5) }
        let mean = moving.reduce(0, +) / Double(max(moving.count, 1))
        let deviation = (moving.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(moving.count, 1))).squareRoot()
        let events = eventTimes(speeds, times: times, peak: peak)
        let inFrame = points.compactMap { $0?.inFrame }
        return MotionStats(
            name: name, pathLength: round3(path), peakSpeed: round3(peak), directionChanges: turns(velocity), holds: holds(speeds, times: times),
            leavesFrame: inFrame.contains(true) && inFrame.contains(false), straightness: path > 1e-6 ? round3(min(chord / path, 1)) : 1,
            speedVariation: mean > 0 ? round3(deviation / mean) : 0, peaks: events.peaks.map(round3),
            onWords: words.isEmpty ? nil : events.all.filter { time in words.contains { abs($0.start - time) <= 0.25 } }.count,
            events: events.all.count
        )
    }

    /// Turns sharper than 75° between moving samples a window apart.
    static func turns(_ velocity: [(dx: Double, dy: Double, speed: Double)?]) -> Int {
        var count = 0
        var last: (dx: Double, dy: Double)?
        var sinceTurn = Int.max / 2
        for item in velocity {
            sinceTurn += 1
            guard let item, item.speed > still * 2 else { continue }
            let direction = (dx: item.dx / item.speed, dy: item.dy / item.speed)
            if let previous = last, previous.dx * direction.dx + previous.dy * direction.dy < cos(75 * Double.pi / 180), sinceTurn > 3 {
                count += 1
                sinceTurn = 0
            }
            last = direction
        }
        return count
    }

    /// Stillnesses of at least 0.2 s that follow a move.
    static func holds(_ speeds: [Double], times: [Double]) -> Int {
        var count = 0
        var moved = false
        var stillSince: Double?
        var counted = false
        for (index, speed) in speeds.enumerated() {
            if speed > still {
                moved = true
                stillSince = nil
                counted = false
            } else if moved {
                let since = stillSince ?? times[index]
                stillSince = since
                if !counted, times[index] - since >= 0.2 {
                    count += 1
                    counted = true
                }
            }
        }
        return count
    }

    /// Peaks (local maxima above 30% of the fastest, 0.25 s apart) and the starts and stops of moves.
    static func eventTimes(_ speeds: [Double], times: [Double], peak: Double) -> (peaks: [Double], all: [Double]) {
        var peaks: [Double] = []
        var all: [Double] = []
        for index in speeds.indices {
            let speed = speeds[index]
            let before = index > 0 ? speeds[index - 1] : 0
            let after = index + 1 < speeds.count ? speeds[index + 1] : 0
            if speed > peak * 0.3, speed >= before, speed > after, peaks.last.map({ times[index] - $0 >= 0.25 }) ?? true {
                peaks.append(times[index])
            }
            if index > 0, (before > still) != (speed > still) { all.append(times[index]) }
        }
        return (peaks, (all + peaks).sorted())
    }

    static func camera(_ samples: [(position: Vec3, forward: Vec3)], times: [Double]) -> CameraMotion? {
        guard samples.count > 2 else { return nil }
        var path = 0.0
        var turn = 0.0
        var speeds: [Double] = []
        for index in samples.indices.dropFirst() {
            let distance = (samples[index].position - samples[index - 1].position).length
            let angle = acos(min(max(samples[index].forward.dot(samples[index - 1].forward), -1), 1)) * 180 / .pi
            path += distance
            turn += angle
            let dt = max(times[index] - times[index - 1], 1e-6)
            // Turning counts as moving too: a metre a second for every 20° a second.
            speeds.append(distance / dt + angle / dt / 20)
        }
        let peak = speeds.max() ?? 0
        let moving = speeds.filter { $0 > peak * 0.05 && $0 > 0.01 }
        let mean = moving.reduce(0, +) / Double(max(moving.count, 1))
        let deviation = (moving.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(moving.count, 1))).squareRoot()
        let variation = mean > 0 ? deviation / mean : 0
        let firstMoving = speeds.firstIndex { $0 > peak * 0.05 && $0 > 0.01 }
        let lastMoving = speeds.lastIndex { $0 > peak * 0.05 && $0 > 0.01 }
        let edge = max(speeds.count / 10, 1)
        let easesIn = firstMoving.map { start in speeds[start ..< min(start + edge, speeds.count)].allSatisfy { $0 < peak * 0.6 } } ?? true
        let easesOut = lastMoving.map { end in speeds[max(end - edge + 1, 0) ... end].allSatisfy { $0 < peak * 0.6 } } ?? true
        let constant = Double(moving.count) > Double(speeds.count) * 0.6 && variation < 0.15 && peak > 0.05
        return CameraMotion(pathLength: round3(path), turn: round3(turn), peakSpeed: round3(peak), speedVariation: round3(variation), easesIn: easesIn,
                            easesOut: easesOut, constantSpeed: constant)
    }

    /// The Motion line: arcs, holds, no constant-speed glides, peaks on words.
    static func check(_ motion: [MotionStats], camera: CameraMotion?, duration: Double, hasWords: Bool) -> RubricCheck {
        var problems: [String] = []
        for item in motion where item.pathLength > 0.3 && item.straightness > 0.98 {
            problems.append("“\(item.name)” moves in a ruler-straight line")
        }
        if !motion.isEmpty, duration > 2, motion.allSatisfy({ $0.holds == 0 }) {
            problems.append("nothing ever holds still")
        }
        for item in motion where item.speedVariation < 0.12 && item.pathLength > 0.3 {
            problems.append("“\(item.name)” glides at one speed")
        }
        if camera?.constantSpeed == true { problems.append("the camera moves at a constant speed (ease it, or land it on a word)") }
        if hasWords {
            let events = motion.reduce(0) { $0 + $1.events }
            let onWords = motion.reduce(0) { $0 + ($1.onWords ?? 0) }
            if events >= 3, Double(onWords) / Double(events) < 0.34 { problems.append("only \(onWords) of \(events) moves land on words") }
        }
        if motion.isEmpty, camera.map({ $0.pathLength < 0.05 && $0.turn < 2 }) ?? true {
            return RubricCheck("Motion", .skipped, "Nothing moves")
        }
        return .check("Motion", problems.isEmpty, problems.isEmpty ? "Arcs, holds and eased moves" : problems.prefix(4).joined(separator: "; "),
                      fix: "arc the path (a mid key off the line), add holds, ease in/out; anticipate big moves; key peaks to words")
    }

    static func round3(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
}
