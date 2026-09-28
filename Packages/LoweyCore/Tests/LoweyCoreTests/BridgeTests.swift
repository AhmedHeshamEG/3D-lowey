@testable import LoweyCore
import XCTest

final class BridgeTests: XCTestCase {
    func testHTTPParsing() throws {
        let raw = "POST /v1/script?dryRun=true&name=a+b HTTP/1.1\r\nHost: ipad\r\nContent-Length: 11\r\nAuthorization: Bearer abc\r\n\r\n{\"x\": true}"
        guard case let .request(request) = HTTPParser.parse(Data(raw.utf8)) else { return XCTFail("not parsed") }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/script")
        XCTAssertEqual(request.query, ["dryRun": "true", "name": "a b"])
        XCTAssertEqual(request.headers["host"], "ipad")
        XCTAssertEqual(request.bearerToken, "abc")
        XCTAssertEqual(String(bytes: request.body, encoding: .utf8), "{\"x\": true}")
        XCTAssertEqual(HTTPParser.parse(Data(raw.dropLast(3).utf8)), .incomplete, "waits for the whole body")
        XCTAssertEqual(HTTPParser.parse(Data("GET / HTTP/1.1\r\n".utf8)), .incomplete)
        XCTAssertEqual(HTTPParser.parse(Data("NONSENSE\r\n\r\n".utf8)), .invalid("bad request line"))
        let response = String(bytes: HTTPResponse.json(["ok": true]).serialized(), encoding: .utf8)!
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(response.contains("Content-Length: 11\r\n"))
        XCTAssertTrue(response.hasSuffix("\r\n\r\n{\"ok\":true}"))
    }

    func testLocalNetworkOnly() {
        for address in ["192.168.1.20", "10.0.0.5", "172.20.1.1", "127.0.0.1", "169.254.3.4", "::1", "fe80::1%en0", "fd12::3", "::ffff:192.168.0.2"] {
            XCTAssertTrue(NetworkPolicy.isLocal(address), address)
        }
        for address in ["8.8.8.8", "172.32.0.1", "2001:4860::8888", "1.1.1.1", "::ffff:8.8.8.8"] {
            XCTAssertFalse(NetworkPolicy.isLocal(address), address)
        }
    }

    func testPairingAndRouting() async throws {
        let auth = BridgeAuth(code: "123456")
        let router = BridgeRouter(auth: auth, routes: [
            BridgeRoute("GET", "/v1/status", requiresAuth: false) { _ in .json(["app": "3D-lowey"]) },
            BridgeRoute("GET", "/v1/scene") { _ in .json(["scene": "Test"]) },
            BridgeRoute("GET", "/v1/renders/*") { request in .json(["file": String(request.path.dropFirst("/v1/renders/".count))]) }
        ])
        let status = await router.handle(HTTPRequest(method: "GET", path: "/v1/status"), from: "192.168.1.9")
        XCTAssertEqual(status.status, 200)
        let outside = await router.handle(HTTPRequest(method: "GET", path: "/v1/status"), from: "8.8.8.8")
        XCTAssertEqual(outside.status, 403)
        let locked = await router.handle(HTTPRequest(method: "GET", path: "/v1/scene"), from: "192.168.1.9")
        XCTAssertEqual(locked.status, 401)
        let wrong = await router.handle(HTTPRequest(method: "POST", path: "/v1/pair", body: Data(#"{"code": "000000"}"#.utf8)), from: "10.0.0.2")
        XCTAssertEqual(wrong.status, 401)
        let paired = await router.handle(HTTPRequest(method: "POST", path: "/v1/pair", body: Data(#"{"code": "123456"}"#.utf8)), from: "10.0.0.2")
        let token = try XCTUnwrap(try JSONDecoder().decode([String: String].self, from: paired.body)["token"])
        let scene = await router.handle(HTTPRequest(method: "GET", path: "/v1/scene", headers: ["authorization": "Bearer \(token)"]), from: "10.0.0.2")
        XCTAssertEqual(scene.status, 200)
        let file = await router.handle(HTTPRequest(method: "GET", path: "/v1/renders/a b.mp4", query: ["token": token]), from: "10.0.0.2")
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: file.body)["file"], "a b.mp4")
        let missing = await router.handle(HTTPRequest(method: "GET", path: "/v1/nope", query: ["token": token]), from: "10.0.0.2")
        XCTAssertEqual(missing.status, 404)
        // Ten wrong guesses change the code.
        for _ in 0 ..< 10 {
            _ = auth.pair(code: "999999")
        }
        XCTAssertNotEqual(auth.code, "123456")
        auth.reset()
        XCTAssertTrue(auth.pairedTokens.isEmpty)
    }

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
