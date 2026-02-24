//
//  DrawThingsHTTPClient.swift
//  DrawThingsStudio
//
//  HTTP client for Draw Things API (port 7860)
//

import Foundation
import AppKit
import OSLog

/// HTTP client for Draw Things image generation API
final class DrawThingsHTTPClient: DrawThingsProvider {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.drawthingsstudio", category: "drawthings-http")

    let transport: DrawThingsTransport = .http

    private let host: String
    private let port: Int
    private let sharedSecret: String
    private let session: URLSession

    private var baseURL: URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        return components.url
    }

    private func validatedBaseURL() throws -> URL {
        guard let baseURL else {
            throw DrawThingsError.invalidConfiguration("Invalid Draw Things HTTP address (\(host):\(port))")
        }
        return baseURL
    }

    // MARK: - Initialization

    init(host: String = "127.0.0.1", port: Int = 7860, sharedSecret: String = "") {
        self.host = host
        self.port = port
        self.sharedSecret = sharedSecret

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    // MARK: - Connection Check

    func checkConnection() async -> Bool {
        do {
            guard let baseURL else {
                logger.error("Invalid Draw Things HTTP address: \(self.host):\(self.port)")
                return false
            }

            let url = baseURL.appendingPathComponent("sdapi/v1/options")
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            applyAuth(&request)

            let (_, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            let success = httpResponse.statusCode == 200
            if success {
                logger.info("Connected to Draw Things HTTP API at \(self.host):\(self.port)")
            }
            return success
        } catch {
            logger.error("Failed to connect to Draw Things: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Image Generation

    func generateImage(
        prompt: String,
        sourceImage: NSImage?,
        mask: NSImage?,
        config: DrawThingsGenerationConfig,
        onProgress: ((GenerationProgress) -> Void)?
    ) async throws -> [NSImage] {
        onProgress?(.starting)

        // Use img2img endpoint if source image provided, otherwise txt2img
        let isImg2Img = sourceImage != nil
        let endpoint = isImg2Img ? "sdapi/v1/img2img" : "sdapi/v1/txt2img"
        let url = try validatedBaseURL().appendingPathComponent(endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)

        var body = config.toRequestBody(prompt: prompt)

        // Add source image for img2img
        if let sourceImage = sourceImage {
            if let base64 = imageToBase64(sourceImage) {
                body["init_images"] = [base64]
                // A1111-compatible API uses denoising_strength for img2img
                body["denoising_strength"] = config.strength
                logger.debug("Using img2img with source image, strength=\(config.strength)")
            }
        }

        // Add mask for inpainting
        if let mask = mask {
            if let base64 = imageToBase64(mask) {
                body["mask"] = base64
                logger.debug("Using mask for inpainting")
            }
        }

        RequestLogger.shared.logHTTPRequest(endpoint: endpoint, body: body)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.debug("Sending \(isImg2Img ? "img2img" : "txt2img") request")

        onProgress?(.sampling(step: 0, totalSteps: config.steps))

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DrawThingsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Generation failed with status \(httpResponse.statusCode): \(errorMessage)")
            throw DrawThingsError.requestFailed(httpResponse.statusCode, errorMessage)
        }

        onProgress?(.decoding)

        let images = try decodeImageResponse(data)

        onProgress?(.complete)

        logger.info("Generated \(images.count) image(s) via \(isImg2Img ? "img2img" : "txt2img")")
        return images
    }

    // MARK: - Fetch Models

    func fetchModels() async throws -> [DrawThingsModel] {
        let url = try validatedBaseURL().appendingPathComponent("sdapi/v1/sd-models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        applyAuth(&request)

        logger.debug("Fetching models from \(url.absoluteString)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DrawThingsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Failed to fetch models: \(httpResponse.statusCode) - \(errorMessage)")
            throw DrawThingsError.requestFailed(httpResponse.statusCode, errorMessage)
        }

        // Try to parse response - could be an array or object
        let json = try JSONSerialization.jsonObject(with: data)

        var models: [DrawThingsModel] = []

        if let jsonArray = json as? [[String: Any]] {
            // Array of model objects (SD WebUI format)
            models = jsonArray.compactMap { dict -> DrawThingsModel? in
                // SD WebUI format: {"title": "model name", "model_name": "filename", "filename": "path"}
                if let title = dict["title"] as? String {
                    let modelName = dict["model_name"] as? String ?? title
                    return DrawThingsModel(name: title, filename: modelName)
                } else if let modelName = dict["model_name"] as? String {
                    return DrawThingsModel(filename: modelName)
                } else if let name = dict["name"] as? String {
                    let filename = dict["filename"] as? String ?? name
                    return DrawThingsModel(name: name, filename: filename)
                }
                return nil
            }
        } else if let stringArray = json as? [String] {
            // Simple array of model names/filenames
            models = stringArray.map { DrawThingsModel(filename: $0) }
        } else if let jsonDict = json as? [String: Any] {
            // Object with models array inside
            if let modelList = jsonDict["models"] as? [String] {
                models = modelList.map { DrawThingsModel(filename: $0) }
            } else if let modelList = jsonDict["data"] as? [[String: Any]] {
                models = modelList.compactMap { dict -> DrawThingsModel? in
                    if let name = dict["name"] as? String {
                        return DrawThingsModel(filename: name)
                    }
                    return nil
                }
            }
        }

        logger.info("Fetched \(models.count) models from Draw Things")
        return models
    }

    // MARK: - Fetch LoRAs

    func fetchLoRAs() async throws -> [DrawThingsLoRA] {
        let url = try validatedBaseURL().appendingPathComponent("sdapi/v1/loras")
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        applyAuth(&request)

        logger.debug("Fetching LoRAs from \(url.absoluteString)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DrawThingsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Failed to fetch LoRAs: \(httpResponse.statusCode) - \(errorMessage)")
            throw DrawThingsError.requestFailed(httpResponse.statusCode, errorMessage)
        }

        // Try to parse response - could be an array or object
        let json = try JSONSerialization.jsonObject(with: data)

        var loras: [DrawThingsLoRA] = []

        if let jsonArray = json as? [[String: Any]] {
            // Array of LoRA objects (SD WebUI format)
            loras = jsonArray.compactMap { dict -> DrawThingsLoRA? in
                if let name = dict["name"] as? String {
                    let filename = dict["path"] as? String ?? name
                    return DrawThingsLoRA(name: name, filename: filename)
                } else if let alias = dict["alias"] as? String {
                    return DrawThingsLoRA(filename: alias)
                }
                return nil
            }
        } else if let stringArray = json as? [String] {
            // Simple array of LoRA names/filenames
            loras = stringArray.map { DrawThingsLoRA(filename: $0) }
        } else if let jsonDict = json as? [String: Any] {
            // Object with loras array inside
            if let loraList = jsonDict["loras"] as? [String] {
                loras = loraList.map { DrawThingsLoRA(filename: $0) }
            } else if let loraList = jsonDict["data"] as? [[String: Any]] {
                loras = loraList.compactMap { dict -> DrawThingsLoRA? in
                    if let name = dict["name"] as? String {
                        return DrawThingsLoRA(filename: name)
                    }
                    return nil
                }
            }
        }

        logger.info("Fetched \(loras.count) LoRAs from Draw Things")
        return loras
    }

    // MARK: - Image Encoding

    private func imageToBase64(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            logger.warning("Failed to convert image to PNG for base64 encoding")
            return nil
        }
        return pngData.base64EncodedString()
    }

    // MARK: - Private Helpers

    private func applyAuth(_ request: inout URLRequest) {
        if !sharedSecret.isEmpty {
            request.setValue("Bearer \(sharedSecret)", forHTTPHeaderField: "Authorization")
        }
    }

    private func decodeImageResponse(_ data: Data) throws -> [NSImage] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DrawThingsError.invalidResponse
        }

        guard let imagesArray = json["images"] as? [String] else {
            // Some Draw Things versions return a different format
            if let singleImage = json["image"] as? String {
                guard let imageData = Data(base64Encoded: singleImage),
                      let nsImage = NSImage(data: imageData) else {
                    throw DrawThingsError.imageDecodingFailed
                }
                return [nsImage]
            }
            throw DrawThingsError.invalidResponse
        }

        var images: [NSImage] = []
        for base64String in imagesArray {
            // Strip data URI prefix if present
            let cleanBase64 = base64String.replacingOccurrences(
                of: "^data:image/[^;]+;base64,",
                with: "",
                options: .regularExpression
            )

            guard let imageData = Data(base64Encoded: cleanBase64),
                  let nsImage = NSImage(data: imageData) else {
                logger.warning("Failed to decode one image from response")
                continue
            }
            images.append(nsImage)
        }

        if images.isEmpty {
            throw DrawThingsError.imageDecodingFailed
        }

        return images
    }
}
