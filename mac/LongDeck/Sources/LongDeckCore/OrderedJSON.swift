import Foundation

public struct JSONMember: Equatable, Sendable {
    public var key: String
    public var value: JSONValue
    public init(key: String, value: JSONValue) {
        self.key = key
        self.value = value
    }
}

public indirect enum JSONValue: Equatable, Sendable {
    case null, bool(Bool), number(String), string(String), array([JSONValue]), object([JSONMember])

    public subscript(key: String) -> JSONValue? {
        guard case .object(let m) = self else { return nil }
        return m.first { $0.key == key }?.value
    }

    public func setting(_ key: String, _ value: JSONValue) -> JSONValue {
        guard case .object(var m) = self else { return self }
        if let i = m.firstIndex(where: { $0.key == key }) {
            m[i].value = value
        } else {
            m.append(JSONMember(key: key, value: value))
        }
        return .object(m)
    }

    public func removing(_ key: String) -> JSONValue {
        guard case .object(let m) = self else { return self }
        return .object(m.filter { $0.key != key })
    }
}

public struct JSONParseError: Error, Equatable, CustomStringConvertible {
    public let description: String
}

public enum JSONText {
    public static func parse(_ data: Data) throws -> JSONValue {
        var p = Parser(bytes: [UInt8](data))
        p.skipSpace()
        let v = try p.value()
        p.skipSpace()
        guard p.i == p.bytes.count else { throw p.fail("trailing data") }
        return v
    }

    public static func pretty(_ value: JSONValue) -> String {
        var out = ""
        write(value, indent: 0, into: &out)
        return out + "\n"
    }

    public static func compact(_ value: JSONValue) -> String {
        var out = ""
        switch value {
        case .null: out = "null"
        case .bool(let b): out = b ? "true" : "false"
        case .number(let n): out = n
        case .string(let s): out = quote(s)
        case .array(let a): out = "[" + a.map(compact).joined(separator: ",") + "]"
        case .object(let m): out = "{" + m.map { quote($0.key) + ":" + compact($0.value) }.joined(separator: ",") + "}"
        }
        return out
    }

    private static func write(_ value: JSONValue, indent: Int, into out: inout String) {
        let pad = String(repeating: "  ", count: indent + 1)
        let close = String(repeating: "  ", count: indent)
        switch value {
        case .array(let a) where !a.isEmpty:
            out += "[\n"
            for (i, e) in a.enumerated() {
                out += pad
                write(e, indent: indent + 1, into: &out)
                out += i == a.count - 1 ? "\n" : ",\n"
            }
            out += close + "]"
        case .object(let m) where !m.isEmpty:
            out += "{\n"
            for (i, e) in m.enumerated() {
                out += pad + quote(e.key) + ": "
                write(e.value, indent: indent + 1, into: &out)
                out += i == m.count - 1 ? "\n" : ",\n"
            }
            out += close + "}"
        default:
            out += compact(value)
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 {
                    let h = String(u.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - h.count) + h
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        return out + "\""
    }

    private struct Parser {
        let bytes: [UInt8]
        var i = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        func fail(_ m: String) -> JSONParseError { JSONParseError(description: "\(m) at offset \(i)") }

        mutating func skipSpace() {
            while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
        }

        mutating func expect(_ s: String) throws {
            for b in s.utf8 {
                guard i < bytes.count, bytes[i] == b else { throw fail("expected \(s)") }
                i += 1
            }
        }

        mutating func value() throws -> JSONValue {
            guard i < bytes.count else { throw fail("unexpected end") }
            switch bytes[i] {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            default: return try number()
        }
        }

        mutating func object() throws -> JSONValue {
            i += 1
            var members: [JSONMember] = []
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object([]) }
            while true {
                skipSpace()
                guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw fail("expected key") }
                let k = try string()
                skipSpace()
                try expect(":")
                skipSpace()
                members.append(JSONMember(key: k, value: try value()))
                skipSpace()
                guard i < bytes.count else { throw fail("unexpected end") }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(members) }
                throw fail("expected , or }")
            }
        }

        mutating func array() throws -> JSONValue {
            i += 1
            var items: [JSONValue] = []
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array([]) }
            while true {
                skipSpace()
                items.append(try value())
                skipSpace()
                guard i < bytes.count else { throw fail("unexpected end") }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
                throw fail("expected , or ]")
            }
        }

        mutating func number() throws -> JSONValue {
            let start = i
            if i < bytes.count, bytes[i] == UInt8(ascii: "-") { i += 1 }
            func digits(_ p: inout Parser) -> Int {
                let s = p.i
                while p.i < p.bytes.count, (0x30...0x39).contains(p.bytes[p.i]) { p.i += 1 }
                return p.i - s
            }
            guard digits(&self) > 0 else { throw fail("invalid value") }
            if i < bytes.count, bytes[i] == UInt8(ascii: ".") {
                i += 1
                guard digits(&self) > 0 else { throw fail("invalid number") }
            }
            if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
                i += 1
                if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
                guard digits(&self) > 0 else { throw fail("invalid number") }
            }
            return .number(String(decoding: bytes[start..<i], as: UTF8.self))
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= bytes.count,
                  let v = UInt32(String(decoding: bytes[i..<i + 4], as: UTF8.self), radix: 16) else {
                throw fail("invalid \\u escape")
            }
            i += 4
            return v
        }

        mutating func string() throws -> String {
            i += 1
            var raw: [UInt8] = []
            while true {
                guard i < bytes.count else { throw fail("unterminated string") }
                let b = bytes[i]
                i += 1
                if b == UInt8(ascii: "\"") { break }
                if b < 0x20 { throw fail("control character in string") }
                guard b == UInt8(ascii: "\\") else { raw.append(b); continue }
                guard i < bytes.count else { throw fail("unterminated string") }
                let e = bytes[i]
                i += 1
                switch e {
                case UInt8(ascii: "\""): raw.append(0x22)
                case UInt8(ascii: "\\"): raw.append(0x5C)
                case UInt8(ascii: "/"): raw.append(0x2F)
                case UInt8(ascii: "b"): raw.append(0x08)
                case UInt8(ascii: "f"): raw.append(0x0C)
                case UInt8(ascii: "n"): raw.append(0x0A)
                case UInt8(ascii: "r"): raw.append(0x0D)
                case UInt8(ascii: "t"): raw.append(0x09)
                case UInt8(ascii: "u"):
                    var cp = try hex4()
                    if (0xD800...0xDBFF).contains(cp) {
                        guard i + 1 < bytes.count, bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") else {
                            throw fail("lone surrogate")
                        }
                        i += 2
                        let lo = try hex4()
                        guard (0xDC00...0xDFFF).contains(lo) else { throw fail("lone surrogate") }
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
                    }
                    guard let u = Unicode.Scalar(cp) else { throw fail("lone surrogate") }
                    raw.append(contentsOf: Array(String(Character(u)).utf8))
                default: throw fail("invalid escape")
                }
            }
            guard let s = String(bytes: raw, encoding: .utf8) else {
                throw fail("invalid UTF-8")
            }
            return s
        }
    }
}
