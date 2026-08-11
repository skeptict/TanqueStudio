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
// per-character lists drifting out of lockstep between the two phases. An editor over the
// emitted file would reintroduce both. So the user edits this, and `StoryFlowCastEmitter`
// builds the project; there is no path from the UI to an item's `value` string.
//
// **Unknown top-level keys survive a round trip.** Both files carry long `_schema` prose
// blocks that are the documentation for anyone editing them by hand. They are parsed into
// `OrderedJSONValue` and written back verbatim, in their original position, so opening a
// project in Tanque Studio and saving it does not quietly strip the file's own manual.

// MARK: - Columns and slots
//
// A phase's prompt is an **alternating sequence** — prose, card, prose, card, … prose:
//
//     "A casting-room headshot of "  ·  IDENTITY  ·  ", wearing "  ·  WARDROBE  ·  ", seated…"
//        prose                          column       prose            column        prose
//
// That was two hardcoded parallel lists — the eight named fragments and the cast row's fixed
// properties — plus a hardcoded interleaving in the emitter. They are one list split in half,
// so they are now one list: each phase owns an ordered list of slots, and the cast table's
// fields are a *view* of the column slots rather than a separate declaration.
//
// The consequence worth stating: a column cannot exist without a place in the prompt, and a
// place in the prompt cannot reference a column that isn't in the cast table. Those were two
// things that could disagree; now there is nothing to disagree.

/// One per-character field: a cast-table column, and one `wildcard` card list per phase that
/// uses it.
struct CastColumn: Identifiable, Equatable {
    var id = UUID()
    /// Doubles as the cast table's field label and the key this column's text is stored under
    /// in `bible.json`, which is why the file stays readable and hand-editable.
    var name: String
    /// Spoken columns are wrapped in `"…"` by the emitter and are the only words `framesDialog`
    /// counts. Everything else is stage direction and costs no frames.
    var isSpoken: Bool = false
}

/// One entry in a phase's ordered sequence.
struct PhaseSlot: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Shared prose, identical for every character.
        case prose(String)
        /// A per-character card list.
        case column(CastColumn.ID)
    }

    var id = UUID()
    var kind: Kind

    static func prose(_ text: String) -> PhaseSlot { PhaseSlot(kind: .prose(text)) }
    static func column(_ id: CastColumn.ID) -> PhaseSlot { PhaseSlot(kind: .column(id)) }

    var proseText: String? {
        if case .prose(let text) = kind { return text }
        return nil
    }

    var columnID: CastColumn.ID? {
        if case .column(let id) = kind { return id }
        return nil
    }
}

/// Which of the two phases a slot list belongs to.
enum CastPhase: String, CaseIterable, Identifiable {
    case stills
    case video

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stills: return "Phase A · stills"
        case .video:  return "Phase B · video"
        }
    }

    var summary: String {
        switch self {
        case .stills: return "Renders one still per character and saves it as that character's anchor."
        case .video:  return "Loads each anchor back as the first frame and renders the spoken clip."
        }
    }
}

// MARK: - Cast

/// One row of the bible. `name` never reaches the model — it labels the row.
struct CastMember: Identifiable, Equatable {
    var id = UUID()
    var name = ""
    /// Pinned so a rejected anchor can be regenerated identically.
    var seed = 0
    /// Per-column text, keyed by column id so renaming a column does not touch the rows.
    var values: [CastColumn.ID: String] = [:]

    /// Keys `bible.json` uses for a row's own metadata; everything else in a row is a column.
    static let reservedKeys: Set<String> = ["name", "seed"]

    func value(_ column: CastColumn) -> String { values[column.id] ?? "" }
}

// MARK: - Staging

struct CanvasSize: Equatable {
    var width: Int
    var height: Int

    var aspect: Double { height == 0 ? 0 : Double(width) / Double(height) }
}

/// Everything in `configs.json` the editor owns. The two DT config blobs are held as parsed
/// `OrderedJSONValue` and never re-typed — they are read off a real render, and a UI that
/// re-serialized them through `Double` would turn an integer sampler enum into `10.0`.
struct CastStaging: Equatable {
    var projectName = ""
    var outputBasename = ""
    var fixtureBasename = ""

    /// The cast table's fields, in table order.
    var columns: [CastColumn] = []
    /// Each phase's ordered prose/column sequence.
    var phases: [CastPhase: [PhaseSlot]] = [:]

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

    func slots(_ phase: CastPhase) -> [PhaseSlot] { phases[phase] ?? [] }

    func column(_ id: CastColumn.ID) -> CastColumn? { columns.first { $0.id == id } }

    /// Columns actually used by a phase, in the order the prompt reads them.
    func columns(in phase: CastPhase) -> [CastColumn] {
        slots(phase).compactMap { $0.columnID.flatMap(column) }
    }

    var spokenColumns: [CastColumn] { columns.filter(\.isSpoken) }
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
    ///
    /// `fragments` is here despite no longer being written: a project authored before the slot
    /// model is migrated on load, and re-preserving the old block beside the new one would
    /// leave two descriptions of the same prompt in one file, which is the drift this whole
    /// feature exists to prevent.
    static let configsOwnedKeys: Set<String> = [
        "configShortcuts", "sizes", "framesDialog", "columns", "phases", "fragments",
        "negativePrompt", "project", "anchorsDirectory", "anchorFilename",
    ]
}

// MARK: - The canonical two-phase arrangement

extension CastStaging {

    /// The arrangement every project used before phases were authorable, and the one a new
    /// project starts from. Also what a pre-slot-model `configs.json` is migrated to, which is
    /// why the prose is passed in rather than hardcoded.
    static func auditionsArrangement(
        fragment: (String) -> String
    ) -> (columns: [CastColumn], phases: [CastPhase: [PhaseSlot]]) {
        let identity = CastColumn(name: "identity")
        let wardrobe = CastColumn(name: "wardrobe")
        let slate = CastColumn(name: "slate", isSpoken: true)
        let line = CastColumn(name: "line", isSpoken: true)
        let voice = CastColumn(name: "voice")

        return (
            columns: [identity, wardrobe, slate, line, voice],
            phases: [
                .stills: [
                    .prose(fragment("A_OPEN")),
                    .column(identity.id),
                    .prose(fragment("WEARING")),
                    .column(wardrobe.id),
                    .prose(fragment("A_CLOSE")),
                ],
                .video: [
                    .prose(fragment("B_OPEN")),
                    .column(identity.id),
                    // Phase A's copy and phase B's copy are separate slots that happen to
                    // share text. Only COLUMNS need to stay in lockstep across phases — the
                    // prose around them is free to differ, and pretending otherwise would be
                    // a constraint the format does not impose.
                    .prose(fragment("WEARING")),
                    .column(wardrobe.id),
                    .prose(fragment("B_SAYS")),
                    .column(slate.id),
                    .prose(fragment("B_BEAT")),
                    .column(line.id),
                    .prose(fragment("B_IN")),
                    .column(voice.id),
                    .prose(fragment("B_CLOSE")),
                ],
            ]
        )
    }
}

// MARK: - Starting a new project

extension StoryFlowCastDocument {

    /// A complete, valid project to start from.
    ///
    /// **Seeded rather than blank, and that is the point.** The prose carries the spacing the
    /// format requires — `concat` appends with no separator — so a new project opens with the
    /// one thing a user cannot reasonably be expected to get right by typing already correct.
    /// The cast rows are deliberately obvious placeholders, following the same convention as
    /// the bundled bibles: prose that reads as real is worse than prose that reads as a TODO.
    ///
    /// Everything validates except the config shortcuts, which cannot be invented — they are
    /// read off a real Draw Things render, and are seeded from the user's saved `#config`
    /// variables when there are any.
    static func starter(projectName: String,
                        folderName: String,
                        configShortcuts: [OrderedJSONMember] = []) -> StoryFlowCastDocument {
        var document = StoryFlowCastDocument()

        let arrangement = CastStaging.auditionsArrangement { Self.starterFragments[$0] ?? "" }
        document.staging.columns = arrangement.columns
        document.staging.phases = arrangement.phases

        let placeholders: [String: String] = [
            "identity": "TODO a one-clause description of who this is, no trailing period",
            "wardrobe": "TODO what they are wearing, reads after the prose before it",
            "slate": "TODO the line where they say their name and what they are here for",
            "line": "TODO their second spoken beat",
            "voice": "TODO how they sound, not what they say",
        ]
        func row(_ name: String, seed: Int) -> CastMember {
            var member = CastMember(name: name, seed: seed)
            for column in arrangement.columns {
                member.values[column.id] = placeholders[column.name] ?? "TODO"
            }
            return member
        }
        document.cast = [row("Character One", seed: 100001), row("Character Two", seed: 100002)]

        document.staging.projectName = projectName
        document.staging.outputBasename = projectName
        document.staging.fixtureBasename = folderName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
        document.staging.anchorsDirectory = "\(folderName)/anchors/"
        document.staging.anchorFilename = "\(folderName)/anchors/anchor.png"

        document.staging.negativePrompt =
            "blurry, low resolution, jpeg artifacts, watermark, on-screen text, subtitles, "
          + "warped face, malformed hands, extra fingers, duplicated limbs, camera shake, "
          + "handheld wobble, zoom, dolly move, rack focus, cut to another shot"

        document.staging.stillsSize = CanvasSize(width: 1024, height: 576)
        document.staging.videoSize = CanvasSize(width: 1024, height: 576)
        document.staging.wps = 2.6
        document.staging.padding = 48
        document.staging.framesDialogGenerate = false

        document.staging.configShortcuts = configShortcuts.isEmpty
            ? Self.placeholderConfigShortcuts
            : configShortcuts

        document.bibleKeyOrder = ["_schema", "characters"]
        document.biblePreserved["_schema"] = Self.starterBibleSchema
        document.configsKeyOrder = ["_schema", "configShortcuts", "sizes", "framesDialog",
                                    "columns", "phases", "negativePrompt", "project",
                                    "anchorsDirectory", "anchorFilename"]
        document.configsPreserved["_schema"] = Self.starterConfigsSchema
        return document
    }

    /// Spacing here is not a style choice — it is what keeps two words from being glued
    /// together in the prompt, and the validator checks the assembled result rather than these
    /// strings.
    static let starterFragments: [String: String] = [
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

    /// The two phases' config slots, empty and obviously so. A config is read off a real
    /// render; inventing something plausible would be worse than an obvious blank — it would
    /// run, and run wrong.
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
            .string("per-character card list from these rows — so a column used in BOTH phases"),
            .string("cannot drift apart. Never hand-edit the emitted project .json; edit this."),
        ])),
        .init(key: "_2_columns", value: .array([
            .string("Each row's keys other than 'name' and 'seed' are the project's COLUMNS, and"),
            .string("they are declared in configs.json. Adding a key here does nothing on its own —"),
            .string("add the column in the pane, which puts it in the prompt at the same time."),
        ])),
        .init(key: "_3_hard_rules", value: .array([
            .string("NO double-quote characters (\") anywhere in any field. framesDialog sizes the"),
            .string("clip by counting words inside \"...\" spans, and the emitter owns those spans."),
            .string("Keep the spoken columns to 26 words or fewer between them if you want Tanque"),
            .string("Studio and Draw Things to render the same length — past that they diverge,"),
            .string("and the pane shows both numbers on the row."),
        ])),
    ])

    private static let starterConfigsSchema = OrderedJSONValue.object([
        .init(key: "_1_config_shortcuts", value: .array([
            .string("The two Draw Things configs, one per phase: #krea2_stills renders the character"),
            .string("stills, #ltx2_video renders the spoken clips. Both are read off a REAL render."),
            .string("Assign them from the pane's Config shortcuts section, or paste them here."),
            .string("Numbers must not be quoted: the pipeline applies a config with Object.assign"),
            .string("and coerces nothing, so \"seedMode\": \"2\" hands Draw Things the string."),
        ])),
        .init(key: "_2_columns_and_phases", value: .array([
            .string("'columns' declares the cast table's fields. 'phases' is each phase's prompt as"),
            .string("an ordered list: {\"prose\": \"...\"} is shared text, {\"column\": \"identity\"} drops"),
            .string("in that character's card. concat appends with NO separator, so the spaces in"),
            .string("the prose are load-bearing — the pane previews the assembled prompt and flags"),
            .string("any seam where two words would run together."),
            .string("A column used in both phases must return the same card on the same pass, which"),
            .string("is why every wildcard is emitted in 'loop' mode."),
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
    /// column loads with that field empty so the user can see and fix it in the table, but a
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
        // Configs first: the columns it declares are what the bible's rows are keyed by.
        try document.applyConfigs(configsJSON)
        try document.applyBible(bibleJSON)
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
            var member = CastMember(name: row["name"]?.stringValue ?? "",
                                    seed: row["seed"]?.intValue ?? 0)
            for column in staging.columns {
                member.values[column.id] = row[column.name]?.stringValue ?? ""
            }
            return member
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

        if let columns = json["columns"]?.elements, json["phases"] != nil {
            applyColumnsAndPhases(columns: columns, phases: json["phases"])
        } else {
            migrateFromFragments(json["fragments"])
        }
    }

    private mutating func applyColumnsAndPhases(columns: [OrderedJSONValue],
                                                phases: OrderedJSONValue?) {
        staging.columns = columns.map {
            CastColumn(name: $0["name"]?.stringValue ?? "",
                       isSpoken: $0["spoken"]?.boolValue ?? false)
        }
        var byName: [String: CastColumn.ID] = [:]
        for column in staging.columns { byName[column.name] = column.id }

        for phase in CastPhase.allCases {
            let slots = (phases?[phase.rawValue]?.elements ?? []).compactMap { entry -> PhaseSlot? in
                if let prose = entry["prose"]?.stringValue { return .prose(prose) }
                // A slot naming a column that isn't declared is dropped rather than guessed at:
                // inventing one would put a card list in the prompt that the cast table has no
                // field for, which is exactly the disagreement this model removes.
                if let name = entry["column"]?.stringValue, let id = byName[name] {
                    return .column(id)
                }
                return nil
            }
            staging.phases[phase] = slots
        }
    }

    /// Migrate a project authored before phases were authorable.
    ///
    /// Those files describe the prompt as eight named fragments in a fixed arrangement, so the
    /// arrangement is reconstructed rather than inferred — it was never stored, because it was
    /// hardcoded in the emitter. The prose carries over verbatim, which is what lets the
    /// byte-identical pinning test prove the migration changed nothing.
    private mutating func migrateFromFragments(_ fragments: OrderedJSONValue?) {
        let arrangement = CastStaging.auditionsArrangement {
            fragments?[$0]?.stringValue ?? StoryFlowCastDocument.starterFragments[$0] ?? ""
        }
        staging.columns = arrangement.columns
        staging.phases = arrangement.phases

        // The old `fragments` block is deliberately not preserved: it would sit beside the new
        // `phases` block describing the same prompt, and two descriptions of one thing is the
        // drift this feature exists to prevent.
        if let index = configsKeyOrder.firstIndex(of: "fragments") {
            configsKeyOrder[index] = "phases"
            configsKeyOrder.insert("columns", at: index)
        }
    }
}

// MARK: - Saving

extension StoryFlowCastDocument {

    /// `bible.json` as it should be written: preserved blocks in place, characters rebuilt
    /// from the table with the project's own column names as keys.
    var bibleJSON: OrderedJSONValue {
        var members: [OrderedJSONMember] = []
        var emitted = Set<String>()

        func appendCharacters() {
            members.append(OrderedJSONMember(key: "characters", value: .array(cast.map { row in
                var fields: [OrderedJSONMember] = [.init(key: "name", value: .string(row.name))]
                for column in staging.columns {
                    fields.append(.init(key: column.name, value: .string(row.value(column))))
                }
                fields.append(.init(key: "seed", value: .int(row.seed)))
                return .object(fields)
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
            "columns": .array(staging.columns.map { column in
                .object([
                    .init(key: "name",   value: .string(column.name)),
                    .init(key: "spoken", value: .bool(column.isSpoken)),
                ])
            }),
            "phases": .object(CastPhase.allCases.map { phase in
                .init(key: phase.rawValue, value: .array(staging.slots(phase).map { slot in
                    switch slot.kind {
                    case .prose(let text):
                        return .object([.init(key: "prose", value: .string(text))])
                    case .column(let id):
                        return .object([.init(key: "column",
                                              value: .string(staging.column(id)?.name ?? ""))])
                    }
                }))
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
