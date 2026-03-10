//
//  GenerationSweep.swift
//  DrawThingsStudio
//
//  Sweep range/list parsing, prompt wildcard expansion, and job queue building.
//  All expansion happens client-side; Draw Things receives fully-resolved jobs.
//

import Foundation

// MARK: - Wildcard Mode

enum WildcardMode: Equatable {
    case random
    case combinatoric
}

// MARK: - Generation Job

/// A fully-resolved (prompt, config) pair ready to send to Draw Things.
struct GenerationJob {
    let prompt: String
    let config: DrawThingsGenerationConfig
}

// MARK: - Sweep Parser

enum SweepParser {
    /// Parse an integer sweep expression.
    /// - "8"      → [8]
    /// - "6-8"    → [6, 7, 8]
    /// - "4,8,16" → [4, 8, 16]
    /// Returns nil if the text is not a valid expression.
    static func parseInts(_ text: String) -> [Int]? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }

        // Comma list: "4,8,16"
        if t.contains(",") {
            let parts = t.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return parts.count >= 2 ? parts : nil
        }

        // Range: digits-dash-digits (dash must not be at start, to avoid negative numbers)
        if let dashIdx = t.firstIndex(of: "-"), dashIdx != t.startIndex {
            let lo = String(t[..<dashIdx])
            let hi = String(t[t.index(after: dashIdx)...])
            if let lo = Int(lo), let hi = Int(hi), lo < hi {
                return Array(lo...hi)
            }
        }

        return Int(t).map { [$0] }
    }

    /// Parse a double sweep expression.
    /// - "1.5"          → [1.5]
    /// - "1.0,1.5,2.0"  → [1.0, 1.5, 2.0]
    static func parseDoubles(_ text: String) -> [Double]? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }

        // Comma list: "1.0,1.5,2.0"
        if t.contains(",") {
            let parts = t.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            return parts.count >= 2 ? parts : nil
        }

        return Double(t).map { [$0] }
    }

    /// Returns the count only when it is > 1 (i.e., a real sweep is active).
    static func sweepCount(ints text: String) -> Int? {
        guard let v = parseInts(text), v.count > 1 else { return nil }
        return v.count
    }

    static func sweepCount(doubles text: String) -> Int? {
        guard let v = parseDoubles(text), v.count > 1 else { return nil }
        return v.count
    }
}

// MARK: - Wildcard Expander

enum WildcardExpander {
    /// Return the option-sets for each {A|B|C} group found in the prompt.
    static func groups(in prompt: String) -> [[String]] {
        var result: [[String]] = []
        var remaining = prompt[...]
        while let openIdx = remaining.firstIndex(of: "{") {
            let afterOpen = remaining.index(after: openIdx)
            if let closeIdx = remaining[afterOpen...].firstIndex(of: "}") {
                let inner = String(remaining[afterOpen..<closeIdx])
                let opts = inner.split(separator: "|", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                if opts.count >= 2 { result.append(opts) }
                remaining = remaining[remaining.index(after: closeIdx)...]
            } else {
                break
            }
        }
        return result
    }

    /// Total number of combinations across all wildcard groups.
    static func combinatorialCount(in prompt: String) -> Int {
        groups(in: prompt).reduce(1) { $0 * $1.count }
    }

    /// Expand the prompt into every possible {A|B|C} combination.
    static func expandAll(_ prompt: String) -> [String] {
        guard prompt.contains("{") else { return [prompt] }
        return expandRecursive(prompt)
    }

    private static func expandRecursive(_ s: String) -> [String] {
        guard let open = s.range(of: "{"),
              let close = s.range(of: "}", range: open.upperBound..<s.endIndex)
        else { return [s] }
        let opts = String(s[open.upperBound..<close.lowerBound])
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        guard opts.count >= 2 else { return [s] }
        let prefix = String(s[..<open.lowerBound])
        let suffix = String(s[close.upperBound...])
        return opts.flatMap { expandRecursive(prefix + $0 + suffix) }
    }

    /// Randomly resolve each {A|B|C} group to produce one concrete prompt.
    static func expandRandom(_ prompt: String) -> String {
        var result = prompt
        while let open = result.range(of: "{"),
              let close = result.range(of: "}", range: open.upperBound..<result.endIndex) {
            let opts = String(result[open.upperBound..<close.lowerBound])
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            let chosen = opts.randomElement() ?? ""
            result = String(result[..<open.lowerBound]) + chosen + String(result[close.upperBound...])
        }
        return result
    }
}

// MARK: - Job Queue Builder

struct JobQueueBuilder {
    let basePrompt: String
    let baseConfig: DrawThingsGenerationConfig
    let stepsText: String
    let guidanceText: String
    let shiftText: String
    let wildcardMode: WildcardMode
    let wildcardRandomCount: Int

    /// Total job count without materialising the full list (for UI display).
    var totalCount: Int {
        promptCount * stepsCount * guidanceCount * shiftCount
    }

    private var promptCount: Int {
        guard !WildcardExpander.groups(in: basePrompt).isEmpty else { return 1 }
        switch wildcardMode {
        case .combinatoric: return WildcardExpander.combinatorialCount(in: basePrompt)
        case .random:       return wildcardRandomCount
        }
    }
    private var stepsCount: Int    { SweepParser.parseInts(stepsText)?.count       ?? 1 }
    private var guidanceCount: Int { SweepParser.parseDoubles(guidanceText)?.count  ?? 1 }
    private var shiftCount: Int    { SweepParser.parseDoubles(shiftText)?.count     ?? 1 }

    /// Build the fully resolved list of GenerationJobs.
    func build() -> [GenerationJob] {
        // Expand prompts from wildcards
        let prompts: [String]
        if WildcardExpander.groups(in: basePrompt).isEmpty {
            prompts = [basePrompt]
        } else {
            switch wildcardMode {
            case .combinatoric:
                prompts = WildcardExpander.expandAll(basePrompt)
            case .random:
                prompts = (0..<wildcardRandomCount).map { _ in WildcardExpander.expandRandom(basePrompt) }
            }
        }

        let stepsValues    = SweepParser.parseInts(stepsText)        ?? [baseConfig.steps]
        let guidanceValues = SweepParser.parseDoubles(guidanceText)   ?? [baseConfig.guidanceScale]
        let shiftValues    = SweepParser.parseDoubles(shiftText)      ?? [baseConfig.shift]

        var jobs: [GenerationJob] = []
        for p in prompts {
            for s in stepsValues {
                for g in guidanceValues {
                    for sh in shiftValues {
                        var cfg = baseConfig
                        cfg.steps = s
                        cfg.guidanceScale = g
                        cfg.shift = sh
                        jobs.append(GenerationJob(prompt: p, config: cfg))
                    }
                }
            }
        }
        return jobs
    }
}
