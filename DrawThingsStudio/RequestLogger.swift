//
//  RequestLogger.swift
//  DrawThingsStudio
//
//  Logs outgoing Draw Things requests (HTTP and gRPC) to a local file for debugging.
//

import Foundation
import AppKit
import DrawThingsClient

final class RequestLogger {
    static let shared = RequestLogger()

    let logFileURL: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("DrawThingsStudio/request_log.txt")

    private init() {
        if let url = logFileURL, !FileManager.default.fileExists(atPath: url.path) {
            try? "DrawThingsStudio Request Log\n".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - HTTP

    func logHTTPRequest(endpoint: String, body: [String: Any]) {
        var entry = "\n── [\(timestamp())] HTTP → \(endpoint) ──\n"

        // Redact base64 image blobs — they're huge and unreadable
        var loggable = body
        if let images = loggable["init_images"] as? [String] {
            loggable["init_images"] = ["<base64 png, \(images.first?.count ?? 0) chars>"]
        }
        if loggable["mask"] is String {
            loggable["mask"] = "<base64 mask>"
        }

        if let data = try? JSONSerialization.data(withJSONObject: loggable, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            entry += json + "\n"
        }

        append(entry)
    }

    // MARK: - gRPC

    func logGRPCRequest(config: DrawThingsConfiguration, prompt: String, negativePrompt: String) {
        var entry = "\n── [\(timestamp())] gRPC → generateImage ──\n"
        entry += "prompt:                   \(prompt.prefix(200))\n"
        if !negativePrompt.isEmpty {
            entry += "negativePrompt:           \(negativePrompt.prefix(200))\n"
        }
        entry += "model:                    \(config.model)\n"
        entry += "sampler:                  \(config.sampler)\n"
        entry += "width:                    \(config.width)\n"
        entry += "height:                   \(config.height)\n"
        entry += "steps:                    \(config.steps)\n"
        entry += "guidanceScale:            \(config.guidanceScale)\n"
        entry += "seed:                     \(config.seed.map { String($0) } ?? "random (nil)")\n"
        entry += "shift:                    \(config.shift)\n"
        entry += "strength:                 \(config.strength)\n"
        entry += "batchCount:               \(config.batchCount)\n"
        entry += "batchSize:                \(config.batchSize)\n"
        entry += "numFrames:                \(config.numFrames)\n"
        entry += "t5TextEncoder:            \(config.t5TextEncoder)\n"
        entry += "resolutionDependentShift: \(config.resolutionDependentShift)\n"
        entry += "cfgZeroStar:              \(config.cfgZeroStar)\n"
        entry += "stochasticSamplingGamma:  \(config.stochasticSamplingGamma)\n"
        if !config.loras.isEmpty {
            entry += "loras:\n"
            for lora in config.loras {
                entry += "  \(lora.file)  weight=\(lora.weight)  mode=\(lora.mode)\n"
            }
        }
        append(entry)
    }

    // MARK: - Response

    func logGRPCResponse(imageCount: Int) {
        append("→ Draw Things returned \(imageCount) image(s)\n")
    }

    // MARK: - Utilities

    func clearLog() {
        guard let url = logFileURL else { return }
        try? "DrawThingsStudio Request Log\n".write(to: url, atomically: true, encoding: .utf8)
    }

    func openLog() {
        guard let url = logFileURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    /// Serial queue ensures concurrent callers (e.g. HTTP and gRPC in parallel)
    /// do not interleave writes and corrupt the log file.
    private let writeQueue = DispatchQueue(
        label: "com.drawthingsstudio.requestlogger",
        qos: .background
    )

    private func append(_ text: String) {
        // Do NOT emit to OSLog — request bodies contain user prompts (PII).
        // The local file already captures everything needed for debugging.
        guard let url = logFileURL,
              let data = text.data(using: .utf8) else { return }
        writeQueue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    // Reused across calls to avoid allocating a new DateFormatter on every log entry.
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private func timestamp() -> String {
        Self.timestampFormatter.string(from: Date())
    }
}
