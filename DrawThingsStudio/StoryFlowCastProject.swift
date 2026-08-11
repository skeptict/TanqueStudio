import Foundation

// MARK: - The cast-and-staging document
//
// The editable half of a two-phase StoryFlow project: a **cast table** and a **staging**
// panel, which together are exactly the inputs `build_project.py` reads — `bible.json` and
// `configs.json`.
//
// **What is deliberately NOT modelled here: the project file.** The whole reason the
// generator exists is that hand-editing the emitted `.json` is how the two silent failures
// get in — triple-escaped wildcard values losing their innermost quotes, and the duplicated
// IDENTITY/WARDROBE lists drifting out of lockstep between the two phases. An editor over
// the emitted file would reintroduce both. So the user edits this, and
// `StoryFlowCastEmitter` builds the project; there is no path from the UI to an item's
// `value` string.
//
// **Unknown top-level keys survive a round trip.** Both files carry long `_schema` prose
// blocks that are the documentation for anyone editing them by hand. They are parsed into
// `OrderedJSONValue` and written back verbatim, in their original position, so opening a
// project in Tanque Studio and saving it does not quietly strip the file's own manual.

// MARK: - Fragment spec

/// The eight shared prose fragments, and where each one needs its spaces.
///
/// This is the Swift half of `FRAGMENT_SPEC` in `build_project.py`, and it is deliberately
/// *structural*: which fragments exist and where their spaces go belongs to the format, while
/// the fragment text is per-project scene writing that lives in `configs.json`. `concat`
/// appends with no separator (`StoryflowPipeline.js:966`), so a fragment that loses its
/// trailing space glues two words together in the prompt with nothing to report it.
struct StoryFlowFragmentSpec: Identifiable, Equatable {
    let name: String
    /// Leading space required.
    let lead: Bool
    /// Trailing space required.
    let trail: Bool
    /// What the fragment does in the assembled prompt, shown beside its field.
    let role: String

    var id: String { name }

    static let all: [StoryFlowFragmentSpec] = [
        .init(name: "A_OPEN",  lead: false, trail: true,
              role: "Opens phase A, runs into the IDENTITY card"),
        .init(name: "WEARING", lead: false, trail: true,
              role: "Between IDENTITY and WARDROBE, both phases"),
        .init(name: "A_CLOSE", lead: false, trail: false,
              role: "Closes phase A. Keep “mouth closed” — the still is phase B's first frame"),
        .init(name: "B_OPEN",  lead: false, trail: true,
              role: "Opens phase B, runs into the IDENTITY card"),
        .init(name: "B_SAYS",  lead: false, trail: true,
              role: "Runs into the first quoted span"),
        .init(name: "B_BEAT",  lead: true,  trail: true,
              role: "Sits between the two quoted spans"),
        .init(name: "B_IN",    lead: true,  trail: true,
              role: "Runs into the VOICE card"),
        .init(name: "B_CLOSE", lead: false, trail: false,
              role: "Closes phase B. Carries the entire audio design — audio is prompt-driven"),
    ]

    static func spec(named name: String) -> StoryFlowFragmentSpec? {
        all.first { $0.name == name }
    }

    /// The spacing problem with `text`, or nil when it is correct.
    ///
    /// Surfaced live in the form rather than only at validation time: a missing space is
    /// invisible in a text field, and the prompt it produces is wrong in a way no run reports.
    func spacingProblem(in text: String) -> String? {
        if text.hasPrefix(" ") != lead {
            return lead ? "needs a leading space" : "must not start with a space"
        }
        if text.hasSuffix(" ") != trail {
            return trail ? "needs a trailing space" : "must not end with a space"
        }
        return nil
    }
}

// MARK: - Cast

/// One row of the bible. `name` never reaches the model — it labels the row.
struct CastMember: Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var identity = ""
    var wardrobe = ""
    var slate = ""
    var line = ""
    var voice = ""
    var seed = 0

    /// The bible's own field order, used when writing `bible.json` back so the file stays
    /// the readable, hand-editable document it is.
    static let fieldOrder = ["name", "identity", "wardrobe", "slate", "line", "voice", "seed"]

    /// Prose fields, which must be non-empty and quote-free.
    var proseFields: [(label: String, value: String)] {
        [("identity", identity), ("wardrobe", wardrobe), ("voice", voice)]
    }

    /// Spoken fields. `build_project.py`'s `quoted()` owns the `"` characters around these,
    /// which is why the text itself may not contain one.
    var spokenFields: [(label: String, value: String)] {
        [("slate", slate), ("line", line)]
    }
}

// MARK: - Staging

struct CanvasSize: Equatable {
    var width: Int
    var height: Int

    var aspect: Double { height == 0 ? 0 : Double(width) / Double(height) }
}

/// Everything in `configs.json` the editor owns. The two DT config blobs are held as parsed
/// `OrderedJSONValue` and never re-typed — they are read off a real render and a UI that
/// re-serialized them through `Double` would turn an integer sampler enum into `10.0`.
struct CastStaging: Equatable {
    var projectName = ""
    var outputBasename = ""
    var fixtureBasename = ""

    var fragments: [String: String] = [:]
    var negativePrompt = ""

    var stillsSize = CanvasSize(width: 1024, height: 576)
    var videoSize = CanvasSize(width: 1024, height: 576)

    var wps: Double = 2.6
    /// Multiple of 8. `framesDialog` returns `8k+1` and the executor adds padding raw
    /// (`StoryflowPipeline.js:1045`), so the Editor's own default of 49 is one of the bad
    /// ones. Nothing here snaps 48 back to 49 — that clamp is the bug, not the rule.
    var padding = 48
    /// Ships `false`: an explicit bare `prompt` follows, which keeps the render point visible
    /// in both step lists and keeps preflight's generate-detection honest.
    var framesDialogGenerate = false

    var anchorsDirectory = ""
    var anchorFilename = ""

    /// `#name` → the config object, in the order `configs.json` declares them.
    var configShortcuts: [OrderedJSONMember] = []

    func fragmentText(_ name: String) -> String { fragments[name] ?? "" }
}

// MARK: - Document

/// Both files, plus enough of their original shape to write them back unharmed.
struct StoryFlowCastDocument: Equatable {
    var cast: [CastMember] = []
    var staging = CastStaging()

    /// Top-level keys of each file in source order, so a save rebuilds the document in the
    /// order it was authored rather than in whatever order a dictionary hands back.
    var bibleKeyOrder: [String] = ["_schema", "characters"]
    var configsKeyOrder: [String] = []
    /// Top-level entries neither file's model covers — the `_schema` / `_note` prose blocks,
    /// and anything a future revision adds. Written back verbatim.
    var biblePreserved: [String: OrderedJSONValue] = [:]
    var configsPreserved: [String: OrderedJSONValue] = [:]

    static let bibleFilename = "bible.json"
    static let configsFilename = "configs.json"

    /// Keys of `configs.json` this type models. Everything else is preserved verbatim.
    static let configsOwnedKeys: Set<String> = [
        "configShortcuts", "sizes", "framesDialog", "fragments",
        "negativePrompt", "project", "anchorsDirectory", "anchorFilename",
    ]
}

// MARK: - Starting a new project

extension StoryFlowCastDocument {

    /// A complete, valid project to start from.
    ///
    /// **Seeded rather than blank, and that is the point.** The eight fragments carry the
    /// spacing the format requires — `concat` appends with no separator — so a new project
    /// opens with the one thing a user cannot reasonably be expected to get right by typing
    /// already correct. The cast rows are deliberately obvious placeholders, following the
    /// same convention as the bundled bibles: nobody should mistake them for finished copy,
    /// and prose that reads as real is worse than prose that reads as a TODO.
    ///
    /// The result validates clean apart from the config shortcuts, which cannot be invented —
    /// they are read off a real Draw Things render. `configShortcuts` are seeded from the
    /// user's own saved `#config` variables when there are any.
    static func starter(projectName: String,
                        folderName: String,
                        configShortcuts: [OrderedJSONMember] = []) -> StoryFlowCastDocument {
        var document = StoryFlowCastDocument()

        document.cast = [
            CastMember(name: "Character One",
                       identity: "TODO a one-clause description of who this is, no trailing period",
                       wardrobe: "TODO what they are wearing, reads after the WEARING fragment",
                       slate: "TODO the line where they say their name and what they are here for",
                       line: "TODO their second spoken beat",
                       voice: "TODO how they sound, not what they say",
                       seed: 100001),
            CastMember(name: "Character Two",
                       identity: "TODO a second one-clause description",
                       wardrobe: "TODO what the second character is wearing",
                       slate: "TODO the second character naming themselves",
                       line: "TODO their second spoken beat",
                       voice: "TODO how the second character sounds",
                       seed: 100002),
        ]

        document.staging.projectName = projectName
        document.staging.outputBasename = projectName
        document.staging.fixtureBasename = folderName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
        document.staging.anchorsDirectory = "\(folderName)/anchors/"
        document.staging.anchorFilename = "\(folderName)/anchors/anchor.png"

        // Spacing here is not a style choice — it is the FRAGMENT_SPEC contract, and getting it
        // wrong glues two words together in the prompt with nothing to report it.
        document.staging.fragments = [
            "A_OPEN":  "A casting-room headshot, medium shot, of ",
            "WEARING": ", wearing ",
            "A_CLOSE": ", seated against a plain wall under flat even light, facing the lens, "
                     + "mouth closed, neutral expression. Sharp focus, 50mm.",
            "B_OPEN":  "A locked-off medium shot of ",
            "B_SAYS":  ", seated in the same room. They look into the lens and say, ",
            "B_BEAT":  " After a beat they add, ",
            "B_IN":    " in ",
            "B_CLOSE": ". The camera holds perfectly still on a tripod, no reframing and no zoom. "
                     + "Faint room tone fills the space between lines. Single continuous shot, "
                     + "natural motion blur.",
        ]

        document.staging.negativePrompt =
            "blurry, low resolution, jpeg artifacts, watermark, on-screen text, subtitles, "
          + "warped face, malformed hands, extra fingers, duplicated limbs, camera shake, "
          + "handheld wobble, zoom, dolly move, rack focus, cut to another shot"

        document.staging.stillsSize = CanvasSize(width: 1024, height: 576)
        document.staging.videoSize = CanvasSize(width: 1024, height: 576)
        document.staging.wps = 2.6
        // 48, not the StoryFlow Editor's default of 49 — see CastStaging.padding.
        document.staging.padding = 48
        document.staging.framesDialogGenerate = false

        document.staging.configShortcuts = configShortcuts.isEmpty
            ? Self.placeholderConfigShortcuts
            : configShortcuts

        document.bibleKeyOrder = ["_schema", "characters"]
        document.biblePreserved["_schema"] = Self.starterBibleSchema
        document.configsKeyOrder = ["_schema", "configShortcuts", "sizes", "framesDialog",
                                    "fragments", "negativePrompt", "project",
                                    "anchorsDirectory", "anchorFilename"]
        document.configsPreserved["_schema"] = Self.starterConfigsSchema
        return document
    }

    /// The two phases' config slots, empty and obviously so. A config is read off a real render;
    /// there is nothing sensible to invent here, and inventing something plausible would be
    /// worse than an obvious blank — it would run, and run wrong.
    static let placeholderConfigShortcuts: [OrderedJSONMember] = [
        .init(key: StoryFlowCastEmitter.stillsConfigShortcut,
              value: .object([.init(key: "model", value: .string("TODO pick a saved config"))])),
        .init(key: StoryFlowCastEmitter.videoConfigShortcut,
              value: .object([.init(key: "model", value: .string("TODO pick a saved config"))])),
    ]

    private static let starterBibleSchema = OrderedJSONValue.object([
        .init(key: "_1_what_this_is", value: .array([
            .string("The character bible. This file is the single source of truth for the project."),
            .string("Tanque Studio's Cast & Staging pane reads and writes it, and emits every"),
            .string("per-character card list from these rows — so the identity and wardrobe lists"),
            .string("that appear in BOTH phases cannot drift apart."),
            .string("Never hand-edit the emitted project .json. Edit this."),
        ])),
        .init(key: "_2_hard_rules", value: .array([
            .string("NO double-quote characters (\") anywhere in any field. framesDialog sizes the"),
            .string("clip by counting words inside \"...\" spans, and the emitter owns those spans."),
            .string("A stray quote splits a span and silently changes the frame count."),
            .string("Keep slate + line to 26 spoken words or fewer if you want Tanque Studio and"),
            .string("Draw Things to render the same length — past that they diverge, and the pane"),
            .string("shows both numbers on the row."),
        ])),
        .init(key: "_3_row_count", value: .array([
            .string("The number of rows here sets the loop count in both phases. Add or remove"),
            .string("whole rows; do not leave a row half-filled."),
        ])),
    ])

    private static let starterConfigsSchema = OrderedJSONValue.object([
        .init(key: "_1_config_shortcuts", value: .array([
            .string("The two Draw Things configs, one per phase: #krea2_stills renders the character"),
            .string("stills, #ltx2_video renders the spoken clips. Both are read off a REAL render —"),
            .string("render one still and one clip in Draw Things, then import the configs."),
            .string("Assign them from the pane's Config shortcuts section, or paste them here."),
            .string("Numbers must not be quoted: the pipeline applies a config with Object.assign"),
            .string("and coerces nothing, so \"seedMode\": \"2\" hands Draw Things the string."),
        ])),
        .init(key: "_2_fragments", value: .array([
            .string("The shared prose. concat appends with NO separator, so the leading and trailing"),
            .string("spaces are load-bearing — the pane shows a marker for the ones each fragment"),
            .string("needs. Keep 'mouth closed' in A_CLOSE: phase A's still is phase B's first frame,"),
            .string("and LTX-2 handles dialogue badly starting mid-word."),
        ])),
        .init(key: "_3_pacing", value: .array([
            .string("padding must be a multiple of 8. framesDialog returns 8k+1 and the executor adds"),
            .string("padding raw, so the StoryFlow Editor's own default of 49 is one of the bad ones."),
        ])),
    ])
}

// MARK: - Loading

enum StoryFlowCastDocumentError: Error, LocalizedError {
    case missingFile(String)
    case malformed(file: String, detail: String)
    case folderNotEmpty(String)

    var errorDescription: String? {
        switch self {
        case .folderNotEmpty(let name):
            return "“\(name)” already exists and is not empty. Pick a different name, or open it "
                 + "with Open Project Folder… if it already holds a project."
        case .missingFile(let name):
            return "\(name) is not in that folder, so it is not a Cast & Staging project. Pick a "
                 + "folder that holds both bible.json and configs.json — or use New Project… to "
                 + "create one."
        case .malformed(let file, let detail):
            return "\(file): \(detail)"
        }
    }
}

extension StoryFlowCastDocument {

    /// Read `bible.json` + `configs.json` out of a project folder.
    ///
    /// Deliberately lenient about *content* and strict about *shape*: a bible row missing a
    /// field loads with that field empty so the user can see and fix it in the table, but a
    /// file that isn't an object at all is an error, because guessing at it would silently
    /// discard whatever was actually in there.
    static func load(fromFolder folder: URL) throws -> StoryFlowCastDocument {
        let bibleURL = folder.appendingPathComponent(bibleFilename)
        let configsURL = folder.appendingPathComponent(configsFilename)

        guard FileManager.default.fileExists(atPath: bibleURL.path) else {
            throw StoryFlowCastDocumentError.missingFile(bibleFilename)
        }
        guard FileManager.default.fileExists(atPath: configsURL.path) else {
            throw StoryFlowCastDocumentError.missingFile(configsFilename)
        }

        let bibleJSON: OrderedJSONValue
        let configsJSON: OrderedJSONValue
        do {
            bibleJSON = try OrderedJSONValue.parse(contentsOf: bibleURL)
        } catch {
            throw StoryFlowCastDocumentError.malformed(file: bibleFilename,
                                                       detail: error.localizedDescription)
        }
        do {
            configsJSON = try OrderedJSONValue.parse(contentsOf: configsURL)
        } catch {
            throw StoryFlowCastDocumentError.malformed(file: configsFilename,
                                                       detail: error.localizedDescription)
        }

        var document = StoryFlowCastDocument()
        try document.applyBible(bibleJSON)
        try document.applyConfigs(configsJSON)
        return document
    }

    private mutating func applyBible(_ json: OrderedJSONValue) throws {
        guard let members = json.members else {
            throw StoryFlowCastDocumentError.malformed(file: Self.bibleFilename,
                                                       detail: "top level is not a JSON object")
        }
        bibleKeyOrder = members.map(\.key)
        for member in members where member.key != "characters" {
            biblePreserved[member.key] = member.value
        }
        guard let rows = json["characters"]?.elements else {
            throw StoryFlowCastDocumentError.malformed(
                file: Self.bibleFilename, detail: "'characters' must be a list")
        }
        cast = rows.map { row in
            CastMember(
                name:     row["name"]?.stringValue ?? "",
                identity: row["identity"]?.stringValue ?? "",
                wardrobe: row["wardrobe"]?.stringValue ?? "",
                slate:    row["slate"]?.stringValue ?? "",
                line:     row["line"]?.stringValue ?? "",
                voice:    row["voice"]?.stringValue ?? "",
                seed:     row["seed"]?.intValue ?? 0
            )
        }
    }

    private mutating func applyConfigs(_ json: OrderedJSONValue) throws {
        guard let members = json.members else {
            throw StoryFlowCastDocumentError.malformed(file: Self.configsFilename,
                                                       detail: "top level is not a JSON object")
        }
        configsKeyOrder = members.map(\.key)
        for member in members where !Self.configsOwnedKeys.contains(member.key) {
            configsPreserved[member.key] = member.value
        }

        staging.projectName     = json["project"]?["name"]?.stringValue ?? ""
        staging.outputBasename  = json["project"]?["outputBasename"]?.stringValue ?? ""
        staging.fixtureBasename = json["project"]?["fixtureBasename"]?.stringValue ?? ""

        staging.negativePrompt   = json["negativePrompt"]?.stringValue ?? ""
        staging.anchorsDirectory = json["anchorsDirectory"]?.stringValue ?? ""
        staging.anchorFilename   = json["anchorFilename"]?.stringValue ?? ""

        if let fragments = json["fragments"]?.members {
            for member in fragments {
                staging.fragments[member.key] = member.value.stringValue ?? ""
            }
        }

        if let stills = json["sizes"]?["stills"] {
            staging.stillsSize = CanvasSize(width: stills["width"]?.intValue ?? 1024,
                                            height: stills["height"]?.intValue ?? 576)
        }
        if let video = json["sizes"]?["video"] {
            staging.videoSize = CanvasSize(width: video["width"]?.intValue ?? 1024,
                                           height: video["height"]?.intValue ?? 576)
        }

        if let fd = json["framesDialog"] {
            staging.wps = fd["wps"]?.doubleValue ?? 2.6
            staging.padding = fd["padding"]?.intValue ?? 48
            staging.framesDialogGenerate = fd["generate"]?.boolValue ?? false
        }

        staging.configShortcuts = json["configShortcuts"]?.members ?? []
    }
}

// MARK: - Saving

extension StoryFlowCastDocument {

    /// `bible.json` as it should be written: preserved blocks in place, characters rebuilt
    /// from the table in the documented field order.
    var bibleJSON: OrderedJSONValue {
        var members: [OrderedJSONMember] = []
        var emitted = Set<String>()

        func appendCharacters() {
            members.append(OrderedJSONMember(key: "characters", value: .array(cast.map { row in
                .object([
                    .init(key: "name",     value: .string(row.name)),
                    .init(key: "identity", value: .string(row.identity)),
                    .init(key: "wardrobe", value: .string(row.wardrobe)),
                    .init(key: "slate",    value: .string(row.slate)),
                    .init(key: "line",     value: .string(row.line)),
                    .init(key: "voice",    value: .string(row.voice)),
                    .init(key: "seed",     value: .int(row.seed)),
                ])
            })))
            emitted.insert("characters")
        }

        for key in bibleKeyOrder {
            guard !emitted.contains(key) else { continue }
            if key == "characters" {
                appendCharacters()
            } else if let preserved = biblePreserved[key] {
                members.append(OrderedJSONMember(key: key, value: preserved))
                emitted.insert(key)
            }
        }
        // A file that somehow arrived without a `characters` key still gets one.
        if !emitted.contains("characters") { appendCharacters() }
        for (key, value) in biblePreserved.sorted(by: { $0.key < $1.key }) where !emitted.contains(key) {
            members.append(OrderedJSONMember(key: key, value: value))
        }
        return .object(members)
    }

    /// `configs.json` as it should be written.
    var configsJSON: OrderedJSONValue {
        var owned: [String: OrderedJSONValue] = [
            "configShortcuts": .object(staging.configShortcuts),
            "sizes": .object([
                .init(key: "stills", value: .object([
                    .init(key: "width",  value: .int(staging.stillsSize.width)),
                    .init(key: "height", value: .int(staging.stillsSize.height)),
                ])),
                .init(key: "video", value: .object([
                    .init(key: "width",  value: .int(staging.videoSize.width)),
                    .init(key: "height", value: .int(staging.videoSize.height)),
                ])),
            ]),
            "framesDialog": .object([
                .init(key: "wps",      value: .double(staging.wps)),
                .init(key: "padding",  value: .int(staging.padding)),
                .init(key: "generate", value: .bool(staging.framesDialogGenerate)),
            ]),
            // Written in FRAGMENT_SPEC order, which is the order the assembled prompt reads
            // them in — the one arrangement of the eight that can be checked against the
            // prompt by eye.
            "fragments": .object(StoryFlowFragmentSpec.all.map {
                .init(key: $0.name, value: .string(staging.fragmentText($0.name)))
            }),
            "negativePrompt": .string(staging.negativePrompt),
            "project": .object([
                .init(key: "name",            value: .string(staging.projectName)),
                .init(key: "outputBasename",  value: .string(staging.outputBasename)),
                .init(key: "fixtureBasename", value: .string(staging.fixtureBasename)),
            ]),
            "anchorsDirectory": .string(staging.anchorsDirectory),
            "anchorFilename":   .string(staging.anchorFilename),
        ]

        var members: [OrderedJSONMember] = []
        for key in configsKeyOrder {
            if let value = owned.removeValue(forKey: key) {
                members.append(OrderedJSONMember(key: key, value: value))
            } else if let preserved = configsPreserved[key] {
                members.append(OrderedJSONMember(key: key, value: preserved))
            }
        }
        // Keys the loaded file never had — a document built from scratch has none of them.
        for key in Self.configsOwnedKeys.sorted() {
            if let value = owned.removeValue(forKey: key) {
                members.append(OrderedJSONMember(key: key, value: value))
            }
        }
        return .object(members)
    }

    /// Write both files back into `folder`.
    ///
    /// Not atomic across the pair: `bible.json` lands before `configs.json`. Both are small
    /// local writes and the failure mode — one file newer than the other — is visible and
    /// re-savable, which is a better trade than a temp-directory dance for two text files.
    func save(toFolder folder: URL) throws {
        try (bibleJSON.prettyJSON + "\n")
            .write(to: folder.appendingPathComponent(Self.bibleFilename),
                   atomically: true, encoding: .utf8)
        try (configsJSON.prettyJSON + "\n")
            .write(to: folder.appendingPathComponent(Self.configsFilename),
                   atomically: true, encoding: .utf8)
    }
}
