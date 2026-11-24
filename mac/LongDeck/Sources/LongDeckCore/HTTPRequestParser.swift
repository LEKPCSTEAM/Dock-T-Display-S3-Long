import Foundation

public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public enum HTTPParseResult: Equatable, Sendable {
    case needMore
    case request(HTTPRequest)
    case failure(status: Int)
}

public enum HTTPRequestParser {
    public static let maxHeaderBytes = 16 * 1024
    public static let maxBodyBytes = 4 * 1024 * 1024

    private static let terminator = Data("\r\n\r\n".utf8)

    public static func parse(_ buffer: Data) -> HTTPParseResult {
        guard let end = buffer.range(of: terminator) else {
            return buffer.count > maxHeaderBytes ? .failure(status: 431) : .needMore
        }
        if end.upperBound > maxHeaderBytes { return .failure(status: 431) }
        guard let head = String(data: buffer[buffer.startIndex..<end.lowerBound], encoding: .utf8) else {
            return .failure(status: 400)
        }
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, !parts[1].isEmpty,
              parts[2] == "HTTP/1.0" || parts[2] == "HTTP/1.1" else {
            return .failure(status: 400)
        }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else {
                return .failure(status: 400)
            }
            let key = line[line.startIndex..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        let method = String(parts[0])
        if headers["transfer-encoding"] != nil { return .failure(status: 501) }
        var length = 0
        if let raw = headers["content-length"] {
            guard !raw.isEmpty, raw.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }), raw.count <= 12,
                  let n = Int(raw) else { return .failure(status: 400) }
            if n > maxBodyBytes { return .failure(status: 413) }
            length = n
        } else if method == "POST" {
            return .failure(status: 411)
        }
        let bodyStart = end.upperBound
        guard buffer.endIndex - bodyStart >= length else { return .needMore }
        let body = Data(buffer[bodyStart..<(bodyStart + length)])
        return .request(HTTPRequest(method: method, path: String(parts[1]), headers: headers, body: body))
    }
}
