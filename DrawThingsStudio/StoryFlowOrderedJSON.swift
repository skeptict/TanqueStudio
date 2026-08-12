import Foundation

// MARK: - Order-preserving JSON
//
// `JSONSerialization` throws object key order away, and `.sortedKeys` invents a new one.
// Both are wrong for this feature, in two places that matter:
//
// 1. **The files the cast editor writes back.** `bible.json` and `configs.json` are
//    hand-authored documents carrying long `_schema` prose blocks. Re-emitting them with
//    sorted keys scrambles a file a human reads, and re-emitting them without the unknown
//    blocks loses the documentation entirely. Neither is acceptable for a file that is the
//    project's source of truth.
//
// 2. **The item values the emitter produces.** An object-valued StoryFlow item's `value` is
//    a JSON *string*, so `{"wild":"loop","cards":[…]}` and `{"cards":[…],"wild":"loop"}` are
//    different strings even though they parse to the same object. `build_project.py` emits
//    Python dict insertion order; matching it is what lets the pinning test compare the two
//    emitters on the exact bytes rather than on a weaker structural equivalence.
//
// So: a small recursive-descent parser and serializer over a value type that keeps members
// in the order it found (or was given) them.
//
// **Numbers keep their source literal.** `2.6` re-emits as `2.6` and `1024` as `1024`,
// which is what `json.dumps` does with the values it read. Round-tripping through `Double`
// and reformatting would turn `1` into `1.0` in the config shortcuts and hand Draw Things a
// float where it wants an integer enum.

struct OrderedJSONMember: Equatable {
    let key: String
    let value: OrderedJSONValue
}

indirect enum OrderedJSONValue: Equatable {
    case object([OrderedJSONMember])
    case array([OrderedJSONValue])
    case string(String)
    /// The number's canonical literal text, e.g. `"2.6"`, `"-1"`, `"1024"`.
    case number(String)
    case bool(Bool)
    case null

    static func int(_ value: Int) -> OrderedJSONValue { .number(String(value)) }

    static func double(_ value: Double) -> OrderedJSONValue {
        value.truncatingRemainder(dividingBy: 1) == 0 && abs(value) < 1e15
            ? .number(String(Int(value)))
            : .number(String(value))
    }
}

// MARK: - Accessors

extension OrderedJSONValue {

    var members: [OrderedJSONMember]? {
        guard case .object(let m) = self else { return nil }
        return m
    }

    var elements: [OrderedJSONValue]? {
        guard case .array(let a) = self else { return nil }
        return a
    }

    var stringValue: String? {
        guard case .string(let s) = self else { return nil }
        return s
    }

    var doubleValue: Double? {
        guard case .number(let literal) = self else { return nil }
        return Double(literal)
    }

    var intValue: Int? {
        guard let d = doubleValue else { return nil }
        return d.truncatingRemainder(dividingBy: 1) == 0 ? Int(d) : nil
    }

    var boolValue: Bool? {
        guard case .bool(let b) = self else { return nil }
        return b
    }

    subscript(key: String) -> OrderedJSONValue? {
        members?.first { $0.key == key }?.value
    }
}

// MARK: - Serialization

extension OrderedJSONValue {

    /// `json.dumps(…, separators=(",", ":"))` — no whitespace at all.
    var compactJSON: String {
        var out = ""
        Self.write(self, into: &out, indent: nil, depth: 0)
        return out
    }

    /// `json.dumps(…, indent=2)` — two-space indent, `": "` after each key, and `{}` / `[]`
    /// for empty containers (Python does not expand those).
    var prettyJSON: String {
        var out = ""
        Self.write(self, into: &out, indent: 2, depth: 0)
        return out
    }

    private static func write(_ value: OrderedJSONValue,
                              into out: inout String,
                              indent: Int?,
                              depth: Int) {
        switch value {
        case .null:            out += "null"
        case .bool(let b):     out += b ? "true" : "false"
        case .number(let n):   out += n
        case .string(let s):   out += quote(s)

        case .array(let items):
            guard !items.isEmpty else { out += "[]"; return }
            guard let indent else {
                out += "["
                for (i, item) in items.enumerated() {
                    if i > 0 { out += "," }
                    write(item, into: &out, indent: nil, depth: 0)
                }
                out += "]"
                return
            }
            let inner = String(repeating: " ", count: indent * (depth + 1))
            let outer = String(repeating: " ", count: indent * depth)
            out += "[\n"
            for (i, item) in items.enumerated() {
                if i > 0 { out += ",\n" }
                out += inner
                write(item, into: &out, indent: indent, depth: depth + 1)
            }
            out += "\n" + outer + "]"

        case .object(let members):
            guard !members.isEmpty else { out += "{}"; return }
            guard let indent else {
                out += "{"
                for (i, member) in members.enumerated() {
                    if i > 0 { out += "," }
                    out += quote(member.key) + ":"
                    write(member.value, into: &out, indent: nil, depth: 0)
                }
                out += "}"
                return
            }
            let inner = String(repeating: " ", count: indent * (depth + 1))
            let outer = String(repeating: " ", count: indent * depth)
            out += "{\n"
            for (i, member) in members.enumerated() {
                if i > 0 { out += ",\n" }
                out += inner + quote(member.key) + ": "
                write(member.value, into: &out, indent: indent, depth: depth + 1)
            }
            out += "\n" + outer + "}"
        }
    }

    /// Matches `json.dumps(ensure_ascii=False)`: non-ASCII stays raw, `/` is not escaped,
    /// and control characters below 0x20 take their short form where one exists.
    private static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"":     out += "\\\""
            case "\\":     out += "\\\\"
            case "\n":     out += "\\n"
            case "\r":     out += "\\r"
            case "\t":     out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

// MARK: - Parsing

enum OrderedJSONError: Error, LocalizedError {
    case syntax(String, offset: Int)

    var errorDescription: String? {
        switch self {
        case .syntax(let message, let offset): return "\(message) (at character \(offset))"
        }
    }
}

extension OrderedJSONValue {

    static func parse(_ text: String) throws -> OrderedJSONValue {
        var parser = OrderedJSONParser(Array(text.unicodeScalars))
        let value = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.isAtEnd else {
            throw OrderedJSONError.syntax("unexpected trailing content", offset: parser.index)
        }
        return value
    }

    static func parse(contentsOf url: URL) throws -> OrderedJSONValue {
        try parse(String(contentsOf: url, encoding: .utf8))
    }
}

private struct OrderedJSONParser {
    private let scalars: [Unicode.Scalar]
    private(set) var index = 0

    init(_ scalars: [Unicode.Scalar]) { self.scalars = scalars }

    var isAtEnd: Bool { index >= scalars.count }

    mutating func skipWhitespace() {
        while index < scalars.count,
              scalars[index] == " " || scalars[index] == "\n"
                || scalars[index] == "\r" || scalars[index] == "\t" {
            index += 1
        }
    }

    mutating func parseValue() throws -> OrderedJSONValue {
        skipWhitespace()
        guard index < scalars.count else {
            throw OrderedJSONError.syntax("unexpected end of input", offset: index)
        }
        switch scalars[index] {
        case "{": return try parseObject()
        case "[": return try parseArray()
        case "\"": return .string(try parseString())
        case "t": try expect("true");  return .bool(true)
        case "f": try expect("false"); return .bool(false)
        case "n": try expect("null");  return .null
        default:  return .number(try parseNumber())
        }
    }

    private mutating func expect(_ literal: String) throws {
        for scalar in literal.unicodeScalars {
            guard index < scalars.count, scalars[index] == scalar else {
                throw OrderedJSONError.syntax("expected \(literal)", offset: index)
            }
            index += 1
        }
    }

    private mutating func parseObject() throws -> OrderedJSONValue {
        index += 1  // '{'
        var members: [OrderedJSONMember] = []
        skipWhitespace()
        if index < scalars.count, scalars[index] == "}" { index += 1; return .object(members) }

        while true {
            skipWhitespace()
            let key = try parseString()
            skipWhitespace()
            guard index < scalars.count, scalars[index] == ":" else {
                throw OrderedJSONError.syntax("expected ':' after object key", offset: index)
            }
            index += 1
            members.append(OrderedJSONMember(key: key, value: try parseValue()))
            skipWhitespace()
            guard index < scalars.count else {
                throw OrderedJSONError.syntax("unterminated object", offset: index)
            }
            if scalars[index] == "," { index += 1; continue }
            if scalars[index] == "}" { index += 1; return .object(members) }
            throw OrderedJSONError.syntax("expected ',' or '}' in object", offset: index)
        }
    }

    private mutating func parseArray() throws -> OrderedJSONValue {
        index += 1  // '['
        var items: [OrderedJSONValue] = []
        skipWhitespace()
        if index < scalars.count, scalars[index] == "]" { index += 1; return .array(items) }

        while true {
            items.append(try parseValue())
            skipWhitespace()
            guard index < scalars.count else {
                throw OrderedJSONError.syntax("unterminated array", offset: index)
            }
            if scalars[index] == "," { index += 1; continue }
            if scalars[index] == "]" { index += 1; return .array(items) }
            throw OrderedJSONError.syntax("expected ',' or ']' in array", offset: index)
        }
    }

    private mutating func parseString() throws -> String {
        guard index < scalars.count, scalars[index] == "\"" else {
            throw OrderedJSONError.syntax("expected a string", offset: index)
        }
        index += 1
        var out = String.UnicodeScalarView()

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\"" { index += 1; return String(out) }
            if scalar != "\\" { out.append(scalar); index += 1; continue }

            index += 1
            guard index < scalars.count else {
                throw OrderedJSONError.syntax("unterminated escape", offset: index)
            }
            switch scalars[index] {
            case "\"": out.append("\""); index += 1
            case "\\": out.append("\\"); index += 1
            case "/":  out.append("/");  index += 1
            case "b":  out.append("\u{08}"); index += 1
            case "f":  out.append("\u{0C}"); index += 1
            case "n":  out.append("\n"); index += 1
            case "r":  out.append("\r"); index += 1
            case "t":  out.append("\t"); index += 1
            case "u":
                index += 1
                let first = try parseHex4()
                // A surrogate pair arrives as two \u escapes and has to be recombined;
                // Unicode.Scalar rejects a lone surrogate outright.
                if first >= 0xD800, first <= 0xDBFF,
                   index + 1 < scalars.count, scalars[index] == "\\", scalars[index + 1] == "u" {
                    index += 2
                    let second = try parseHex4()
                    let combined = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                    guard let scalar = Unicode.Scalar(combined) else {
                        throw OrderedJSONError.syntax("invalid surrogate pair", offset: index)
                    }
                    out.append(scalar)
                } else {
                    guard let scalar = Unicode.Scalar(first) else {
                        throw OrderedJSONError.syntax("invalid \\u escape", offset: index)
                    }
                    out.append(scalar)
                }
            default:
                throw OrderedJSONError.syntax("unknown escape", offset: index)
            }
        }
        throw OrderedJSONError.syntax("unterminated string", offset: index)
    }

    private mutating func parseHex4() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard index < scalars.count,
                  let digit = scalars[index].hexDigitValue else {
                throw OrderedJSONError.syntax("expected 4 hex digits", offset: index)
            }
            value = value << 4 | UInt32(digit)
            index += 1
        }
        return value
    }

    private mutating func parseNumber() throws -> String {
        let start = index
        if index < scalars.count, scalars[index] == "-" { index += 1 }
        while index < scalars.count,
              scalars[index] == "." || scalars[index] == "e" || scalars[index] == "E"
                || scalars[index] == "+" || scalars[index] == "-"
                || (scalars[index].value >= 0x30 && scalars[index].value <= 0x39) {
            index += 1
        }
        let literal = String(String.UnicodeScalarView(scalars[start..<index]))
        guard !literal.isEmpty, Double(literal) != nil else {
            throw OrderedJSONError.syntax("invalid number", offset: start)
        }
        return literal
    }
}

private extension Unicode.Scalar {
    var hexDigitValue: Int? {
        switch value {
        case 0x30...0x39: return Int(value - 0x30)
        case 0x41...0x46: return Int(value - 0x41 + 10)
        case 0x61...0x66: return Int(value - 0x61 + 10)
        default:          return nil
        }
    }
}
