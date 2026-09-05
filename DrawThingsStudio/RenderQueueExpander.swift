//
//  RenderQueueExpander.swift
//  TanqueStudio
//
//  Pure matrix -> job-list expansion. No SwiftData, no ModelContext — takes
//  plain values in, returns plain (prompt, configJSON) pairs out, so the
//  cross-product logic is testable without a persistence stack. The view
//  layer turns each result into a RenderQueueJob.
//

import Foundation

enum RenderQueueExpander {

    struct AxisInput {
        let kind: RenderQueueAxisKind
        let values: [String]
        /// Defaulted so every existing call site — and every test written before
        /// pairing existed — keeps the cross-product behaviour it was written for.
        var mode: RenderQueueAxisMode = .cross

        init(kind: RenderQueueAxisKind, values: [String], mode: RenderQueueAxisMode = .cross) {
            self.kind = kind
            self.values = values
            self.mode = mode
        }
    }

    struct ExpandedJob: Equatable {
        let prompt: String
        let configJSON: String
        /// `TSImage` UUID string when a `.sourceImage` axis (or the base source)
        /// applies to this job.
        ///
        /// The expander stays a **pure function over strings** — it has no
        /// `ModelContext` and cannot read image bytes — so it emits the
        /// identifier and the view resolves it to bytes when it inserts the
        /// `RenderQueueJob`. That keeps the whole matrix mechanism unit-testable
        /// with no persistence stack, which is the reason it was written this way
        /// in the first place.
        var sourceImageID: String? = nil
    }

    /// What `plan` produces: the jobs, plus anything the user should be told
    /// *before* committing them to the queue.
    struct ExpansionPlan {
        let jobs: [ExpandedJob]
        /// Human-readable, shown next to Expand. Empty is the normal case.
        let warnings: [String]
    }

    /// Cross product of every axis that has at least one value. An axis with
    /// zero values contributes nothing (not even a "use the default" no-op
    /// dimension) — it's simply absent from the product. If every axis is
    /// empty, expansion still produces exactly one job: the base prompt and
    /// config as-is, so "Expand" always does something reasonable even
    /// before any axis is set up.
    ///
    /// Axis order is nesting order: the first active axis varies slowest.
    /// Values that don't parse for a numeric kind (steps/seed/guidanceScale/
    /// strength/shift) are dropped silently rather than failing the whole
    /// expansion — one typo'd line shouldn't block every other combination.
    static func expand(
        axes: [AxisInput],
        basePrompt: String,
        baseConfigJSON: String,
        baseSourceImageID: String? = nil
    ) -> [ExpandedJob] {
        plan(axes: axes, basePrompt: basePrompt, baseConfigJSON: baseConfigJSON,
             baseSourceImageID: baseSourceImageID).jobs
    }

    /// As `expand`, but also reports what the user should know before pressing
    /// Expand for real — currently the ragged-pairing case (§2 of
    /// `Docs/render-queue-image-inputs-spec.md`).
    static func plan(
        axes: [AxisInput],
        basePrompt: String,
        baseConfigJSON: String,
        baseSourceImageID: String? = nil
    ) -> ExpansionPlan {
        let active = axes.filter { !$0.values.isEmpty }
        let (combinations, warnings) = combos(active)

        let jobs = combinations.map { combo -> ExpandedJob in
            var config = DrawThingsGenerationConfig()
            if let dict = jsonDict(baseConfigJSON) {
                StoryFlowEngine.mergeDict(dict, into: &config)
            }
            var prompt = basePrompt
            var sourceImageID = baseSourceImageID

            for (kind, value) in combo {
                switch kind {
                case .prompt: prompt = value
                case .negativePrompt: config.negativePrompt = value
                case .model: config.model = value
                case .sampler: config.sampler = value
                case .seedMode: config.seedMode = value
                case .loraSet: config.loras = parseLoRASet(value)
                case .steps: if let v = Int(value) { config.steps = v }
                case .seed: if let v = Int(value) { config.seed = v }
                case .guidanceScale: if let v = Double(value) { config.guidanceScale = v }
                case .strength: if let v = Double(value) { config.strength = v }
                case .shift: if let v = Double(value) { config.shift = v }
                case .sourceImage: sourceImageID = value.isEmpty ? nil : value
                }
            }

            let configJSON = (try? JSONEncoder().encode(config))
                .flatMap { String(data: $0, encoding: .utf8) } ?? baseConfigJSON
            return ExpandedJob(prompt: prompt, configJSON: configJSON,
                               sourceImageID: sourceImageID)
        }
        return ExpansionPlan(jobs: jobs, warnings: warnings)
    }

    // MARK: - Combining axes

    typealias Combo = [(kind: RenderQueueAxisKind, value: String)]

    /// Turn the active axes into one job per output combination.
    ///
    /// **Two modes, because a cross product cannot express the batch case.** Ten
    /// source images crossed with ten prompts is a hundred jobs; what you want for
    /// "animate each image with its own prompt" is ten — image *i* with prompt *i*.
    /// So axes marked `.pair` advance **together**, as a single dimension, and that
    /// dimension then takes part in the cross product with the `.cross` axes like
    /// any other factor:
    ///
    ///     images  [a, b, c]  pair  ┐
    ///     prompts [P, Q, R]  pair  ┘→ (a,P) (b,Q) (c,R)   3
    ///     steps   [8, 12]    cross  → ×2                  6 jobs
    ///
    /// The paired dimension is inserted at the position of the **first** paired
    /// axis, so "the first active axis varies slowest" still describes the output.
    ///
    /// ⚠️ **Ragged pairs stop at the shortest, and say so.** Repeating a short
    /// axis to fill would pair an image with a prompt written for a different one —
    /// an error that is invisible in a grid of finished renders, and expensive,
    /// since each of those jobs is a video. A single paired axis is just a normal
    /// dimension and never warns.
    private static func combos(_ axes: [AxisInput]) -> (combos: [Combo], warnings: [String]) {
        let paired = axes.filter { $0.mode == .pair }
        guard !paired.isEmpty else { return (cartesianProduct(axes), []) }

        let length = paired.map(\.values.count).min() ?? 0
        var warnings: [String] = []
        if paired.count > 1, paired.contains(where: { $0.values.count != length }) {
            let detail = paired
                .map { "\($0.kind.displayName) \($0.values.count)" }
                .joined(separator: ", ")
            warnings.append(
                "Paired axes have different lengths (\(detail)) — pairing stops at \(length). "
              + "Extra values are unused."
            )
        }

        // Collapse the paired axes into one synthetic axis whose "values" are
        // whole combos, then run the ordinary product with that in place.
        let zipped: [Combo] = (0..<length).map { i in
            paired.map { (kind: $0.kind, value: $0.values[i]) }
        }

        var result: [Combo] = [[]]
        var insertedPaired = false
        for axis in axes {
            if axis.mode == .pair {
                guard !insertedPaired else { continue }   // already folded in
                insertedPaired = true
                result = result.flatMap { combo in zipped.map { combo + $0 } }
            } else {
                result = result.flatMap { combo in axis.values.map { combo + [(axis.kind, $0)] } }
            }
        }
        return (result, warnings)
    }

    // MARK: - Cross product

    private static func cartesianProduct(
        _ axes: [AxisInput]
    ) -> [[(kind: RenderQueueAxisKind, value: String)]] {
        var result: [[(kind: RenderQueueAxisKind, value: String)]] = [[]]
        for axis in axes {
            var next: [[(kind: RenderQueueAxisKind, value: String)]] = []
            next.reserveCapacity(result.count * axis.values.count)
            for combo in result {
                for value in axis.values {
                    next.append(combo + [(axis.kind, value)])
                }
            }
            result = next
        }
        return result
    }

    // MARK: - LoRA set syntax: "file@weight, file@weight" — blank = none

    static func parseLoRASet(_ line: String) -> [DrawThingsGenerationConfig.LoRAConfig] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(separator: ",").compactMap { entry in
            let parts = entry.split(separator: "@", maxSplits: 1)
            let file = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard !file.isEmpty else { return nil }
            let weight = parts.count > 1
                ? Double(parts[1].trimmingCharacters(in: .whitespaces)) ?? 1.0
                : 1.0
            return .init(file: file, weight: weight)
        }
    }

    /// Renders a parsed LoRA set back to the same line syntax, for round-trip
    /// display (e.g. pre-filling an axis row from an existing job).
    static func formatLoRASet(_ loras: [DrawThingsGenerationConfig.LoRAConfig]) -> String {
        loras.map { "\($0.file)@\($0.weight)" }.joined(separator: ", ")
    }

    // MARK: - Fitting the canvas to a source image

    /// What fitting a config's canvas to a source image's shape would do.
    struct CanvasFit: Equatable {
        let fromWidth: Int, fromHeight: Int
        let toWidth: Int, toHeight: Int

        var changesAnything: Bool { fromWidth != toWidth || fromHeight != toHeight }
        var description: String { "\(fromWidth)×\(fromHeight) → \(toWidth)×\(toHeight)" }
    }

    /// Canvas that matches `aspect` at the config's **own pixel budget**.
    ///
    /// Not the source image's own dimensions: a 4096² reference would otherwise
    /// turn a modest LTX job into a 16-megapixel one. Area is what governs render
    /// time and memory and is the user's real choice; the shape is what the source
    /// image dictates. So the budget is kept and the rectangle is reshaped.
    ///
    /// The grid arithmetic is `CanvasSizing.dimensions(ratio:area:)` — Draw Things
    /// floors both axes to a multiple of 64, and rounding each axis independently
    /// compounds badly enough to miss the ratio visibly (16:9 at the 1024² budget
    /// lands on 7:4). That type already searches all four grid corners and prefers
    /// ratio over area; there is no second implementation here.
    ///
    /// Returns `nil` when the config has no usable width/height to work from.
    static func canvasFit(inConfigJSON json: String, toAspect aspect: Double) -> CanvasFit? {
        guard aspect.isFinite, aspect > 0,
              let dict = jsonDict(json),
              let w = (dict["width"] as? NSNumber)?.intValue, w > 0,
              let h = (dict["height"] as? NSNumber)?.intValue, h > 0
        else { return nil }

        let fitted = CanvasSizing.dimensions(ratio: aspect, area: Double(w) * Double(h))
        return CanvasFit(fromWidth: w, fromHeight: h, toWidth: fitted.w, toHeight: fitted.h)
    }

    /// `json` with width and height replaced by the fit. Returns the original
    /// string unchanged if it cannot be parsed, so a malformed config degrades to
    /// "no fit applied" rather than losing the job's config entirely.
    static func applying(_ fit: CanvasFit, toConfigJSON json: String) -> String {
        guard var dict = jsonDict(json) else { return json }
        dict["width"] = fit.toWidth
        dict["height"] = fit.toHeight
        guard let data = try? JSONSerialization.data(withJSONObject: dict,
                                                     options: [.sortedKeys]),
              let out = String(data: data, encoding: .utf8) else { return json }
        return out
    }

    /// `numFrames` out of an already-expanded job's config, for the Expand
    /// preview. Returns 0 when absent or not a video config; callers treat that
    /// as one frame.
    static func numFrames(inConfigJSON json: String) -> Int {
        guard let dict = jsonDict(json) else { return 0 }
        return (dict["numFrames"] as? NSNumber)?.intValue ?? 0
    }

    private static func jsonDict(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
