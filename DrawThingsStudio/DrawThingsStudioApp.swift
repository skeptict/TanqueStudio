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

// MARK: - App

@main
struct DrawThingsStudioApp: App {
    var sharedModelContainer: ModelContainer = {
        // Increment when the SwiftData schema changes incompatibly.
        // On macOS 14 (SwiftData 1.0), automatic lightweight migration can
        // leave stale SQLite constraints (e.g. UNIQUE indexes from a removed
        // @Attribute(.unique)) that cause EXC_BAD_INSTRUCTION on insert.
        // Wiping the store on version bump is safe for a beta app and prevents
        // the crash for any user who had an older build installed.
        //
        // v3: switched to an explicit store URL so the migration path is
        // predictable and we don't accidentally delete the wrong file.
        let currentSchemaVersion = 3
        let schemaVersionKey = "dts.schemaVersion"

        let schema = Schema([
            SavedWorkflow.self,
            ModelConfig.self,
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

        if UserDefaults.standard.integer(forKey: schemaVersionKey) < currentSchemaVersion {
            // Delete the persistent store + WAL companions at the named URL
            // and also probe the legacy unnamed location ("default.store") that
            // earlier builds may have used, so SwiftData opens a clean database.
            let storeURL = modelConfiguration.url
            let appSupport = storeURL.deletingLastPathComponent()
            let fm = FileManager.default
            let candidates: [URL] = [
                storeURL,
                appSupport.appendingPathComponent("default.store"),
            ]
            for base in candidates {
                for suffix in ["", "-shm", "-wal"] {
                    try? fm.removeItem(at: URL(fileURLWithPath: base.path + suffix))
                }
            }
            UserDefaults.standard.set(currentSchemaVersion, forKey: schemaVersionKey)
        }

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            WorkflowCommands()
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .preferredColorScheme(.light)
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
