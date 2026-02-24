//
//  ImageStorageManager.swift
//  DrawThingsStudio
//
//  Manages auto-saving generated images to ~/Pictures/DrawThingsStudio/
//

import Foundation
import AppKit
import Combine
import OSLog
import ImageIO
import UniformTypeIdentifiers

/// Manages persistent storage of generated images and their metadata
@MainActor
final class ImageStorageManager: ObservableObject {
    static let shared = ImageStorageManager()

    private let logger = Logger(subsystem: "com.drawthingsstudio", category: "image-storage")

    // Reused across calls — ISO8601DateFormatter is expensive to allocate.
    private static let filenameFormatter = ISO8601DateFormatter()

    private let storageDirectory: URL

    @Published var savedImages: [GeneratedImage] = []

    // MARK: - Initialization

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.storageDirectory = appSupport.appendingPathComponent("DrawThingsStudio/GeneratedImages", isDirectory: true)
        ensureDirectoryExists()
    }

    // MARK: - Public Methods

    /// Save a generated image to disk with metadata sidecar
    func saveImage(_ image: NSImage, prompt: String, negativePrompt: String, config: DrawThingsGenerationConfig, inferenceTimeMs: Int?) -> GeneratedImage? {
        // Ensure directory exists before saving
        ensureDirectoryExists()

        let timestamp = Self.filenameFormatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "T", with: "_")
        let filename = "gen_\(timestamp)_\(UUID().uuidString.prefix(8))"

        let imageURL = storageDirectory.appendingPathComponent("\(filename).png")
        let metadataURL = storageDirectory.appendingPathComponent("\(filename).json")

        // Build A1111 parameters text (used in both EXIF fields and iTXt chunk)
        let parametersText = buildA1111Parameters(prompt: prompt, negativePrompt: negativePrompt, config: config)

        // Save PNG with TIFF/IPTC/EXIF metadata embedded via CGImageDestination
        // (TIFF ImageDescription + IPTC Caption-Abstract appear in Finder Get Info)
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmapRep.cgImage else {
            logger.error("Failed to convert image to CGImage")
            return nil
        }

        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData, UTType.png.identifier as CFString, 1, nil
        ) else {
            logger.error("Failed to create CGImageDestination")
            return nil
        }

        let imageProps: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFImageDescription: parametersText
            ] as [CFString: Any],
            kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCCaptionAbstract: parametersText
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifUserComment: parametersText
            ] as [CFString: Any]
        ]

        CGImageDestinationAddImage(dest, cgImage, imageProps as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            logger.error("Failed to finalize CGImageDestination")
            return nil
        }

        // Also inject A1111 iTXt chunk for compatibility with A1111/ComfyUI tools
        let basePngData = mutableData as Data
        let pngWithMeta = injectPNGTextChunk(into: basePngData, keyword: "parameters", text: parametersText)

        do {
            try pngWithMeta.write(to: imageURL)
        } catch {
            logger.error("Failed to write image file: \(error.localizedDescription)")
            return nil
        }

        // Save metadata sidecar
        let metadata = ImageMetadata(
            prompt: prompt,
            negativePrompt: negativePrompt,
            config: config,
            generatedAt: Date(),
            inferenceTimeMs: inferenceTimeMs
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(metadata)
            try jsonData.write(to: metadataURL)
        } catch {
            logger.warning("Failed to write metadata file: \(error.localizedDescription)")
            // Non-fatal: image is saved even without metadata
        }

        let generatedImage = GeneratedImage(
            image: image,
            prompt: prompt,
            negativePrompt: negativePrompt,
            config: config,
            generatedAt: Date(),
            inferenceTimeMs: inferenceTimeMs,
            filePath: imageURL
        )

        savedImages.insert(generatedImage, at: 0)
        logger.info("Saved image to \(imageURL.path)")
        return generatedImage
    }

    /// Load previously saved images from disk
    func loadSavedImages() {
        ensureDirectoryExists()

        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let pngFiles = files
            .filter { $0.pathExtension == "png" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }

        var loaded: [GeneratedImage] = []
        for pngURL in pngFiles {
            guard let image = NSImage(contentsOf: pngURL) else { continue }

            let metadataURL = pngURL.deletingPathExtension().appendingPathExtension("json")
            var prompt = ""
            var negativePrompt = ""
            var config = DrawThingsGenerationConfig()
            var generatedAt = (try? pngURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            var inferenceTimeMs: Int?

            if let metadataData = try? Data(contentsOf: metadataURL),
               let metadata = try? JSONDecoder().decode(ImageMetadata.self, from: metadataData) {
                prompt = metadata.prompt
                negativePrompt = metadata.negativePrompt
                config = metadata.config
                generatedAt = metadata.generatedAt
                inferenceTimeMs = metadata.inferenceTimeMs
            }

            loaded.append(GeneratedImage(
                image: image,
                prompt: prompt,
                negativePrompt: negativePrompt,
                config: config,
                generatedAt: generatedAt,
                inferenceTimeMs: inferenceTimeMs,
                filePath: pngURL
            ))
        }

        savedImages = loaded
        logger.info("Loaded \(loaded.count) saved images from disk")
    }

    /// Delete a saved image and its metadata
    func deleteImage(_ generatedImage: GeneratedImage) {
        guard let filePath = generatedImage.filePath else { return }

        let fileManager = FileManager.default
        try? fileManager.removeItem(at: filePath)

        let metadataURL = filePath.deletingPathExtension().appendingPathExtension("json")
        try? fileManager.removeItem(at: metadataURL)

        savedImages.removeAll { $0.id == generatedImage.id }
        logger.info("Deleted image at \(filePath.path)")
    }

    /// Reveal image in Finder
    func revealInFinder(_ generatedImage: GeneratedImage) {
        guard let filePath = generatedImage.filePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([filePath])
    }

    /// Copy image to clipboard
    func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    /// Open storage directory in Finder
    func openStorageDirectory() {
        NSWorkspace.shared.open(storageDirectory)
    }

    // MARK: - Private

    // MARK: - PNG Metadata Embedding

    /// Builds an A1111-compatible "parameters" text block.
    /// Format read back by DTS Image Inspector (parseA1111) and compatible with
    /// tools like automatic1111, ComfyUI manager, etc.
    private func buildA1111Parameters(prompt: String, negativePrompt: String, config: DrawThingsGenerationConfig) -> String {
        var lines: [String] = [prompt]

        if !negativePrompt.isEmpty {
            lines.append("Negative prompt: \(negativePrompt)")
        }

        var params: [String] = []
        params.append("Steps: \(config.steps)")
        params.append("Sampler: \(config.sampler)")
        params.append("CFG scale: \(String(format: "%.1f", config.guidanceScale))")
        if config.seed >= 0 {
            params.append("Seed: \(config.seed)")
        }
        params.append("Size: \(config.width)x\(config.height)")
        if !config.model.isEmpty {
            params.append("Model: \(config.model)")
        }
        if config.strength < 1.0 {
            params.append("Denoising strength: \(String(format: "%.2f", config.strength))")
        }

        lines.append(params.joined(separator: ", "))
        return lines.joined(separator: "\n")
    }

    /// Inserts an uncompressed PNG iTXt chunk carrying `keyword` / `text` (UTF-8)
    /// immediately after the IHDR chunk.  PNG structure:
    ///   8-byte signature | IHDR (always 25 bytes) | … other chunks … | IEND
    /// Chunk layout: [4-byte big-endian data-length][4-byte type][data][4-byte CRC32]
    /// iTXt data:    keyword\0 + compressionFlag(0) + compressionMethod(0) +
    ///               languageTag\0 + translatedKeyword\0 + text-utf8
    private func injectPNGTextChunk(into pngData: Data, keyword: String, text: String) -> Data {
        // Validate PNG signature (8 bytes) + at least one IHDR chunk header (8 bytes)
        guard pngData.count > 16 else { return pngData }

        // Locate end of IHDR: signature(8) + length(4) + type(4) + data(length) + crc(4)
        let ihdrDataLength = Int(pngData[8]) << 24 | Int(pngData[9]) << 16 |
                             Int(pngData[10]) << 8 | Int(pngData[11])
        let insertOffset = 8 + 4 + 4 + ihdrDataLength + 4  // right after IHDR CRC

        guard insertOffset < pngData.count else { return pngData }

        // Build iTXt chunk data
        var chunkData = Data()
        chunkData.append(contentsOf: keyword.utf8)
        chunkData.append(0)     // null after keyword
        chunkData.append(0)     // compression flag: 0 = not compressed
        chunkData.append(0)     // compression method: 0
        chunkData.append(0)     // language tag: empty, null-terminated
        chunkData.append(0)     // translated keyword: empty, null-terminated
        chunkData.append(contentsOf: text.utf8)

        // CRC32 of chunk type bytes + chunk data
        var crcInput = Data("iTXt".utf8)
        crcInput.append(chunkData)
        let checksum = pngCRC32(crcInput)

        // Full chunk: length(4) + type(4) + data + crc(4)
        var chunk = Data()
        var lengthBE = UInt32(chunkData.count).bigEndian
        withUnsafeBytes(of: &lengthBE) { chunk.append(contentsOf: $0) }
        chunk.append(contentsOf: "iTXt".utf8)
        chunk.append(chunkData)
        var crcBE = checksum.bigEndian
        withUnsafeBytes(of: &crcBE) { chunk.append(contentsOf: $0) }

        // Splice chunk into PNG data right after IHDR
        var result = pngData
        result.insert(contentsOf: chunk, at: insertOffset)
        return result
    }

    /// CRC-32 using the IEEE 802.3 polynomial (same as used by PNG/zlib).
    private func pngCRC32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (0xEDB8_8320 & ~((crc & 1) &- 1))
            }
        }
        return ~crc
    }

    private func ensureDirectoryExists() {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: storageDirectory.path, isDirectory: &isDirectory)

        if !exists || !isDirectory.boolValue {
            do {
                try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true, attributes: nil)
                logger.info("Created storage directory at \(self.storageDirectory.path)")
            } catch {
                logger.error("Failed to create storage directory: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Metadata Model

private struct ImageMetadata: Codable {
    let prompt: String
    let negativePrompt: String
    let config: DrawThingsGenerationConfig
    let generatedAt: Date
    let inferenceTimeMs: Int?
}
