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

/// Heterogeneous item value. In the editor format:
///   - `crop`, `canvasClear`, `loopEnd` → Bool `true`
///   - everything else              → String
///
/// The codec preserves the original JSON type exactly (string stays string,
/// bool stays bool). Do NOT coerce between them.
enum StoryFlowItemValue: Codable, Equatable {
    case string(String)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        // Bool must be tried first: JSON `true`/`false` decode as Bool;
        // string `"true"` would correctly fall through to String.
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
            return
        }
        self = .string(try c.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let b):   try c.encode(b)
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
