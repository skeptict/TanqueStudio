import Foundation
import AppKit
import SwiftUI

// MARK: - StoryFlowCastViewModel
//
// Owns the open project folder and the document inside it. The folder — not the emitted
// `.json` — is the unit of work: `bible.json` and `configs.json` are the files of record, and
// the project is a build artifact this pane produces from them, exactly as
// `build_project.py` does. Nothing here can edit an emitted project.

@MainActor
@Observable
final class StoryFlowCastViewModel {

    // MARK: - State

    var document = StoryFlowCastDocument()

    /// Recomputed by `revalidate()` rather than computed on demand: the view reads it from
    /// three separate panels, and validation emits a whole project and simulates every loop
    /// pass to do its job.
    private(set) var issues: [StoryFlowCastIssue] = []

    private(set) var folderURL: URL?
    private(set) var status = "No project open."

    /// The document as it last existed on disk.
    ///
    /// `isDirty` is derived from this rather than set by an edit hook, because the view's
    /// change observer cannot tell an edit from a load — assigning a freshly loaded document
    /// *is* a change, and a flag set from there marks an untouched project dirty the moment it
    /// opens. Comparing against what was written cannot get that wrong.
    private var savedSnapshot = StoryFlowCastDocument()

    var isDirty: Bool { document != savedSnapshot }
    var errorMessage: String?

    /// Row the table has focused, so the staging and validation panels can highlight it.
    var selectedRowID: CastMember.ID?

    private let settings = AppSettings.shared

    var projectFileName: String {
        document.staging.outputBasename.isEmpty
            ? "project.json"
            : "\(document.staging.outputBasename).json"
    }

    var isOpen: Bool { folderURL != nil }

    // MARK: - Opening

    /// Reopen the folder from the last session. Silent on failure — a missing or revoked
    /// bookmark is a normal first-launch state, not an error worth a dialog.
    func restoreLastFolder() {
        guard folderURL == nil,
              let bookmark = settings.castProjectFolderBookmark else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale) else { return }
        open(folder: url, bookmark: bookmark, announceFailure: false)
    }

    /// Create a new project folder with a seeded `bible.json` + `configs.json`, then open it.
    ///
    /// Uses a save panel rather than a bare folder picker so the user gets Finder's own
    /// navigation, its New Folder button, and a name field in one dialog — the same shape as
    /// "save a document somewhere", which is what this is.
    func createProject() {
        let panel = NSSavePanel()
        panel.title = "New Cast & Staging Project"
        panel.message = "Choose where to create the project folder"
        panel.prompt = "Create"
        panel.nameFieldLabel = "Project name:"
        panel.nameFieldStringValue = "New Auditions"
        panel.canCreateDirectories = true
        if let folderURL { panel.directoryURL = folderURL.deletingLastPathComponent() }

        guard panel.runModal() == .OK, let target = panel.url else { return }

        let folderName = target.lastPathComponent
        // The save panel offers to "replace" an existing item. Replacing a folder that already
        // holds someone's bible would be unrecoverable, so refuse rather than trust the prompt.
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory) {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: target.path)) ?? []
            let meaningful = contents.filter { $0 != ".DS_Store" }
            guard isDirectory.boolValue, meaningful.isEmpty else {
                errorMessage = StoryFlowCastDocumentError.folderNotEmpty(folderName).localizedDescription
                return
            }
        }

        // The panel's own grant covers the folder we are about to write, so take the bookmark
        // from it — there is nothing to resolve yet.
        let bookmark = try? target.deletingLastPathComponent().bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)

        let document = StoryFlowCastDocument.starter(
            projectName: folderName,
            folderName: folderName,
            configShortcuts: Self.savedConfigShortcuts()
        )

        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try document.save(toFolder: target)
        } catch {
            errorMessage = "Could not create the project: \(error.localizedDescription)"
            return
        }

        open(folder: target, bookmark: bookmark, announceFailure: true)
        status = "Created \(folderName). Assign both config shortcuts, then rewrite the cast."
    }

    /// Seed the two config slots from the user's own saved `#config` variables when the names
    /// make the intent unambiguous. A wrong guess here is worse than no guess — a still config
    /// on the video phase renders one frame — so anything less than an obvious match is left as
    /// a placeholder for the user to assign.
    static func savedConfigShortcuts() -> [OrderedJSONMember] {
        let configs = StoryFlowStorage.shared.loadVariables()
            .filter { $0.type == .config && !($0.configJSON ?? "").isEmpty }

        func match(_ keywords: [String]) -> OrderedJSONValue? {
            guard let hit = configs.first(where: { variable in
                let name = variable.name.lowercased()
                return keywords.contains { name.contains($0) }
            }) else { return nil }
            return (try? OrderedJSONValue.parse(hit.configJSON ?? ""))
        }

        let stills = match(["krea", "still", "image"])
        let video = match(["ltx", "video", "clip"])
        guard stills != nil || video != nil else { return [] }

        return [
            .init(key: StoryFlowCastEmitter.stillsConfigShortcut,
                  value: stills ?? StoryFlowCastDocument.placeholderConfigShortcuts[0].value),
            .init(key: StoryFlowCastEmitter.videoConfigShortcut,
                  value: video ?? StoryFlowCastDocument.placeholderConfigShortcuts[1].value),
        ]
    }

    /// Assign a saved `#config` variable's JSON to one of the two phase slots.
    func assignConfig(_ json: String, to shortcutKey: String) {
        guard let parsed = try? OrderedJSONValue.parse(json), parsed.members != nil else {
            errorMessage = "That saved config is not a JSON object."
            return
        }
        if let index = document.staging.configShortcuts.firstIndex(where: { $0.key == shortcutKey }) {
            document.staging.configShortcuts[index] = .init(key: shortcutKey, value: parsed)
        } else {
            document.staging.configShortcuts.append(.init(key: shortcutKey, value: parsed))
        }
        documentChanged()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the project folder holding bible.json and configs.json"
        panel.prompt = "Open Project"
        if let folderURL { panel.directoryURL = folderURL.deletingLastPathComponent() }

        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        let bookmark = try? chosen.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
        open(folder: chosen, bookmark: bookmark, announceFailure: true)
    }

    private func open(folder: URL, bookmark: Data?, announceFailure: Bool) {
        let outcome: Result<StoryFlowCastDocument, Error> = withAccess(to: folder, bookmark: bookmark) {
            Result { try StoryFlowCastDocument.load(fromFolder: folder) }
        }

        switch outcome {
        case .success(let loaded):
            document = loaded
            savedSnapshot = loaded
            folderURL = folder
            errorMessage = nil
            selectedRowID = loaded.cast.first?.id
            settings.castProjectFolder = folder.path
            if let bookmark { settings.castProjectFolderBookmark = bookmark }
            status = "\(loaded.cast.count) in the cast — \(folder.lastPathComponent)"
            revalidate()
        case .failure(let error):
            if announceFailure { errorMessage = error.localizedDescription }
        }
    }

    /// Run `body` with a security-scoped grant for `folder`.
    ///
    /// The project folder normally lives outside the sandbox container, where `FileManager`
    /// misreports in both directions without a live grant — reads fail and writes silently do
    /// nothing. Every read and write of the two files goes through here.
    private func withAccess<T>(to folder: URL, bookmark: Data?, _ body: () -> T) -> T {
        var scoped: URL?
        if let bookmark {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark,
                                       options: .withSecurityScope,
                                       relativeTo: nil,
                                       bookmarkDataIsStale: &isStale),
               resolved.startAccessingSecurityScopedResource() {
                scoped = resolved
            }
        }
        defer { scoped?.stopAccessingSecurityScopedResource() }
        return body()
    }

    private func withCurrentFolder<T>(_ body: (URL) -> T) -> T? {
        guard let folderURL else { return nil }
        return withAccess(to: folderURL, bookmark: settings.castProjectFolderBookmark) {
            body(folderURL)
        }
    }

    // MARK: - Editing

    /// Called from the pane's single `onChange(of: document)` observer, so every field in all
    /// three panels reports its edits without each of them having to remember to.
    func documentChanged() {
        revalidate()
    }

    func revalidate() {
        issues = StoryFlowCastValidator.validate(cast: document.cast, staging: document.staging)
    }

    func addMember() {
        // A fresh row seeds a distinct seed rather than 0 for every row: pinned seeds exist so
        // a rejected anchor can be regenerated identically, and two rows sharing one defeats
        // that for both.
        let highest = document.cast.map(\.seed).max() ?? 811000
        var member = CastMember()
        member.seed = highest + 1
        document.cast.append(member)
        selectedRowID = member.id
        documentChanged()
    }

    func duplicate(_ member: CastMember) {
        guard let index = document.cast.firstIndex(where: { $0.id == member.id }) else { return }
        var copy = member
        copy.id = UUID()
        copy.name = member.name.isEmpty ? "" : member.name + " copy"
        copy.seed = (document.cast.map(\.seed).max() ?? member.seed) + 1
        document.cast.insert(copy, at: index + 1)
        selectedRowID = copy.id
        documentChanged()
    }

    func delete(_ member: CastMember) {
        document.cast.removeAll { $0.id == member.id }
        if selectedRowID == member.id { selectedRowID = document.cast.first?.id }
        documentChanged()
    }

    func move(from offsets: IndexSet, to destination: Int) {
        document.cast.move(fromOffsets: offsets, toOffset: destination)
        documentChanged()
    }

    // MARK: - Saving the source files

    func save() {
        guard folderURL != nil else { return }
        let outcome: Result<Void, Error>? = withCurrentFolder { folder in
            Result { try document.save(toFolder: folder) }
        }
        switch outcome {
        case .success:
            savedSnapshot = document
            errorMessage = nil
            status = "Saved bible.json and configs.json."
        case .failure(let error):
            errorMessage = "Could not save: \(error.localizedDescription)"
        case nil:
            errorMessage = "No project folder is open."
        }
    }

    // MARK: - Emitting the project

    /// Write `<outputBasename>.json` and `<outputBasename>.pipeline.json` into the project
    /// folder, saving the source files first so the two can never describe different casts.
    ///
    /// Blocked while any validation failure stands. Each of those failures is silent in Draw
    /// Things — the run finishes and produces a full set of wrong videos — so letting one
    /// through would be handing over an artifact that looks fine and is not.
    func emitProject() {
        errorMessage = nil
        guard !issues.hasFailures else {
            errorMessage = "\(issues.failures.count) validation failure(s) still to fix. "
                + "Every one of them renders silently wrong rather than erroring."
            return
        }
        guard !document.staging.outputBasename.isEmpty else {
            errorMessage = "The project has no output basename, so there is nothing to name the file."
            return
        }
        if isDirty { save() }
        guard errorMessage == nil else { return }

        let projectText = StoryFlowCastEmitter
            .projectJSON(cast: document.cast, staging: document.staging).prettyJSON + "\n"
        let pipelineText = StoryFlowCastEmitter
            .pipelineJSON(cast: document.cast, staging: document.staging).prettyJSON + "\n"
        let basename = document.staging.outputBasename

        let outcome: Result<Void, Error>? = withCurrentFolder { folder in
            Result {
                try projectText.write(to: folder.appendingPathComponent("\(basename).json"),
                                      atomically: true, encoding: .utf8)
                try pipelineText.write(to: folder.appendingPathComponent("\(basename).pipeline.json"),
                                       atomically: true, encoding: .utf8)
            }
        }

        switch outcome {
        case .success:
            errorMessage = nil
            let warnings = issues.warnings.count
            status = "Emitted \(basename).json and \(basename).pipeline.json"
                + (warnings > 0 ? " — \(warnings) warning(s) stand." : ".")
        case .failure(let error):
            errorMessage = "Could not emit: \(error.localizedDescription)"
        case nil:
            errorMessage = "No project folder is open."
        }
    }

    /// The Draw Things-ready form, for pasting straight into the StoryFlow script.
    func copyPipeline() {
        let text = StoryFlowCastEmitter
            .pipelineJSON(cast: document.cast, staging: document.staging).prettyJSON
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = "Pipeline array copied — paste this one into Draw Things."
    }

    func revealInFinder() {
        guard let folderURL else { return }
        ImageFolderAccess.revealInFinder(folderURL, bookmark: settings.castProjectFolderBookmark)
    }

    // MARK: - Readouts

    func frameReadout(for member: CastMember) -> StoryFlowFrameBudget.Readout {
        StoryFlowFrameBudget.readout(for: member, staging: document.staging)
    }

    func issues(forRow index: Int) -> [StoryFlowCastIssue] {
        issues.filter { $0.anchor == .castRow(index) }
    }

    func issues(forFragment name: String) -> [StoryFlowCastIssue] {
        issues.filter { $0.anchor == .fragment(name) }
    }

    func issues(forStaging key: String) -> [StoryFlowCastIssue] {
        issues.filter { $0.anchor == .staging(key) }
    }
}
