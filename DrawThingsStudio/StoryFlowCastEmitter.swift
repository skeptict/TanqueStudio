import Foundation

// MARK: - StoryFlowCastEmitter
//
// cast + staging → `StoryFlowProject`. The Swift half of `build_project.py`'s `build_items`
// and `build_project`, and the only thing in the app that writes an object-valued item's
// `value` string.
//
// **Why the shape is hardcoded.** This emits exactly the plan's §3 architecture — a note,
// a canvasClear, a persistent negPrompt, phase A's loop over stills, the trim-line note,
// then phase B's loop over clips. A general composer would hand the user back every silent
// failure this design removes: a wildcard in the wrong mode, card lists of unequal length,
// a `loop` without `start: 0`. Here they are structural, not checks.
//
// **Nothing concatenates strings to build JSON.** Object values go through
// `OrderedJSONValue.compactJSON`, which is escaping layer 2 of 3 — layer 1 is the literal
// `"` that `quoted(_:)` puts around spoken dialogue, layer 3 is the encode of the whole
// project. Building any of those by hand is how the innermost quotes get lost, and losing
// them means `framesDialog` counts zero spoken words and every clip renders at exactly
// `padding` frames, with nothing to report it.

enum StoryFlowCastEmitter {

    /// The two config shortcut names both phases reference. Structural, not per-project:
    /// `build_project.py` hardcodes the same two, and `configs.json` supplies their contents.
    static let stillsConfigShortcut = "#krea2_stills"
    static let videoConfigShortcut = "#ltx2_video"

    static let trimMarker = "──────── TRIM LINE ────────"

    // MARK: - Project

    static func project(cast: [CastMember], staging: CastStaging) -> StoryFlowProject {
        StoryFlowProject(
            projectName: staging.projectName,
            items: items(cast: cast, staging: staging),
            // All four shortcut maps must be present even when empty — the Editor and the
            // Swift codec both decode them as non-optional.
            promptTriggers: [:],
            configShortcuts: Dictionary(
                staging.configShortcuts.map { ($0.key, $0.value.compactJSON) },
                uniquingKeysWith: { _, latest in latest }
            ),
            poseJSONShortcuts: [:],
            wildcardShortcuts: [:]
        )
    }

    // MARK: - Items

    static func items(cast: [CastMember], staging: CastStaging) -> [StoryFlowItem] {
        let count = cast.count

        let identityCards = cast.map(\.identity)
        let wardrobeCards = cast.map(\.wardrobe)
        let voiceCards = cast.map(\.voice)
        let slateCards = cast.map { quoted($0.slate) }
        let lineCards = cast.map { quoted($0.line) }
        // Sweep cards are stored as strings in Editor-authored projects and coerced to real
        // JSON numbers on export (`StoryFlowProjectCodec`'s sweep branch). Matching that
        // convention keeps the file byte-shaped like one the Editor would have written.
        let seedCards = cast.map { String($0.seed) }

        // `start` must be present and must be 0. `loopSave` computes `_loopCounter +
        // _startCount` (`:1279`) and `loopLoad` does not (`:1258`), so a non-zero start makes
        // the pairing depend on the anchors folder holding exactly these files — and an
        // *absent* start leaves `_startCount` undefined, so every file is written as
        // `anchor_NaN.png`.
        let loopValue = OrderedJSONValue.object([
            .init(key: "loop",  value: .int(count)),
            .init(key: "start", value: .int(0)),
        ])

        func fragment(_ name: String) -> StoryFlowItem {
            .init(type: "concat", value: .string(staging.fragmentText(name)))
        }

        return [
            .init(type: "note", value: .string(setupNote(staging: staging, count: count))),
            .init(type: "canvasClear", value: .bool(true)),
            // `negPrompt` is persistent and does not render (`StoryflowPipeline.js:1000`).
            // One setting above both phases rather than one per phase.
            .init(type: "negPrompt", value: .string(staging.negativePrompt)),

            // ── PHASE A · CHARACTERS (stills) ────────────────────────────────
            .init(type: "config", value: .string(stillsConfigShortcut)),
            // `size` merges into the configuration AND calls `updateCanvasSize`; `config`
            // merges without touching the canvas. This is the item that re-frames the canvas,
            // which is why each phase carries one ABOVE its loop — `loopLoad`, unlike
            // `canvasLoad`, does not re-frame and will drop a 16:9 anchor onto a square canvas.
            sizeItem(staging.stillsSize),

            .init(type: "loop", value: .string(loopValue.compactJSON)),
            // Inside the loop, so each still starts clean rather than img2img-ing the
            // previous character.
            .init(type: "canvasClear", value: .bool(true)),
            // Pinned seeds: insurance for regenerating an anchor you already approved. Seed is
            // NOT the consistency mechanism — phase B is image-to-video, so identity arrives
            // as pixels.
            .init(type: "sweep", value: .string(OrderedJSONValue.object([
                .init(key: "paramName", value: .string("seed")),
                .init(key: "wild",      value: .string("loop")),
                .init(key: "cards",     value: .array(seedCards.map { .string($0) })),
            ]).compactJSON)),
            fragment("A_OPEN"),
            wildcardItem(identityCards),
            fragment("WEARING"),
            wildcardItem(wardrobeCards),
            fragment("A_CLOSE"),
            // `prompt` IS the render trigger: `concat += value; generate(); concat = ""`
            // (`:959`). There is no separate generate instruction in this format.
            .init(type: "prompt", value: .string("")),
            .init(type: "loopSave", value: .string(staging.anchorFilename)),
            .init(type: "loopEnd", value: .bool(true)),

            .init(type: "note", value: .string(trimNote(staging: staging, count: count))),

            // ── PHASE B · AUDITIONS (video) ──────────────────────────────────
            .init(type: "config", value: .string(videoConfigShortcut)),
            sizeItem(staging.videoSize),

            .init(type: "loop", value: .string(loopValue.compactJSON)),
            .init(type: "loopLoad", value: .string(staging.anchorsDirectory)),
            fragment("B_OPEN"),
            wildcardItem(identityCards),
            fragment("WEARING"),
            wildcardItem(wardrobeCards),
            fragment("B_SAYS"),
            wildcardItem(slateCards),
            fragment("B_BEAT"),
            wildcardItem(lineCards),
            fragment("B_IN"),
            wildcardItem(voiceCards),
            fragment("B_CLOSE"),
            .init(type: "framesDialog", value: .string(OrderedJSONValue.object([
                .init(key: "wps",      value: .double(staging.wps)),
                .init(key: "padding",  value: .int(staging.padding)),
                .init(key: "generate", value: .bool(staging.framesDialogGenerate)),
            ]).compactJSON)),
            .init(type: "prompt", value: .string("")),
            .init(type: "loopEnd", value: .bool(true)),
        ]
    }

    // MARK: - Pieces

    /// A per-character wildcard. ALWAYS `wild: "loop"`.
    ///
    /// `loop` is the only mode that is a pure function of the global counter — `once` keeps an
    /// index, `shuffle` consumes a deck, `random` reaches for entropy. The whole two-phase
    /// architecture rests on that: phase B's IDENTITY wildcard is a SECOND registry entry
    /// holding a duplicate of phase A's cards (you cannot reference one wildcard from two
    /// places), and the only thing making entry #2 return the same card at counter 3 that
    /// entry #1 returned is that both are stateless reads of the same counter.
    private static func wildcardItem(_ cards: [String]) -> StoryFlowItem {
        .init(type: "wildcard", value: .string(OrderedJSONValue.object([
            .init(key: "wild",  value: .string("loop")),
            .init(key: "cards", value: .array(cards.map { .string($0) })),
        ]).compactJSON))
    }

    private static func sizeItem(_ size: CanvasSize) -> StoryFlowItem {
        .init(type: "size", value: .string(OrderedJSONValue.object([
            .init(key: "width",  value: .int(size.width)),
            .init(key: "height", value: .int(size.height)),
        ]).compactJSON))
    }

    /// Wrap spoken text in the literal quotation marks `framesDialog` counts words inside.
    ///
    /// Its regex is `/"([^"]+)"/g` (`StoryflowPipeline.js:451`) and it pairs quotes left to
    /// right across the whole accumulated `concat`, so a `"` anywhere in a bible field or a
    /// shared fragment re-pairs the spans and changes the frame count without erroring. That
    /// is why the emitter owns these quotes and the bible is forbidden from containing any —
    /// `StoryFlowCastValidator` fails on one.
    static func quoted(_ spoken: String) -> String { "\"\(spoken)\"" }

    // MARK: - Notes

    /// The note at the top of the project — written for whoever runs it, not for us.
    static func setupNote(staging: CastStaging, count: Int) -> String {
        let name = staging.projectName.uppercased()
        let anchors = staging.anchorsDirectory
        return """
        \(name) — read this before running.

        SETUP: create the folder ~Pictures/\(anchors) before the first run. Nothing in the \
        pipeline creates directories, and loopSave is handed a full path.

        Keep that folder EMPTY except for what this project writes. loopLoad indexes the \
        directory by sorted position, so any stray image — a thumbnail, an old export — pairs \
        every anchor with the wrong character.

        RUN ORDER: phase A writes the \(count) anchors, phase B reads them back as first frames. \
        Run the whole project in one pass. In Tanque Studio it must be one pass — loop paths \
        there resolve against the run's own timestamped output folder, so anchors from an \
        earlier run are invisible to a later one.

        FIRST TIME: set both loop counts to 1 and run phase A alone. That proves the folder \
        exists and that the canvas save lands, in a fraction of the time a full run takes.

        TRIM: to keep the characters and skip the spoken scenes, delete the marked note below \
        and everything after it.
        """
    }

    // MARK: - Serialization
    //
    // The emitted files are written through `OrderedJSONValue` rather than through
    // `StoryFlowProjectCodec.save`, which sorts keys. Not cosmetics: `build_project.py` writes
    // the same two files, and matching its layout byte-for-byte means the check that matters —
    // emit from the UI, then `git diff` the project folder — comes back empty when nothing
    // changed, instead of showing a whole-file reshuffle that hides a real change inside it.
    //
    // The *model* still goes through the codec's own `StoryFlowProject`; nothing here builds an
    // item's `value` by string concatenation.

    /// The Editor project file, laid out as `json.dumps(project, indent=2)` would lay it out.
    static func projectJSON(cast: [CastMember], staging: CastStaging) -> OrderedJSONValue {
        .object([
            .init(key: "projectName", value: .string(staging.projectName)),
            .init(key: "items", value: .array(items(cast: cast, staging: staging).map { item in
                .object([
                    .init(key: "type",  value: .string(item.type)),
                    .init(key: "value", value: ordered(item.value)),
                ])
            })),
            // All four shortcut maps must be present even when empty.
            .init(key: "promptTriggers", value: .object([])),
            // configShortcuts values are JSON *strings*: `resolveConfigShortcuts` does raw text
            // substitution of `#key` into the config item's value.
            .init(key: "configShortcuts", value: .object(staging.configShortcuts.map {
                .init(key: $0.key, value: .string($0.value.compactJSON))
            })),
            .init(key: "poseJSONShortcuts", value: .object([])),
            .init(key: "wildcardShortcuts", value: .object([])),
        ])
    }

    /// The flat pipeline instruction array — the form `StoryflowPipeline.js` actually accepts.
    ///
    /// Hand it a *project* instead and preflight dies on `arr.entries is not a function`, because
    /// `validateInstructionArray` calls an Array method on an object. Emitting this beside the
    /// project means a recipient with only Draw Things never needs an exporter.
    ///
    /// The transform matches `StoryFlowProjectCodec.toPipelineArray` and the Editor's own
    /// exporter; `StoryFlowCastEmitterTests` pins it to the codec so the two cannot drift.
    static func pipelineJSON(cast: [CastMember], staging: CastStaging) -> OrderedJSONValue {
        let shortcuts = Dictionary(staging.configShortcuts.map { ($0.key, $0.value) },
                                   uniquingKeysWith: { _, latest in latest })
        var out: [OrderedJSONValue] = []

        for item in items(cast: cast, staging: staging) {
            let raw = item.value.stringValue

            switch item.type {
            case "note":
                // The Editor collapses whitespace runs to single spaces for note/interrogate/
                // enhance on export, but deliberately does NOT for prompt/negPrompt/concat,
                // which keep their newlines.
                out.append(.object([.init(key: "note",
                                          value: .string(collapsingWhitespace(raw ?? "")))]))

            case "config":
                if let raw, raw.hasPrefix("#"), let resolved = shortcuts[raw] {
                    out.append(.object([.init(key: "config", value: resolved)]))
                } else if let parsed = raw.flatMap({ try? OrderedJSONValue.parse($0) }) {
                    out.append(.object([.init(key: "config", value: parsed)]))
                } else {
                    out.append(.object([.init(key: "config", value: ordered(item.value))]))
                }

            case "sweep":
                // The form stores every sweep card as a string; the export coerces the
                // numeric-looking ones to real JSON numbers, because the pipeline does
                // `configuration[paramName] = pickedValue` with no coercion of its own.
                if var parsed = raw.flatMap({ try? OrderedJSONValue.parse($0) })?.members {
                    if let cardIndex = parsed.firstIndex(where: { $0.key == "cards" }),
                       let cards = parsed[cardIndex].value.elements {
                        parsed[cardIndex] = .init(key: "cards", value: .array(cards.map(coerceNumber)))
                    }
                    out.append(.object([.init(key: "sweep", value: .object(parsed))]))
                } else {
                    out.append(.object([.init(key: "sweep", value: ordered(item.value))]))
                }

            case _ where StoryFlowCastValidator.allowedKeys[item.type] == .object:
                let parsed = raw.flatMap { try? OrderedJSONValue.parse($0) } ?? ordered(item.value)
                out.append(.object([.init(key: item.type, value: parsed)]))

            default:
                out.append(.object([.init(key: item.type, value: ordered(item.value))]))
            }
        }

        out.append(.object([.init(key: "end", value: .bool(true))]))
        return .array(out)
    }

    private static func ordered(_ value: StoryFlowItemValue) -> OrderedJSONValue {
        switch value {
        case .string(let s): return .string(s)
        case .bool(let b):   return .bool(b)
        case .int(let i):    return .int(i)
        case .double(let d): return .double(d)
        }
    }

    private static func coerceNumber(_ card: OrderedJSONValue) -> OrderedJSONValue {
        guard let text = card.stringValue else { return card }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let number = Double(trimmed) else { return card }
        return number.truncatingRemainder(dividingBy: 1) == 0 && abs(number) < 1e15
            ? .int(Int(number))
            : .number(String(number))
    }

    private static func collapsingWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func trimNote(staging: CastStaging, count: Int) -> String {
        "\(trimMarker)  Delete this note and EVERY item below it to turn this into a "
            + "characters-only project. Everything above it stands alone: it renders \(count) "
            + "stills and saves them to ~Pictures/\(staging.anchorsDirectory). Nothing below it "
            + "is referenced from above."
    }
}

// MARK: - Frame budget

/// `framesDialog()` plus the executor's `+ padding` (`StoryflowPipeline.js:1045-1050`).
///
/// Kept apart from `StoryFlowEngine.spokenFrameCount`, which answers a different question:
/// the engine counts quoted spans in a *fully assembled* prompt and applies Tanque Studio's
/// 257-frame cap. This one works from one cast row so the table can show a live per-row
/// readout before any prompt exists, and reports the uncapped number alongside the cap so
/// the divergence is visible rather than silently applied.
enum StoryFlowFrameBudget {

    /// Tanque Studio caps `spokenFrameCount` here. `StoryflowPipeline.js` has no cap at all,
    /// so past this point the two engines silently render different lengths.
    static let tanqueStudioCap = 257

    /// Words in `slate` + `line`. These are the spoken fields, and the emitter is what puts
    /// them inside `"…"` spans — so counting them directly is the same count `framesDialog`
    /// arrives at by regex, without needing the assembled prompt.
    static func spokenWordCount(_ member: CastMember) -> Int {
        wordCount(member.slate) + wordCount(member.line)
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    static func numFrames(words: Int, wps: Double, padding: Int) -> Int {
        guard wps > 0 else { return 1 + padding }
        let raw = (Double(words) / wps) * 25.0
        return Int((raw / 8).rounded(.up)) * 8 + 1 + padding
    }

    static func numFrames(for member: CastMember, staging: CastStaging) -> Int {
        numFrames(words: spokenWordCount(member), wps: staging.wps, padding: staging.padding)
    }
}
