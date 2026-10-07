@testable import HmmMedia
import XCTest

final class MediaTests: XCTestCase {
    func testBitrateAndValidity() {
        let hd = EncodeSettings(width: 1920, height: 1080, fps: 30, codec: .h264)
        XCTAssertEqual(hd.bitrate, Int(1920.0 * 1080 * 30 * 0.12))
        XCTAssertEqual(hd.keyframeInterval, 60)
        XCTAssertTrue(hd.isValid)
        XCTAssertFalse(EncodeSettings(width: 1919, height: 1080, fps: 30, codec: .h264).isValid)
        let best = EncodeSettings(width: 1920, height: 1080, fps: 30, codec: .hevc, quality: 1)
        XCTAssertGreaterThan(best.bitrate, EncodeSettings(width: 1920, height: 1080, fps: 30, codec: .hevc).bitrate)
        XCTAssertEqual(VideoCodecKind.hevcAlpha.fileExtension, "mov")
        XCTAssertEqual(VideoCodecKind.h264.fileExtension, "mp4")
        XCTAssertTrue(VideoCodecKind.prores4444.hasAlpha)
    }

    func testVerificationFindsEveryProblem() {
        let expected = ExportExpectation(duration: 10, frameCount: 300, width: 1920, height: 1080, audio: true, alpha: true)
        let good = MediaFacts(duration: 10.01, frameCount: 300, width: 1920, height: 1080, hasAudio: true, hasAlpha: true)
        XCTAssertEqual(ExportVerification.problems(good, expected: expected), [])
        let bad = MediaFacts(duration: 8, frameCount: 240, width: 1280, height: 720, hasAudio: false, hasAlpha: false)
        let problems = ExportVerification.problems(bad, expected: expected)
        XCTAssertEqual(problems.count, 5)
        XCTAssertTrue(problems.contains("The sound is missing."))
    }

    func testOneFrameOfSlackIsAllowed() {
        let expected = ExportExpectation(duration: 2, frameCount: 60, width: 100, height: 100, audio: false)
        let facts = MediaFacts(duration: 2.033, frameCount: 61, width: 100, height: 100, hasAudio: false)
        XCTAssertEqual(ExportVerification.problems(facts, expected: expected), [])
    }
}
