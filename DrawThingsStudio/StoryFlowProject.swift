import Foundation

// MARK: - StoryFlowProject
//
// Faithful Codable mirror of the StoryFlow Editor project format produced by
// [Save Project] in CutsceneArtist's StoryFlow Editor. Encode/decode is structural
// (no translation table) so the codec is lossless for all item types — including
// types TanqueStudio cannot yet execute.

struct StoryFlowProject: Codable {
    var projectName: String
    var items: [StoryFlowItem]
    var promptTriggers: [String: String]
    var configShortcuts: [String: String]
    var poseJSONShortcuts: [String: String]
    var wildcardShortcuts: [String: String]
}

struct StoryFlowItem: Codable {
    var type: String
    var value: StoryFlowItemValue
}

/// Heterogeneous item value. In the editor format (see `readItemsFromDOM` in
/// StoryflowEditor_260723.html):
///   - flag items (`crop`, `canvasClear`, `loopEnd`, `approve`, …) → Bool `true`
///   - `frames`, `frames8`, `moodboardRemove`                      → Number
///   - everything else, INCLUDING object items whose value is
///     JSON-stringified by the editor's form builder                → String
///
/// The codec preserves the original JSON type exactly. Do NOT coerce between
/// them — re-encoding `frames` as `"1"` would produce a project the editor and
/// pipeline both mis-handle.
enum StoryFlowItemValue: Codable, Equatable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        // Order matters. Bool first: JSON `true`/`false` decode as Bool, while
        // the string `"true"` correctly falls through to String. Int before
        // Double so a whole number re-encodes as `1`, not `1.0`.
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else {
            self = .string(try c.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let b):   try c.encode(b)
        case .int(let i):    try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        }
    }

    var stringValue: String? {
        guard case .string(let s) = self else { return nil }
        return s
    }

    var boolValue: Bool? {
        guard case .bool(let b) = self else { return nil }
        return b
    }
}
