#if canImport(Security)
    import Foundation
    import Security

    /// Paired clients in the Keychain (this device only, available after first unlock so the bridge can answer with
    /// the screen locked). One generic-password item holds the JSON list.
    public final class KeychainClientStore: PairedClientStore {
        private let service: String
        private let account = "paired-clients"

        /// `service` e.g. "studio.hmm.lowey.bridge".
        public init(service: String) {
            self.service = service
        }

        private var query: [String: Any] {
            [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        }

        public func load() -> [PairedClient] {
            var request = query
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
                  let clients = try? JSONDecoder().decode([PairedClient].self, from: data) else { return [] }
            return clients
        }

        public func save(_ clients: [PairedClient]) {
            guard let data = try? JSONEncoder().encode(clients) else { return }
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
                var add = query
                add.merge(attributes) { $1 }
                SecItemAdd(add as CFDictionary, nil)
            }
        }
    }
#endif
