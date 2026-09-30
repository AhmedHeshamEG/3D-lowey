import Foundation

// The bridge's HTTP layer: requests, responses and a small HTTP/1.1 parser. Pure Swift, so it's tested on Linux.

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

    public static func reason(_ status: Int) -> String {
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
    public enum Result: Equatable, Sendable {
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
            let name = line[..<colon].lowercased().trimmingCharacters(in: .whitespaces)
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
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
        return .request(HTTPRequest(method: String(parts[0]).uppercased(), path: path.removingPercentEncoding ?? path, query: query,
                                    headers: headers, body: Data(body)))
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
