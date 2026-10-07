@testable import HmmDiagnostics
import XCTest

final class DeviceTierTests: XCTestCase {
    func testTiersFollowTheGPUAndMemory() {
        // iPad Air M3, iPad Pro M4, iPad Air M1.
        XCTAssertEqual(DeviceTier.classify(gpu: .init(appleFamily: 9), memoryGB: 8), .a)
        XCTAssertEqual(DeviceTier.classify(gpu: .init(appleFamily: 9), memoryGB: 16), .a)
        XCTAssertEqual(DeviceTier.classify(gpu: .init(appleFamily: 7), memoryGB: 8), .a)
        // iPad (A16, 6 GB), iPad mini 6 (A15, 4 GB), iPad Air 4 (A14, 4 GB).
        XCTAssertEqual(DeviceTier.classify(gpu: .init(appleFamily: 8), memoryGB: 6), .b)
        XCTAssertEqual(DeviceTier.classify(gpu: .init(appleFamily: 8), memoryGB: 4), .b)
        XCTAssertEqual(DeviceTier.classify(gpu: .init(appleFamily: 7), memoryGB: 4), .b)
        // iPad 8th/9th generation (A12/A13, 3 GB), iPad Air 3 (A12, 3 GB).
        XCTAssertEqual(DeviceTier.classify(gpu: .init(appleFamily: 6), memoryGB: 3), .c)
        XCTAssertEqual(DeviceTier.classify(gpu: .init(appleFamily: 5), memoryGB: 3), .c)
        XCTAssertTrue(DeviceTier.a < .b && DeviceTier.b < .c)
    }

    func testTheTierCanBeForcedFromTheLaunchArguments() {
        XCTAssertEqual(DeviceTier.override(arguments: ["app", "-device-tier", "b"]), .b)
        XCTAssertNil(DeviceTier.override(arguments: ["app", "-device-tier"]))
        XCTAssertNil(DeviceTier.override(arguments: ["app"]))
    }

    func testTheMeterStaysSilentWhileTheDeviceKeepsUp() {
        var meter = LoadMeter(budget: 0.008)
        feed(&meter, frame: 0.005, from: 0, seconds: 3)
        XCTAssertEqual(meter.level, .comfortable)
        XCTAssertLessThan(meter.pressure, 0.7)
    }

    func testTheChipAppearsBeforeFramesDropAndLeavesWithoutFlicker() {
        var meter = LoadMeter(budget: 0.008)
        // 0.0072 s is 90% of the budget: nothing dropped yet, but close.
        feed(&meter, frame: 0.0072, from: 0, seconds: 0.5)
        XCTAssertEqual(meter.level, .comfortable, "it waits to be sure")
        feed(&meter, frame: 0.0072, from: 0.5, seconds: 1.5)
        XCTAssertEqual(meter.level, .approaching)
        // 78%: inside the band between hide and show, it stays.
        feed(&meter, frame: 0.0062, from: 2, seconds: 3)
        XCTAssertEqual(meter.level, .approaching)
        feed(&meter, frame: 0.004, from: 5, seconds: 4)
        XCTAssertEqual(meter.level, .comfortable)
    }

    func testAHeavySceneWarnsEvenBeforeAFrameIsSlow() {
        var meter = LoadMeter(budget: 0.008)
        feed(&meter, frame: 0.004, from: 0, seconds: 1)
        meter.setSceneCost(1.3, at: 1)
        feed(&meter, frame: 0.004, from: 1, seconds: 1.5)
        XCTAssertEqual(meter.level, .over)
        meter.reset()
        XCTAssertEqual(meter.level, .comfortable)
    }

    private func feed(_ meter: inout LoadMeter, frame: Double, from start: Double, seconds: Double) {
        var time = start
        while time < start + seconds {
            meter.record(frame: frame, at: time)
            time += 1.0 / 120.0
        }
    }
}
