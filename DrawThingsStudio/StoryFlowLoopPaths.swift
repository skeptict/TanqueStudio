import Foundation

// MARK: - StoryFlowLoopPaths

/// Path arithmetic for the `loop*` instruction family.
///
/// A direct port of three functions in `misc/StoryflowPipeline_260802/StoryflowPipeline.js`:
/// `generatePath` (`:782`), `extractNumber` (`:824`) and the filter/sort half of
/// `getDirectoryByIndex` (`:841`). Kept string-only and separate from the engine so the
/// ordering is testable without a filesystem — the ordering is the part that matters, because
/// `loopSave` and `loopLoad` are designed to pair and **a different tie-break silently changes
/// which saved file comes back on which loop pass**. Nothing downstream notices; the only
/// symptom is a wrong image.
///
/// `loopAddMB` and `loopLoadMask` are not executed yet, but they call the same
/// `getDirectoryByIndex` in the pipeline (`:1263`, `:1270`) — so adding them is a switch case
/// in the engine and nothing here.
enum StoryFlowLoopPaths {

    /// The extensions `getDirectoryByIndex` accepts (`:843`). Anything else in the folder —
    /// a `.txt`, a stray `.mov` — is not a candidate and does not shift the indices.
    static let imageExtensions = ["png", "jpg", "jpeg", "webp"]

    // MARK: — generatePath

    /// `generatePath(value, i)` — split off the extension, append `_` and the index padded to
    /// three digits, reattach.
    ///
    /// Faithful to the JS in the edge cases, which is why it is not one `String` interpolation:
    /// a value with no extension gets a bare `name_007`, a value with no directory keeps none,
    /// and an index of four digits or more is **not truncated** (`padStart` only pads).
    static func indexedPath(_ value: String, index: Int) -> String {
        let dirPath: String
        let fileName: String
        if let slash = value.lastIndex(of: "/") {
            dirPath  = String(value[...slash])
            fileName = String(value[value.index(after: slash)...])
        } else {
            dirPath  = ""
            fileName = value
        }

        let baseName: String
        let ext: String
        if let dot = fileName.lastIndex(of: ".") {
            baseName = String(fileName[..<dot])
            ext      = String(fileName[fileName.index(after: dot)...])
        } else {
            baseName = fileName
            ext      = ""
        }

        let padded = paddedIndex(index)
        return ext.isEmpty ? "\(dirPath)\(baseName)_\(padded)"
                           : "\(dirPath)\(baseName)_\(padded).\(ext)"
    }

    /// `String(i).padStart(3, '0')` — pads to three, never truncates past it.
    static func paddedIndex(_ index: Int) -> String {
        let digits = String(index)
        guard digits.count < 3 else { return digits }
        return String(repeating: "0", count: 3 - digits.count) + digits
    }

    // MARK: — extractNumber

    /// `extractNumber` — the digits at the very start of a **filename**, up to the first `_`.
    ///
    /// The JS regex is `/^(\d+)_/` applied to the last path component, so `12_a.png` is 12,
    /// `12.png` is 0 (no underscore), and `anchor_003.png` is 0 (the digits are not leading).
    /// The 0 fallback is load-bearing: it is what collects every unnumbered file into one
    /// group that the alphabetical tie-break then orders.
    static func leadingNumber(inFileName name: String) -> Int {
        var digits = ""
        for character in name {
            if character.isASCII, character.isNumber {
                digits.append(character)
            } else {
                guard character == "_", !digits.isEmpty else { return 0 }
                return Int(digits) ?? 0
            }
        }
        return 0   // all digits, no underscore — no match
    }

    // MARK: — getDirectoryByIndex

    /// Filter to loadable images, then sort numerically with a case-insensitive alphabetical
    /// tie-break. `paths` may be full paths or bare filenames; entries from one directory
    /// share a prefix either way, so the tie-break sees the same order.
    static func imageEntries(from paths: [String]) -> [String] {
        let filtered = paths.filter { path in
            guard !path.isEmpty else { return false }
            // The JS excludes `.DS_Store` by name before the extension check. Redundant —
            // it has no image extension either — but ported so the intent stays visible.
            guard fileName(of: path) != ".DS_Store" else { return false }
            let lowered = path.lowercased()
            return imageExtensions.contains { lowered.hasSuffix(".\($0)") }
        }
        return filtered.sorted { lhs, rhs in
            let left  = leadingNumber(inFileName: fileName(of: lhs))
            let right = leadingNumber(inFileName: fileName(of: rhs))
            if left != right { return left < right }
            return lhs.lowercased().compare(rhs.lowercased(),
                                            options: [],
                                            range: nil,
                                            locale: .current) == .orderedAscending
        }
    }

    /// The entry `getDirectoryByIndex` would return: sorted, then indexed with a
    /// positive-wrapping modulo so an index past the file count comes back round to the start.
    /// Nil when the folder holds no loadable image, which is where the JS logs and returns
    /// `undefined`.
    static func entry(from paths: [String], at index: Int) -> String? {
        let entries = imageEntries(from: paths)
        guard !entries.isEmpty else { return nil }
        let count = entries.count
        return entries[((index % count) + count) % count]
    }

    /// Last path component, without touching the filesystem.
    static func fileName(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }
}
