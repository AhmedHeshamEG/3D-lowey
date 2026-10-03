import Foundation
@testable import LoweyCore
import XCTest

final class FoleyTests: XCTestCase {
    func testEverySoundIsShapedAndDeterministic() throws {
        for sound in Foley.allCases {
            let samples = sound.samples()
            XCTAssertEqual(samples.count, Int(sound.duration * Double(Foley.sampleRate)), sound.title)
            let peak = samples.map(abs).max() ?? 0
            XCTAssertEqual(peak, 0.89, accuracy: 0.001, "\(sound.title) is normalised")
            XCTAssertEqual(samples, sound.samples(), "\(sound.title) is the same every time")
            // It fades out instead of stopping with a click.
            let tail = samples.suffix(64).map(abs).max() ?? 1
            XCTAssertLessThan(tail, 0.2, sound.title)
            let decoded = try XCTUnwrap(WAV.read(sound.wav()))
            XCTAssertEqual(decoded.channels.count, 1)
            XCTAssertEqual(decoded.channels[0].count, samples.count)
        }
    }

    func testAWhooshPeaksWhereItLands() {
        let samples = Foley.whoosh.samples()
        let window = 2205
        var loudest = (index: 0, energy: Float(0))
        for start in stride(from: 0, to: samples.count - window, by: window) {
            let energy = samples[start ..< start + window].reduce(0) { $0 + $1 * $1 }
            if energy > loudest.energy { loudest = (start, energy) }
        }
        let peakTime = Double(loudest.index) / Double(Foley.sampleRate)
        XCTAssertEqual(peakTime, Foley.whoosh.hit, accuracy: 0.15)
        // A pop starts at full strength.
        XCTAssertGreaterThan(Foley.pop.samples().prefix(400).map(abs).max() ?? 0, 0.5)
    }
}
