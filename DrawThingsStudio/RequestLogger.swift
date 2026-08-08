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
        .appendingPathComponent("TanqueStudio/request_log.txt")

    private init() {
        guard let url = logFileURL else { return }
        // Don't rely on ImageStorageManager having created the shared
        // "TanqueStudio" directory first as a side effect of saving an image —
        // on a first run the first request is logged before any image is saved,
        // and every write here is a silent try?, so that first entry would just
        // vanish.
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "TanqueStudio Request Log\n".write(to: url, atomically: true, encoding: .utf8)
        }

        // Turn on the gRPC client's own request/response logging. It reports
        // per-response detail (image count, chunk state, signposts, tags) that
        // nothing else surfaces. Note it goes to os_log under subsystem
        // "com.drawthings.client" — NOT "com.drawthings.kit" as that package's
        // README claims — and every message is a dynamic string logged without
        // `privacy: .public`, so an outside reader (`log stream`) sees
        // `<private>` unless private-data logging is enabled system-wide. It is
        // readable in Xcode's console. The stage trace written to this file is
        // the version that needs no such setup.
        DrawThingsClientLogger.minimumLevel = .debug
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

    func logGRPCRequest(host: String, port: Int, config: DrawThingsConfiguration, prompt: String, negativePrompt: String) {
        var entry = "\n── [\(timestamp())] gRPC → generateImage ──\n"
        // Which server this went to. Two identical requests can succeed on one
        // host and fail on another (models installed differ per machine) — without
        // this line the log can't distinguish them.
        entry += "server:                   \(host):\(port)\n"
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
        entry += "maskBlur:                 \(config.maskBlur)\n"
        entry += "maskBlurOutset:           \(config.maskBlurOutset)\n"
        entry += "preserveOriginalAfterInpaint: \(config.preserveOriginalAfterInpaint)\n"
        entry += "hiresFix:                 \(config.hiresFix)\n"
        if config.hiresFix {
            // Read back from the client's own properties — its didSet floors each
            // to a multiple of 64, so this logs what actually goes on the wire,
            // not what we asked for.
            entry += "hiresFixWidth:            \(config.hiresFixWidth)\n"
            entry += "hiresFixHeight:           \(config.hiresFixHeight)\n"
            entry += "hiresFixStrength:         \(config.hiresFixStrength)\n"
        }
        // Tiling values here are the client's, i.e. already in units of 64 — the
        // pixel figure is what the UI shows. Logged both ways so the ÷64 boundary
        // is verifiable from the log rather than inferred.
        entry += "tiledDiffusion:           \(config.tiledDiffusion)\n"
        if config.tiledDiffusion {
            entry += "diffusionTile:            \(config.diffusionTileWidth)\u{00D7}\(config.diffusionTileHeight) units "
            entry += "(\(config.diffusionTileWidth * 64)\u{00D7}\(config.diffusionTileHeight * 64) px)\n"
            entry += "diffusionTileOverlap:     \(config.diffusionTileOverlap) units (\(config.diffusionTileOverlap * 64) px)\n"
        }
        entry += "tiledDecoding:            \(config.tiledDecoding)\n"
        if config.tiledDecoding {
            entry += "decodingTile:             \(config.decodingTileWidth)\u{00D7}\(config.decodingTileHeight) units "
            entry += "(\(config.decodingTileWidth * 64)\u{00D7}\(config.decodingTileHeight * 64) px)\n"
            entry += "decodingTileOverlap:      \(config.decodingTileOverlap) units (\(config.decodingTileOverlap * 64) px)\n"
        }
        // SDXL size conditioning. Logged only when set — but note what "not set"
        // means downstream: the client substitutes the render's own width/height for
        // any of these left at 0 at encode time, so the FlatBuffer never carries a
        // zero. This line reports what TanqueStudio chose, not what the wire ends up
        // holding, and those differ precisely in the unset case.
        if config.originalImageWidth > 0 || config.targetImageWidth > 0
            || config.negativeOriginalImageWidth > 0 {
            entry += "sdxlOriginalImage:        \(config.originalImageWidth)\u{00D7}\(config.originalImageHeight)\n"
            entry += "sdxlTargetImage:          \(config.targetImageWidth)\u{00D7}\(config.targetImageHeight)\n"
            entry += "sdxlNegativeOriginal:     \(config.negativeOriginalImageWidth)\u{00D7}\(config.negativeOriginalImageHeight)\n"
        }
        if !config.loras.isEmpty {
            entry += "loras:\n"
            for lora in config.loras {
                entry += "  \(lora.file)  weight=\(lora.weight)  mode=\(lora.mode)\n"
            }
        }
        append(entry)
    }

    // MARK: - Response

    /// The client-side watchdog in force for the request just logged. Recorded up
    /// front so a log that ends in a timeout shows what deadline it was measured
    /// against, without having to re-derive it from the config.
    func logGRPCDeadline(seconds: Int) {
        append("deadline:                 \(seconds)s (client-side watchdog)\n")
    }

    func logGRPCResponse(imageCount: Int) {
        append("→ Draw Things returned \(imageCount) image(s)\n")
    }

    func logGRPCTimeout(after seconds: Int) {
        append("→ TIMED OUT after \(seconds)s — Draw Things never answered the render call\n")
    }

    /// The stage sequence Draw Things reported while working on one render.
    ///
    /// This is the only readable view of what the server actually did. Draw
    /// Things emits its own diagnostics through swift-log's default handler,
    /// which writes to **stdout** — discarded entirely when the app is launched
    /// from Finder — and it registers nothing with the unified log, so
    /// `log show`/`log stream` return nothing for it. Meanwhile the progress
    /// poller in `DrawThingsGRPCClient` already sees every stage and throws away
    /// the ones it can't turn into a percentage (text encoding, upscale, face
    /// restore) — which are precisely the ones that say how far a render that
    /// produced no image actually got before it stopped.
    func logGRPCStages(_ summary: String) {
        append("\(summary)\n")
    }

    // MARK: - Utilities

    func clearLog() {
        guard let url = logFileURL else { return }
        try? "TanqueStudio Request Log\n".write(to: url, atomically: true, encoding: .utf8)
    }

    func openLog() {
        guard let url = logFileURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    /// Serial queue ensures concurrent callers (e.g. HTTP and gRPC in parallel)
    /// do not interleave writes and corrupt the log file.
    private let writeQueue = DispatchQueue(
        label: "com.tanquestudio.requestlogger",
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
