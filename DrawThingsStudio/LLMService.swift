import AppKit
import Foundation

// MARK: - LLM Provider

enum LLMProvider: String, CaseIterable, Codable {
    case ollama   = "ollama"
    case lmStudio = "lmStudio"
    case jan      = "jan"

    var displayName: String {
        switch self {
        case .ollama:   return "Ollama"
        case .lmStudio: return "LM Studio"
        case .jan:      return "Jan"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .ollama:   return "http://localhost:11434"
        case .lmStudio: return "http://localhost:1234"
        case .jan:      return "http://localhost:1337"
        }
    }
}

// MARK: - LLM Error

enum LLMError: LocalizedError {
    case httpError(Int)
    case emptyResponse
    case invalidURL
    case decodingFailed
    case imageEncodingFailed
    case noImageAvailable
    case modelRejectedImage(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "HTTP \(code)"
        case .emptyResponse:       return "LLM returned an empty response"
        case .invalidURL:          return "Invalid base URL"
        case .decodingFailed:      return "Failed to decode LLM response"
        case .imageEncodingFailed: return "Couldn't encode the image for the LLM"
        case .noImageAvailable:    return "No image to describe — generate one, or pick another source"
        case .modelRejectedImage(let model):
            return "\(model) rejected the image — it's most likely a text-only model. Pick a vision model (llava, qwen2.5-vl) in MODEL above."
        }
    }
}

// MARK: - LLM Service

struct LLMService {

    /// Run an arbitrary LLM operation defined by a system prompt.
    /// Used by AssistTabView with the selected LLMOperation's systemPrompt.
    ///
    /// Passing `images` sends a multimodal request — the user message becomes a
    /// content-part array instead of a bare string. This requires a vision-capable
    /// model on the other end; see `chat` for what a text-only model does with it.
    static func runOperation(
        systemPrompt: String,
        input: String,
        model: String,
        baseURL: String,
        provider: LLMProvider,
        apiKey: String = "",
        images: [NSImage] = []
    ) async throws -> String {
        return try await chat(
            system: systemPrompt,
            user: input,
            model: model,
            baseURL: baseURL,
            provider: provider,
            apiKey: apiKey,
            images: images
        )
    }

    /// Fetch available model IDs from the /v1/models endpoint.
    /// For Jan without an API key: the /v1/models endpoint returns HTTP 403.
    /// In that case we test reachability via the root URL and return [] so the
    /// user can still enter model names manually. When an API key is provided
    /// Jan's /v1/models returns a proper model list.
    static func fetchModels(baseURL: String, provider: LLMProvider, apiKey: String = "") async throws -> [String] {
        if provider == .jan {
            if apiKey.isEmpty {
                // No key — test reachability via root URL only.
                let rootString = normalizedURL(baseURL, path: "", provider: provider)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard let url = URL(string: rootString) else { throw LLMError.invalidURL }
                _ = try await URLSession.shared.data(from: url)
                return []
            } else {
                // Key provided — try /v1/models with auth first, then without auth
                // (some Jan versions don't require auth for model listing).
                let urlString = normalizedURL(baseURL, path: "v1/models", provider: provider)
                guard let url = URL(string: urlString) else { throw LLMError.invalidURL }

                // Attempt with Bearer auth
                var authRequest = URLRequest(url: url)
                authRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                if let (data, resp) = try? await URLSession.shared.data(for: authRequest),
                   let code = (resp as? HTTPURLResponse)?.statusCode,
                   (200..<300).contains(code),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["data"] as? [[String: Any]] {
                    let names = models.compactMap { $0["id"] as? String }
                    if !names.isEmpty { return names }
                }

                // Attempt without auth (some Jan configs serve model list unauthenticated)
                if let (data, resp) = try? await URLSession.shared.data(from: url),
                   let code = (resp as? HTTPURLResponse)?.statusCode,
                   (200..<300).contains(code),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["data"] as? [[String: Any]] {
                    let names = models.compactMap { $0["id"] as? String }
                    if !names.isEmpty { return names }
                }

                return []
            }
        }

        let urlString = normalizedURL(baseURL, path: "v1/models", provider: provider)
        guard let url = URL(string: urlString) else { throw LLMError.invalidURL }
        var request = URLRequest(url: url)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw LLMError.httpError(code) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]]
        else { throw LLMError.decodingFailed }
        return models.compactMap { $0["id"] as? String }
    }

    // MARK: - Private

    private static func chat(system: String, user: String, model: String, baseURL: String, provider: LLMProvider, apiKey: String = "", images: [NSImage] = []) async throws -> String {
        let urlString = normalizedURL(baseURL, path: "v1/chat/completions", provider: provider)
        guard let url = URL(string: urlString) else { throw LLMError.invalidURL }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": try userContent(text: user, images: images)]
            ],
            "stream": false
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            // A text-only model given an image content-part answers 400 rather than
            // anything self-explanatory (measured against a text-only MLX build on
            // Ollama), and a bare "HTTP 400" sends the user looking at their network.
            if code == 400, !images.isEmpty { throw LLMError.modelRejectedImage(model) }
            throw LLMError.httpError(code)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw LLMError.emptyResponse }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds the `content` value for the user message.
    ///
    /// With no images this stays a plain string — the shape every text-only
    /// endpoint has always accepted, so nothing about the existing operations
    /// changes. With images it becomes the OpenAI content-part array, which
    /// Ollama and LM Studio both accept on `/v1/chat/completions` when the model
    /// is vision-capable. A text-only model does not error on this; it either
    /// ignores the image part or answers from the text alone, which is why the
    /// Assist tab warns rather than relying on a failure here.
    private static func userContent(text: String, images: [NSImage]) throws -> Any {
        guard !images.isEmpty else { return text }

        var parts: [[String: Any]] = []
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(["type": "text", "text": text])
        }
        for image in images {
            guard let uri = LLMImageEncoder.dataURI(for: image) else {
                throw LLMError.imageEncodingFailed
            }
            parts.append(["type": "image_url", "image_url": ["url": uri]])
        }
        guard !parts.isEmpty else { throw LLMError.imageEncodingFailed }
        return parts
    }

    private static func normalizedURL(_ base: String, path: String, provider: LLMProvider) -> String {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed

        let hadScheme = trimmed.contains("://")

        if !hadScheme {
            trimmed = "http://\(trimmed)"
        }

        // Only append the default port when the user entered a bare host/IP (no
        // scheme). A URL entered with an explicit scheme is treated as intentional
        // — don't override its port behaviour.
        if !hadScheme, let url = URL(string: trimmed), url.port == nil {
            let defaultPort = URL(string: provider.defaultBaseURL)?.port ?? 11434
            trimmed = "\(trimmed):\(defaultPort)"
        }

        return path.isEmpty ? trimmed : "\(trimmed)/\(path)"
    }
}

// MARK: - Navigation

extension Notification.Name {
    static let tanqueNavigateToSettings = Notification.Name("tanqueStudio.navigateToSettings")
    /// Posted after a successful Settings → Test Connection so views can refresh DT inventory.
    static let tanqueDTConnectionVerified = Notification.Name("tanqueStudio.dtConnectionVerified")
    /// Posted when the LLM Operations folder changes so the Assist tab reloads operations.
    static let tanqueLLMOperationsFolderChanged = Notification.Name("tanqueStudio.llmOperationsFolderChanged")
}
