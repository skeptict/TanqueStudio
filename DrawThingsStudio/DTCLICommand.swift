//
//  DTCLICommand.swift
//  Tanque Studio
//
//  Generate's settings as a `draw-things-cli generate` command to paste into a terminal.
//  The CLI takes the same flat JSON Draw Things copies to the clipboard (its
//  JSGenerationConfiguration format), so the config half is DTConfigExporter's output.
//
//  One difference matters: the CLI *merges* --config-json onto the model's recommended
//  settings, key by key. A key we leave out takes the recommended value, so anything
//  the clipboard omits when it's off has to be written out as off here, or the model's
//  recommendation turns it back on.
//

import Foundation

enum DTCLICommand {

    /// Where the CLI runs the generation.
    enum Backend: Equatable {
        /// Models on the Mac the command is pasted on — usually the Draw Things Mac.
        case local
        /// The Draw Things server on the Mac the command is pasted on, always as
        /// `localhost`. The CLI checks the server's certificate against the hostname, and
        /// Draw Things' certificate names only localhost, so a LAN address times out
        /// ("Remote echo timed out.") even when the server is up (CLI v26.1023.0).
        case server(port: Int)
        /// Draw Things cloud compute. Needs `draw-things-cli auth login` once.
        case cloud
    }

    static let executable = "draw-things-cli"

    /// The full command, one option per line. Nil when there is no model to name.
    static func make(config: DrawThingsGenerationConfig, prompt: String, negativePrompt: String,
                     backend: Backend, outputName: String) -> String? {
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, let json = configJSON(for: config) else { return nil }

        var lines = ["\(executable) generate"]
        switch backend {
        case .local:
            break
        case let .server(port):
            lines.append("--remote --remote-url localhost --remote-port \(port)")
        case .cloud:
            lines.append("--cloud-compute")
        }
        lines.append("--model \(shellQuote(model))")
        lines.append("--prompt \(shellQuote(prompt))")
        // Always passed, even empty: left out, the model's recommended negative prompt
        // would apply, and Generate sends exactly what's in the box.
        lines.append("--negative-prompt \(shellQuote(negativePrompt))")
        lines.append("--config-json \(shellQuote(json))")
        lines.append("--output \(shellQuote(outputName))")
        return lines.joined(separator: " \\\n  ")
    }

    /// The config Generate would actually send: dimensions snapped to 64, the RDS shift
    /// applied, and with Randomize on, a fresh seed — written into the command so the
    /// result can be reproduced, not left to the CLI.
    static func prepared(_ config: DrawThingsGenerationConfig, randomizeSeed: Bool) -> DrawThingsGenerationConfig {
        var cfg = config
        _ = cfg.snapDimensionsTo64()
        cfg.applyRDSShiftIfNeeded()
        if randomizeSeed {
            cfg.seed = Int(UInt32.random(in: 0...UInt32.max))
        }
        return cfg
    }

    /// DTConfigExporter's clipboard JSON, adjusted for the CLI's merge (see the header).
    static func configJSON(for config: DrawThingsGenerationConfig) -> String? {
        guard let clipboard = DTConfigExporter.encodeDTClipboard(config: config),
              let data = clipboard.data(using: .utf8),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // --model names it, and the CLI overwrites this key with the resolved file anyway.
        dict.removeValue(forKey: "model")
        // The clipboard omits these when they're off; here that would mean "recommended".
        for key in ["hiresFix", "tiledDecoding", "tiledDiffusion"] where dict[key] == nil {
            dict[key] = false
        }
        // 0 means "the model's default" in Tanque Studio. Sent as 0, the CLI would ask
        // for zero frames, so leave it to the recommended settings instead.
        if config.numFrames <= 0 {
            dict.removeValue(forKey: "numFrames")
        }

        guard let out = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        else { return nil }
        return String(data: out, encoding: .utf8)
    }

    /// A default output file in the terminal's current directory.
    static func outputName(for config: DrawThingsGenerationConfig, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let isVideo = config.isVideoModel || config.numFrames > 1
        return "tanque-\(formatter.string(from: date)).\(isVideo ? "mp4" : "png")"
    }

    /// POSIX single-quoting, safe in zsh and bash for any text, newlines included.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
