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

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "HTTP \(code)"
        case .emptyResponse:       return "LLM returned an empty response"
        case .invalidURL:          return "Invalid base URL"
        case .decodingFailed:      return "Failed to decode LLM response"
        }
    }
}

// MARK: - LLM Service

struct LLMService {

    /// Run an arbitrary LLM operation defined by a system prompt.
    /// Used by AssistTabView with the selected LLMOperation's systemPrompt.
    static func runOperation(
        systemPrompt: String,
        input: String,
        model: String,
        baseURL: String,
        provider: LLMProvider
    ) async throws -> String {
        return try await chat(
            system: systemPrompt,
            user: input,
            model: model,
            baseURL: baseURL,
            provider: provider
        )
    }

    /// Fetch available model IDs from the /v1/models endpoint.
    /// For Jan: the /v1/models endpoint requires an API key and returns HTTP 403.
    /// We test reachability via GET on the base URL root instead and return [] —
    /// an empty model list is acceptable; the user enters the model name manually.
    static func fetchModels(baseURL: String, provider: LLMProvider) async throws -> [String] {
        if provider == .jan {
            // Jan requires an API key for /v1/models (returns 403). Test reachability
            // via the root URL instead — any HTTP response means the server is up.
            let rootString = normalizedURL(baseURL, path: "", provider: provider)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let url = URL(string: rootString) else { throw LLMError.invalidURL }
            _ = try await URLSession.shared.data(from: url)
            // Any response (200, 403, etc.) means Jan is reachable; return empty list.
            return []
        }

        let urlString = normalizedURL(baseURL, path: "v1/models", provider: provider)
        guard let url = URL(string: urlString) else { throw LLMError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw LLMError.httpError(code) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]]
        else { throw LLMError.decodingFailed }
        return models.compactMap { $0["id"] as? String }
    }

    // MARK: - Private

    private static func chat(system: String, user: String, model: String, baseURL: String, provider: LLMProvider) async throws -> String {
        let urlString = normalizedURL(baseURL, path: "v1/chat/completions", provider: provider)
        guard let url = URL(string: urlString) else { throw LLMError.invalidURL }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": user]
            ],
            "stream": false
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw LLMError.httpError(code) }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw LLMError.emptyResponse }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedURL(_ base: String, path: String, provider: LLMProvider) -> String {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed

        // Prepend scheme if missing
        if !trimmed.contains("://") {
            trimmed = "http://\(trimmed)"
        }

        // Append default port if no port is present after the host
        // Parse the URL to check — if no port, append provider default
        if let url = URL(string: trimmed), url.port == nil {
            let defaultPort = URL(string: provider.defaultBaseURL)?.port ?? 11434
            trimmed = "\(trimmed):\(defaultPort)"
        }

        return "\(trimmed)/\(path)"
    }
}

// MARK: - Navigation

extension Notification.Name {
    static let tanqueNavigateToSettings = Notification.Name("tanqueStudio.navigateToSettings")
}
