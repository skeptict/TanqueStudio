//
//  DTVideoExporter.swift
//  DrawThingsStudio
//
//  Exports frames or a DTVideoClip to a .mov file using AVAssetWriter.
//
//  Design note: all work (including the finishWriting wait) runs synchronously on
//  DispatchQueue.global inside a single outer withCheckedThrowingContinuation.
//  This avoids nested Swift Concurrency continuations and executor hops inside the
//  export path, which on macOS 26 beta caused swift_task_isMainExecutorImpl to read
//  a dangling executor reference during concurrent _SwiftData_SwiftUI layout passes.
//

import Foundation
import AVFoundation
import AppKit

// MARK: - Error

enum DTVideoExportError: LocalizedError {
    case noFrames
    case invalidDimensions
    case databaseUnavailable
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noFrames:             return "No frames to export"
        case .invalidDimensions:    return "Invalid frame dimensions — cannot create video"
        case .databaseUnavailable:  return "Could not open source database for export"
        case .writerFailed(let m):  return "Export failed: \(m)"
        }
    }
}

// MARK: - Exporter

/// Exports frames or a `DTVideoClip` to a temporary .mov file.
/// The caller is responsible for moving the result to the final destination.
struct DTVideoExporter {

    // MARK: exportFrames

    /// Export a flat array of images to a temporary .mov.
    /// Runs entirely on DispatchQueue.global — no Swift Concurrency executor hops.
    static func exportFrames(
        _ frames: [NSImage],
        fps: Double = 16.0,
        prompt: String = "",
        config: DrawThingsGenerationConfig
    ) async throws -> URL {
        let width  = config.width  > 0 ? config.width  : Int(frames.first?.size.width  ?? 0)
        let height = config.height > 0 ? config.height : Int(frames.first?.size.height ?? 0)
        let meta   = buildMetadata(prompt: prompt, config: config, width: width, height: height)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let url = try _write(frames: frames, width: width, height: height,
                                        fps: fps, metadata: meta)
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: export(clip:)

    /// Export a `DTVideoClip`, loading full-size thumbnails from the project database.
    static func export(clip: DTVideoClip, fps: Double = 8.0, projectURL: URL) async throws -> URL {
        let frames = clip.frames
        guard !frames.isEmpty else { throw DTVideoExportError.noFrames }

        let width  = clip.width  > 0 ? clip.width  : 512
        let height = clip.height > 0 ? clip.height : 512

        // Build a synthetic config for metadata
        var cfg = DrawThingsGenerationConfig()
        cfg.width = width; cfg.height = height
        cfg.seed = Int(clip.seed); cfg.steps = clip.steps
        cfg.guidanceScale = Double(clip.guidanceScale)
        cfg.sampler = clip.sampler; cfg.model = clip.model
        cfg.loras = clip.loras.map { .init(file: $0.file, weight: Double($0.weight)) }
        let meta = buildMetadata(prompt: clip.prompt, config: cfg, width: width, height: height)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Open DB on the background thread (read-only, safe alongside main connection)
                guard let db = DTProjectDatabase(fileURL: projectURL) else {
                    continuation.resume(throwing: DTVideoExportError.databaseUnavailable)
                    return
                }
                let images: [NSImage] = frames.map { frame in
                    db.fetchFullSizeThumbnail(previewId: frame.previewId)
                        ?? frame.thumbnail
                        ?? NSImage(size: NSSize(width: width, height: height))
                }
                do {
                    let url = try _write(frames: images, width: width, height: height,
                                        fps: fps, metadata: meta)
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Private helpers

    /// Synchronous AVAssetWriter export. Must be called from a non-cooperative thread
    /// (e.g. DispatchQueue.global) so that DispatchSemaphore.wait() is safe.
    private static func _write(
        frames: [NSImage],
        width: Int,
        height: Int,
        fps: Double,
        metadata: [AVMetadataItem]
    ) throws -> URL {
        guard !frames.isEmpty else { throw DTVideoExportError.noFrames }
        guard width > 0, height > 0 else { throw DTVideoExportError.invalidDimensions }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey:  width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(width * height * 2, 500_000),
                AVVideoProfileLevelKey:   AVVideoProfileLevelH264HighAutoLevel
            ] as [String: Any]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey  as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        writer.metadata = metadata
        writer.add(writerInput)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        for (index, image) in frames.enumerated() {
            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(index))
            if let pb = image.toDTCVPixelBuffer(width: width, height: height) {
                if !DTAppendPixelBufferSafely(adaptor, pb, pts) { break }
            }
        }

        writerInput.markAsFinished()

        // DispatchSemaphore is safe here because we're on a DispatchQueue thread, not a
        // Swift cooperative thread. This avoids any Swift Concurrency executor transition
        // inside the export path.
        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting { sema.signal() }
        sema.wait()

        if let error = writer.error { throw DTVideoExportError.writerFailed(error.localizedDescription) }
        return outputURL
    }

    private static func buildMetadata(
        prompt: String,
        config: DrawThingsGenerationConfig,
        width: Int,
        height: Int
    ) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        if !prompt.isEmpty {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierTitle
            item.locale = Locale(identifier: "und")
            item.value = String(prompt.prefix(255)) as NSString
            items.append(item)
        }
        let parts: [String] = [
            config.model.isEmpty ? nil : "Model: \(config.model)",
            "Seed: \(config.seed)",
            config.steps > 0 ? "Steps: \(config.steps)" : nil,
            "Guidance: \(config.guidanceScale)",
            "Sampler: \(config.sampler)",
            "\(width)×\(height)",
            config.loras.isEmpty ? nil : config.loras.map {
                "LoRA: \($0.file) @ \(String(format: "%.2f", $0.weight))"
            }.joined(separator: ", ")
        ].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierDescription
            item.locale = Locale(identifier: "und")
            item.value = parts.joined(separator: "\n") as NSString
            items.append(item)
        }
        return items
    }
}

// MARK: - NSImage → CVPixelBuffer

private extension NSImage {
    /// Convert to a 32-BGRA CVPixelBuffer scaled to fill `width × height`.
    func toDTCVPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey:               kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey:                         width,
            kCVPixelBufferHeightKey:                        height,
            kCVPixelBufferCGImageCompatibilityKey:          true,
            kCVPixelBufferCGBitmapContextCompatibilityKey:  true
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb
        ) == kCVReturnSuccess, let pixelBuffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: baseAddr,
                width: width, height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))

        var rect = CGRect(origin: .zero, size: self.size)
        guard let cgImg = cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }

        let sx = CGFloat(width)  / self.size.width
        let sy = CGFloat(height) / self.size.height
        let s  = max(sx, sy)
        let dw = self.size.width  * s
        let dh = self.size.height * s
        let dx = (CGFloat(width)  - dw) / 2
        let dy = (CGFloat(height) - dh) / 2

        ctx.draw(cgImg, in: CGRect(x: dx, y: dy, width: dw, height: dh))
        return pixelBuffer
    }
}
