import Foundation

/// One endpoint.
public struct BridgeRoute: Sendable {
    public var method: String
    public var path: String
    public var handler: @Sendable (HTTPRequest, PairedClient) async -> HTTPResponse

    public init(_ method: String, _ path: String, handler: @escaping @Sendable (HTTPRequest, PairedClient) async -> HTTPResponse) {
        self.method = method
        self.path = path
        self.handler = handler
    }

    /// Exact match, or a prefix match for routes ending in "/*".
    public func matches(_ request: HTTPRequest) -> Bool {
        guard request.method == method else { return false }
        if path.hasSuffix("/*") { return request.path.hasPrefix(String(path.dropLast(1))) }
        return request.path == path
    }
}

/// What a device says about itself before pairing (no secrets).
public struct BridgeHello: Codable, Hashable, Sendable {
    public var app: String
    public var appVersion: String
    public var device: String
    public var bridgeVersion: Int
    public var pairing: Bool

    public init(app: String, appVersion: String, device: String, bridgeVersion: Int = 2, pairing: Bool) {
        self.app = app
        self.appVersion = appVersion
        self.device = device
        self.bridgeVersion = bridgeVersion
        self.pairing = pairing
    }
}

/// Routes requests: local network only, `/v1/hello` and `/v1/pair` open, everything else needs a paired token.
public struct BridgeRouter: Sendable {
    public var authority: PairingAuthority
    public var routes: [BridgeRoute]
    public var hello: @Sendable () -> BridgeHello

    public init(authority: PairingAuthority, routes: [BridgeRoute], hello: @escaping @Sendable () -> BridgeHello) {
        self.authority = authority
        self.routes = routes
        self.hello = hello
    }

    private struct PairRequest: Decodable {
        var code: String
        var client: String?
    }

    public func handle(_ request: HTTPRequest, from address: String) async -> HTTPResponse {
        guard NetworkPolicy.isLocal(address) else {
            return .error(403, "The bridge only answers devices on your local network.")
        }
        switch (request.method, request.path) {
        case ("GET", "/v1/hello"):
            var info = hello()
            info.pairing = authority.currentCode() != nil
            return .json(info)
        case ("POST", "/v1/pair"):
            guard let pairing = try? request.json(PairRequest.self) else {
                return .error(400, "Send {\"code\": \"123456\", \"client\": \"my laptop\"} with the code shown on the device.")
            }
            switch authority.redeem(code: pairing.code, clientName: pairing.client ?? "A laptop") {
            case let .success(client):
                return .json(["token": client.token, "client": client.id])
            case let .failure(error):
                return .error(error == .notPairing ? 409 : 401, error.description)
            }
        default:
            break
        }
        guard let client = authority.authorize(token: request.bearerToken) else {
            return .error(401, "Not paired. On the device open Bridge ▸ Pair a laptop, then POST /v1/pair with the code "
                + "and send the token as “Authorization: Bearer …”.")
        }
        guard let route = routes.first(where: { $0.matches(request) }) else {
            let known = routes.map { "\($0.method) \($0.path)" }.joined(separator: ", ")
            return .error(404, "No such endpoint. Known: \(known)")
        }
        return await route.handler(request, client)
    }
}
