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
    }

    struct ExpandedJob: Equatable {
        let prompt: String
        let configJSON: String
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
        baseConfigJSON: String
    ) -> [ExpandedJob] {
        let active = axes.filter { !$0.values.isEmpty }
        let combinations = cartesianProduct(active)

        return combinations.map { combo in
            var config = DrawThingsGenerationConfig()
            if let dict = jsonDict(baseConfigJSON) {
                StoryFlowEngine.mergeDict(dict, into: &config)
            }
            var prompt = basePrompt

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
                }
            }

            let configJSON = (try? JSONEncoder().encode(config))
                .flatMap { String(data: $0, encoding: .utf8) } ?? baseConfigJSON
            return ExpandedJob(prompt: prompt, configJSON: configJSON)
        }
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

    private static func jsonDict(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
