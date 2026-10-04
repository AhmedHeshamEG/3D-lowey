#if canImport(Security)
    @testable import HmmBridge
    import XCTest

    final class KeychainTests: XCTestCase {
        func testClientsRoundTripThroughTheKeychain() throws {
            let store = KeychainClientStore(service: "studio.hmm.tests.\(UUID().uuidString)")
            let client = PairedClient(id: "1", name: "Mac", token: PairingAuthority.makeToken(), created: Date(timeIntervalSince1970: 1),
                                      lastSeen: Date(timeIntervalSince1970: 2))
            store.save([client])
            let loaded = store.load()
            try XCTSkipIf(loaded.isEmpty, "This test host has no Keychain access")
            XCTAssertEqual(loaded, [client])
            store.save([])
            XCTAssertEqual(store.load(), [])
        }
    }
#endif
