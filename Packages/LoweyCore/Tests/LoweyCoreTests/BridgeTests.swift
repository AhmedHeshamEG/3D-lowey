@testable import LoweyCore
import XCTest

final class BridgeTests: XCTestCase {
    func testSummariesAreCompact() throws {
        var document = makeDocument()
        var ids = IDFactory.sequential("h")
        let character = CharacterBuilder.build(CharacterRecipe(name: "Me"), ids: &ids)
        document = try assertReverts(.insert(character, parent: nil, index: nil), on: document)
        let summary = SceneSummary(document)
        XCTAssertEqual(summary.objects.map(\.name), ["A", "B", "C", "Me"], "a character is one thing, not 80 parts")
        XCTAssertEqual(summary.objects[0].at, [1, 0, 0])
        XCTAssertEqual(summary.objects[1].parent, "A")
        XCTAssertEqual(summary.objects[0].kind, "cube")
        let json = try JSONEncoder().encode(summary)
        XCTAssertLessThan(json.count, 1500)
        var timeline = Timeline()
        timeline.audio = [AudioClip(id: "vo", role: .voiceover, name: "VO", file: "vo.m4a", duration: 3)]
        timeline.transcripts = [Transcript(clip: "vo", language: "en-US", words: [TranscriptWord(text: "Enigma", start: 1.234, end: 1.8)])]
        let words = TranscriptSummary(timeline)
        XCTAssertEqual(words.words.first?.t, 1.23)
        XCTAssertEqual(words.language, "en-US")
        let manifest = LibraryManifest(assets: [LibraryAsset(id: "t", name: "Tiger", tags: ["animal"], format: .glb, file: "tiger.glb")])
        XCTAssertEqual(AssetSummary.search("tig", in: manifest).first?.name, "Tiger")
        XCTAssertEqual(AssetSummary.search("", in: manifest).count, 1)
    }
}
