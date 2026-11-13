import AppKit
import Foundation
import Observation

/// The sheet being written. Shared, because the Labs page is rebuilt on every
/// visit and the draft has to survive a trip to another tab.
@MainActor
@Observable
final class WritingDeskSession {
    static let shared = WritingDeskSession()

    private(set) var text = ""
    private(set) var savedText = ""
    private(set) var lastSaved: URL?
    /// One line about the last thing that happened, shown under the buttons.
    var status = ""

    var hasUnsavedText: Bool { !text.isEmpty && text != savedText }

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TanqueStudio/WritingDesk", isDirectory: true)
    }

    func append(_ string: String) { text += string }
    func newline() { text += "\n" }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }

    func newSheet() {
        text = ""
        savedText = ""
        lastSaved = nil
        status = "New sheet"
    }

    /// Writes the sheet as Markdown. Saving the same sheet again updates its file.
    @discardableResult
    func save(now: Date = Date()) -> Bool {
        guard !text.isEmpty else {
            status = "Nothing to save yet"
            return false
        }
        let url = lastSaved ?? Self.folder.appendingPathComponent(Self.fileName(for: now))
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try (text + "\n").write(to: url, atomically: true, encoding: .utf8)
            lastSaved = url
            savedText = text
            status = "Saved \(url.lastPathComponent)"
            return true
        } catch {
            status = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "sheet-\(formatter.string(from: date)).md"
    }

    /// Shows the saved sheet in Finder, or the sheets folder if nothing is saved yet.
    func revealInFinder() {
        if let lastSaved, FileManager.default.fileExists(atPath: lastSaved.path) {
            NSWorkspace.shared.activateFileViewerSelecting([lastSaved])
        } else {
            Self.reveal(folder: Self.folder)
        }
    }

    static func reveal(folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
