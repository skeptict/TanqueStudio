//
//  DTProjectDatabase.swift
//  TanqueStudio
//
//  Read-only SQLite reader for Draw Things project databases (.sqlite3).
//  Parses FlatBuffer blobs to extract generation metadata and JPEG thumbnails.
//
//  Ported from v0.9.x with video-export and full-res tensor decode removed.
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
    let tensorId: Int64
    let scaleFactor: Float  // scale_factor_by_120 / 120.0
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
    let resolutionDependentShift: Bool
    let stochasticSamplingGamma: Float
    let wallClock: Date
    let loras: [DTLoRAEntry]
    /// The video clip this row belongs to, or nil for a still image. Draw Things
    /// writes `-1` for stills; that sentinel is normalised to nil here so callers
    /// don't have to know it.
    let clipId: Int64?
    /// Position within the clip, contiguous from zero. Zero for stills.
    let indexInClip: Int
    var thumbnail: NSImage?

    var isVideoFrame: Bool { clipId != nil }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: DTGenerationEntry, rhs: DTGenerationEntry) -> Bool { lhs.id == rhs.id }
}

/// A video clip's own record, from Draw Things' separate `clip` table.
///
/// Frame count and fps come free here — no counting rows required, which matters
/// because the browser needs the count *before* it decides how to page.
struct DTClip: Hashable {
    let clipId: Int64
    let count: Int
    let framesPerSecond: Double
    let width: Int
    let height: Int
}

/// One row in the browser's grid: a still, or a whole clip collapsed to one cell.
///
/// This exists so that grouping can happen **before** pagination. The browser used
/// to page raw rows with `LIMIT`/`OFFSET`, which cannot work for series — a
/// 369-frame clip spans several pages and would collapse differently on each one.
/// Slots are computed over the whole table once, then paged.
enum DTBrowserSlot: Hashable {
    case still(rowid: Int64)
    case clip(clipId: Int64, representativeRowid: Int64, frameRowids: [Int64])

    /// The row to parse and show. For a clip that is its first frame, matching how
    /// Draw Things itself presents a clip.
    var representativeRowid: Int64 {
        switch self {
        case .still(let rowid):                 return rowid
        case .clip(_, let representative, _):   return representative
        }
    }

    var frameCount: Int {
        switch self {
        case .still:                        return 1
        case .clip(_, _, let frameRowids):  return frameRowids.count
        }
    }
}

/// Just enough of a row to group it, without paying for prompts, LoRAs or strings.
struct DTRowRef: Hashable {
    let rowid: Int64
    let clipId: Int64?
    let indexInClip: Int
}

// MARK: - FlatBuffer Reader

private struct FBReader {
    let data: Data

    // vtable slot = 4 + 2 * fieldIndex over `table TensorHistoryNode` in tensor_history.fbs
    // declaration order; deprecated fields still occupy a slot.
    static let VT_START_WIDTH: Int = 8
    static let VT_START_HEIGHT: Int = 10
    static let VT_SEED: Int = 12
    static let VT_STEPS: Int = 14
    static let VT_GUIDANCE_SCALE: Int = 16
    static let VT_STRENGTH: Int = 18
    static let VT_MODEL: Int = 20
    static let VT_TENSOR_ID: Int = 22
    static let VT_WALL_CLOCK: Int = 26
    static let VT_SAMPLER: Int = 34
    static let VT_SEED_MODE: Int = 54
    static let VT_LORAS: Int = 64
    static let VT_PREVIEW_ID: Int = 86
    static let VT_SCALE_FACTOR_BY_120: Int = 92
    static let VT_STOCHASTIC_SAMPLING_GAMMA: Int = 152
    static let VT_SHIFT: Int = 136
    static let VT_RESOLUTION_DEPENDENT_SHIFT: Int = 182
    static let VT_TEXT_PROMPT: Int = 200
    static let VT_NEG_TEXT_PROMPT: Int = 202
    // Draw Things' own definition of "this row is a video frame" is `clip_id >= 0`
    // (ImageHistoryManager.swift:635, :1025). It writes one row per frame sharing a
    // clip id, with a sequential index (:984-985), and reads frames back by
    // `TensorHistoryNode.clipId == clip.clipId` (:510) — so the grouping the browser
    // wants is the grouping Draw Things already performs internally.
    static let VT_CLIP_ID: Int = 204
    static let VT_INDEX_IN_A_CLIP: Int = 206

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

    func fieldOffset(vtablePos: Int, vtableSize: Int, slot: Int) -> Int? {
        guard slot >= 0, slot + 2 <= vtableSize else { return nil }
        let offset = Int(readUInt16(at: vtablePos + slot))
        return offset == 0 ? nil : offset
    }

    func readUInt8(at offset: Int) -> UInt8 {
        guard offset >= 0, offset < data.count else { return 0 }
        return data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt8.self) }
    }

    func readUInt16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self) }
    }

    func readInt32(at offset: Int) -> Int32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Int32.self) }
    }

    func readUInt32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
    }

    func readFloat(at offset: Int) -> Float {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Float.self) }
    }

    func readDouble(at offset: Int) -> Double {
        guard offset >= 0, offset + 8 <= data.count else { return 0 }
        return data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Double.self) }
    }

    func readInt64(at offset: Int) -> Int64 {
        guard offset >= 0, offset + 8 <= data.count else { return 0 }
        return data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Int64.self) }
    }

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

            var file = ""
            var weight: Float = 0.6
            if 6 <= vtSize {
                let foff = Int(readUInt16(at: vtPos + 4))
                if foff > 0, let str = readString(tablePos: elemPos, fieldRelOffset: foff) { file = str }
            }
            if 8 <= vtSize {
                let foff = Int(readUInt16(at: vtPos + 6))
                if foff > 0 { weight = readFloat(at: elemPos + foff) }
            }
            if !file.isEmpty { loras.append(DTLoRAEntry(file: file, weight: weight)) }
        }
        return loras
    }
}

// MARK: - Database Reader

final class DTProjectDatabase: @unchecked Sendable {
    private nonisolated(unsafe) let db: OpaquePointer?
    let fileURL: URL

    init?(fileURL: URL) {
        self.fileURL = fileURL
        var dbPtr: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX

        if sqlite3_open_v2(fileURL.path, &dbPtr, flags, nil) == SQLITE_OK {
            self.db = dbPtr
            return
        }

        // Fallback: immutable=1 URI for read-only/external/non-APFS media
        let escaped = fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileURL.path
        let uri = "file://\(escaped)?immutable=1"
        let uriFlags = flags | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &dbPtr, uriFlags, nil) == SQLITE_OK else { return nil }
        self.db = dbPtr
    }

    deinit {
        if let db = db { sqlite3_close(db) }
    }

    func entryCount() -> Int {
        guard let db = db else { return 0 }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM tensorhistorynode", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func fetchEntries(offset: Int = 0, limit: Int = 50) -> [DTGenerationEntry] {
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

    // MARK: - Clips

    /// True when this project has ever contained a video.
    ///
    /// The `clip` table is created **conditionally** — `ImageHistoryManager.swift:1032`
    /// only includes `Clip.self` in the schema for projects that have one — so six of
    /// eleven of Ned's real databases have no such table at all. Probe rather than
    /// assume; querying a missing table is an error, not an empty result.
    func hasClipTable() -> Bool {
        guard let db = db else { return false }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name='clip' LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    /// Every clip in the project, keyed by id. Empty when the project has no videos.
    func fetchClips() -> [Int64: DTClip] {
        guard let db = db, hasClipTable() else { return [:] }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT __pk0, p FROM clip", -1, &stmt, nil) == SQLITE_OK else { return [:] }

        var clips: [Int64: DTClip] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let pk0 = sqlite3_column_int64(stmt, 0)
            guard let blobPtr = sqlite3_column_blob(stmt, 1) else { continue }
            let blobSize = Int(sqlite3_column_bytes(stmt, 1))
            guard blobSize > 0 else { continue }
            let fb = FBReader(data: Data(bytes: blobPtr, count: blobSize))
            guard let (tablePos, vtablePos, vtableSize) = fb.rootTable() else { continue }
            func foff(_ slot: Int) -> Int? {
                fb.fieldOffset(vtablePos: vtablePos, vtableSize: vtableSize, slot: slot)
            }
            // table Clip { clip_id: long; count: int; frames_per_second: double;
            //              width: int; height: int } — slots 4, 6, 8, 10, 12.
            let clipId = foff(4).map { fb.readInt64(at: tablePos + $0) } ?? pk0
            let count  = foff(6).map { Int(fb.readInt32(at: tablePos + $0)) } ?? 0
            let fps    = foff(8).map { fb.readDouble(at: tablePos + $0) } ?? 0
            let width  = foff(10).map { Int(fb.readInt32(at: tablePos + $0)) } ?? 0
            let height = foff(12).map { Int(fb.readInt32(at: tablePos + $0)) } ?? 0
            clips[clipId] = DTClip(clipId: clipId, count: count,
                                   framesPerSecond: fps, width: width, height: height)
        }
        return clips
    }

    // MARK: - Grouping

    /// Row identity and clip membership for every row, newest first — the input the
    /// grouping needs and nothing more.
    ///
    /// This parses every blob in the table, which sounds expensive and isn't: the
    /// FlatBuffer is random-access, so reading two integers costs a vtable lookup
    /// each and no string decoding. It is paid once per database rather than per page.
    func fetchRowRefs() -> [DTRowRef] {
        guard let db = db else { return [] }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT rowid, p FROM tensorhistorynode ORDER BY rowid DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }

        var refs: [DTRowRef] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowid = sqlite3_column_int64(stmt, 0)
            guard let blobPtr = sqlite3_column_blob(stmt, 1) else { continue }
            let blobSize = Int(sqlite3_column_bytes(stmt, 1))
            guard blobSize > 0 else { continue }
            let fb = FBReader(data: Data(bytes: blobPtr, count: blobSize))
            guard let (tablePos, vtablePos, vtableSize) = fb.rootTable() else { continue }
            func foff(_ slot: Int) -> Int? {
                fb.fieldOffset(vtablePos: vtablePos, vtableSize: vtableSize, slot: slot)
            }
            let rawClipId = foff(FBReader.VT_CLIP_ID).map { fb.readInt64(at: tablePos + $0) } ?? -1
            let index = foff(FBReader.VT_INDEX_IN_A_CLIP).map { Int(fb.readInt32(at: tablePos + $0)) } ?? 0
            refs.append(DTRowRef(rowid: rowid,
                                 clipId: rawClipId >= 0 ? rawClipId : nil,
                                 indexInClip: index))
        }
        return refs
    }

    /// Collapse rows into browser slots: one per still, one per clip.
    ///
    /// Pure and static so it can be tested without a database. Two properties matter
    /// and are easy to get wrong:
    ///   - **A clip occupies the position of its first-seen row.** `refs` arrives
    ///     newest-first, so a clip lands where its newest frame was, keeping the grid
    ///     in the order the user expects rather than jumping to wherever frame 0 sits.
    ///   - **The representative is frame 0**, the lowest `indexInClip` — that is the
    ///     frame Draw Things itself shows for a clip.
    static func collapseIntoSlots(_ refs: [DTRowRef]) -> [DTBrowserSlot] {
        var slots: [DTBrowserSlot] = []
        var clipPosition: [Int64: Int] = [:]      // clipId → index into `slots`
        var clipFrames: [Int64: [DTRowRef]] = [:]

        for ref in refs {
            guard let clipId = ref.clipId else {
                slots.append(.still(rowid: ref.rowid))
                continue
            }
            clipFrames[clipId, default: []].append(ref)
            if clipPosition[clipId] == nil {
                clipPosition[clipId] = slots.count
                // Placeholder; rewritten below once every frame is known.
                slots.append(.clip(clipId: clipId, representativeRowid: ref.rowid, frameRowids: []))
            }
        }

        for (clipId, position) in clipPosition {
            let frames = (clipFrames[clipId] ?? []).sorted { $0.indexInClip < $1.indexInClip }
            guard let first = frames.first else { continue }
            slots[position] = .clip(clipId: clipId,
                                    representativeRowid: first.rowid,
                                    frameRowids: frames.map(\.rowid))
        }
        return slots
    }

    /// Fully parse the rows a page of slots needs, keyed by rowid.
    func fetchEntries(rowids: [Int64]) -> [Int64: DTGenerationEntry] {
        guard let db = db, !rowids.isEmpty else { return [:] }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let placeholders = Array(repeating: "?", count: rowids.count).joined(separator: ",")
        let sql = "SELECT rowid, __pk0, __pk1, p FROM tensorhistorynode WHERE rowid IN (\(placeholders))"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        for (i, rowid) in rowids.enumerated() {
            sqlite3_bind_int64(stmt, Int32(i + 1), rowid)
        }

        var byRowid: [Int64: DTGenerationEntry] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowid = sqlite3_column_int64(stmt, 0)
            let pk0 = sqlite3_column_int64(stmt, 1)
            let pk1 = sqlite3_column_int64(stmt, 2)
            guard let blobPtr = sqlite3_column_blob(stmt, 3) else { continue }
            let blobSize = Int(sqlite3_column_bytes(stmt, 3))
            guard blobSize > 0 else { continue }
            let blob = Data(bytes: blobPtr, count: blobSize)
            if let entry = parseEntry(rowid: rowid, lineage: pk0, logicalTime: pk1, blob: blob) {
                byRowid[rowid] = entry
            }
        }
        return byRowid
    }

    private enum ThumbnailTable: String {
        case half = "thumbnailhistoryhalfnode"
        case full = "thumbnailhistorynode"
    }

    func fetchThumbnail(previewId: Int64) -> NSImage? {
        guard previewId > 0 else { return nil }
        return queryThumbnailByPk0(table: .half, pk0: previewId)
            ?? queryThumbnailByPk0(table: .full, pk0: previewId)
    }

    /// Raw JPEG bytes for export. Prefers the full-size preview table (the grid
    /// uses the half-size one) and returns the stored bytes as-is — no re-encode.
    func fetchThumbnailJPEGData(previewId: Int64) -> Data? {
        guard previewId > 0 else { return nil }
        return queryThumbnailData(table: .full, pk0: previewId)
            ?? queryThumbnailData(table: .half, pk0: previewId)
    }

    // MARK: - Private

    private func parseEntry(rowid: Int64, lineage: Int64, logicalTime: Int64, blob: Data) -> DTGenerationEntry? {
        let fb = FBReader(data: blob)
        guard let (tablePos, vtablePos, vtableSize) = fb.rootTable() else { return nil }

        func foff(_ slot: Int) -> Int? {
            fb.fieldOffset(vtablePos: vtablePos, vtableSize: vtableSize, slot: slot)
        }

        let startWidth  = foff(FBReader.VT_START_WIDTH).map  { Int(fb.readUInt16(at: tablePos + $0)) } ?? 0
        let startHeight = foff(FBReader.VT_START_HEIGHT).map { Int(fb.readUInt16(at: tablePos + $0)) } ?? 0
        let seed        = foff(FBReader.VT_SEED).map         { fb.readUInt32(at: tablePos + $0) } ?? 0
        let steps       = foff(FBReader.VT_STEPS).map        { Int(fb.readUInt32(at: tablePos + $0)) } ?? 0
        let guidanceScale = foff(FBReader.VT_GUIDANCE_SCALE).map { fb.readFloat(at: tablePos + $0) } ?? 0
        let strength    = foff(FBReader.VT_STRENGTH).map     { fb.readFloat(at: tablePos + $0) } ?? 0
        let wallClockInt = foff(FBReader.VT_WALL_CLOCK).map  { fb.readInt64(at: tablePos + $0) } ?? 0
        let samplerByte  = foff(FBReader.VT_SAMPLER).map     { fb.readUInt8(at: tablePos + $0) } ?? 0
        let seedModeByte = foff(FBReader.VT_SEED_MODE).map   { fb.readUInt8(at: tablePos + $0) } ?? 0
        let previewId   = foff(FBReader.VT_PREVIEW_ID).map   { fb.readInt64(at: tablePos + $0) } ?? 0
        let tensorId    = foff(FBReader.VT_TENSOR_ID).map    { fb.readInt64(at: tablePos + $0) } ?? 0
        let rawScaleBy120 = foff(FBReader.VT_SCALE_FACTOR_BY_120).map { Int(fb.readInt32(at: tablePos + $0)) } ?? 120
        let scaleFactorBy120 = rawScaleBy120 > 0 ? rawScaleBy120 : 120
        let shift = foff(FBReader.VT_SHIFT).map { fb.readFloat(at: tablePos + $0) } ?? 1.0
        let resolutionDependentShift = foff(FBReader.VT_RESOLUTION_DEPENDENT_SHIFT)
            .map { fb.readUInt8(at: tablePos + $0) != 0 } ?? true
        // Was hardcoded to 0.3. Measured across 2698 rows in three databases the slot
        // is absent in every one, so the hardcode happened to be right for all real
        // data seen — but it was a lie waiting for the first non-default gamma
        // (spec §7.2, "benign today").
        let stochasticSamplingGamma = foff(FBReader.VT_STOCHASTIC_SAMPLING_GAMMA)
            .map { fb.readFloat(at: tablePos + $0) } ?? 0.3
        // -1 is Draw Things' "not a video" sentinel; normalise it away at the boundary.
        let rawClipId = foff(FBReader.VT_CLIP_ID).map { fb.readInt64(at: tablePos + $0) } ?? -1
        let clipId: Int64? = rawClipId >= 0 ? rawClipId : nil
        let indexInClip = foff(FBReader.VT_INDEX_IN_A_CLIP).map { Int(fb.readInt32(at: tablePos + $0)) } ?? 0
        let model      = foff(FBReader.VT_MODEL).flatMap          { fb.readString(tablePos: tablePos, fieldRelOffset: $0) } ?? ""
        let textPrompt = foff(FBReader.VT_TEXT_PROMPT).flatMap    { fb.readString(tablePos: tablePos, fieldRelOffset: $0) } ?? ""
        let negPrompt  = foff(FBReader.VT_NEG_TEXT_PROMPT).flatMap { fb.readString(tablePos: tablePos, fieldRelOffset: $0) } ?? ""
        let loras      = foff(FBReader.VT_LORAS).map { fb.readLoRAVector(tablePos: tablePos, fieldRelOffset: $0) } ?? []

        let wallClock = wallClockInt > 0
            ? Date(timeIntervalSince1970: TimeInterval(wallClockInt))
            : Date.distantPast

        return DTGenerationEntry(
            id: rowid,
            lineage: lineage,
            logicalTime: logicalTime,
            previewId: previewId,
            tensorId: tensorId,
            scaleFactor: Float(scaleFactorBy120) / 120.0,
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
            resolutionDependentShift: resolutionDependentShift,
            stochasticSamplingGamma: stochasticSamplingGamma,
            wallClock: wallClock,
            loras: loras,
            clipId: clipId,
            indexInClip: indexInClip,
            thumbnail: nil
        )
    }

    private func queryThumbnailByPk0(table: ThumbnailTable, pk0: Int64) -> NSImage? {
        queryThumbnailData(table: table, pk0: pk0).flatMap { NSImage(data: $0) }
    }

    private func queryThumbnailData(table: ThumbnailTable, pk0: Int64) -> Data? {
        guard let db = db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT p FROM \(table.rawValue) WHERE __pk0 = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_int64(stmt, 1, pk0)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let blobPtr = sqlite3_column_blob(stmt, 0) else { return nil }
        let blobSize = Int(sqlite3_column_bytes(stmt, 0))
        guard blobSize > 0 else { return nil }
        return extractJPEGData(from: Data(bytes: blobPtr, count: blobSize))
    }

    private func extractJPEGData(from data: Data) -> Data? {
        guard data.count > 4 else { return nil }
        var jpegStart: Int?
        for i in 0..<(data.count - 1) {
            if data[i] == 0xFF && data[i + 1] == 0xD8 { jpegStart = i; break }
        }
        guard let start = jpegStart else { return nil }
        var jpegEnd: Int?
        for i in stride(from: data.count - 1, through: start + 2, by: -1) {
            if data[i] == 0xD9 && data[i - 1] == 0xFF { jpegEnd = i + 1; break }
        }
        guard let end = jpegEnd, end > start else { return nil }
        return Data(data[start..<end])
    }

    // MARK: - Enum Lookups

    static func samplerName(_ value: UInt8) -> String {
        switch value {
        case 0:  return "DPM++ 2M Karras"
        case 1:  return "Euler A"
        case 2:  return "DDIM"
        case 3:  return "PLMS"
        case 4:  return "DPM++ SDE Karras"
        case 5:  return "UniPC"
        case 6:  return "LCM"
        case 7:  return "Euler A Substep"
        case 8:  return "DPM++ SDE Substep"
        case 9:  return "TCD"
        case 10: return "Euler A Trailing"
        case 11: return "DPM++ SDE Trailing"
        case 12: return "DPM++ 2M AYS"
        case 13: return "Euler A AYS"
        case 14: return "DPM++ SDE AYS"
        case 15: return "DPM++ 2M Trailing"
        case 16: return "DDIM Trailing"
        case 17: return "UniPC Trailing"
        case 18: return "UniPC AYS"
        case 19: return "TCD Trailing"
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

    static func deleteEntry(rowid: Int64, previewId: Int64, from fileURL: URL) throws {
        var writeDb: OpaquePointer?
        let openResult = sqlite3_open_v2(fileURL.path, &writeDb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil)
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

        var deleteOk = false
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(writeDb, "DELETE FROM tensorhistorynode WHERE rowid = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, rowid)
            deleteOk = sqlite3_step(stmt) == SQLITE_DONE
        }
        sqlite3_finalize(stmt)

        if previewId > 0 {
            for table in ["thumbnailhistoryhalfnode", "thumbnailhistorynode"] {
                var tStmt: OpaquePointer?
                if sqlite3_prepare_v2(writeDb, "DELETE FROM \(table) WHERE __pk0 = ?", -1, &tStmt, nil) == SQLITE_OK {
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
}
