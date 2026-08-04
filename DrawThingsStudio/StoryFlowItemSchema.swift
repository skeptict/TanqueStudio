import Foundation

// MARK: - StoryFlow instruction schema (260723 Phase 2)
//
// The declarative table §8.1 of `Docs/storyflow-260723-spec.md` argues for, and
// the direct analogue of the editor's own `ITEM_CONFIGS`
// (`StoryflowEditor_260725.html:955-990` plus the `buildJsonForm` branches).
//
// **Why a table rather than ~22 new `WorkflowStepType` cases.** Each enum case has
// to be handled in eight separate switches — displayName, iconName, accent,
// parameterSummary, the step-card editor, `stepFromItem`, `itemsFromStep`,
// `toPipelineArray` and `execute`. Twenty-two instructions × eight sites is ~176
// near-identical hand-written cases, for instructions Tanque Studio does not
// execute and in several cases never will. One table entry replaces all of it,
// because `.passthrough` already round-trips these losslessly — the *only* thing
// separating a passthrough item from an authorable one is that there is no form
// for it.
//
// **The defaults here are transcribed from the editor, not invented.** A default
// that disagrees with the editor's produces a project that behaves differently
// depending on which tool wrote it, which is exactly the class of divergence the
// reference-export test exists to catch. `StoryFlowItemSchemaTests` asserts the
// transcription against the values quoted below.
//
// **When an instruction graduates:** Phase 3 gives real executors to the runnable
// subset. Those instructions get promoted to first-class `WorkflowStepType` cases
// and drop out of this table. The table is the staging area for "authorable but
// not executable", which is precisely what Phase 2 is.

// MARK: - Value shapes

/// One field inside an object-valued instruction.
struct StoryFlowObjectField: Equatable {
    enum Kind: Equatable {
        /// `range` mirrors the editor's own min/max clamp where it has one.
        case number(default: Double, range: ClosedRange<Double>?, step: Double, isInteger: Bool)
        case toggle(default: Bool)
        case text(default: String)
        case picklist(default: String, options: [String])
        /// One card per line in the form; a JSON array of strings in the project.
        case cardList(default: [String])
    }

    let key: String
    let label: String
    let kind: Kind
}

/// The JSON shape an instruction's value takes in the *project* format.
enum StoryFlowValueShape: Equatable {
    /// Value is literally `true`. The pipeline types these "flag".
    case flag
    case string(default: String, placeholder: String, prefix: String?, multiline: Bool)
    case number(default: Double, isInteger: Bool)
    case object([StoryFlowObjectField])
}

// MARK: - Schema

struct StoryFlowItemSchema: Equatable {

    /// How the editor's instruction drawer groups its buttons, reused for the
    /// add-step menu so the two tools stay navigable in the same shape.
    enum Group: String, CaseIterable {
        case prompt = "Prompt"
        case config = "Config"
        case canvas = "Canvas"
        case moodboard = "Moodboard"
        case mask = "Mask & Depth"
        case loop = "Loop"
    }

    /// The pipeline key, and the name shown on the card — StoryFlow instruction
    /// names are the vocabulary users already read in the editor and in the docs,
    /// so they are not prettified.
    let itemType: String
    let group: Group
    let icon: String
    let shape: StoryFlowValueShape
    /// The type the pipeline's `allowedKeys` demands, or nil for an instruction that
    /// exists only in the project format.
    ///
    /// **Stored rather than derived from `shape`, because the two genuinely differ.**
    /// `poseJSON` is free text in the editor — you paste or reference a pose blob, the
    /// same way `config` works — but it is emitted as a real JSON *object*. Inferring
    /// the pipeline type from the authoring shape would have quietly typed it "string"
    /// and produced exports that fail preflight. Only `frames8` is nil: it is
    /// editor-only and exports as plain `frames` (spec §8.3.4).
    let pipelineType: String?

    /// One line explaining what the instruction does, from the editor's own label
    /// or placeholder text where it has one.
    let summary: String

    /// Accent from what the instruction *does*, not from the fact that it isn't
    /// executable yet.
    ///
    /// Before Phase 2 every passthrough card rendered grey, because the accent keyed
    /// off the step type (`.passthrough`) rather than the instruction. That made
    /// `size` and `concat` look identical — visible the moment a real project was
    /// loaded, and wrong: they do quite different things to a run.
    var accent: StoryFlowDS.Accent {
        switch group {
        case .prompt, .config:            return .accumulator
        case .canvas, .moodboard, .mask:  return .canvas
        case .loop:                       return .flow
        }
    }

    /// The value a freshly-added instruction carries, in the *project* format —
    /// object values are JSON **strings** there, matching `dataset.jsonValue`
    /// (spec §8.3.1).
    var defaultProjectValue: StoryFlowItemValue {
        switch shape {
        case .flag:
            return .bool(true)
        case .string(let value, _, _, _):
            return .string(value)
        case .number(let value, let isInteger):
            return isInteger ? .int(Int(value)) : .double(value)
        case .object(let fields):
            var dict: [String: Any] = [:]
            for field in fields {
                switch field.kind {
                case .number(let d, _, _, let isInteger): dict[field.key] = isInteger ? Int(d) : d
                case .toggle(let d):                      dict[field.key] = d
                case .text(let d):                        dict[field.key] = d
                case .picklist(let d, _):                 dict[field.key] = d
                case .cardList(let d):                    dict[field.key] = d
                }
            }
            let data = (try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])) ?? Data()
            return .string(String(data: data, encoding: .utf8) ?? "{}")
        }
    }
}

// MARK: - The table

extension StoryFlowItemSchema {

    /// Every instruction Tanque Studio can author but not execute.
    ///
    /// Deliberately **excludes**:
    /// - the 14 already handled as first-class `WorkflowStepType` cases (`note`,
    ///   `prompt`, `config`, `canvasClear`, `canvasSave`, `canvasLoad`, `moveScale`,
    ///   `crop`, `moodboardClear`, `moodboardCanvas`, `moodboardAdd`, `loop`,
    ///   `loopEnd`, `generate`) — spec §8.2 lists `moodboardAdd` in the backlog, but
    ///   the codec has imported it since 260225; adding it here would give it two
    ///   competing homes.
    /// - `interrogate` — Ned's scope call (§6.1): not authorable, not executed. It
    ///   still round-trips as passthrough, so nothing is lost.
    /// - `end` — the codec emits it as the export terminator; it is not authored.
    static let all: [StoryFlowItemSchema] = [

        // MARK: New in 260723

        .init(itemType: "concat", group: .prompt, icon: "text.append",
              shape: .string(default: "",
                             placeholder: "Accumulates text for Prompt or Enhance — @hero at $location",
                             prefix: nil, multiline: true),
              pipelineType: "string",
              summary: "Appends text to the running prompt without rendering."),

        .init(itemType: "wildcard", group: .prompt, icon: "shuffle",
              shape: .object([
                  .init(key: "wild", label: "Mode",
                        kind: .picklist(default: "shuffle", options: Self.wildModes)),
                  .init(key: "cards", label: "Cards",
                        kind: .cardList(default: ["aardvark", "badger", "cat", "dog"])),
              ]),
              pipelineType: "object",
              summary: "Appends one card to the prompt, picked fresh each loop pass."),

        .init(itemType: "sweep", group: .config, icon: "slider.horizontal.3",
              shape: .object([
                  .init(key: "paramName", label: "Param", kind: .text(default: "steps")),
                  .init(key: "wild", label: "Mode",
                        kind: .picklist(default: "loop", options: Self.wildModes)),
                  // Stored as strings; the export coerces numeric-looking cards to
                  // real JSON numbers, matching editor 260725 (spec §8.3.3).
                  .init(key: "cards", label: "Cards",
                        kind: .cardList(default: ["6", "7", "8", "9"])),
              ]),
              pipelineType: "object",
              summary: "Writes a picked card into a config parameter each loop pass."),

        .init(itemType: "enhance", group: .prompt, icon: "wand.and.stars",
              shape: .string(default: "",
                             placeholder: "System prompt — the accumulated text is appended, and the answer replaces it",
                             prefix: nil, multiline: true),
              pipelineType: "string",
              summary: "Rewrites the accumulated prompt using Draw Things' answer model."),

        .init(itemType: "approve", group: .prompt, icon: "hand.raised",
              shape: .flag,
              pipelineType: "flag",
              summary: "Pauses the run for a human edit of the accumulated prompt."),

        .init(itemType: "framesDialog", group: .config, icon: "film.stack",
              shape: .object([
                  .init(key: "wps", label: "WPS",
                        kind: .number(default: 2.4, range: 1.2...3.2, step: 0.1, isInteger: false)),
                  .init(key: "padding", label: "Pad frames",
                        kind: .number(default: 49, range: 1...4096, step: 8, isInteger: true)),
                  .init(key: "generate", label: "Generate", kind: .toggle(default: false)),
              ]),
              pipelineType: "object",
              summary: "Derives a frame count from the words in the accumulated prompt."),

        .init(itemType: "size", group: .config, icon: "aspectratio",
              shape: .object([
                  .init(key: "width", label: "Width",
                        kind: .number(default: 1024, range: 128...16384, step: 64, isInteger: true)),
                  .init(key: "height", label: "Height",
                        kind: .number(default: 1024, range: 128...16384, step: 64, isInteger: true)),
              ]),
              pipelineType: "object",
              summary: "Resizes the canvas immediately, rather than at the next render."),

        // Same object-merge semantics as `config`/`configInline` (`Object.assign`,
        // no canvas update) — the 260802 pipeline gives Hires Fix its own node
        // rather than asking the author to hand-type the four keys into a raw
        // config blob. Field keys and defaults match the reference editor exactly
        // (`hiresFix`, `hiresFixWidth`, `hiresFixHeight`, `hiresFixStrength`) —
        // already the exact keys `mergeDict` has understood since Batch F.
        .init(itemType: "hrf", group: .config, icon: "wand.and.rays",
              shape: .object([
                  .init(key: "hiresFix", label: "Enable", kind: .toggle(default: true)),
                  .init(key: "hiresFixWidth", label: "Width",
                        kind: .number(default: 1024, range: 128...16384, step: 64, isInteger: true)),
                  .init(key: "hiresFixHeight", label: "Height",
                        kind: .number(default: 576, range: 128...16384, step: 64, isInteger: true)),
                  .init(key: "hiresFixStrength", label: "Strength",
                        kind: .number(default: 0.4, range: 0...1, step: 0.01, isInteger: false)),
              ]),
              pipelineType: "object",
              summary: "Dedicated Hires Fix controls — same effect as setting these four keys via Config."),

        // MARK: Long-passthrough backlog

        .init(itemType: "negPrompt", group: .prompt, icon: "minus.square",
              shape: .string(default: "",
                             placeholder: "Update the negative prompt (persistent)",
                             prefix: nil, multiline: true),
              pipelineType: "string",
              summary: "Replaces the negative prompt for every render that follows."),

        .init(itemType: "frames", group: .config, icon: "film",
              shape: .number(default: 1, isInteger: true),
              pipelineType: "number",
              summary: "Sets the video frame count."),

        .init(itemType: "frames8", group: .config, icon: "film",
              shape: .number(default: 1, isInteger: true),
              pipelineType: nil,
              summary: "Frame count at 25 fps. Editor-only — exports as plain frames."),

        .init(itemType: "adaptSize", group: .config, icon: "arrow.down.right.and.arrow.up.left",
              shape: .object([
                  .init(key: "maxWidth", label: "Max width",
                        kind: .number(default: 1664, range: 128...16384, step: 64, isInteger: true)),
                  .init(key: "maxHeight", label: "Max height",
                        kind: .number(default: 1664, range: 128...16384, step: 64, isInteger: true)),
              ]),
              pipelineType: "object",
              summary: "Scales the canvas down to fit within a bounding box."),

        .init(itemType: "xlMagic", group: .config, icon: "sparkles.rectangle.stack",
              shape: .object([
                  .init(key: "original", label: "Original",
                        kind: .number(default: 3, range: 1...8, step: 1, isInteger: true)),
                  .init(key: "target", label: "Target",
                        kind: .number(default: 4, range: 1...8, step: 1, isInteger: true)),
                  .init(key: "negative", label: "Negative",
                        kind: .number(default: 7, range: 1...8, step: 1, isInteger: true)),
              ]),
              pipelineType: "object",
              summary: "SDXL size-conditioning. Three harmonic slider positions (1–8) resolved through the shared latent table."),

        .init(itemType: "inpaintTools", group: .canvas, icon: "paintbrush.pointed",
              shape: .object([
                  .init(key: "strength", label: "Strength",
                        kind: .number(default: 1, range: 0...1, step: 0.01, isInteger: false)),
                  .init(key: "maskBlur", label: "Blur",
                        kind: .number(default: 0, range: 0...15, step: 0.1, isInteger: false)),
                  .init(key: "maskBlurOutset", label: "Outset",
                        kind: .number(default: 0, range: -100...100, step: 1, isInteger: true)),
                  .init(key: "preserveOriginalAfterInpaint", label: "Preserve original",
                        kind: .toggle(default: true)),
              ]),
              pipelineType: "object",
              summary: "Inpaint settings for the renders that follow."),

        .init(itemType: "moodboardWeights", group: .moodboard, icon: "slider.horizontal.below.rectangle",
              shape: .object((0..<6).map { i in
                  .init(key: "index_\(i)", label: "Idx \(i)",
                        kind: .number(default: i == 0 ? 1 : 0, range: 0...1, step: 0.1, isInteger: false))
              }),
              pipelineType: "object",
              summary: "Sets the weight of each moodboard slot."),

        .init(itemType: "moodboardRemove", group: .moodboard, icon: "minus.circle",
              shape: .number(default: 0, isInteger: true),
              pipelineType: "number",
              summary: "Removes one moodboard entry by index."),

        .init(itemType: "maskBody", group: .mask, icon: "figure.stand",
              // Typed "flag" upstream but really an object — `setBodyparts()` reads
              // these keys, and preflight skips validation for flag-typed keys, so
              // the mislabel is harmless (spec §8.3.5). Emit the object.
              shape: .object([
                  .init(key: "upper", label: "Upper body", kind: .toggle(default: false)),
                  .init(key: "lower", label: "Lower body", kind: .toggle(default: false)),
                  .init(key: "clothes", label: "Clothes", kind: .toggle(default: true)),
                  .init(key: "neck", label: "Neck", kind: .toggle(default: false)),
                  .init(key: "extra", label: "Extra",
                        kind: .number(default: 5, range: 0...100, step: 1, isInteger: true)),
              ]),
              // Upstream types this "flag", but that is a mislabel: setBodyparts()
              // reads these keys, and preflight skips flag-typed keys entirely, so the
              // object passes and is what the pipeline actually needs (spec §8.3.5).
              pipelineType: "object",
              summary: "Masks body parts by category."),

        .init(itemType: "maskClear", group: .mask, icon: "xmark.square", shape: .flag,
              pipelineType: "flag",
              summary: "Clears the selection mask."),
        .init(itemType: "maskGet", group: .mask, icon: "square.on.square", shape: .flag,
              pipelineType: "flag",
              summary: "Copies the selection mask to the canvas."),
        .init(itemType: "maskBkgd", group: .mask, icon: "square.dashed", shape: .flag,
              pipelineType: "flag",
              summary: "Masks the background."),
        .init(itemType: "maskFG", group: .mask, icon: "square.dashed.inset.filled", shape: .flag,
              pipelineType: "flag",
              summary: "Masks the foreground."),

        .init(itemType: "maskLoad", group: .mask, icon: "square.and.arrow.down",
              shape: .string(default: "", placeholder: "myProject/image.png",
                             prefix: "~Pictures/", multiline: false),
              pipelineType: "string",
              summary: "Loads a mask from a file."),

        .init(itemType: "maskAsk", group: .mask, icon: "questionmark.square",
              shape: .string(default: "", placeholder: "a hat",
                             prefix: "find object: ", multiline: false),
              pipelineType: "string",
              summary: "Masks an object described in words. Needs Draw Things' answer model."),

        .init(itemType: "depthExtract", group: .mask, icon: "cube.transparent", shape: .flag,
              pipelineType: "flag",
              summary: "Extracts a depth map from the canvas to the depth layer."),
        .init(itemType: "depthCanvas", group: .mask, icon: "square.stack.3d.down.right", shape: .flag,
              pipelineType: "flag",
              summary: "Moves a depth map. Does not extract."),
        .init(itemType: "depthToCanvas", group: .mask, icon: "square.stack.3d.up", shape: .flag,
              pipelineType: "flag",
              summary: "Moves a depth map to the canvas. Does not extract."),
        .init(itemType: "poseExtract", group: .mask, icon: "figure.walk", shape: .flag,
              pipelineType: "flag",
              summary: "Extracts a pose from the canvas."),

        // Free text in the editor — you paste a pose blob or reference a #shortcut
        // from `poseJSONShortcuts`, exactly the way `config` works — but it exports
        // as a real JSON object. Hence the string shape with an object pipeline type.
        // Spec §8.5.3 leaves editing the shortcuts themselves as a separate question;
        // authoring the instruction does not depend on it.
        .init(itemType: "poseJSON", group: .mask, icon: "figure.stand.line.dotted.figure.stand",
              shape: .string(default: "", placeholder: "paste a full JSON pose {…} or #armsup",
                             prefix: nil, multiline: true),
              pipelineType: "object",
              summary: "Applies a pose from JSON, or from a #shortcut in the project's poses."),

        .init(itemType: "faceZoom", group: .canvas, icon: "face.dashed", shape: .flag,
              pipelineType: "flag",
              summary: "Detects a face and scales in. Does not crop."),
        .init(itemType: "removeBkgd", group: .canvas, icon: "person.crop.rectangle", shape: .flag,
              pipelineType: "flag",
              summary: "Makes the background transparent or flat grey."),

        // 260802: `sizex2()` — save the visible canvas, double the config's
        // width/height, then reload the saved image onto the now-larger canvas.
        // No parameters; the reference implementation takes none.
        .init(itemType: "sizex2", group: .canvas, icon: "arrow.up.left.and.arrow.down.right",
              shape: .flag,
              pipelineType: "flag",
              summary: "Doubles the canvas width and height, keeping the current image centered — ready for tiling or upscaling."),

        // 260802: `colorfill()` + `crop()` — a flat-color foundation layer sized
        // to the current canvas, useful as a backdrop before positioning layers
        // with Move Scale. `grey` is in the reference `solidColors` table but not
        // the editor's own picklist; included here since the pipeline itself
        // supports it.
        .init(itemType: "matte", group: .canvas, icon: "square.fill",
              shape: .object([
                  .init(key: "color", label: "Color",
                        kind: .picklist(default: "black", options: Self.matteColors)),
              ]),
              pipelineType: "object",
              summary: "Fills the canvas with a flat color — a foundation layer for Move Scale layouts."),

        .init(itemType: "askZoom", group: .canvas, icon: "text.magnifyingglass",
              shape: .string(default: "", placeholder: "a hat",
                             prefix: "find object: ", multiline: false),
              pipelineType: "string",
              summary: "Zooms to an object described in words. Needs Draw Things' answer model."),

        .init(itemType: "loopLoad", group: .loop, icon: "folder",
              shape: .string(default: "", placeholder: "myProject/batchFolder/",
                             prefix: "~Pictures/", multiline: false),
              pipelineType: "string",
              summary: "Loads the next image from a folder on each loop pass."),
        .init(itemType: "loopAddMB", group: .loop, icon: "folder.badge.plus",
              shape: .string(default: "", placeholder: "myProject/batchFolder/",
                             prefix: "~Pictures/", multiline: false),
              pipelineType: "string",
              summary: "Adds the next image from a folder to the moodboard each pass."),
        .init(itemType: "loopLoadMask", group: .loop, icon: "folder.badge.questionmark",
              shape: .string(default: "", placeholder: "myProject/batchFolder/",
                             prefix: "~Pictures/", multiline: false),
              pipelineType: "string",
              summary: "Loads the next mask from a folder on each loop pass."),
        .init(itemType: "loopSave", group: .loop, icon: "square.and.arrow.up",
              shape: .string(default: "", placeholder: "myProject/image.png",
                             prefix: "~Pictures/", multiline: false),
              pipelineType: "string",
              summary: "Saves the render each loop pass, numbered."),
    ]

    /// `WildcardTracker.getNextCard` (`StoryflowPipeline_260723.js:386-414`) accepts
    /// exactly these four. Phase 2 only needs the picklist; Phase 3 ports the tracker.
    static let wildModes = ["loop", "once", "shuffle", "random"]

    /// `colorfill()`'s `solidColors` table (`StoryflowPipeline.js:761-770`, 260802).
    static let matteColors = ["black", "white", "grey", "green", "magenta", "blue", "yellow", "cyan", "red"]

    static func schema(for itemType: String) -> StoryFlowItemSchema? {
        all.first { $0.itemType == itemType }
    }

    static func grouped() -> [(group: Group, items: [StoryFlowItemSchema])] {
        Group.allCases.compactMap { group in
            let items = all.filter { $0.group == group }
            return items.isEmpty ? nil : (group, items)
        }
    }
}
