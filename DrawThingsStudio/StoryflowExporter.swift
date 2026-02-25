//
//  StoryflowExporter.swift
//  DrawThingsStudio
//
//  JSON export functionality for StoryFlow instructions
//

import Foundation
import AppKit
import UniformTypeIdentifiers

/// Errors that can occur during export
enum ExportError: LocalizedError {
    case encodingFailed
    case fileWriteFailed(path: String)
    case invalidInstructions

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode instructions to JSON"
        case .fileWriteFailed(let path):
            return "Failed to write file to: \(path)"
        case .invalidInstructions:
            return "Instructions array is empty or invalid"
        }
    }
}

/// Handles exporting StoryFlow instructions to various formats
final class StoryflowExporter {

    // MARK: - JSON Export

    /// Export instructions to a formatted JSON string
    /// - Parameter instructions: Array of instruction dictionaries
    /// - Returns: Pretty-printed JSON string
    func exportToJSON(instructions: [[String: Any]]) throws -> String {
        guard !instructions.isEmpty else {
            throw ExportError.invalidInstructions
        }

        let jsonData = try JSONSerialization.data(
            withJSONObject: instructions,
            options: [.prettyPrinted, .sortedKeys]
        )

        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ExportError.encodingFailed
        }

        return jsonString
    }

    /// Export instructions to a compact JSON string (no formatting)
    func exportToCompactJSON(instructions: [[String: Any]]) throws -> String {
        guard !instructions.isEmpty else {
            throw ExportError.invalidInstructions
        }

        let jsonData = try JSONSerialization.data(
            withJSONObject: instructions,
            options: []
        )

        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ExportError.encodingFailed
        }

        return jsonString
    }

    // MARK: - File Export

    /// Export instructions to a file
    /// - Parameters:
    ///   - instructions: Array of instruction dictionaries
    ///   - filename: Name for the file (without extension)
    ///   - directory: Directory to save to (defaults to temporary directory)
    /// - Returns: URL of the saved file
    func exportToFile(
        instructions: [[String: Any]],
        filename: String,
        directory: URL? = nil
    ) throws -> URL {
        let jsonString = try exportToJSON(instructions: instructions)

        let targetDirectory = directory ?? FileManager.default.temporaryDirectory
        let fileURL = targetDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension("json")

        do {
            try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.fileWriteFailed(path: fileURL.path)
        }

        return fileURL
    }

    /// Export instructions to a .txt file (for easy pasting)
    func exportToTextFile(
        instructions: [[String: Any]],
        filename: String,
        directory: URL? = nil
    ) throws -> URL {
        let jsonString = try exportToJSON(instructions: instructions)

        let targetDirectory = directory ?? FileManager.default.temporaryDirectory
        let fileURL = targetDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension("txt")

        do {
            try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.fileWriteFailed(path: fileURL.path)
        }

        return fileURL
    }

    /// Export to user-selected location with save panel
    func exportWithSavePanel(
        instructions: [[String: Any]],
        suggestedFilename: String = "storyflow_instructions"
    ) async throws -> URL? {
        let jsonString = try exportToJSON(instructions: instructions)

        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.json, .plainText]
                savePanel.nameFieldStringValue = suggestedFilename
                savePanel.title = "Save StoryFlow Instructions"
                savePanel.message = "Choose where to save your StoryFlow instructions"

                savePanel.begin { response in
                    guard response == .OK, let url = savePanel.url else {
                        continuation.resume(returning: nil)
                        return
                    }

                    do {
                        try jsonString.write(to: url, atomically: true, encoding: .utf8)
                        continuation.resume(returning: url)
                    } catch {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    // MARK: - Clipboard Operations

    /// Copy instructions JSON to clipboard
    /// - Parameter instructions: Array of instruction dictionaries
    func copyToClipboard(instructions: [[String: Any]]) throws {
        let jsonString = try exportToJSON(instructions: instructions)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(jsonString, forType: .string)
    }

    /// Copy compact JSON to clipboard (better for direct pasting)
    func copyCompactToClipboard(instructions: [[String: Any]]) throws {
        let jsonString = try exportToCompactJSON(instructions: instructions)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(jsonString, forType: .string)
    }

    // MARK: - Import

    /// Import instructions from JSON string
    /// - Parameter jsonString: JSON string containing instructions
    /// - Returns: Array of instruction dictionaries
    func importFromJSON(_ jsonString: String) throws -> [[String: Any]] {
        guard let data = jsonString.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }

        let parsed = try JSONSerialization.jsonObject(with: data, options: [])

        guard let instructions = parsed as? [[String: Any]] else {
            throw ExportError.invalidInstructions
        }

        return instructions
    }

    /// Import instructions from file URL
    func importFromFile(_ fileURL: URL) throws -> [[String: Any]] {
        let jsonString = try String(contentsOf: fileURL, encoding: .utf8)
        return try importFromJSON(jsonString)
    }

    /// Import from clipboard
    func importFromClipboard() throws -> [[String: Any]]? {
        guard let jsonString = NSPasteboard.general.string(forType: .string) else {
            return nil
        }

        return try importFromJSON(jsonString)
    }

    // MARK: - Utilities

    /// Get the size of the JSON output in bytes
    func getJSONSize(instructions: [[String: Any]]) throws -> Int {
        let jsonString = try exportToJSON(instructions: instructions)
        return jsonString.utf8.count
    }

    /// Get instruction count summary
    func getInstructionSummary(instructions: [[String: Any]]) -> [String: Int] {
        var summary: [String: Int] = [:]

        for instruction in instructions {
            if let key = instruction.keys.first {
                summary[key, default: 0] += 1
            }
        }

        return summary
    }

    private static let fileSizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useBytes, .useKB, .useMB]
        f.countStyle = .file
        return f
    }()

    /// Format file size for display
    func formatFileSize(_ bytes: Int) -> String {
        Self.fileSizeFormatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Convenience Extensions

extension StoryflowExporter {

    /// Quick export to clipboard with feedback
    func quickExport(instructions: [[String: Any]]) -> (success: Bool, message: String) {
        do {
            try copyToClipboard(instructions: instructions)
            let size = try getJSONSize(instructions: instructions)
            return (true, "Copied \(instructions.count) instructions (\(formatFileSize(size))) to clipboard")
        } catch {
            return (false, "Export failed: \(error.localizedDescription)")
        }
    }
}
