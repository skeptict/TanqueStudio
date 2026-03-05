//
//  DTProjectDatabase.swift
//  DrawThingsStudio
//
//  Read-only SQLite reader for Draw Things project databases (.sqlite3).
//  Parses FlatBuffer blobs to extract generation metadata and JPEG thumbnails.
//

import Foundation
import SQLite3
import AppKit

// MARK: - Errors

enum DTProjectDatabaseError: LocalizedError {
    case cannotOpen(String)
    case databaseLocked
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let msg): return "Could not open database: \(msg)"
        case .databaseLocked:     return "Database is locked. Close Draw Things and try again."
        case .deleteFailed(let msg): return "Delete failed: \(msg)"
        }
    }
}

// MARK: - Data Models

struct DTLoRAEntry: Hashable {
    let file: String
    let weight: Float
}

struct DTGenerationEntry: Identifiable, Hashable {
    let id: Int64           // rowid
    let lineage: Int64      // __pk0
    let logicalTime: Int64  // __pk1
    let previewId: Int64
    let prompt: String
    let negativePrompt: String
    let model: String
    let width: Int          // start_width * 64
    let height: Int         // start_height * 64
    let steps: Int
    let guidanceScale: Float
    let seed: UInt32
    let strength: Float
    let sampler: String
    let seedMode: String
    let shift: Float
    let stochasticSamplingGamma: Float
    let wallClock: Date
    let loras: [DTLoRAEntry]
    var thumbnail: NSImage?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DTGenerationEntry, rhs: DTGenerationEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Video Clip

/// A group of generation entries sharing the same lineage (__pk0).
/// When a Draw Things video model (e.g. WAN 2.2) generates N frames, each frame
/// is stored as a separate `tensorhistorynode` row with the same lineage but a
/// different logicalTime (frame index). Single still images have exactly one frame.
struct DTVideoClip: Identifiable {
    let id: Int64                       // lineage (__pk0) — unique per generation run
    let frames: [DTGenerationEntry]     // sorted ascending by logicalTime

    var isVideo: Bool       { frames.count > 1 }
    var frameCount: Int     { frames.count }

    // Representative metadata — shared across all frames
    var prompt: String      { frames.first?.prompt ?? "" }
    var negativePrompt: String { frames.first?.negativePrompt ?? "" }
    var model: String       { frames.first?.model ?? "" }
    var seed: UInt32        { frames.first?.seed ?? 0 }
    var width: Int          { frames.first?.width ?? 0 }
    var height: Int         { frames.first?.height ?? 0 }
    var steps: Int          { frames.first?.steps ?? 0 }
    var guidanceScale: Float { frames.first?.guidanceScale ?? 0 }
    var strength: Float     { frames.first?.strength ?? 0 }
    var sampler: String     { frames.first?.sampler ?? "" }
    var seedMode: String    { frames.first?.seedMode ?? "" }
    var shift: Float        { frames.first?.shift ?? 0 }
    var stochasticSamplingGamma: Float { frames.first?.stochasticSamplingGamma ?? 0.3 }
    var loras: [DTLoRAEntry] { frames.first?.loras ?? [] }
    var wallClock: Date     { frames.first?.wallClock ?? Date.distantPast }
    var thumbnail: NSImage? { frames.first?.thumbnail }

    /// Returns true when the model filename is a known video-generation model.
    /// Only entries whose model passes this check are grouped into multi-frame clips;
    /// all other entries are treated as individual still images regardless of their
    /// shared lineage value (which prevents batch image renders from being incorrectly
    /// grouped together as if they were video frames).
    static func isVideoModel(_ modelName: String) -> Bool {
        let lower = modelName.lowercased()
        // WAN (Wan Video) — wan2.1, wan2.2, wan-video, etc.
        if lower.contains("wan") { return true }
        // LTX-Video 2 — ltx2, ltxv2, ltx-2, ltx-video-2, etc.
        if lower.contains("ltx") { return true }
        // Seedance — seedance, seed-dance, etc.
        if lower.contains("seedance") { return true }
        return false
    }

    /// Group a flat list of entries (any order) into clips, sorted newest-first by rowid.
    ///
    /// __pk0 (lineage) is configuration-scoped in Draw Things: two separate renders with
    /// identical settings (model, prompt, seed) share the same __pk0 even if the source
    /// canvas differs. The reliable per-run boundary signal is __pk1 (logicalTime) resetting
    /// back to 0 within the same __pk0 group. Processing entries in ascending rowid order,
    /// each reset of logicalTime to a value ≤ the previous frame's index marks the start
    /// of a new generation run and produces a distinct clip.
    ///
    /// Still-image entries are never grouped — each gets its own single-frame clip keyed
    /// on its negative rowid, which never collides with positive lineage values.
    static func group(from entries: [DTGenerationEntry]) -> [DTVideoClip] {
        // Process chronologically so logicalTime resets are detectable.
        let chronological = entries.sorted { $0.id < $1.id }

        // (lineage, runIndex) → frames collected so far
        var byKey: [String: [DTGenerationEntry]] = [:]
        // lineage → (current run index, last seen logicalTime)
        var runState: [Int64: (run: Int, prevTime: Int64)] = [:]

        for entry in chronological {
            if isVideoModel(entry.model) {
                var (run, prevTime) = runState[entry.lineage] ?? (0, -1)

                // A reset of logicalTime (frame index back to 0, or any non-monotone
                // jump) means Draw Things started a new generation run under the same
                // lineage key.
                if prevTime >= 0 && entry.logicalTime <= prevTime {
                    run += 1
                }
                prevTime = entry.logicalTime
                runState[entry.lineage] = (run, prevTime)

                let key = "\(entry.lineage)_\(run)"
                byKey[key, default: []].append(entry)
            } else {
                // Each still image gets its own clip. Prefix "s" avoids any collision
                // with the lineage_run keys used for video entries.
                byKey["s\(entry.id)"] = [entry]
            }
        }

        return byKey.values.map { frames in
            // Sort frames ascending by logicalTime so frame 0 is first.
            let sorted = frames.sorted { $0.logicalTime < $1.logicalTime }
            // Use the highest rowid in the clip as its stable ID.
            let clipId = sorted.last?.id ?? sorted[0].id
            return DTVideoClip(id: clipId, frames: sorted)
        }
        .sorted { a, b in
            // Newest clip first: highest rowid in clip = most recent frame generated.
            (a.frames.last?.id ?? 0) > (b.frames.last?.id ?? 0)
        }
    }
}

// MARK: - FlatBuffer Reader

/// Minimal FlatBuffer binary reader for TensorHistoryNode blobs.
/// Reads scalars, strings, and LoRA vectors without a full FlatBuffer library.
private struct FBReader {
    let data: Data

    // VTable slot constants for TensorHistoryNode fields.
    // Slot = 4 + 2 * fieldIndex (from the .fbs schema).
    static let VT_START_WIDTH: Int = 8       // field 2, ushort
    static let VT_START_HEIGHT: Int = 10     // field 3, ushort
    static let VT_SEED: Int = 12             // field 4, uint
    static let VT_STEPS: Int = 14            // field 5, uint
    static let VT_GUIDANCE_SCALE: Int = 16   // field 6, float
    static let VT_STRENGTH: Int = 18         // field 7, float
    static let VT_MODEL: Int = 20            // field 8, string
    static let VT_WALL_CLOCK: Int = 26       // field 11, long
    static let VT_SAMPLER: Int = 34          // field 15, byte (SamplerType)
    static let VT_SEED_MODE: Int = 54        // field 25, byte (SeedMode)
    static let VT_LORAS: Int = 64            // field 30, [LoRA]
    static let VT_PREVIEW_ID: Int = 86       // field 41, long
    static let VT_SHIFT: Int = 136           // field 66, float
    static let VT_TEXT_PROMPT: Int = 200      // field 98, string
    static let VT_NEG_TEXT_PROMPT: Int = 202  // field 99, string

    /// Navigate to the root table. Returns (tablePos, vtablePos, vtableSize).
    func rootTable() -> (tablePos: Int, vtablePos: Int, vtableSize: Int)? {
        guard data.count >= 8 else { return nil }
        let rootOffset = readUInt32(at: 0)
        let tablePos = Int(rootOffset)
        guard tablePos + 4 <= data.count else { return nil }

        let vtableRelOffset = readInt32(at: tablePos)
        let vtablePos = tablePos - Int(vtableRelOffset)
        guard vtablePos >= 0, vtablePos + 4 <= data.count else { return nil }

        let vtableSize = Int(readUInt16(at: vtablePos))
        guard vtablePos + vtableSize <= data.count else { return nil }

        return (tablePos, vtablePos, vtableSize)
    }

    /// Read the field offset from vtable. Returns nil if field is absent.
    func fieldOffset(vtablePos: Int, vtableSize: Int, slot: Int) -> Int? {
        guard slot >= 0, slot + 2 <= vtableSize else { return nil }
        let offset = Int(readUInt16(at: vtablePos + slot))
        return offset == 0 ? nil : offset
    }

    // MARK: Scalar Readers

    func readUInt8(at offset: Int) -> UInt8 {
        guard offset >= 0, offset < data.count else { return 0 }
        return data.withUnsafeBytes { buf in
            buf.load(fromByteOffset: offset, as: UInt8.self)
        }
    }

    func readUInt16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return data.withUnsafeBytes { buf in
            buf.load(fromByteOffset: offset, as: UInt16.self)
        }
    }

    func readInt32(at offset: Int) -> Int32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { buf in
            buf.load(fromByteOffset: offset, as: Int32.self)
        }
    }

    func readUInt32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { buf in
            buf.load(fromByteOffset: offset, as: UInt32.self)
        }
    }

    func readFloat(at offset: Int) -> Float {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { buf in
            buf.load(fromByteOffset: offset, as: Float.self)
        }
    }

    func readInt64(at offset: Int) -> Int64 {
        guard offset >= 0, offset + 8 <= data.count else { return 0 }
        return data.withUnsafeBytes { buf in
            buf.load(fromByteOffset: offset, as: Int64.self)
        }
    }

    // MARK: Complex Readers

    /// Read a FlatBuffer string at tablePos + fieldRelOffset.
    func readString(tablePos: Int, fieldRelOffset: Int) -> String? {
        let refPos = tablePos + fieldRelOffset
        guard refPos + 4 <= data.count else { return nil }
        let relOffset = Int(readUInt32(at: refPos))
        guard relOffset > 0 else { return nil }
        let stringPos = refPos + relOffset
        guard stringPos + 4 <= data.count else { return nil }
        let length = Int(readUInt32(at: stringPos))
        let start = stringPos + 4
        guard length > 0, start + length <= data.count else { return nil }
        return String(data: data[start..<(start + length)], encoding: .utf8)
    }

    /// Read a vector of LoRA tables at tablePos + fieldRelOffset.
    func readLoRAVector(tablePos: Int, fieldRelOffset: Int) -> [DTLoRAEntry] {
        let refPos = tablePos + fieldRelOffset
        guard refPos + 4 <= data.count else { return [] }
        let relOffset = Int(readUInt32(at: refPos))
        guard relOffset > 0 else { return [] }
        let vectorPos = refPos + relOffset
        guard vectorPos + 4 <= data.count else { return [] }
        let count = Int(readUInt32(at: vectorPos))
        guard count > 0, count < 100 else { return [] }

        var loras: [DTLoRAEntry] = []
        for i in 0..<count {
            let elemRefPos = vectorPos + 4 + (i * 4)
            guard elemRefPos + 4 <= data.count else { break }
            let elemOffset = Int(readUInt32(at: elemRefPos))
            guard elemOffset > 0 else { continue }
            let elemPos = elemRefPos + elemOffset

            guard elemPos + 4 <= data.count else { break }
            let vtRelOff = readInt32(at: elemPos)
            let vtPos = elemPos - Int(vtRelOff)
            guard vtPos >= 0, vtPos + 4 <= data.count else { break }
            let vtSize = Int(readUInt16(at: vtPos))

            // LoRA table: file (slot 4, string), weight (slot 6, float)
            var file = ""
            var weight: Float = 0.6

            if 6 <= vtSize {
                let foff = Int(readUInt16(at: vtPos + 4))
                if foff > 0, let str = readString(tablePos: elemPos, fieldRelOffset: foff) {
                    file = str
                }
            }
            if 8 <= vtSize {
                let foff = Int(readUInt16(at: vtPos + 6))
                if foff > 0 {
                    weight = readFloat(at: elemPos + foff)
                }
            }

            if !file.isEmpty {
                loras.append(DTLoRAEntry(file: file, weight: weight))
            }
        }
        return loras
    }
}

// MARK: - Database Reader

/// Read-only SQLite reader for Draw Things project databases.
/// Intentionally NOT @MainActor — all operations are thread-safe for use from background queues.
final class DTProjectDatabase: @unchecked Sendable {
    // `db` is assigned exactly once in init and never mutated after that, so `let`
    // is correct. `nonisolated(unsafe)` is still required because OpaquePointer is
    // not Sendable, but immutability eliminates any real data-race risk.
    private nonisolated(unsafe) let db: OpaquePointer?
    let fileURL: URL

    init?(fileURL: URL) {
        self.fileURL = fileURL
        var dbPtr: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX

        // Try normal read-only open first
        if sqlite3_open_v2(fileURL.path, &dbPtr, flags, nil) == SQLITE_OK {
            self.db = dbPtr
            return
        }

        // Fallback: use immutable=1 URI for read-only/external/non-APFS media
        // This skips WAL sidecar creation and file locking, which fail on
        // exFAT, FAT32, NTFS, and read-only volumes.
        let escaped = fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileURL.path
        let uri = "file://\(escaped)?immutable=1"
        let uriFlags = flags | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &dbPtr, uriFlags, nil) == SQLITE_OK else {
            return nil
        }
        self.db = dbPtr
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    /// Total number of entries in the database.
    func entryCount() -> Int {
        guard let db = db else { return 0 }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM tensorhistorynode", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// Fetch generation entries with pagination, newest first.
    func fetchEntries(offset: Int = 0, limit: Int = 200) -> [DTGenerationEntry] {
        guard let db = db else { return [] }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let sql = "SELECT rowid, __pk0, __pk1, p FROM tensorhistorynode ORDER BY rowid DESC LIMIT ? OFFSET ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        sqlite3_bind_int(stmt, 2, Int32(offset))

        var entries: [DTGenerationEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowid = sqlite3_column_int64(stmt, 0)
            let pk0 = sqlite3_column_int64(stmt, 1)
            let pk1 = sqlite3_column_int64(stmt, 2)

            guard let blobPtr = sqlite3_column_blob(stmt, 3) else { continue }
            let blobSize = Int(sqlite3_column_bytes(stmt, 3))
            guard blobSize > 0 else { continue }

            let blob = Data(bytes: blobPtr, count: blobSize)
            if let entry = parseEntry(rowid: rowid, lineage: pk0, logicalTime: pk1, blob: blob) {
                entries.append(entry)
            }
        }
        return entries
    }

    /// Known thumbnail table names. Using an enum prevents table-name string interpolation
    /// in SQL queries, which would otherwise be a SQL injection risk if the value were
    /// ever derived from external input.
    private enum ThumbnailTable: String {
        case half = "thumbnailhistoryhalfnode"
        case full = "thumbnailhistorynode"
    }

    /// Fetch a JPEG thumbnail for a generation entry.
    /// The thumbnail tables use a single `__pk0` key which matches the `preview_id`
    /// from the TensorHistoryNode FlatBuffer blob.
    func fetchThumbnail(previewId: Int64) -> NSImage? {
        guard previewId > 0 else { return nil }
        // Try half-res first (smaller, faster)
        if let img = queryThumbnailByPk0(table: .half, pk0: previewId) {
            return img
        }
        // Fall back to full-res
        return queryThumbnailByPk0(table: .full, pk0: previewId)
    }

    /// Fetch the highest-quality available thumbnail (full-res first, then half-res).
    /// Used for video export where quality matters more than speed.
    func fetchFullSizeThumbnail(previewId: Int64) -> NSImage? {
        guard previewId > 0 else { return nil }
        return queryThumbnailByPk0(table: .full, pk0: previewId)
            ?? queryThumbnailByPk0(table: .half, pk0: previewId)
    }

    // MARK: - Private Helpers

    private func parseEntry(rowid: Int64, lineage: Int64, logicalTime: Int64, blob: Data) -> DTGenerationEntry? {
        let fb = FBReader(data: blob)
        guard let (tablePos, vtablePos, vtableSize) = fb.rootTable() else { return nil }

        func foff(_ slot: Int) -> Int? {
            fb.fieldOffset(vtablePos: vtablePos, vtableSize: vtableSize, slot: slot)
        }

        let startWidth = foff(FBReader.VT_START_WIDTH).map { Int(fb.readUInt16(at: tablePos + $0)) } ?? 0
        let startHeight = foff(FBReader.VT_START_HEIGHT).map { Int(fb.readUInt16(at: tablePos + $0)) } ?? 0
        let seed = foff(FBReader.VT_SEED).map { fb.readUInt32(at: tablePos + $0) } ?? 0
        let steps = foff(FBReader.VT_STEPS).map { Int(fb.readUInt32(at: tablePos + $0)) } ?? 0
        let guidanceScale = foff(FBReader.VT_GUIDANCE_SCALE).map { fb.readFloat(at: tablePos + $0) } ?? 0
        let strength = foff(FBReader.VT_STRENGTH).map { fb.readFloat(at: tablePos + $0) } ?? 0
        let wallClockInt = foff(FBReader.VT_WALL_CLOCK).map { fb.readInt64(at: tablePos + $0) } ?? 0
        let samplerByte = foff(FBReader.VT_SAMPLER).map { fb.readUInt8(at: tablePos + $0) } ?? 0
        let seedModeByte = foff(FBReader.VT_SEED_MODE).map { fb.readUInt8(at: tablePos + $0) } ?? 0
        let previewId = foff(FBReader.VT_PREVIEW_ID).map { fb.readInt64(at: tablePos + $0) } ?? 0
        let shift = foff(FBReader.VT_SHIFT).map { fb.readFloat(at: tablePos + $0) } ?? 1.0

        let model = foff(FBReader.VT_MODEL).flatMap { fb.readString(tablePos: tablePos, fieldRelOffset: $0) } ?? ""
        let textPrompt = foff(FBReader.VT_TEXT_PROMPT).flatMap { fb.readString(tablePos: tablePos, fieldRelOffset: $0) } ?? ""
        let negPrompt = foff(FBReader.VT_NEG_TEXT_PROMPT).flatMap { fb.readString(tablePos: tablePos, fieldRelOffset: $0) } ?? ""
        let loras = foff(FBReader.VT_LORAS).map { fb.readLoRAVector(tablePos: tablePos, fieldRelOffset: $0) } ?? []

        let wallClock = wallClockInt > 0
            ? Date(timeIntervalSince1970: TimeInterval(wallClockInt))
            : Date.distantPast

        return DTGenerationEntry(
            id: rowid,
            lineage: lineage,
            logicalTime: logicalTime,
            previewId: previewId,
            prompt: textPrompt,
            negativePrompt: negPrompt,
            model: model,
            width: startWidth * 64,
            height: startHeight * 64,
            steps: steps,
            guidanceScale: guidanceScale,
            seed: seed,
            strength: strength,
            sampler: Self.samplerName(samplerByte),
            seedMode: Self.seedModeName(seedModeByte),
            shift: shift,
            // NOTE: stochasticSamplingGamma is not yet parsed from the FlatBuffer blob
            // because the VTable slot for this field is not yet defined in this reader.
            // The FlatBuffer schema default is 0.3, so we use that as a safe fallback.
            stochasticSamplingGamma: 0.3,
            wallClock: wallClock,
            loras: loras,
            thumbnail: nil
        )
    }

    private func queryThumbnailByPk0(table: ThumbnailTable, pk0: Int64) -> NSImage? {
        guard let db = db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        // table.rawValue is a compile-time constant — safe from SQL injection.
        let sql = "SELECT p FROM \(table.rawValue) WHERE __pk0 = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_int64(stmt, 1, pk0)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let blobPtr = sqlite3_column_blob(stmt, 0) else { return nil }
        let blobSize = Int(sqlite3_column_bytes(stmt, 0))
        guard blobSize > 0 else { return nil }

        return extractJPEG(from: Data(bytes: blobPtr, count: blobSize))
    }

    /// Scan a FlatBuffer blob for JPEG SOI (FF D8) and EOI (FF D9) markers.
    private func extractJPEG(from data: Data) -> NSImage? {
        guard data.count > 4 else { return nil }

        // Find JPEG Start-of-Image
        var jpegStart: Int?
        for i in 0..<(data.count - 1) {
            if data[i] == 0xFF && data[i + 1] == 0xD8 {
                jpegStart = i
                break
            }
        }
        guard let start = jpegStart else { return nil }

        // Find JPEG End-of-Image (scan backward)
        var jpegEnd: Int?
        for i in stride(from: data.count - 1, through: start + 2, by: -1) {
            if data[i] == 0xD9 && data[i - 1] == 0xFF {
                jpegEnd = i + 1
                break
            }
        }
        guard let end = jpegEnd, end > start else { return nil }

        return NSImage(data: Data(data[start..<end]))
    }

    // MARK: - Enum Lookups

    static func samplerName(_ value: UInt8) -> String {
        switch value {
        case 0: return "DPM++ 2M Karras"
        case 1: return "Euler A"
        case 2: return "DDIM"
        case 3: return "PLMS"
        case 4: return "DPM++ SDE Karras"
        case 5: return "UniPC"
        case 6: return "LCM"
        case 7: return "Euler A Substep"
        case 8: return "DPM++ SDE Substep"
        case 9: return "TCD"
        // TCD Trailing — added in Draw Things alongside UniPC AYS (18)
        case 19: return "TCD Trailing"
        case 10: return "Euler A Trailing"
        case 11: return "DPM++ SDE Trailing"
        case 12: return "DPM++ 2M AYS"
        case 13: return "Euler A AYS"
        case 14: return "DPM++ SDE AYS"
        case 15: return "DPM++ 2M Trailing"
        case 16: return "DDIM Trailing"
        case 17: return "UniPC Trailing"
        case 18: return "UniPC AYS"
        default: return "Unknown (\(value))"
        }
    }

    static func seedModeName(_ value: UInt8) -> String {
        switch value {
        case 0: return "Legacy"
        case 1: return "Torch CPU"
        case 2: return "Scale Alike"
        case 3: return "Nvidia GPU"
        default: return "Unknown"
        }
    }

    // MARK: - Delete

    /// Permanently delete a generation entry and its associated thumbnails.
    /// Opens a separate read-write connection (the browsing connection is read-only).
    /// Throws `DTProjectDatabaseError.databaseLocked` if Draw Things has the file open.
    static func deleteEntry(rowid: Int64, previewId: Int64, from fileURL: URL) throws {
        var writeDb: OpaquePointer?
        let openResult = sqlite3_open_v2(
            fileURL.path, &writeDb,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, writeDb != nil else {
            let code = sqlite3_errcode(writeDb)
            sqlite3_close(writeDb)
            if code == SQLITE_BUSY || code == SQLITE_LOCKED {
                throw DTProjectDatabaseError.databaseLocked
            }
            throw DTProjectDatabaseError.cannotOpen("SQLite error \(openResult)")
        }
        defer { sqlite3_close(writeDb) }

        // BEGIN IMMEDIATE fails fast if another writer (Draw Things) holds the DB
        let beginResult = sqlite3_exec(writeDb, "BEGIN IMMEDIATE", nil, nil, nil)
        if beginResult == SQLITE_BUSY || beginResult == SQLITE_LOCKED {
            throw DTProjectDatabaseError.databaseLocked
        }
        guard beginResult == SQLITE_OK else {
            throw DTProjectDatabaseError.deleteFailed("Could not begin transaction (code \(beginResult))")
        }

        // Delete the main generation entry
        var deleteOk = false
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(writeDb, "DELETE FROM tensorhistorynode WHERE rowid = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, rowid)
            deleteOk = sqlite3_step(stmt) == SQLITE_DONE
        }
        sqlite3_finalize(stmt)

        // Delete associated thumbnails (best-effort; don't abort the transaction if missing).
        // ThumbnailTable.rawValue is a compile-time constant — safe from SQL injection.
        if previewId > 0 {
            for table in [ThumbnailTable.half, ThumbnailTable.full] {
                var tStmt: OpaquePointer?
                let sql = "DELETE FROM \(table.rawValue) WHERE __pk0 = ?"
                if sqlite3_prepare_v2(writeDb, sql, -1, &tStmt, nil) == SQLITE_OK {
                    sqlite3_bind_int64(tStmt, 1, previewId)
                    sqlite3_step(tStmt)
                }
                sqlite3_finalize(tStmt)
            }
        }

        if deleteOk {
            sqlite3_exec(writeDb, "COMMIT", nil, nil, nil)
        } else {
            sqlite3_exec(writeDb, "ROLLBACK", nil, nil, nil)
            throw DTProjectDatabaseError.deleteFailed("Row not found or could not be deleted")
        }
    }

    /// Permanently delete multiple generation entries (e.g. all frames of a video clip).
    /// Opens a separate read-write connection; throws `databaseLocked` if Draw Things is open.
    static func deleteEntries(rowids: [Int64], previewIds: [Int64], from fileURL: URL) throws {
        guard !rowids.isEmpty else { return }

        var writeDb: OpaquePointer?
        let openResult = sqlite3_open_v2(
            fileURL.path, &writeDb,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, writeDb != nil else {
            let code = sqlite3_errcode(writeDb)
            sqlite3_close(writeDb)
            throw (code == SQLITE_BUSY || code == SQLITE_LOCKED)
                ? DTProjectDatabaseError.databaseLocked
                : DTProjectDatabaseError.cannotOpen("SQLite error \(openResult)")
        }
        defer { sqlite3_close(writeDb) }

        let beginResult = sqlite3_exec(writeDb, "BEGIN IMMEDIATE", nil, nil, nil)
        if beginResult == SQLITE_BUSY || beginResult == SQLITE_LOCKED {
            throw DTProjectDatabaseError.databaseLocked
        }
        guard beginResult == SQLITE_OK else {
            throw DTProjectDatabaseError.deleteFailed("Could not begin transaction (code \(beginResult))")
        }

        var allSucceeded = true

        for (rowid, previewId) in zip(rowids, previewIds) {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(writeDb, "DELETE FROM tensorhistorynode WHERE rowid = ?", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, rowid)
                let stepResult = sqlite3_step(stmt)
                if stepResult != SQLITE_DONE {
                    allSucceeded = false
                }
            } else {
                allSucceeded = false
            }
            sqlite3_finalize(stmt)

            if previewId > 0 {
                for table in [ThumbnailTable.half, ThumbnailTable.full] {
                    var tStmt: OpaquePointer?
                    let sql = "DELETE FROM \(table.rawValue) WHERE __pk0 = ?"
                    if sqlite3_prepare_v2(writeDb, sql, -1, &tStmt, nil) == SQLITE_OK {
                        sqlite3_bind_int64(tStmt, 1, previewId)
                        let stepResult = sqlite3_step(tStmt)
                        if stepResult != SQLITE_DONE {
                            allSucceeded = false
                        }
                    } else {
                        allSucceeded = false
                    }
                    sqlite3_finalize(tStmt)
                }
            }
        }

        if allSucceeded {
            sqlite3_exec(writeDb, "COMMIT", nil, nil, nil)
        } else {
            sqlite3_exec(writeDb, "ROLLBACK", nil, nil, nil)
            throw DTProjectDatabaseError.deleteFailed("One or more DELETE statements failed; transaction rolled back")
        }
    }
}
