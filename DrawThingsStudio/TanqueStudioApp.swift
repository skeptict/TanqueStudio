import SwiftUI
import SwiftData

// MARK: - UserDefaults key for backup restore signal
// Written by TanqueStudioApp on schema wipe/recovery; read and cleared by ContentView.
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

// MARK: - App

@main
struct TanqueStudioApp: App {
    var sharedModelContainer: ModelContainer = {
        migrateUserDefaultsKeys()
        migrateAppSupportDirectoryIfNeeded()

        // Schema versioning:
        // currentSchemaVersion — bump on every schema change
        // lastDestructiveVersion — bump only when a store wipe is required
        let currentSchemaVersion = 1
        let lastDestructiveVersion = 1
        let schemaVersionKey = "tanqueStudio.schemaVersion"

        let schema = Schema([TSImage.self])
        let modelConfiguration = ModelConfiguration(
            "TanqueStudio", schema: schema, isStoredInMemoryOnly: false)

        let storedVersion = UserDefaults.standard.integer(forKey: schemaVersionKey)
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

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
