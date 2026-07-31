//
//  DTExportPlan.swift
//  TanqueStudio
//
//  What a project-wide export will actually write, decided before anything is written.
//

import Foundation

/// The outputs one export will produce, grouped by kind.
///
/// **Separated from the writing on purpose.** The defect this replaces was a planning
/// mistake, not an I/O one: Export All paged over raw database rows while the grid
/// showed grouped slots, so a five-clip project wrote ~1,285 loose frames named by
/// rowid. Nothing about that is visible in the code that writes a file — it is visible
/// in what the file list *should have been*. A pure function producing that list can be
/// tested without a database, which is the only reason the counts below are trustworthy.
struct DTExportPlan: Equatable {
    /// Rowids to write as a single image each — plain stills, plus clip cover frames
    /// when the mode asks for covers.
    var images: [Int64] = []
    /// Clips to write as a numbered JPEG sequence, in clip order.
    var frameSequences: [(clipId: Int64, rowids: [Int64])] = []
    /// Clips to assemble into a movie, in clip order.
    var movies: [(clipId: Int64, rowids: [Int64])] = []

    /// How many files land on disk. What the confirmation sheet promises.
    var fileCount: Int {
        images.count + movies.count + frameSequences.reduce(0) { $0 + $1.rowids.count }
    }

    /// How many clips this export covers, however they are being written.
    var clipCount: Int { frameSequences.count + movies.count }

    static func == (lhs: DTExportPlan, rhs: DTExportPlan) -> Bool {
        lhs.images == rhs.images
            && lhs.frameSequences.map(\.rowids) == rhs.frameSequences.map(\.rowids)
            && lhs.frameSequences.map(\.clipId) == rhs.frameSequences.map(\.clipId)
            && lhs.movies.map(\.rowids) == rhs.movies.map(\.rowids)
            && lhs.movies.map(\.clipId) == rhs.movies.map(\.clipId)
    }
}

extension DTExportPlan {

    /// Turns browser slots into the files an export of `mode` will write.
    ///
    /// A still is one image under every mode — the three modes only differ in what they
    /// do with a *clip*, which is why this reuses `DTSeriesExportMode` rather than
    /// inventing a parallel set of project-wide options. Whatever "Export Series…" does
    /// to one clip, this does to all of them.
    ///
    /// Slot order is preserved throughout, so exported names sort the way the grid reads.
    static func plan(slots: [DTBrowserSlot], mode: DTSeriesExportMode) -> DTExportPlan {
        var plan = DTExportPlan()
        for slot in slots {
            switch slot {
            case .still(let rowid):
                plan.images.append(rowid)

            case .clip(let clipId, let representative, let frameRowids):
                // A clip whose frame list came back empty still has a representative row
                // worth exporting. Dropping it silently is how a project ends up
                // exporting fewer files than it has cells — see the browser's own
                // grouping notes on filters that drop rows.
                guard !frameRowids.isEmpty else {
                    plan.images.append(representative)
                    continue
                }
                switch mode {
                case .coverFrame:
                    plan.images.append(representative)
                case .allFrames:
                    plan.frameSequences.append((clipId: clipId, rowids: frameRowids))
                case .movie:
                    plan.movies.append((clipId: clipId, rowids: frameRowids))
                }
            }
        }
        return plan
    }

    /// One line describing what this mode will produce, for the confirmation sheet.
    ///
    /// Written from the plan rather than from the mode, so the sheet cannot promise
    /// something different from what the exporter goes on to do.
    func summary(for mode: DTSeriesExportMode) -> String {
        let stills = images.count
        switch mode {
        case .coverFrame:
            return "\(fileCount) image\(fileCount == 1 ? "" : "s") — one per cell in the grid."
        case .allFrames:
            let frames = frameSequences.reduce(0) { $0 + $1.rowids.count }
            if clipCount == 0 { return "\(stills) image\(stills == 1 ? "" : "s")." }
            return "\(fileCount) files — \(stills) still\(stills == 1 ? "" : "s") "
                + "plus every frame of \(clipCount) clip\(clipCount == 1 ? "" : "s") (\(frames))."
        case .movie:
            if clipCount == 0 { return "\(stills) image\(stills == 1 ? "" : "s") — this project has no clips." }
            return "\(clipCount) movie\(clipCount == 1 ? "" : "s") with sound"
                + (stills > 0 ? ", plus \(stills) still\(stills == 1 ? "" : "s")." : ".")
        }
    }
}
