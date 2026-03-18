//
//  OpenAICompatibleClient.swift
//  DrawThingsStudio
//
//  HTTP client for OpenAI-compatible APIs (LM Studio, Jan, etc.)
//

import Foundation
import Combine
import OSLog

/// Client for OpenAI-compatible HTTP APIs (LM Studio, Jan, etc.)
@MainActor
final class OpenAICompatibleClient: LLMProvider, ObservableObject {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.drawthingsstudio", category: "openai-compat")

    @Published var connectionStatus: LLMConnectionStatus = .disconnected
    @Published var availableModels: [LLMModel] = []

    var host: String
    var port: Int
    var defaultModel: String
    var apiKey: String?
    let providerType: LLMProviderType

    private var baseURL: URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/v1"
        return components.url
    }

    private func validatedBaseURL() throws -> URL {
        guard let baseURL else {
            throw LLMError.invalidConfiguration("Invalid \(providerType.displayName) address (\(host):\(port))")
        }
        return baseURL
    }

    private let session: URLSession

    // MARK: - LLMProvider Protocol

    var providerName: String {
        providerType.displayName
    }

    // MARK: - Initialization

    init(
        providerType: LLMProviderType = .lmStudio,
        host: String = "localhost",
        port: Int? = nil,
        defaultModel: String = "default",
        apiKey: String? = nil
    ) {
        self.providerType = providerType
        self.host = host
        self.port = port ?? providerType.defaultPort
        self.defaultModel = defaultModel
        self.apiKey = apiKey

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    /// Convenience initializer for LM Studio
    static func lmStudio(host: String = "localhost", port: Int = 1234) -> OpenAICompatibleClient {
        OpenAICompatibleClient(providerType: .lmStudio, host: host, port: port)
    }

    /// Convenience initializer for Jan
    static func jan(host: String = "localhost", port: Int = 1337, apiKey: String? = nil) -> OpenAICompatibleClient {
        OpenAICompatibleClient(providerType: .jan, host: host, port: port, apiKey: apiKey)
    }

    // MARK: - Request Helper

    /// Add authorization header if API key is set
    private func addAuthHeader(to request: inout URLRequest) {
        if let apiKey = apiKey {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
            }
        }
        // Jan validates the Host header and rejects anything other than "localhost"
        // (DNS-rebinding protection). Override it so remote connections work.
        if providerType == .jan {
            request.setValue("localhost", forHTTPHeaderField: "Host")
        }
    }

    // MARK: - Connection Check

    func checkConnection() async -> Bool {
        connectionStatus = .connecting

        do {
            guard let baseURL else {
                connectionStatus = .error("Invalid host/port configuration")
                return false
            }

            let url = baseURL.appendingPathComponent("models")
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            addAuthHeader(to: &request)

            logger.info("Connecting to \(url.absoluteString), apiKey: \(self.apiKey != nil ? "\(self.apiKey!.count) chars" : "none")")

            let (_, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                connectionStatus = .error("Invalid response")
                return false
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                connectionStatus = .error("Unauthorized — check API key in \(providerType.displayName) settings")
                return false
            }

            guard httpResponse.statusCode == 200 else {
                connectionStatus = .error("HTTP \(httpResponse.statusCode) — check host/port")
                return false
            }

            connectionStatus = .connected
            logger.info("Connected to \(self.providerType.displayName) at \(self.host):\(self.port)")
            return true
        } catch {
            connectionStatus = .error(error.localizedDescription)
            logger.error("Failed to connect to \(self.providerType.displayName): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - List Models

    func listModels() async throws -> [LLMModel] {
        let url = try validatedBaseURL().appendingPathComponent("models")
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LLMError.requestFailed("Failed to list models")
        }

        let result = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)

        let models = result.data.map { model in
            LLMModel(
                name: model.id,
                size: nil,
                modifiedAt: Date(timeIntervalSince1970: TimeInterval(model.created ?? 0)),
                digest: nil
            )
        }

        availableModels = models

        // Set default model if we have one and current default is "default"
        if defaultModel == "default", let firstModel = models.first {
            defaultModel = firstModel.name
        }

        return models
    }

    // MARK: - Model Resolution

    /// Returns the first available model ID from the server when `defaultModel` is still
    /// the unset sentinel "default". Caches the result in `defaultModel` for subsequent calls.
    private func resolvedModel(_ requested: String) async throws -> String {
        guard requested == "default" else { return requested }
        let models = try await listModels()
        guard let first = models.first else {
            throw LLMError.requestFailed("No models available on \(providerType.displayName). Load a model first.")
        }
        return first.name
    }

    // MARK: - Generate Text

    func generateText(prompt: String) async throws -> String {
        try await generateText(prompt: prompt, model: defaultModel, options: .default)
    }

    func generateText(
        prompt: String,
        model: String,
        options: LLMGenerationOptions = .default
    ) async throws -> String {
        let resolvedModelName = try await resolvedModel(model)
        let url = try validatedBaseURL().appendingPathComponent("chat/completions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body: [String: Any] = [
            "model": resolvedModelName,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": options.temperature,
            "top_p": options.topP,
            "max_tokens": options.maxTokens,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.debug("Generating text with model: \(resolvedModelName)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.requestFailed("Status \(httpResponse.statusCode): \(errorMessage)")
        }

        let result = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)

        guard let content = result.choices.first?.message.content else {
            throw LLMError.invalidResponse
        }

        logger.debug("Generated \(content.count) characters")

        return content
    }

    func generateText(
        systemPrompt: String,
        userMessage: String,
        model: String,
        options: LLMGenerationOptions = .default
    ) async throws -> String {
        try await chat(
            messages: [.system(systemPrompt), .user(userMessage)],
            model: model,
            options: options
        )
    }

    // MARK: - Generate Text Streaming

    func generateTextStreaming(
        prompt: String,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        try await generateTextStreaming(prompt: prompt, model: defaultModel, options: .default, onToken: onToken)
    }

    func generateTextStreaming(
        prompt: String,
        model: String,
        options: LLMGenerationOptions = .default,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        let url = try validatedBaseURL().appendingPathComponent("chat/completions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": options.temperature,
            "top_p": options.topP,
            "max_tokens": options.maxTokens,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.debug("Starting streaming generation with model: \(model)")

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LLMError.requestFailed("Streaming request failed")
        }

        var fullResponse = ""

        for try await line in bytes.lines {
            // SSE format: "data: {...}" or "data: [DONE]"
            guard line.hasPrefix("data: ") else { continue }

            let jsonString = String(line.dropFirst(6))

            if jsonString == "[DONE]" {
                break
            }

            guard let data = jsonString.data(using: .utf8) else { continue }

            do {
                let chunk = try JSONDecoder().decode(OpenAIStreamChunk.self, from: data)
                if let content = chunk.choices.first?.delta.content {
                    fullResponse += content
                    onToken(content)
                }
            } catch {
                // Skip malformed chunks
                logger.warning("Failed to parse stream chunk: \(error.localizedDescription)")
            }
        }

        return fullResponse
    }

    // MARK: - Image Description (Vision)

    func describeImage(
        _ imageData: Data,
        systemPrompt: String,
        userMessage: String,
        model: String
    ) async throws -> String {
        let resolvedModelName = try await resolvedModel(model)
        let url = try validatedBaseURL().appendingPathComponent("chat/completions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let base64Image = imageData.base64EncodedString()
        let dataURL = "data:image/jpeg;base64,\(base64Image)"

        let body: [String: Any] = [
            "model": resolvedModelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": userMessage],
                        ["type": "image_url", "image_url": ["url": dataURL]]
                    ]
                ]
            ],
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            if errorBody.contains("mmproj") || errorBody.contains("image input is not supported") {
                throw LLMError.requestFailed("The model loaded in \(providerType.displayName) doesn't support vision. Load a multimodal model (with mmproj) to use image description.")
            }
            throw LLMError.requestFailed("Vision request failed (status \(httpResponse.statusCode)): \(errorBody)")
        }

        let result = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = result.choices.first?.message.content else {
            throw LLMError.invalidResponse
        }
        return content
    }

    // MARK: - Chat Completion

    func chat(
        messages: [ChatMessage],
        model: String? = nil,
        options: LLMGenerationOptions = .default
    ) async throws -> String {
        let url = try validatedBaseURL().appendingPathComponent("chat/completions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body: [String: Any] = [
            "model": model ?? defaultModel,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": options.temperature,
            "top_p": options.topP,
            "max_tokens": options.maxTokens,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LLMError.requestFailed("Chat request failed")
        }

        let result = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)

        guard let content = result.choices.first?.message.content else {
            throw LLMError.invalidResponse
        }

        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LLMError.requestFailed(LLMError.emptyResponseMessage)
        }

        return content
    }
}

// MARK: - OpenAI API Response Types

private struct OpenAIModelsResponse: Codable {
    let data: [OpenAIModel]
    let object: String?
}

private struct OpenAIModel: Codable {
    let id: String
    let object: String?
    let created: Int?
    let ownedBy: String?

    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
    }
}

private struct OpenAIChatResponse: Codable {
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

private struct OpenAIChoice: Codable {
    let index: Int
    let message: OpenAIMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

private struct OpenAIMessage: Codable {
    let role: String
    let content: String?
}

private struct OpenAIUsage: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

private struct OpenAIStreamChunk: Codable {
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [OpenAIStreamChoice]
}

private struct OpenAIStreamChoice: Codable {
    let index: Int
    let delta: OpenAIDelta
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

private struct OpenAIDelta: Codable {
    let role: String?
    let content: String?
}
