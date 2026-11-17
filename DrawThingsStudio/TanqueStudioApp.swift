import SwiftUI
import SwiftData
import TipKit

// MARK: - UserDefaults key for backup restore signal
// Written by TanqueStudioApp on schema wipe/recovery. Not currently read
// anywhere in the app (pre-existing — was already unread before ContentView
// was removed, despite an earlier comment here claiming otherwise).
let needsBackupRestoreKey = "tanqueStudio.needsBackupRestore"

// MARK: - Migration helpers

/// Migrates legacy `dts.*` UserDefaults keys to `tanqueStudio.*` on first launch after rename.
/// Gates on `tanqueStudio.migrationV1.complete` so it runs exactly once.
private func migrateUserDefaultsKeys() {
    let completedKey = "tanqueStudio.migrationV1.complete"
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: completedKey) else { return }

    let keyMigrations: [(old: String, new: String)] = [
        ("dts.needsBackupRestore", "tanqueStudio.needsBackupRestore"),
        ("dts.schemaVersion",      "tanqueStudio.schemaVersion"),
    ]
    for (old, new) in keyMigrations {
        if let value = defaults.object(forKey: old) {
            defaults.set(value, forKey: new)
        }
    }
    defaults.set(true, forKey: completedKey)
}

/// Copies the Application Support subdirectory from `DrawThingsStudio/` to `TanqueStudio/`
/// on first launch after rename. Old directory is preserved for safe rollback.
/// Must run before any code reads from the TanqueStudio/ path.
private func migrateAppSupportDirectoryIfNeeded() {
    let completedKey = "tanqueStudio.appSupportMigrationV1.complete"
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: completedKey) else { return }
    defer { defaults.set(true, forKey: completedKey) }

    let fm = FileManager.default
    guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }

    let oldDir = appSupport.appendingPathComponent("DrawThingsStudio", isDirectory: true)
    let newDir = appSupport.appendingPathComponent("TanqueStudio", isDirectory: true)

    guard fm.fileExists(atPath: oldDir.path), !fm.fileExists(atPath: newDir.path) else { return }
    try? fm.copyItem(at: oldDir, to: newDir)
}

/// Removes a SQLite store and its WAL/SHM siblings.
private func wipeSQLiteStore(_ modelConfiguration: ModelConfiguration) {
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
}

/// Copies the SQLite store and its WAL/SHM siblings into
/// `Application Support/TanqueStudio/StoreBackups/<label>-<timestamp>/` before a
/// schema migration. The container-open path below wipes the store if opening
/// fails, so this copy is the only way back from a bad migration. Never throws:
/// a failed backup is logged and the launch carries on.
private func backupSQLiteStore(_ modelConfiguration: ModelConfiguration, label: String) {
    let storeURL = modelConfiguration.url
    let fm = FileManager.default
    print("[TanqueStudio] SwiftData store: \(storeURL.path)")
    guard fm.fileExists(atPath: storeURL.path),
          let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    let folder = appSupport
        .appendingPathComponent("TanqueStudio", isDirectory: true)
        .appendingPathComponent("StoreBackups", isDirectory: true)
        .appendingPathComponent("\(label)-\(stamp)", isDirectory: true)
    do {
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for suffix in ["", "-shm", "-wal"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: source.path) else { continue }
            try fm.copyItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
        }
        print("[TanqueStudio] Store backed up to \(folder.path)")
    } catch {
        print("[TanqueStudio] Store backup failed: \(error)")
    }
}

// MARK: - App

@main
struct TanqueStudioApp: App {
    var sharedModelContainer: ModelContainer = {
        migrateUserDefaultsKeys()
        migrateAppSupportDirectoryIfNeeded()

        // Schema versioning:
        // currentSchemaVersion — bump on every schema change
        // lastDestructiveVersion — bump only when a store wipe is required
        let currentSchemaVersion = 4
        let lastDestructiveVersion = 1
        let schemaVersionKey = "tanqueStudio.schemaVersion"

        let schema = Schema([
            TSImage.self,
            StoryProject.self,
            StoryCharacter.self,
            StorySetting.self,
            StoryChapter.self,
            StoryScene.self,
            SceneCharacterPresence.self,
            RenderQueueAxis.self,
            RenderQueueJob.self,
            StoryPage.self,
            PagePanel.self,
        ])
        let modelConfiguration = ModelConfiguration(
            "TanqueStudio", schema: schema, isStoredInMemoryOnly: false)

        let storedVersion = UserDefaults.standard.integer(forKey: schemaVersionKey)
        if storedVersion > 0 && storedVersion < currentSchemaVersion {
            backupSQLiteStore(modelConfiguration, label: "before-schema-v\(currentSchemaVersion)")
        }
        if storedVersion < lastDestructiveVersion {
            wipeSQLiteStore(modelConfiguration)
            UserDefaults.standard.set(true, forKey: needsBackupRestoreKey)
        }
        if storedVersion < currentSchemaVersion {
            UserDefaults.standard.set(currentSchemaVersion, forKey: schemaVersionKey)
        }

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("[TanqueStudio] ModelContainer failed to open, wiping store: \(error)")
            wipeSQLiteStore(modelConfiguration)
            UserDefaults.standard.set(true, forKey: needsBackupRestoreKey)
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer even after recovery wipe: \(error)")
            }
        }
    }()

    init() {
        try? Tips.configure()

        // Built-in `#config` presets, at launch rather than when the StoryFlow
        // pane first loads. They are read by every Labs surface with a "Use a
        // saved config…" menu — Story Studio, Cast & Staging, Render Queue —
        // and those read `StoryFlowStorage.shared` directly, so hanging the
        // migration off StoryFlowViewModel.loadAll() left anyone who opened
        // Render Queue first looking at the previous version's presets.
        // Both calls are idempotent and version-guarded.
        StoryFlowStorage.shared.migrateBuiltInsIfNeeded()
        StoryFlowStorage.shared.seedBuiltInsIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            DashboardRootView()
                .ignoresSafeArea()
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        // Without this the window cannot be made smaller than the content's
        // *ideal* height, which is what `.automatic` resizability enforces. The
        // Focus Room's right column is a long stack of sections, so that ideal
        // ran past the screen: measured at 1075 points tall on a 982-point
        // display, where dragging the bottom edge up simply snapped back and the
        // window sat partly below the screen with no way to recover it.
        //
        // `.contentMinSize` honours the content's *minimum* instead. The panels
        // are already inside ScrollViews, so a shorter window scrolls rather than
        // clipping — the tall ideal was never a real constraint.
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .help) {
                HelpMenuCommands()
            }
        }

        #if os(macOS)
        Window("Tanque Studio Help", id: tanqueHelpWindowID) {
            HelpWindowView()
        }
        .defaultSize(width: 780, height: 560)

        Settings {
            SettingsView()
        }
        #endif
    }
}

// MARK: - Help menu

/// Replaces the default Help menu: reopen the welcome flow + the Help window.
/// Split into its own view so `openWindow` resolves from the command environment.
private struct HelpMenuCommands: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Welcome to Tanque Studio") {
            NotificationCenter.default.post(name: .tanqueShowWelcome, object: nil)
        }
        Button("Tanque Studio Help") {
            openWindow(id: tanqueHelpWindowID)
        }
        .keyboardShortcut("?", modifiers: .command)
    }
}
