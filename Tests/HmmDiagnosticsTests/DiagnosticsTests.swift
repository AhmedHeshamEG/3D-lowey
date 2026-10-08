import Foundation
@testable import HmmDiagnostics
import XCTest

final class DiagnosticsTests: XCTestCase {
    func testPercentilesAndDroppedFrames() {
        var stats = FrameStats(window: 0, budget: 1.0 / 120.0)
        for index in 0 ..< 100 {
            stats.record(duration: index < 95 ? 0.008 : 0.040, at: Double(index) / 120)
        }
        XCTAssertEqual(stats.p50, 0.008, accuracy: 1e-9)
        XCTAssertEqual(stats.p95, 0.008, accuracy: 1e-9)
        XCTAssertEqual(stats.p99, 0.040, accuracy: 1e-9)
        XCTAssertEqual(stats.dropped, 5)
        XCTAssertEqual(stats.hitches(), 5)
        XCTAssertEqual(stats.worst, 0.040)
        XCTAssertEqual(stats.fps, 120, accuracy: 0.01)
    }

    func testWindowDropsOldSamples() {
        var stats = FrameStats(window: 5)
        for second in 0 ... 10 {
            stats.record(duration: 0.01, at: Double(second))
        }
        XCTAssertEqual(stats.samples.first?.time, 5)
        stats.reset()
        XCTAssertEqual(stats.count, 0)
        XCTAssertEqual(stats.p95, 0)
        XCTAssertEqual(stats.mean, 0)
    }

    func testBenchmarkRecorderAndReport() throws {
        var recorder = BenchmarkRecorder(duration: 1, target: BenchmarkTarget(p95Milliseconds: 8.3, minimumRenderScale: 0.85))
        var done = false
        var frame = 0
        while !done {
            done = recorder.frame(duration: 0.007, at: Double(frame) / 120, renderScale: frame == 3 ? 0.9 : 1,
                                  thermal: frame == 10 ? .fair : .nominal, memoryMB: 300 + Double(frame % 7))
            frame += 1
        }
        let report = recorder.report(app: "3D-lowey", appVersion: "2.0.0-beta.1", scene: "Night Market", device: "iPad Air (M3)",
                                     system: "iPadOS 26.0", sceneFacts: ["objects": 400])
        XCTAssertTrue(report.passed)
        XCTAssertEqual(report.thermalWorst, .fair)
        XCTAssertEqual(report.renderScaleMin, 0.9)
        XCTAssertEqual(report.memoryPeakMB, 306)
        XCTAssertEqual(report.fileName, "benchmark-iPad-Air-(M3)-2.0.0-beta.1.json")
        let json = try String(decoding: report.json(), as: UTF8.self)
        XCTAssertTrue(json.contains("\"scene\" : \"Night Market\""))
        let slow = BenchmarkTarget(p95Milliseconds: 8.3, minimumRenderScale: 0.85)
        XCTAssertFalse(slow.passes(p95: 9, renderScaleMin: 1, hitches: 0))
        XCTAssertFalse(slow.passes(p95: 5, renderScaleMin: 0.7, hitches: 0))
        XCTAssertFalse(slow.passes(p95: 5, renderScaleMin: 1, hitches: 1))
    }

    func testThermalOrdering() {
        XCTAssertLessThan(ThermalLevel.fair, .serious)
        XCTAssertEqual(ThermalLevel.allCases.max(), .critical)
    }

    func testRotatingLogKeepsAFewSmallFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hmm-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = RotatingLog(folder: folder, name: "test", maxBytes: 200, keep: 3)
        for index in 0 ..< 40 {
            log.write("line \(index) with some padding to fill the file up")
        }
        log.flush()
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertLessThanOrEqual(files.count, 3)
        XCTAssertTrue(log.contents().contains("line 39"))
        XCTAssertFalse(log.contents().contains("line 0 "), "old lines rotate out")
        let export = try log.export(header: "Device: test")
        XCTAssertTrue(try String(contentsOf: export, encoding: .utf8).hasPrefix("Device: test"))
    }
}
