//
//  DrawThingsStudioApp.swift
//  DrawThingsStudio
//
//  Created by skeptict on 1/14/26.
//

import SwiftUI
import SwiftData

// MARK: - Focused Values

struct FocusedWorkflowKey: FocusedValueKey {
    typealias Value = WorkflowBuilderViewModel
}

extension FocusedValues {
    var workflowViewModel: WorkflowBuilderViewModel? {
        get { self[FocusedWorkflowKey.self] }
        set { self[FocusedWorkflowKey.self] = newValue }
    }
}

// MARK: - Constants

/// UserDefaults key signalling that BackupCoordinator should restore from JSON on next launch.
/// Written by DrawThingsStudioApp (schema wipe / recovery), read and cleared by ContentView.
let needsBackupRestoreKey = "dts.needsBackupRestore"

/// Removes a SQLite store and its WAL/SHM siblings. Safe to call when files are absent.
private func wipeSQLiteStore(_ modelConfiguration: ModelConfiguration) {
    let storeURL = modelConfiguration.url
    let appSupport = storeURL.deletingLastPathComponent()
    let fm = FileManager.default
    // Include "default.store" as a legacy fallback for stores created before the named
    // configuration was introduced (pre-v3 builds may have used that path).
    let candidates: [URL] = [
        storeURL,
        appSupport.appendingPathComponent("default.store"),
    ]
    for base in candidates {
        for suffix in ["", "-shm", "-wal"] {
            try? fm.removeItem(at: URL(fileURLWithPath: base.path + suffix))
        }
    }
}

// MARK: - App

@main
struct DrawThingsStudioApp: App {
    var sharedModelContainer: ModelContainer = {
        // Schema versioning strategy:
        //
        // currentSchemaVersion — bumped on every schema change (additive or destructive).
        //   Used to detect first-launch with a new version.
        //
        // lastDestructiveVersion — bumped ONLY when the change requires wiping the store
        //   (e.g. removing a column, changing a type, adding @Attribute(.unique)).
        //   Additive changes (new fields with defaults) do NOT need a wipe; SwiftData
        //   handles them automatically via CoreData lightweight migration.
        //   On macOS 14 (SwiftData 1.0), the wipe guards against stale SQLite UNIQUE
        //   index constraints left by removed @Attribute(.unique) attributes.
        //
        // History:
        //   v1–v2: various early schema changes
        //   v3: switched to explicit store URL
        //   v4: added SceneVariant.isApproved (additive — no wipe needed)
        let currentSchemaVersion = 4
        let lastDestructiveVersion = 3  // last version that required a store wipe
        let schemaVersionKey = "dts.schemaVersion"

        let schema = Schema([
            SavedWorkflow.self,
            ModelConfig.self,
            SavedPipeline.self,
            StoryProject.self,
            StoryCharacter.self,
            CharacterAppearance.self,
            StorySetting.self,
            StoryChapter.self,
            StoryScene.self,
            SceneCharacterPresence.self,
            SceneVariant.self
        ])

        // Naming the configuration pins the store filename to
        // "DrawThingsStudio.store" so the migration path is predictable —
        // without a name SwiftData may derive a different path across schema
        // versions, causing the guard to delete the wrong file.
        let modelConfiguration = ModelConfiguration(
            "DrawThingsStudio", schema: schema, isStoredInMemoryOnly: false)

        let storedVersion = UserDefaults.standard.integer(forKey: schemaVersionKey)
        if storedVersion < lastDestructiveVersion {
            // Wipe only for destructive schema changes — removes stale constraints
            // and incompatible table structures. Additive changes (new columns with
            // defaults) are left to SwiftData's automatic lightweight migration.
            wipeSQLiteStore(modelConfiguration)
            // Signal BackupCoordinator to restore from JSON backup on next launch
            UserDefaults.standard.set(true, forKey: needsBackupRestoreKey)
        }
        if storedVersion < currentSchemaVersion {
            UserDefaults.standard.set(currentSchemaVersion, forKey: schemaVersionKey)
        }

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Recovery: store may be corrupt or incompatible (e.g. pre-release OS SwiftData changes).
            // Wipe and retry once — BackupCoordinator will restore data on next launch.
            wipeSQLiteStore(modelConfiguration)
            UserDefaults.standard.set(true, forKey: needsBackupRestoreKey)
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer even after recovery wipe: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .commands {
            WorkflowCommands()
        }

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

// MARK: - Workflow Commands

struct WorkflowCommands: Commands {
    @FocusedValue(\.workflowViewModel) var viewModel

    var body: some Commands {
        // File menu
        CommandGroup(replacing: .newItem) {
            Button("New Workflow") {
                viewModel?.clearAllInstructions()
                viewModel?.workflowName = "Untitled Workflow"
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open Workflow...") {
                Task {
                    await viewModel?.importWithOpenPanel()
                }
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("Save Workflow...") {
                Task {
                    await viewModel?.exportWithSavePanel()
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(viewModel?.instructions.isEmpty ?? true)
        }

        // Edit menu additions
        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Delete Instruction") {
                viewModel?.deleteSelectedInstruction()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(viewModel?.hasSelection != true)

            Button("Duplicate Instruction") {
                viewModel?.duplicateSelectedInstruction()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(viewModel?.hasSelection != true)

            Divider()

            Button("Move Up") {
                viewModel?.moveSelectedUp()
            }
            .keyboardShortcut(.upArrow, modifiers: [.option, .command])
            .disabled(viewModel?.hasSelection != true)

            Button("Move Down") {
                viewModel?.moveSelectedDown()
            }
            .keyboardShortcut(.downArrow, modifiers: [.option, .command])
            .disabled(viewModel?.hasSelection != true)
        }

        // Workflow menu
        CommandMenu("Workflow") {
            Button("Validate") {
                _ = viewModel?.validate()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(viewModel?.instructions.isEmpty ?? true)

            Button("Copy JSON to Clipboard") {
                viewModel?.copyToClipboard()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(viewModel?.instructions.isEmpty ?? true)

            Divider()

            Menu("Add Instruction") {
                Button("Note") { viewModel?.addInstruction(.note("")) }
                Button("Prompt") { viewModel?.addInstruction(.prompt("")) }
                Button("Negative Prompt") { viewModel?.addInstruction(.negativePrompt("")) }
                Button("Config") { viewModel?.addInstruction(.config(DrawThingsConfig())) }

                Divider()

                Button("Loop") { viewModel?.addInstruction(.loop(count: 5, start: 0)) }
                Button("Loop End") { viewModel?.addInstruction(.loopEnd) }

                Divider()

                Button("Clear Canvas") { viewModel?.addInstruction(.canvasClear) }
                Button("Load Canvas") { viewModel?.addInstruction(.canvasLoad("")) }
                Button("Save Canvas") { viewModel?.addInstruction(.canvasSave("output.png")) }
            }

            Divider()

            Button("Clear All Instructions") {
                viewModel?.clearAllInstructions()
            }
            .disabled(viewModel?.instructions.isEmpty ?? true)
        }
    }
}
