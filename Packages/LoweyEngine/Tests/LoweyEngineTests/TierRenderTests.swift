import CoreGraphics
import HmmDiagnostics
import LoweyCore
@testable import LoweyEngine
import XCTest

/// Every device tier previews the same features (CONTEXT §6): each Look renders at Tier B and C with only the
/// lighter shadows and render scale to tell them apart from the full-quality goldens, and exports never change.
@MainActor
final class TierRenderTests: XCTestCase {
    private static let size = (width: 640, height: 360)

    private func render(_ document: Document, quality: PreviewQuality, scale: Float = 1) async throws -> CGImage {
        let models = ModelLibrary()
        let frames = try FrameRenderer(device: RenderDevice.sharedDevice(), models: models, quality: quality)
        let builder = ShotBuilder(document: document, catalog: .empty, models: models)
        let request = builder.request(at: 0, framing: .landscape, size: CGSize(width: Self.size.width, height: Self.size.height),
                                      frameIndex: 0, renderScale: scale)
        return try await frames.image(request, width: Self.size.width, height: Self.size.height)
    }

    func testEveryTierPreviewsEveryLook() async throws {
        for preset in LookPreset.builtIns {
            let document = TestScenes.lookCheck(look: preset.id, mood: .day)
            let full = try await render(document, quality: .full)
            for tier in [DeviceTier.b, .c] {
                let quality = PreviewQuality(tier: tier)
                let preview = try await render(document, quality: quality, scale: quality.renderScale.upperBound)
                var golden = GoldenImage()
                golden.channelTolerance = 40
                let result = golden.compare(full, preview)
                XCTAssertGreaterThan(GoldenImage.coverage(preview).content, 0.08, "\(preset.id) at tier \(tier.rawValue): the objects are drawn")
                XCTAssertLessThan(result.differentFraction, 0.06, "\(preset.id) at tier \(tier.rawValue) looks like the full preview")
                golden.attach(preview, name: "tier-\(tier.rawValue)-\(preset.id)")
            }
        }
    }

    func testExportsIgnoreTheTier() {
        XCTAssertEqual(PreviewQuality.full.tier, .a)
        XCTAssertEqual(PreviewQuality.full.shadowMapSize, 2048)
        XCTAssertEqual(PreviewQuality.full.renderScale.upperBound, 1)
        XCTAssertLessThan(PreviewQuality(tier: .c).shadowMapSize, PreviewQuality(tier: .b).shadowMapSize)
    }

    func testTheBenchmarkPassRuleFollowsTheScreen() {
        XCTAssertEqual(MarketBenchmark.target(tier: .a, budget: 1.0 / 120.0).p95Milliseconds, 10, accuracy: 0.01)
        XCTAssertEqual(MarketBenchmark.target(tier: .a, budget: 1.0 / 60.0).p95Milliseconds, 20, accuracy: 0.01)
        XCTAssertEqual(MarketBenchmark.target(tier: .a, budget: 1.0 / 120.0).minimumRenderScale, 0.85, accuracy: 0.001)
        XCTAssertLessThan(MarketBenchmark.target(tier: .b, budget: 1.0 / 60.0).minimumRenderScale, 0.85)
    }

    func testTheDynamicScaleStaysInTheTiersRange() {
        var scale = DynamicScale(budget: 1.0 / 60.0, range: PreviewQuality(tier: .b).renderScale)
        XCTAssertEqual(scale.scale, 0.85)
        for _ in 0 ..< 40 {
            _ = scale.update(gpuTime: 0.03, thermal: .nominal)
        }
        XCTAssertEqual(scale.scale, 0.6, accuracy: 0.001)
        _ = scale.update(gpuTime: 0.001, thermal: .serious)
        XCTAssertLessThanOrEqual(scale.scale, 0.6 + 0.25 * 0.25 + 0.001)
        scale.enabled = false
        XCTAssertEqual(scale.update(gpuTime: 0.03, thermal: .nominal), 1, "Full-resolution stage means full resolution on every tier")
    }
}
