//
//  DescribeAgentsManager.swift
//  DrawThingsStudio
//
//  Data model and manager for image description agents
//

import Foundation
import Combine
import AppKit
import OSLog

// MARK: - Describe Agent

struct DescribeAgent: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var targetModel: String
    var systemPrompt: String
    var userMessage: String
    var preferredVisionModel: String
    var icon: String
    var isBuiltIn: Bool

    init(
        id: String,
        name: String,
        targetModel: String = "",
        systemPrompt: String,
        userMessage: String,
        preferredVisionModel: String = "",
        icon: String = "eye",
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.targetModel = targetModel
        self.systemPrompt = systemPrompt
        self.userMessage = userMessage
        self.preferredVisionModel = preferredVisionModel
        self.icon = icon
        self.isBuiltIn = isBuiltIn
    }
}

// MARK: - Built-In Agents

enum BuiltInDescribeAgent: String, CaseIterable {
    case general      = "general"
    case flux         = "flux"
    case sdxl         = "sdxl"
    case zImageTurbo  = "zimage-turbo"
    case ltx2         = "ltx2"
    case wan22        = "wan22"
    case sd15         = "sd15"

    var agent: DescribeAgent {
        switch self {
        case .general:
            return DescribeAgent(
                id: rawValue,
                name: "General Description",
                targetModel: "Any",
                systemPrompt: "You are an expert image analyst. Describe images in clear, accurate detail. Focus on the subject, composition, lighting, colors, style, mood, and any notable artistic techniques.",
                userMessage: "Describe this image in detail. Include the main subject, composition, lighting, colors, mood, and artistic style.",
                preferredVisionModel: "",
                icon: "eye",
                isBuiltIn: true
            )
        case .flux:
            return DescribeAgent(
                id: rawValue,
                name: "FLUX Prompt",
                targetModel: "FLUX",
                systemPrompt: "You are an expert at writing prompts for FLUX diffusion models. FLUX responds well to natural, descriptive language and detailed scene descriptions. Write prompts as flowing prose, not keyword lists. Include subject, setting, lighting, color palette, atmosphere, and artistic style. Output only the prompt, no explanations.",
                userMessage: "Analyze this image and write a FLUX-optimized generation prompt that would recreate it. Use natural, descriptive language as flowing prose.",
                preferredVisionModel: "",
                icon: "wand.and.stars",
                isBuiltIn: true
            )
        case .sdxl:
            return DescribeAgent(
                id: rawValue,
                name: "SDXL Prompt",
                targetModel: "SDXL",
                systemPrompt: "You are an expert at writing prompts for Stable Diffusion XL (SDXL). Write prompts as comma-separated keyword phrases. Include: subject, art style, lighting, quality tags (masterpiece, best quality, 8k), composition, colors, and mood. Output only the prompt, no explanations.",
                userMessage: "Analyze this image and write an SDXL-optimized prompt with comma-separated keywords that would recreate it.",
                preferredVisionModel: "",
                icon: "rectangle.3.group",
                isBuiltIn: true
            )
        case .zImageTurbo:
            return DescribeAgent(
                id: rawValue,
                name: "Z Image Turbo",
                targetModel: "Z Image Turbo",
                systemPrompt: "You are an expert at writing prompts for Z Image Turbo, a fast diffusion model optimized for concise prompts (30–77 tokens). Use terse, impactful descriptors. Prioritize: subject, key visual qualities, lighting, style. Skip verbose phrases. Output only the prompt, no explanations.",
                userMessage: "Analyze this image and write a concise Z Image Turbo prompt (max 77 tokens) that would recreate it.",
                preferredVisionModel: "",
                icon: "bolt",
                isBuiltIn: true
            )
        case .ltx2:
            return DescribeAgent(
                id: rawValue,
                name: "LTX-2 Prompt",
                targetModel: "LTX-2",
                systemPrompt: "You are an expert at writing prompts for LTX-2, a latent video generation model. LTX-2 benefits from prompts that describe motion, action, and temporal flow alongside visual details. Include camera movement, subject motion, scene dynamics, lighting conditions, and overall atmosphere. Output only the prompt, no explanations.",
                userMessage: "Analyze this image and write an LTX-2 prompt suitable for video generation from this scene. Include motion descriptions and camera movement.",
                preferredVisionModel: "",
                icon: "film",
                isBuiltIn: true
            )
        case .wan22:
            return DescribeAgent(
                id: rawValue,
                name: "Wan 2.2 Prompt",
                targetModel: "Wan 2.2",
                systemPrompt: "You are an expert at writing prompts for Wan 2.2, Alibaba's video generation model. Wan 2.2 excels at realistic motion and cinematic sequences. Write prompts that describe the scene's visual content, motion dynamics, camera behavior, lighting, and atmosphere. Use clear, natural language. Avoid abstract concepts — focus on what is literally visible and moving in the scene. Output only the prompt, no explanations.",
                userMessage: "Analyze this image and write a Wan 2.2 video generation prompt. Describe the scene content, any implied or suitable motion, camera movement, lighting, and mood.",
                preferredVisionModel: "",
                icon: "video",
                isBuiltIn: true
            )
        case .sd15:
            return DescribeAgent(
                id: rawValue,
                name: "SD 1.5 Prompt",
                targetModel: "SD 1.5",
                systemPrompt: "You are an expert at writing prompts for Stable Diffusion 1.5. Use comma-separated keyword phrases including: subject, art style (e.g., 'oil painting', 'concept art'), quality boosters (masterpiece, best quality, highly detailed), lighting, colors, composition. Keep it under 75 tokens for best results. Output only the prompt, no explanations.",
                userMessage: "Analyze this image and write an SD 1.5-style prompt with comma-separated keywords that would recreate it.",
                preferredVisionModel: "",
                icon: "paintbrush.pointed",
                isBuiltIn: true
            )
        }
    }
}

// MARK: - Manager

@MainActor
final class DescribeAgentsManager: ObservableObject {
    static let shared = DescribeAgentsManager()

    private let logger = Logger(subsystem: "com.drawthingsstudio", category: "describe-agents")

    @Published private(set) var agents: [DescribeAgent] = []

    nonisolated let agentsFilePath: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("DrawThingsStudio/describe_agents.json")
    }()

    init() {
        loadAgentsSync()
    }

    private func loadAgentsSync() {
        var loaded: [DescribeAgent] = []

        if FileManager.default.fileExists(atPath: agentsFilePath.path),
           let data = try? Data(contentsOf: agentsFilePath),
           let custom = try? JSONDecoder().decode([DescribeAgent].self, from: data) {
            loaded = custom
        }

        let builtIns = BuiltInDescribeAgent.allCases.map { $0.agent }
        let customIDs = Set(loaded.map { $0.id })
        for builtIn in builtIns where !customIDs.contains(builtIn.id) {
            loaded.append(builtIn)
        }

        agents = loaded.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn { return !lhs.isBuiltIn }
            return lhs.name < rhs.name
        }
    }

    func loadAgents() { loadAgentsSync() }

    func saveAgents() {
        let builtInDefaults = Dictionary(
            uniqueKeysWithValues: BuiltInDescribeAgent.allCases.map { ($0.rawValue, $0.agent) }
        )
        let toSave = agents.filter { agent in
            if agent.isBuiltIn { return false }
            if let builtIn = builtInDefaults[agent.id] {
                return agent.systemPrompt != builtIn.systemPrompt
                    || agent.name != builtIn.name
                    || agent.userMessage != builtIn.userMessage
                    || agent.preferredVisionModel != builtIn.preferredVisionModel
                    || agent.targetModel != builtIn.targetModel
                    || agent.icon != builtIn.icon
            }
            return true
        }

        let dir = agentsFilePath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(toSave)
            try data.write(to: agentsFilePath)
        } catch {
            logger.error("Failed to save describe agents: \(error.localizedDescription)")
        }
    }

    func addAgent(_ agent: DescribeAgent) {
        var a = agent
        a.isBuiltIn = false
        agents.insert(a, at: 0)
        saveAgents()
    }

    func updateAgent(_ agent: DescribeAgent) {
        if let idx = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[idx] = agent
            saveAgents()
        }
    }

    func removeAgent(id: String) {
        let builtInIDs = Set(BuiltInDescribeAgent.allCases.map { $0.rawValue })
        if builtInIDs.contains(id) {
            resetBuiltInAgent(id: id)
        } else {
            agents.removeAll { $0.id == id }
            saveAgents()
        }
    }

    func resetBuiltInAgent(id: String) {
        guard let builtIn = BuiltInDescribeAgent(rawValue: id) else { return }
        let defaultAgent = builtIn.agent
        if let idx = agents.firstIndex(where: { $0.id == id }) {
            agents[idx] = defaultAgent
        }
        saveAgents()
    }

    func isBuiltInModified(id: String) -> Bool {
        guard let builtIn = BuiltInDescribeAgent(rawValue: id) else { return false }
        let d = builtIn.agent
        guard let current = agents.first(where: { $0.id == id }) else { return false }
        return current.systemPrompt != d.systemPrompt
            || current.name != d.name
            || current.userMessage != d.userMessage
            || current.preferredVisionModel != d.preferredVisionModel
            || current.targetModel != d.targetModel
            || current.icon != d.icon
    }

    func agent(for id: String) -> DescribeAgent? {
        agents.first { $0.id == id }
    }

    func openAgentsFile() {
        if !FileManager.default.fileExists(atPath: agentsFilePath.path) {
            createAgentsFileWithDefaults()
        }
        NSWorkspace.shared.open(agentsFilePath)
    }

    private func createAgentsFileWithDefaults() {
        let allAgents = BuiltInDescribeAgent.allCases.map { b -> DescribeAgent in
            var a = b.agent
            a.isBuiltIn = false
            return a
        }
        let dir = agentsFilePath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(allAgents) {
            try? data.write(to: agentsFilePath)
            loadAgents()
        }
    }
}
