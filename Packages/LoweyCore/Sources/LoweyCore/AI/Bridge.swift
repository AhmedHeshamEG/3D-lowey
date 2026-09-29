import Foundation

// The LAN Bridge: a tiny HTTP API inside the app so AI tools (lowey-mcp on the laptop), the laptop companion
// (lowey-link) and scripts can drive 3D-lowey. Off by default, pairing code, local network only. The networking
// lives in the app; parsing, routing, auth and the JSON shapes live here so they're tested.

// MARK: - HTTP

public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    public var path: String
    public var query: [String: String]
    /// Lower-cased names.
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    public var bearerToken: String? {
        guard let value = headers["authorization"], value.lowercased().hasPrefix("bearer ") else { return nil }
        return String(value.dropFirst(7)).trimmingCharacters(in: .whitespaces)
    }

    public func json<T: Decodable>(_: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: body)
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public static func json(_ value: some Encodable, status: Int = 200) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8"], body: body)
    }

    public static func error(_ status: Int, _ message: String) -> HTTPResponse {
        json(["error": message], status: status)
    }

    public static func data(_ data: Data, type: String) -> HTTPResponse {
        HTTPResponse(status: 200, headers: ["Content-Type": type], body: data)
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 408: "Request Timeout"
        case 409: "Conflict"
        case 413: "Payload Too Large"
        case 422: "Unprocessable Entity"
        case 429: "Too Many Requests"
        default: status < 500 ? "Error" : "Server Error"
        }
    }

    /// The bytes on the wire (HTTP/1.1, connection closes after the response).
    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        var all = headers
        all["Content-Length"] = String(body.count)
        all["Connection"] = "close"
        for key in all.keys.sorted() {
            head += "\(key): \(all[key] ?? "")\r\n"
        }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}

public enum HTTPParser {
    public enum Result: Equatable {
        /// Need more bytes.
        case incomplete
        case request(HTTPRequest)
        case invalid(String)
    }

    /// Largest body accepted (models and audio sent from the laptop).
    public static let maxBody = 512 * 1024 * 1024

    public static func parse(_ data: Data) -> Result {
        let separator = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: separator) else {
            return data.count > 64 * 1024 ? .invalid("headers too large") : .incomplete
        }
        guard let head = String(bytes: data[data.startIndex ..< end.lowerBound], encoding: .utf8) else { return .invalid("headers aren't text") }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count >= 2 else { return .invalid("bad request line") }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased().trimmingCharacters(in: .whitespaces)] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0, length <= maxBody else { return .invalid("body too large") }
        let bodyStart = end.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return .incomplete }
        let body = data[bodyStart ..< bodyStart + length]
        let target = String(parts[1])
        var path = target
        var query: [String: String] = [:]
        if let mark = target.firstIndex(of: "?") {
            path = String(target[..<mark])
            for pair in target[target.index(after: mark)...].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
                query[kv[0]] = kv.count > 1 ? kv[1].replacingOccurrences(of: "+", with: " ") : ""
            }
        }
        return .request(HTTPRequest(method: String(parts[0]).uppercased(), path: path.removingPercentEncoding ?? path, query: query, headers: headers,
                                    body: Data(body)))
    }
}

// MARK: - Local network only

public enum NetworkPolicy {
    /// Private, link-local and loopback addresses only (the bridge never answers the internet).
    public static func isLocal(_ address: String) -> Bool {
        var host = address.lowercased()
        if host.hasPrefix("::ffff:") { host = String(host.dropFirst(7)) }
        if let percent = host.firstIndex(of: "%") { host = String(host[..<percent]) }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4, octets.allSatisfy({ (0 ... 255).contains($0) }) {
            switch (octets[0], octets[1]) {
            case (10, _), (127, _), (192, 168), (169, 254): return true
            case (172, 16 ... 31): return true
            case (100, 64 ... 127): return true // carrier-grade NAT / hotspot
            default: return false
            }
        }
        if host == "::1" { return true }
        if host.hasPrefix("fe8") || host.hasPrefix("fe9") || host.hasPrefix("fea") || host.hasPrefix("feb") { return true }
        if host.hasPrefix("fc") || host.hasPrefix("fd") { return true }
        return false
    }
}

// MARK: - Pairing

/// A 6-digit code shown on the iPad; a client trades it for a token (kept, so pairing happens once per laptop).
/// The code is permanent by default (the same every time, "000000" until changed); `oneTime` makes a new one after
/// every pairing. Wrong guesses are limited: ten in a row pause pairing for a minute (a one-time code changes instead).
public final class BridgeAuth: @unchecked Sendable {
    public static let defaultCode = "000000"
    private let lock = NSLock()
    public private(set) var code: String
    /// A new code after each successful pairing.
    public private(set) var oneTime: Bool
    private var tokens: Set<String>
    private var failures = 0
    private var lockedUntil: Date?
    /// Called after a device paired (to save the tokens right away).
    public var onPaired: (@Sendable () -> Void)?

    public init(code: String = BridgeAuth.defaultCode, oneTime: Bool = false, tokens: Set<String> = []) {
        self.code = Self.isValid(code) ? code : Self.defaultCode
        self.oneTime = oneTime
        self.tokens = tokens
    }

    public static func makeCode() -> String {
        String(format: "%06d", Int.random(in: 0 ... 999_999))
    }

    /// Six digits.
    public static func isValid(_ code: String) -> Bool {
        code.count == 6 && code.allSatisfy { $0.isASCII && $0.isNumber }
    }

    public var pairedTokens: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return tokens
    }

    /// Sets the permanent code (six digits); false if it isn't one.
    @discardableResult
    public func setCode(_ newCode: String) -> Bool {
        let trimmed = newCode.trimmingCharacters(in: .whitespaces)
        guard Self.isValid(trimmed) else { return false }
        lock.lock()
        defer { lock.unlock() }
        code = trimmed
        failures = 0
        lockedUntil = nil
        return true
    }

    /// One-time codes: a fresh random code now and after every pairing. Permanent: back to `permanentCode`.
    public func setOneTime(_ on: Bool, permanentCode: String = BridgeAuth.defaultCode) {
        lock.lock()
        oneTime = on
        code = on ? Self.makeCode() : (Self.isValid(permanentCode) ? permanentCode : Self.defaultCode)
        failures = 0
        lockedUntil = nil
        lock.unlock()
    }

    /// A token for the right code; nil otherwise.
    public func pair(code attempt: String, now: Date = Date()) -> String? {
        lock.lock()
        if let lockedUntil, now < lockedUntil {
            lock.unlock()
            return nil
        }
        guard attempt.trimmingCharacters(in: .whitespaces) == code else {
            failures += 1
            if failures >= 10 {
                failures = 0
                if oneTime { code = Self.makeCode() } else { lockedUntil = now.addingTimeInterval(60) }
            }
            lock.unlock()
            return nil
        }
        failures = 0
        lockedUntil = nil
        let token = UUID().uuidString.lowercased() + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        tokens.insert(token)
        if oneTime { code = Self.makeCode() }
        let paired = onPaired
        lock.unlock()
        paired?()
        return token
    }

    public func isAuthorized(_ request: HTTPRequest) -> Bool {
        guard let token = request.bearerToken ?? request.query["token"] else { return false }
        lock.lock()
        defer { lock.unlock() }
        return tokens.contains(token)
    }

    /// Forget every paired device (a one-time code also changes).
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        tokens = []
        if oneTime { code = Self.makeCode() }
    }
}

// MARK: - Routing

public struct BridgeRoute: Sendable {
    public var method: String
    public var path: String
    public var requiresAuth: Bool
    public var handler: @Sendable (HTTPRequest) async -> HTTPResponse

    public init(_ method: String, _ path: String, requiresAuth: Bool = true, handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
        self.method = method
        self.path = path
        self.requiresAuth = requiresAuth
        self.handler = handler
    }

    /// Exact match, or a prefix match for routes ending in "/*".
    func matches(_ request: HTTPRequest) -> Bool {
        guard request.method == method else { return false }
        if path.hasSuffix("/*") { return request.path.hasPrefix(String(path.dropLast(1))) }
        return request.path == path
    }
}

public struct BridgeRouter: Sendable {
    public var auth: BridgeAuth
    public var routes: [BridgeRoute]

    public init(auth: BridgeAuth, routes: [BridgeRoute]) {
        self.auth = auth
        self.routes = routes
    }

    public func handle(_ request: HTTPRequest, from address: String) async -> HTTPResponse {
        guard NetworkPolicy.isLocal(address) else { return .error(403, "The 3D-lowey bridge only answers devices on your local network") }
        if request.method == "POST", request.path == "/v1/pair" {
            struct Pairing: Decodable { var code: String }
            guard let pairing = try? request.json(Pairing.self) else { return .error(400, "Send {\"code\": \"123456\"} (the code shown on the iPad)") }
            guard let token = auth.pair(code: pairing.code) else { return .error(401, "Wrong code — check the Bridge panel on the iPad") }
            return .json(["token": token])
        }
        guard let route = routes.first(where: { $0.matches(request) }) else {
            let known = routes.map { "\($0.method) \($0.path)" }.joined(separator: ", ")
            return .error(404, "No such endpoint. Known: \(known)")
        }
        if route.requiresAuth, !auth.isAuthorized(request) {
            return .error(401, "Pair first: POST /v1/pair {\"code\": …} and send the token as “Authorization: Bearer …”")
        }
        return await route.handler(request)
    }
}

// MARK: - What the AI sees (compact, token-efficient)

public struct SceneSummary: Codable, Hashable, Sendable {
    public struct Item: Codable, Hashable, Sendable {
        public var name: String
        public var kind: String
        public var at: [Double]
        public var size: [Double]?
        public var parent: String?
        public var animated: Bool?
    }

    public struct Camera: Codable, Hashable, Sendable {
        public var name: String
        public var at: [Double]
        public var looking: [Double]
        public var focalLength: Double
    }

    public var scene: String
    public var seconds: Double
    public var fps: Int
    public var mood: String?
    public var post: Bool
    public var objects: [Item]
    public var cameras: [Camera]
    public var cuts: [String]
    public var markers: [String]
    public var effects: [String]
    public var transcript: String?

    static func r(_ value: Double) -> Double { (value * 100).rounded() / 100 }
    static func r(_ vector: Vec3) -> [Double] { [r(vector.x), r(vector.y), r(vector.z)] }

    /// Top-level objects and their direct children (a scene of 300 objects stays readable). `bounds` measures them.
    public init(_ document: Document, bounds: SceneBounds = SceneBounds(), depth: Int = 2) {
        let scene = document.scene
        let timeline = scene.timeline
        self.scene = scene.name
        seconds = timeline.duration
        fps = timeline.fps
        mood = document.effectiveLook.lightingPreset?.rawValue
        post = !document.effectiveLook.post.isNeutral
        let animated = timeline.animatedObjects
        var items: [Item] = []
        func visit(_ id: ObjectID, level: Int) {
            guard let object = scene.objects[id], level <= depth else { return }
            if object.kind != .camera {
                let box = bounds.worldBounds(of: id, in: scene)
                items.append(Item(
                    name: object.name, kind: Self.kind(object.kind), at: Self.r(scene.worldTransform(of: id).position),
                    size: box.map { Self.r($0.size) }, parent: object.parent.flatMap { scene.objects[$0]?.name },
                    animated: animated.contains(id) ? true : nil
                ))
            }
            // Characters and prefabs are summarised as one thing.
            guard object[.rigStandard] == nil else { return }
            for child in object.children {
                visit(child, level: level + 1)
            }
        }
        for root in scene.roots {
            visit(root, level: 1)
        }
        objects = items
        cameras = scene.cameras.compactMap { id in
            guard let object = scene.objects[id] else { return nil }
            let world = scene.worldTransform(of: id)
            return Camera(name: object.name, at: Self.r(world.position), looking: Self.r(world.rotation.act(Vec3(0, 0, -1))),
                          focalLength: Self.r(CameraLens(object).focalLength))
        }
        cuts = timeline.cuts.map { "\(Self.r($0.time))s → \(scene.objects[$0.camera]?.name ?? "?")\($0.transition.map { " (\($0.kind.rawValue))" } ?? "")" }
        markers = timeline.markers.map { "\(Self.r($0.time))s \($0.name)" }
        effects = timeline.effects.map { "\(Self.r($0.start))s \($0.kind.rawValue)" }
        let words = timeline.words
        transcript = words.isEmpty ? nil : words.map(\.text).joined(separator: " ")
    }

    static func kind(_ kind: ObjectKind) -> String {
        switch kind {
        case let .primitive(shape): shape.rawValue
        case let .light(type): "\(type.rawValue) light"
        case let .overlay(recipe): "overlay:\(recipe.shape.rawValue)"
        case let .particles(recipe): "particles:\(recipe.preset.rawValue)"
        case let .text(recipe): "text:\(recipe.text)"
        default: kind.typeName
        }
    }
}

/// Spoken words with their times (for "sync to the voiceover").
public struct TranscriptSummary: Codable, Hashable, Sendable {
    public struct Word: Codable, Hashable, Sendable {
        public var i: Int
        public var w: String
        public var t: Double
        public var e: Double
    }

    public var language: String?
    public var words: [Word]

    public init(_ timeline: Timeline) {
        language = timeline.transcripts.first?.language
        words = timeline.words.enumerated().map { index, word in
            Word(i: index, w: word.text, t: SceneSummary.r(word.start), e: SceneSummary.r(word.end))
        }
    }
}

/// Library items for the AI (search results).
public struct AssetSummary: Codable, Hashable, Sendable {
    public var name: String
    public var kind: String
    public var tags: [String]
    public var rig: String?
    public var clips: [String]?
    public var size: [Double]?

    public static func search(_ query: String, in manifest: LibraryManifest, limit: Int = 40) -> [AssetSummary] {
        let items = query.isEmpty ? manifest.assets.map(LibraryItem.asset) + manifest.prefabs.map(LibraryItem.prefab)
            : LibrarySearch.search(query, in: manifest)
        return items.prefix(limit).compactMap { item in
            switch item {
            case let .asset(asset):
                AssetSummary(name: asset.name, kind: "model", tags: asset.tags, rig: asset.rig.isRigged ? asset.rig.rawValue : nil,
                             clips: asset.clips.isEmpty ? nil : asset.clips, size: asset.bounds.map { SceneSummary.r($0.size) })
            case let .prefab(prefab):
                AssetSummary(name: prefab.name, kind: "prefab", tags: prefab.tags, rig: nil, clips: nil, size: nil)
            default:
                nil
            }
        }
    }
}
