import Foundation

// MARK: - StoryFlowCastValidator
//
// The Swift port of `verify_project.py`, surfaced in the UI instead of on a terminal.
//
// **Every check here exists because its failure mode is silent.** None of them raise in Draw
// Things. They produce a set of finished, plausible-looking renders that are wrong:
//
//   wildcard not in "loop" mode  → phase B pairs each character with somebody else's anchor
//   unequal card counts          → the same, by a different route: the lists fall out of step
//   zero quoted spans            → framesDialog counts no words and EVERY clip is exactly
//                                  `padding` frames long, and the run looks completely normal
//   padding not a multiple of 8  → numFrames is not 8k+1, which LTX will not accept cleanly
//   mismatched size aspects      → loopLoad does not call updateCanvasSize, so the anchor
//                                  arrives squashed rather than cropped or letterboxed
//   an unparseable object value  → the pipeline refuses the entire run (loud, but loud in
//                                  Draw Things rather than here)
//
// Checks run against the **emitted project**, not against the intent that produced it — a
// test of the parameters requested is not a test of the artifact. The handful that cannot be
// expressed that way (a `"` in a bible field, a fragment that lost its trailing space) run
// against the source so they can point at the row or field that needs fixing.
//
// The one thing this cannot check is whether the prompt is any good.

struct StoryFlowCastIssue: Identifiable, Equatable {

    enum Severity: Equatable {
        /// Would render wrong. Blocks emission.
        case fail
        /// Worth knowing before spending GPU time on it.
        case warn
    }

    /// Where in the UI the issue belongs, so a failure lands on the control that caused it.
    enum Anchor: Equatable {
        case project
        case castRow(Int)
        case fragment(String)
        case staging(String)
    }

    let id = UUID()
    let severity: Severity
    let anchor: Anchor
    let message: String

    static func == (lhs: StoryFlowCastIssue, rhs: StoryFlowCastIssue) -> Bool {
        lhs.severity == rhs.severity && lhs.anchor == rhs.anchor && lhs.message == rhs.message
    }
}

enum StoryFlowCastValidator {

    // MARK: - allowedKeys
    //
    // Transcribed from `StoryflowPipeline.js:59-113` (the 260802 drop) by way of
    // `verify_project.py`. Exactly 52 keys. `validateInstructionArray` refuses the WHOLE
    // instruction array on an unknown key or a type mismatch, so an item type that is not in
    // this table does not "mostly work" — the run never starts.
    //
    // Note what is NOT here: `frames8`. It exists in the Editor as the 25fps duration readout
    // and is rewritten to `frames` on export. Emitting it verbatim would fail preflight.

    enum PipelineType: String {
        case string, number, flag, object
    }

    static let allowedKeys: [String: PipelineType] = [
        "note": .string, "prompt": .string, "config": .object, "size": .object,
        "frames": .number, "framesDialog": .object, "faceZoom": .flag, "askZoom": .string,
        "removeBkgd": .flag, "canvasClear": .flag, "canvasSave": .string, "canvasLoad": .string,
        "moveScale": .object, "adaptSize": .object, "crop": .flag, "moodboardClear": .flag,
        "moodboardCanvas": .flag, "moodboardLoad": .flag, "moodboardAdd": .string,
        "moodboardRemove": .number, "moodboardWeights": .object, "maskClear": .flag,
        "maskLoad": .string, "maskGet": .flag, "maskBkgd": .flag, "maskFG": .flag,
        "maskBody": .flag, "maskAsk": .string, "depthExtract": .flag, "depthCanvas": .flag,
        "depthToCanvas": .flag, "inpaintTools": .object, "xlMagic": .object, "negPrompt": .string,
        "poseExtract": .flag, "poseJSON": .object, "loop": .object, "loopLoad": .string,
        "loopAddMB": .string, "loopLoadMask": .string, "loopSave": .string, "loopEnd": .flag,
        "end": .flag, "concat": .string, "approve": .flag, "wildcard": .object, "sweep": .object,
        "interrogate": .string, "enhance": .string, "sizex2": .flag, "matte": .object,
        "hrf": .object,
    ]

    /// A string that is really a number or a bool wearing quotes. `"2"` is valid JSON, exports
    /// cleanly, and is then assigned verbatim to a numeric config field — the pipeline applies
    /// a config with `Object.assign` and coerces nothing.
    private static let quotedScalar = try? NSRegularExpression(
        pattern: #"^\s*(-?\d+(\.\d+)?([eE][-+]?\d+)?|true|false|null)\s*$"#)

    private static let quotedSpan = try? NSRegularExpression(pattern: "\"([^\"]+)\"")

    // MARK: - Entry point

    /// Validate the project `cast` + `staging` would emit, plus the source-level rules that
    /// have to point at a row or a field to be actionable.
    static func validate(cast: [CastMember], staging: CastStaging) -> [StoryFlowCastIssue] {
        var issues: [StoryFlowCastIssue] = []

        issues += validateSource(cast: cast, staging: staging)
        guard !cast.isEmpty else { return issues }

        let project = StoryFlowCastEmitter.project(cast: cast, staging: staging)
        issues += validate(project: project)
        return issues
    }

    // MARK: - Source-level

    private static func validateSource(cast: [CastMember], staging: CastStaging) -> [StoryFlowCastIssue] {
        var issues: [StoryFlowCastIssue] = []

        if cast.isEmpty {
            issues.append(.init(severity: .fail, anchor: .project,
                                message: "The cast is empty. This project is built on per-character card lists."))
        }

        for (index, member) in cast.enumerated() {
            let label = member.name.isEmpty ? "Row \(index + 1)" : member.name
            for (field, value) in member.proseFields + member.spokenFields {
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(.init(severity: .fail, anchor: .castRow(index),
                                        message: "\(label): \(field) is empty."))
                }
                if value.contains("\"") {
                    issues.append(.init(
                        severity: .fail, anchor: .castRow(index),
                        message: "\(label): \(field) contains a quote character. framesDialog "
                            + "counts words inside \"…\" spans and the emitter owns those quotes, "
                            + "so this one would split a span and change the clip's length."))
                }
            }
            if member.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(severity: .warn, anchor: .castRow(index),
                                    message: "Row \(index + 1) has no name. It never reaches the "
                                        + "model, but it is how this row is identified everywhere else."))
            }
        }

        // Fragment spacing is structural: `concat` appends with no separator, so a fragment
        // that loses a space glues two words together in the prompt.
        for spec in StoryFlowFragmentSpec.all {
            let text = staging.fragmentText(spec.name)
            if text.isEmpty {
                issues.append(.init(severity: .fail, anchor: .fragment(spec.name),
                                    message: "\(spec.name) is empty."))
                continue
            }
            if let problem = spec.spacingProblem(in: text) {
                issues.append(.init(severity: .fail, anchor: .fragment(spec.name),
                                    message: "\(spec.name) \(problem) — concat appends with no separator."))
            }
            if text.contains("\"") {
                issues.append(.init(
                    severity: .fail, anchor: .fragment(spec.name),
                    message: "\(spec.name) contains a quote character. It would create a spurious "
                        + "framesDialog span and shift every clip's frame count."))
            }
        }

        if !staging.fragmentText("A_CLOSE").contains("mouth closed") {
            issues.append(.init(
                severity: .warn, anchor: .fragment("A_CLOSE"),
                message: "A_CLOSE no longer says “mouth closed”. Phase A's still is phase B's "
                    + "first frame, and LTX-2 handles dialogue badly starting mid-word."))
        }

        if staging.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .fail, anchor: .staging("project"),
                                message: "The project has no name."))
        }
        if staging.anchorFilename.isEmpty || staging.anchorsDirectory.isEmpty {
            issues.append(.init(severity: .fail, anchor: .staging("anchors"),
                                message: "The anchors folder and anchor filename are both required — "
                                    + "phase A writes to one and phase B reads back the other."))
        }
        if staging.negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .warn, anchor: .staging("negativePrompt"),
                                message: "The negative prompt is empty."))
        }
        if staging.configShortcuts.isEmpty {
            issues.append(.init(severity: .fail, anchor: .staging("configs"),
                                message: "configs.json declares no configShortcuts, so both "
                                    + "phases reference a config that does not exist."))
        }
        return issues
    }

    // MARK: - Project-level

    /// Runs against the emitted project alone, so it is also the check a project loaded from
    /// disk can be put through — nothing here needs the cast table that produced it.
    static func validate(project: StoryFlowProject) -> [StoryFlowCastIssue] {
        var issues: [StoryFlowCastIssue] = []
        var parsed: [(index: Int, type: String, value: OrderedJSONValue)] = []

        // Types and value shapes.
        for (index, item) in project.items.enumerated() {
            guard let expected = allowedKeys[item.type] else {
                issues.append(.init(severity: .fail, anchor: .project,
                                    message: "Item \(index): type '\(item.type)' is not one of the "
                                        + "52 allowedKeys — the pipeline refuses the entire "
                                        + "instruction array on an unknown key."))
                continue
            }

            switch expected {
            case .flag where item.value.boolValue != true:
                issues.append(.init(severity: .fail, anchor: .project,
                                    message: "Item \(index) (\(item.type)): a flag-typed value must "
                                        + "be literal true."))
            case .string where item.value.stringValue == nil:
                issues.append(.init(severity: .fail, anchor: .project,
                                    message: "Item \(index) (\(item.type)): must be a JSON string."))
            case .object:
                guard let raw = item.value.stringValue else {
                    issues.append(.init(severity: .fail, anchor: .project,
                                        message: "Item \(index) (\(item.type)): object-valued items "
                                            + "are stored as JSON strings in the project format."))
                    continue
                }
                // A `config` holding a `#shortcut` reference is resolved at export.
                if item.type == "config", raw.hasPrefix("#") { continue }
                guard let value = try? OrderedJSONValue.parse(raw), value.members != nil else {
                    issues.append(.init(severity: .fail, anchor: .project,
                                        message: "Item \(index) (\(item.type)): value does not parse "
                                            + "as a JSON object."))
                    continue
                }
                parsed.append((index, item.type, value))
            default:
                break
            }
        }

        issues += checkWildcards(parsed)
        issues += checkLoops(parsed, cardCount: uniformCardCount(parsed))
        issues += checkPadding(parsed)
        issues += checkSeedSweep(parsed)
        issues += checkSizes(parsed)
        issues += checkConfigShortcuts(project)
        issues += checkAssembledPrompts(project)
        return issues
    }

    // MARK: - Individual checks

    private static func uniformCardCount(_ parsed: [(index: Int, type: String, value: OrderedJSONValue)]) -> Int? {
        let counts = Set(parsed.filter { $0.type == "wildcard" }
            .compactMap { $0.value["cards"]?.elements?.count })
        return counts.count == 1 ? counts.first : nil
    }

    /// Every wildcard in `loop` mode, and every per-character card list the same length.
    private static func checkWildcards(
        _ parsed: [(index: Int, type: String, value: OrderedJSONValue)]
    ) -> [StoryFlowCastIssue] {
        var issues: [StoryFlowCastIssue] = []
        var countsByLength: [Int: [Int]] = [:]
        var sawWildcard = false

        for entry in parsed where entry.type == "wildcard" || entry.type == "sweep" {
            if entry.type == "wildcard" { sawWildcard = true }
            let mode = entry.value["wild"]?.stringValue
            if mode != "loop" {
                issues.append(.init(
                    severity: .fail, anchor: .project,
                    message: "Item \(entry.index) (\(entry.type)): wild is "
                        + "'\(mode ?? "missing")', must be 'loop'. Any other mode carries state "
                        + "or entropy and decorrelates the two phases, pairing each character "
                        + "with somebody else's anchor."))
            }
            guard let cards = entry.value["cards"]?.elements, !cards.isEmpty else {
                issues.append(.init(severity: .fail, anchor: .project,
                                    message: "Item \(entry.index) (\(entry.type)): 'cards' must be "
                                        + "a non-empty list."))
                continue
            }
            countsByLength[cards.count, default: []].append(entry.index)
        }

        if !sawWildcard {
            issues.append(.init(severity: .fail, anchor: .project,
                                message: "No wildcard items at all — this project is built on them."))
        }
        if countsByLength.count > 1 {
            let detail = countsByLength.sorted { $0.key < $1.key }
                .map { "\($0.key) cards at items \($0.value.map(String.init).joined(separator: ", "))" }
                .joined(separator: "; ")
            issues.append(.init(severity: .fail, anchor: .project,
                                message: "Card counts are not all equal, so the lists fall out of "
                                    + "lockstep — \(detail)."))
        }
        return issues
    }

    private static func checkLoops(
        _ parsed: [(index: Int, type: String, value: OrderedJSONValue)],
        cardCount: Int?
    ) -> [StoryFlowCastIssue] {
        var issues: [StoryFlowCastIssue] = []
        for entry in parsed where entry.type == "loop" {
            guard let start = entry.value["start"] else {
                issues.append(.init(severity: .fail, anchor: .project,
                                    message: "Item \(entry.index) (loop): 'start' is absent. "
                                        + "loopSave computes _loopCounter + _startCount, so an "
                                        + "undefined start writes anchor_NaN.png."))
                continue
            }
            if start.intValue != 0 {
                issues.append(.init(
                    severity: .fail, anchor: .project,
                    message: "Item \(entry.index) (loop): start must be 0. loopSave offsets by "
                        + "start and loopLoad does not, so a non-zero start makes the anchor "
                        + "pairing depend on the folder holding exactly these files."))
            }
            if let cardCount, entry.value["loop"]?.intValue != cardCount {
                issues.append(.init(severity: .fail, anchor: .project,
                                    message: "Item \(entry.index) (loop): loop count "
                                        + "\(entry.value["loop"]?.intValue.map(String.init) ?? "?") "
                                        + "does not match the \(cardCount)-card wildcards."))
            }
        }
        return issues
    }

    private static func checkPadding(
        _ parsed: [(index: Int, type: String, value: OrderedJSONValue)]
    ) -> [StoryFlowCastIssue] {
        parsed.filter { $0.type == "framesDialog" }.compactMap { entry -> StoryFlowCastIssue? in
            guard let padding = entry.value["padding"]?.intValue else {
                return StoryFlowCastIssue(
                    severity: .fail, anchor: .staging("framesDialog"),
                    message: "framesDialog padding must be an integer.")
            }
            guard padding % 8 != 0 else { return nil }
            return StoryFlowCastIssue(
                severity: .fail, anchor: .staging("framesDialog"),
                message: "framesDialog padding \(padding) is not a multiple of 8. framesDialog() "
                    + "returns 8k+1 and the executor adds padding raw, so \(padding) gives "
                    + "numFrames ≡ \((1 + padding) % 8) (mod 8). The Editor's default of 49 is one "
                    + "of the bad ones; use 48.")
        }
    }

    /// Pinned seeds exist so a rejected anchor can be regenerated identically. Two characters
    /// sharing one defeats that for both — regenerate either and you get the other's roll —
    /// and it is the obvious slip when a character is added by copying the row above.
    private static func checkSeedSweep(
        _ parsed: [(index: Int, type: String, value: OrderedJSONValue)]
    ) -> [StoryFlowCastIssue] {
        var issues: [StoryFlowCastIssue] = []
        for entry in parsed
        where entry.type == "sweep" && entry.value["paramName"]?.stringValue == "seed" {
            let cards = entry.value["cards"]?.elements ?? []
            var positions: [String: [Int]] = [:]
            for (position, card) in cards.enumerated() {
                let key = card.stringValue ?? card.compactJSON
                positions[key, default: []].append(position)
            }
            let duplicates = positions.filter { $0.value.count > 1 }
            guard !duplicates.isEmpty else { continue }
            let detail = duplicates.sorted { $0.key < $1.key }
                .map { "\($0.key) at rows \($0.value.map { String($0 + 1) }.joined(separator: ", "))" }
                .joined(separator: "; ")
            issues.append(.init(severity: .warn, anchor: .project,
                                message: "Duplicate pinned seeds — \(detail). Each character wants "
                                    + "its own, or regenerating one anchor reproduces the other's."))
        }
        return issues
    }

    /// Every `size` item must share one aspect ratio, or the anchors come in distorted.
    ///
    /// Found on a real run (2026-08-09): stills at 1024×1024 and video at 1024×576 produced
    /// clips whose anchor was vertically SQUASHED — not cropped, not letterboxed. `loopLoad`
    /// does not call `updateCanvasSize` (`:1255-1259`); `canvasLoad` does. So it drops the
    /// anchor onto whatever canvas the `size` item above the loop already set, and nothing
    /// rescales proportionally. Phase A's output IS phase B's first frame, which is what makes
    /// this a project-level invariant rather than a matter of taste.
    private static func checkSizes(
        _ parsed: [(index: Int, type: String, value: OrderedJSONValue)]
    ) -> [StoryFlowCastIssue] {
        var issues: [StoryFlowCastIssue] = []
        let sizes = parsed.filter { $0.type == "size" }.map { entry -> (Int, Int, Int) in
            (entry.index, entry.value["width"]?.intValue ?? 0, entry.value["height"]?.intValue ?? 0)
        }

        for (_, width, height) in sizes {
            for (label, value) in [("width", width), ("height", height)] where value % 32 != 0 {
                issues.append(.init(severity: .fail, anchor: .staging("sizes"),
                                    message: "Canvas \(label) \(value) is not divisible by 32."))
            }
        }

        guard let base = sizes.first else { return issues }
        for entry in sizes.dropFirst() {
            let (_, width, height) = entry
            guard base.2 != 0, height != 0 else {
                issues.append(.init(severity: .fail, anchor: .staging("sizes"),
                                    message: "Canvas height must not be zero."))
                continue
            }
            let a = Double(base.1) / Double(base.2)
            let b = Double(width) / Double(height)
            if abs(a - b) > 1e-6 {
                issues.append(.init(
                    severity: .fail, anchor: .staging("sizes"),
                    message: "The two canvases are \(base.1)×\(base.2) and \(width)×\(height) — "
                        + "different aspect ratios. The anchor is loaded onto the video canvas "
                        + "without a proportional rescale, so it arrives SQUASHED. Make both the "
                        + "same shape."))
            } else if (base.1, base.2) != (width, height) {
                issues.append(.init(
                    severity: .warn, anchor: .staging("sizes"),
                    message: "\(base.1)×\(base.2) and \(width)×\(height): same aspect, different "
                        + "pixels. Untested — loopLoad does not rescale, so prefer identical "
                        + "dimensions."))
            }
        }
        return issues
    }

    private static func checkConfigShortcuts(_ project: StoryFlowProject) -> [StoryFlowCastIssue] {
        var issues: [StoryFlowCastIssue] = []
        for (index, item) in project.items.enumerated() where item.type == "config" {
            guard let reference = item.value.stringValue, reference.hasPrefix("#") else { continue }
            guard let json = project.configShortcuts[reference], !json.isEmpty else {
                issues.append(.init(severity: .fail, anchor: .staging("configs"),
                                    message: "Item \(index) (config) references '\(reference)', "
                                        + "which is not in configShortcuts."))
                continue
            }
            guard let value = try? OrderedJSONValue.parse(json), let members = value.members else {
                issues.append(.init(severity: .fail, anchor: .staging("configs"),
                                    message: "configShortcuts['\(reference)'] does not parse as a "
                                        + "JSON object."))
                continue
            }
            // A freshly created project carries placeholder configs, and a placeholder renders
            // nothing. Blocking emission is right: the emitted file's whole purpose is to be
            // handed to Draw Things, and one naming a model that does not exist fails there
            // rather than here.
            if let model = value["model"]?.stringValue, model.hasPrefix("TODO") || model.isEmpty {
                issues.append(.init(
                    severity: .fail, anchor: .staging("configs"),
                    message: "\(reference) has no config assigned yet. Assign a saved config in "
                        + "the Config shortcuts section — it is read off a real Draw Things "
                        + "render, so there is nothing sensible to default it to."))
                continue
            }

            for member in members {
                guard let text = member.value.stringValue, isQuotedScalar(text) else { continue }
                issues.append(.init(
                    severity: .fail, anchor: .staging("configs"),
                    message: "\(reference).\(member.key) is the STRING '\(text)', not the value "
                        + "\(text.trimmingCharacters(in: .whitespaces)). Draw Things applies the "
                        + "config with Object.assign and coerces nothing, so a quoted number is "
                        + "handed over as text. Drop the quotes."))
            }
        }
        return issues
    }

    private static func isQuotedScalar(_ text: String) -> Bool {
        guard let quotedScalar else { return false }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return quotedScalar.firstMatch(in: text, range: range) != nil
    }

    // MARK: - Loop-block simulation
    //
    // The part that catches the silent frame-count failure. Rebuilding the accumulated
    // `concat` for each pass is the only way to see what `framesDialog` will actually count:
    // the quotes live inside wildcard cards, the spans are paired left-to-right across the
    // whole accumulator, and a stray quote anywhere upstream re-pairs them.

    private static func checkAssembledPrompts(_ project: StoryFlowProject) -> [StoryFlowCastIssue] {
        var issues: [StoryFlowCastIssue] = []

        for block in loopBlocks(project.items) {
            guard let fdItem = project.items[block.start..<block.end]
                .first(where: { $0.type == "framesDialog" }),
                let fd = fdItem.value.stringValue.flatMap({ try? OrderedJSONValue.parse($0) })
            else { continue }

            let wps = fd["wps"]?.doubleValue ?? 2.4
            let padding = fd["padding"]?.intValue ?? 49

            for pass in 0..<block.repeats {
                let concat = simulate(project.items, block: block, counter: pass)
                let spans = quotedSpans(in: concat)
                guard !spans.isEmpty else {
                    issues.append(.init(
                        severity: .fail, anchor: .castRow(pass),
                        message: "Pass \(pass + 1): the assembled prompt has ZERO quoted spans. "
                            + "framesDialog would count no words and this clip would render at "
                            + "exactly \(padding) frames — the failure that looks like a working run."))
                    continue
                }
                let words = spans.reduce(0) { $0 + max(1, StoryFlowFrameBudget.wordCount($1)) }
                let readout = StoryFlowFrameBudget.readout(words: words, wps: wps, padding: padding)
                if readout.diverges {
                    issues.append(.init(
                        severity: .warn, anchor: .castRow(pass),
                        message: "Pass \(pass + 1): \(words) spoken words put the two engines out "
                            + "of step — Tanque Studio renders \(readout.tanqueStudioFrames) frames "
                            + "and Draw Things renders \(readout.drawThingsFrames). Tanque Studio "
                            + "caps the spoken count at "
                            + "\(StoryFlowFrameBudget.spokenFrameCap) before padding is added and "
                            + "StoryflowPipeline.js has no cap at all. Trim this character, or "
                            + "accept two different clip lengths."))
                }
            }
        }
        return issues
    }

    struct LoopBlock {
        let start: Int
        let end: Int
        let repeats: Int
    }

    /// Top-level `loop`…`loopEnd` pairs. Sequential blocks are the design; nested ones are not
    /// possible in this format at all — the pipeline has a single `_loopMarker`, and `loop`
    /// only initialises when it is -1.
    static func loopBlocks(_ items: [StoryFlowItem]) -> [LoopBlock] {
        var blocks: [LoopBlock] = []
        var open: (index: Int, repeats: Int)?

        for (index, item) in items.enumerated() {
            if item.type == "loop", open == nil {
                let repeats = item.value.stringValue
                    .flatMap { try? OrderedJSONValue.parse($0) }?["loop"]?.intValue ?? 1
                open = (index, repeats)
            } else if item.type == "loopEnd", let current = open {
                blocks.append(LoopBlock(start: current.index, end: index, repeats: current.repeats))
                open = nil
            }
        }
        return blocks
    }

    /// Rebuild the accumulated `concat` for one pass of one loop block, mirroring the
    /// executor: `concat` grows on concat/wildcard, and `prompt` fires the render and clears it
    /// (`:959-969`). Card selection is `originalCards[counter % len]`, which is exactly what
    /// `wild: "loop"` does.
    static func simulate(_ items: [StoryFlowItem], block: LoopBlock, counter: Int) -> String {
        var concat = ""
        for item in items[block.start..<block.end] {
            switch item.type {
            case "concat":
                concat += item.value.stringValue ?? ""
            case "wildcard":
                guard let cards = item.value.stringValue
                    .flatMap({ try? OrderedJSONValue.parse($0) })?["cards"]?.elements,
                    !cards.isEmpty else { continue }
                concat += cards[counter % cards.count].stringValue ?? ""
            case "prompt":
                concat += item.value.stringValue ?? ""
                return concat  // the render fires here; everything after is the next pass
            default:
                continue
            }
        }
        return concat
    }

    static func quotedSpans(in text: String) -> [String] {
        guard let quotedSpan else { return [] }
        let ns = text as NSString
        return quotedSpan.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .filter { $0.numberOfRanges > 1 }
            .map { ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

// MARK: - Summary

extension Array where Element == StoryFlowCastIssue {
    var failures: [StoryFlowCastIssue] { filter { $0.severity == .fail } }
    var warnings: [StoryFlowCastIssue] { filter { $0.severity == .warn } }
    var hasFailures: Bool { contains { $0.severity == .fail } }
}
