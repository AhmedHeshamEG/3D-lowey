import Foundation
@testable import HmmBridge
import XCTest

final class BridgeTests: XCTestCase {
    private func router(_ authority: PairingAuthority) -> BridgeRouter {
        BridgeRouter(authority: authority, routes: [
            BridgeRoute("GET", "/v1/scene") { _, client in .json(["scene": "Desk", "client": client.name]) },
            BridgeRoute("POST", "/v1/files/*") { request, _ in .json(["path": request.path]) }
        ], hello: { BridgeHello(app: "lowey", appVersion: "2.0.0", device: "iPad", pairing: false) })
    }

    private func pairRequest(_ code: String) -> HTTPRequest {
        HTTPRequest(method: "POST", path: "/v1/pair", body: Data(#"{"code":"\#(code)","client":"MacBook"}"#.utf8))
    }

    private func token(from response: HTTPResponse) throws -> String {
        let json = try JSONDecoder().decode([String: String].self, from: response.body)
        return try XCTUnwrap(json["token"])
    }

    // MARK: Refusals

    func testUnpairedRequestsAreRefused() async {
        let router = router(PairingAuthority(store: InMemoryClientStore()))
        let response = await router.handle(HTTPRequest(method: "GET", path: "/v1/scene"), from: "192.168.1.5")
        XCTAssertEqual(response.status, 401)
        let wrong = await router.handle(HTTPRequest(method: "GET", path: "/v1/scene", headers: ["authorization": "Bearer nope"]),
                                        from: "192.168.1.5")
        XCTAssertEqual(wrong.status, 401)
        let viaQuery = await router.handle(HTTPRequest(method: "GET", path: "/v1/scene", query: ["token": "nope"]), from: "10.0.0.2")
        XCTAssertEqual(viaQuery.status, 401, "tokens in URLs are never accepted")
    }

    func testInternetAddressesAreRefused() async {
        let router = router(PairingAuthority(store: InMemoryClientStore()))
        let response = await router.handle(HTTPRequest(method: "GET", path: "/v1/hello"), from: "8.8.8.8")
        XCTAssertEqual(response.status, 403)
    }

    func testNoPairingWithoutACodeOnScreen() async {
        let router = router(PairingAuthority(store: InMemoryClientStore()))
        let response = await router.handle(pairRequest("000000"), from: "192.168.1.5")
        XCTAssertEqual(response.status, 409, "there is no permanent code: pairing needs the device to show one")
    }

    // MARK: Pairing

    func testPairingIsSingleUseAndGrantsAccess() async throws {
        let authority = PairingAuthority(store: InMemoryClientStore())
        let router = router(authority)
        let code = authority.startPairing()
        XCTAssertEqual(code.digits.count, 6)
        let paired = await router.handle(pairRequest(code.digits), from: "192.168.1.5")
        XCTAssertEqual(paired.status, 200)
        let token = try token(from: paired)
        XCTAssertEqual(token.count, 64)
        let again = await router.handle(pairRequest(code.digits), from: "192.168.1.6")
        XCTAssertEqual(again.status, 409, "the code works once")
        let scene = await router.handle(HTTPRequest(method: "GET", path: "/v1/scene", headers: ["authorization": "Bearer \(token)"]),
                                        from: "192.168.1.5")
        XCTAssertEqual(scene.status, 200)
        XCTAssertTrue(String(decoding: scene.body, as: UTF8.self).contains("MacBook"))
        let files = await router.handle(HTTPRequest(method: "POST", path: "/v1/files/a.glb", headers: ["authorization": "Bearer \(token)"]),
                                        from: "192.168.1.5")
        XCTAssertEqual(files.status, 200)
        let missing = await router.handle(HTTPRequest(method: "GET", path: "/v1/none", headers: ["authorization": "Bearer \(token)"]),
                                          from: "192.168.1.5")
        XCTAssertEqual(missing.status, 404)
    }

    func testWrongCodesBurnTheCode() {
        let authority = PairingAuthority(store: InMemoryClientStore())
        let code = authority.startPairing()
        let wrong = code.digits == "111111" ? "222222" : "111111"
        for attempt in 1 ..< PairingAuthority.maxAttempts {
            XCTAssertEqual(authority.redeem(code: wrong, clientName: "x"), .failure(.wrongCode(attemptsLeft: PairingAuthority.maxAttempts - attempt)))
        }
        XCTAssertEqual(authority.redeem(code: wrong, clientName: "x"), .failure(.tooManyAttempts))
        XCTAssertEqual(authority.redeem(code: code.digits, clientName: "x"), .failure(.notPairing), "even the right code is dead now")
    }

    func testCodesExpire() {
        let authority = PairingAuthority(store: InMemoryClientStore())
        let now = Date()
        let code = authority.startPairing(now: now)
        XCTAssertNotNil(authority.currentCode(now: now))
        let later = now.addingTimeInterval(PairingAuthority.codeLifetime + 1)
        XCTAssertNil(authority.currentCode(now: later))
        XCTAssertEqual(authority.redeem(code: code.digits, clientName: "x", now: later), .failure(.expired))
    }

    func testCancelAndRevoke() throws {
        let store = InMemoryClientStore()
        let authority = PairingAuthority(store: store)
        authority.startPairing()
        authority.cancelPairing()
        XCTAssertNil(authority.currentCode())
        let code = authority.startPairing()
        let client = try authority.redeem(code: code.digits, clientName: "  ").get()
        XCTAssertEqual(client.name, "A laptop")
        XCTAssertEqual(store.load().count, 1, "paired clients are saved at once")
        XCTAssertNotNil(authority.authorize(token: client.token))
        authority.revoke(client.id)
        XCTAssertNil(authority.authorize(token: client.token))
        XCTAssertTrue(store.load().isEmpty)
        let second = try authority.redeem(code: authority.startPairing().digits, clientName: "b").get()
        authority.revokeAll()
        XCTAssertNil(authority.authorize(token: second.token))
        XCTAssertNil(authority.authorize(token: nil))
    }

    func testTokensSurviveARestartThroughTheStore() throws {
        let store = InMemoryClientStore()
        let first = PairingAuthority(store: store)
        let client = try first.redeem(code: first.startPairing().digits, clientName: "Mac").get()
        let restarted = PairingAuthority(store: store)
        XCTAssertEqual(restarted.authorize(token: client.token)?.name, "Mac")
    }

    func testHelloSaysWhetherPairingIsOpen() async throws {
        let authority = PairingAuthority(store: InMemoryClientStore())
        let router = router(authority)
        let hello = HTTPRequest(method: "GET", path: "/v1/hello")
        let closed = try await JSONDecoder().decode(BridgeHello.self, from: router.handle(hello, from: "::1").body)
        XCTAssertFalse(closed.pairing)
        authority.startPairing()
        let open = try await JSONDecoder().decode(BridgeHello.self, from: router.handle(hello, from: "::1").body)
        XCTAssertTrue(open.pairing)
        XCTAssertEqual(open.app, "lowey")
    }

    func testConstantTimeCompareAndCodes() {
        XCTAssertTrue(PairingAuthority.constantTimeEqual("123456", "123456"))
        XCTAssertFalse(PairingAuthority.constantTimeEqual("123456", "123457"))
        XCTAssertFalse(PairingAuthority.constantTimeEqual("12345", "123456"))
        let codes = Set((0 ..< 50).map { _ in PairingAuthority.makeCode() })
        XCTAssertGreaterThan(codes.count, 40, "codes are random")
        XCTAssertTrue(codes.allSatisfy { $0.count == 6 && $0.allSatisfy(\.isNumber) })
    }

    // MARK: HTTP

    func testParserAndSerializer() {
        let raw = Data("POST /v1/pair?x=a%20b&y=1+2 HTTP/1.1\r\nContent-Length: 2\r\nAuthorization: Bearer abc\r\n\r\n{}".utf8)
        guard case let .request(request) = HTTPParser.parse(raw) else { return XCTFail("not parsed") }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.query["x"], "a b")
        XCTAssertEqual(request.query["y"], "1 2")
        XCTAssertEqual(request.bearerToken, "abc")
        XCTAssertEqual(HTTPParser.parse(Data("GET / HTTP/1.1\r\nContent-Length: 5\r\n\r\nab".utf8)), .incomplete)
        XCTAssertEqual(HTTPParser.parse(Data("GARBAGE\r\n\r\n".utf8)), .invalid("bad request line"))
        let wire = String(decoding: HTTPResponse.error(401, "no").serialized(), as: UTF8.self)
        XCTAssertTrue(wire.hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        XCTAssertEqual(HTTPResponse.reason(503), "Server Error")
    }

    func testNetworkPolicy() {
        for local in ["10.1.2.3", "192.168.0.10", "172.20.1.1", "127.0.0.1", "169.254.3.3", "100.64.0.1", "::1", "fe80::1%en0", "fd00::2",
                      "::ffff:192.168.1.1"] {
            XCTAssertTrue(NetworkPolicy.isLocal(local), local)
        }
        for remote in ["8.8.8.8", "172.32.0.1", "2001:4860::8888", "100.128.0.1"] {
            XCTAssertFalse(NetworkPolicy.isLocal(remote), remote)
        }
    }

    // MARK: Proposals

    func testProposalQueue() {
        var queue = ProposalQueue()
        let proposal = Proposal(title: "Build the desk", summary: "Adds 4 objects", source: "Claude")
        XCTAssertEqual(queue.submit(proposal), .ask)
        XCTAssertEqual(queue.pending.count, 1)
        XCTAssertEqual(queue.resolve(proposal.id, as: .applied)?.status, .applied)
        XCTAssertNil(queue.resolve(proposal.id, as: .applied))
        queue.autoApplyThisSession = true
        XCTAssertEqual(queue.submit(Proposal(title: "b", summary: "", source: "c")), .apply)
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertEqual(queue.recent.count, 2)
        queue.autoApplyThisSession = false
        let old = Proposal(title: "old", summary: "", source: "c", created: Date(timeIntervalSinceNow: -600))
        _ = queue.submit(old)
        XCTAssertEqual(queue.expire(olderThan: 300).map(\.id), [old.id])
        XCTAssertEqual(queue.recent.first?.status, .expired)
    }

    func testProposalDecisions() async {
        let decisions = ProposalDecisions()
        async let waited = decisions.wait(for: "a", timeout: .seconds(5))
        try? await Task.sleep(for: .milliseconds(50))
        await decisions.decide("a", .applied)
        let status = await waited
        XCTAssertEqual(status, .applied)
        await decisions.decide("b", .declined)
        let early = await decisions.wait(for: "b", timeout: .seconds(5))
        XCTAssertEqual(early, .declined)
        let expired = await decisions.wait(for: "c", timeout: .milliseconds(50))
        XCTAssertEqual(expired, .expired)
    }
}
