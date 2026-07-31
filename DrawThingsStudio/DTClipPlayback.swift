//
//  DTClipPlayback.swift
//  TanqueStudio
//
//  Playing a Draw Things video clip out of a project database.
//
//  The approach is the one KC Jerrell's dtm uses over the same data, and it is
//  worth saying why rather than assuming: it does NOT assemble a movie. It
//  decodes every frame once, then blits one already-decoded frame per display
//  tick. Assembling an .mp4 to preview a clip would cost an encode pass and a
//  temp file before the first frame appears; that path is kept for export, where
//  a file is the point.
//

import SwiftUI
import AppKit
import ImageIO

// MARK: - Clock

/// Which frame of a clip should be on screen after `elapsed` seconds.
///
/// **The index is derived from elapsed time, never incremented.** A dropped tick
/// then costs one frame instead of permanently shifting playback behind the
/// clock, and looping falls out of the modulus for free. Pure and separately
/// tested — the timing is the part most likely to be subtly wrong.
enum DTClipClock {
    static func frame(elapsed: TimeInterval, fps: Double, frameCount: Int) -> Int {
        guard frameCount > 0 else { return 0 }
        guard fps > 0, elapsed > 0 else { return 0 }
        let raw = Int((elapsed * fps).rounded(.down))
        return raw % frameCount
    }
}

// MARK: - Frame loading

/// Decodes a clip's frames and holds them ready to draw.
///
/// Frames are published **only once the whole clip is decoded** (Ned, 2026-07-26).
/// The alternative — start at the first N and grow — makes the loop length change
/// underneath a time-derived index, so a hover would begin as a stuttering
/// short loop and lengthen. Holding frame 0 until it can play properly is the
/// honest presentation of a clip that is not ready yet.
@MainActor
@Observable
final class DTClipFrameLoader {

    /// Decoded frames in clip order, empty until the whole clip is in.
    private(set) var frames: [CGImage] = []
    private(set) var isLoading = false
    /// The clip currently loaded or loading, by its representative rowid.
    private(set) var clipKey: Int64?
    /// When the frames became available — playback's clock origin. Taken here
    /// rather than at hover so a clip always starts from frame 0 however long it
    /// took to decode.
    private(set) var readyAt: Date?

    private var task: Task<Void, Never>?

    /// Longest edge to decode to.
    ///
    /// Frames are decoded at display size rather than stored size, which a
    /// browser cannot do — dtm's `<img>` preload decodes at natural size. The
    /// difference is the whole memory budget: a 257-frame 2:1 clip is ~250 MB
    /// decoded at the stored half-size, and ~34 MB at 384. Big enough for a grid
    /// cell and for the detail column; raise it if playback looks soft.
    static let decodeMaxPixelSize = 384

    func load(clipKey key: Int64, frameRowids: [Int64], from url: URL) {
        guard clipKey != key else { return }   // already showing or fetching this clip
        cancel()
        clipKey = key
        isLoading = true

        task = Task { [maxPixel = Self.decodeMaxPixelSize] in
            let decoded = await Task.detached(priority: .userInitiated) { () -> [CGImage] in
                guard let db = DTProjectDatabase(fileURL: url) else { return [] }
                let entries = db.fetchEntries(rowids: frameRowids)
                var images: [CGImage] = []
                images.reserveCapacity(frameRowids.count)
                // frameRowids is already in clip order; fetchEntries returns a
                // dictionary, so the order has to come from the request.
                for rowid in frameRowids {
                    if Task.isCancelled { return [] }
                    guard let previewId = entries[rowid]?.previewId,
                          let data = db.fetchThumbnailJPEGData(previewId: previewId),
                          let image = Self.decode(data, maxPixelSize: maxPixel)
                    else { continue }
                    images.append(image)
                }
                return images
            }.value

            guard !Task.isCancelled else { return }
            frames = decoded
            readyAt = Date()
            isLoading = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        frames = []
        readyAt = nil
        isLoading = false
        clipKey = nil
    }

    /// Decodes straight to the size we will draw at. `CreateThumbnailFromImageAlways`
    /// matters: without it ImageIO returns an embedded thumbnail when the JPEG has
    /// one, which is far smaller than asked for and visibly mushy.
    nonisolated static func decode(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

// MARK: - Playback surface

/// Draws the current frame of a loaded clip.
///
/// A `Canvas` rather than an `Image` per frame: at 25fps a new `Image` view every
/// tick churns view identity for no benefit, where a Canvas redraws in place.
/// `TimelineView(.animation)` is the display-linked tick — the AppKit equivalent
/// of the `requestAnimationFrame` loop this design is modelled on.
struct DTClipPlaybackView: View {
    let frames: [CGImage]
    let fps: Double
    /// Where the scrubber is parked. Used while paused; playback ignores it.
    let pausedIndex: Int
    let isPlaying: Bool
    /// Playback's own clock origin, owned by the caller so pausing can snap the
    /// scrubber to wherever playback had got to.
    let startedAt: Date
    /// Seconds into the clip according to the audio, when sound is playing.
    ///
    /// **When there is audio, it is the clock.** Frames timed from `Date` and
    /// sound played by the audio hardware run off different oscillators; over a
    /// ten-second clip they separate visibly. Following the audio's own position
    /// makes drift impossible rather than merely small.
    var audioTime: () -> TimeInterval? = { nil }

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { context in
            let elapsed = audioTime() ?? context.date.timeIntervalSince(startedAt)
            let index = isPlaying
                ? DTClipClock.frame(elapsed: elapsed,
                                    fps: fps,
                                    frameCount: frames.count)
                : min(max(pausedIndex, 0), max(frames.count - 1, 0))

            Canvas { ctx, size in
                guard frames.indices.contains(index) else { return }
                ctx.draw(Image(decorative: frames[index], scale: 1),
                         in: CGRect(origin: .zero, size: size))
            }
        }
    }

    /// The frame playback is on right now — used to hand the scrubber a sensible
    /// position when the user hits pause.
    static func liveIndex(startedAt: Date, fps: Double, frameCount: Int) -> Int {
        DTClipClock.frame(elapsed: Date().timeIntervalSince(startedAt),
                          fps: fps,
                          frameCount: frameCount)
    }
}

// MARK: - Export

/// What "export this clip" means. Offered as a choice rather than guessed at,
/// because all three are reasonable and they differ by three orders of magnitude
/// in output size.
enum DTSeriesExportMode: String, CaseIterable, Identifiable {
    case coverFrame
    case allFrames
    case movie

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coverFrame: return "Cover frame only"
        case .allFrames:  return "All frames (JPEG)"
        case .movie:      return "Movie (.mp4)"
        }
    }

    /// Wording for a whole-project export, where the same choice applies to many
    /// clips at once and "only" / "all" read as being about the project rather than
    /// about one render.
    var bulkTitle: String {
        switch self {
        case .coverFrame: return "One image per cell"
        case .allFrames:  return "Every frame as JPEG"
        case .movie:      return "Movies for clips, images for stills"
        }
    }

    func detail(frameCount: Int, fps: Double) -> String {
        switch self {
        case .coverFrame:
            return "One image — the frame Draw Things shows for this render."
        case .allFrames:
            return "\(frameCount) images, numbered in order."
        case .movie:
            let seconds = fps > 0 ? Double(frameCount) / fps : 0
            return String(format: "One file, %.1fs at %g fps.", seconds, fps)
        }
    }
}

/// Asks which shape a whole-project export should take.
///
/// The same three choices as a single clip, applied to every clip in the project —
/// which is the point: "Export All" should do to all of them what "Export Series…"
/// does to one, rather than offering a second, different set of options.
///
/// **Shown only when the export actually contains a clip.** For a project of stills
/// all three modes produce identical output, and a chooser with one real answer is
/// just a step in the way.
///
/// The file counts come from the plan, not from the mode, so the sheet cannot promise
/// a different number than the exporter goes on to write — a five-clip project reads
/// "5 movies with sound, plus 43 stills" against "1,285 files", which is the whole
/// reason this screen exists.
struct DTBulkExportSheet: View {
    let title: String
    let cellCount: Int
    let clipCount: Int
    /// Plan summary per mode, prepared by the caller from the view model.
    let detail: (DTSeriesExportMode) -> String
    let onCancel: () -> Void
    let onExport: (DTSeriesExportMode) -> Void

    @State private var mode: DTSeriesExportMode = .movie

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DashboardDS.text)
                Text("\(cellCount) cell\(cellCount == 1 ? "" : "s"), "
                     + "\(clipCount) of them video clip\(clipCount == 1 ? "" : "s")")
                    .font(TanqueDS.Font.mono(11))
                    .foregroundStyle(DashboardDS.muted)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(DTSeriesExportMode.allCases) { option in
                    Button { mode = option } label: {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: mode == option ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(mode == option ? DashboardDS.brass : DashboardDS.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.bulkTitle)
                                    .font(TanqueDS.Font.monoSemiBold(11.5))
                                    .foregroundStyle(DashboardDS.text)
                                Text(detail(option))
                                    .font(TanqueDS.Font.mono(10.5))
                                    .foregroundStyle(DashboardDS.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(9)
                        .background(mode == option ? DashboardDS.brassSubtle : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(DashboardGhostButtonStyle())
                Button("Export…") { onExport(mode) }
                    .buttonStyle(DashboardPrimaryButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(DashboardDS.surf1)
    }
}

/// Asks which shape a clip export should take.
///
/// A sheet rather than three context-menu items: the three outputs differ by
/// orders of magnitude in size and count, and the numbers that make the choice
/// obvious (how many frames, how long) belong next to the options.
struct DTSeriesExportSheet: View {
    let frameCount: Int
    let fps: Double
    let onCancel: () -> Void
    let onExport: (DTSeriesExportMode) -> Void

    @State private var mode: DTSeriesExportMode = .movie

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export Video Series")
                    .font(.headline)
                    .foregroundStyle(DashboardDS.text)
                Text("\(frameCount) frames at \(Int(fps)) fps")
                    .font(TanqueDS.Font.mono(11))
                    .foregroundStyle(DashboardDS.muted)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(DTSeriesExportMode.allCases) { option in
                    Button { mode = option } label: {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: mode == option ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(mode == option ? DashboardDS.brass : DashboardDS.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(TanqueDS.Font.monoSemiBold(11.5))
                                    .foregroundStyle(DashboardDS.text)
                                Text(option.detail(frameCount: frameCount, fps: fps))
                                    .font(TanqueDS.Font.mono(10.5))
                                    .foregroundStyle(DashboardDS.muted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(9)
                        .background(mode == option ? DashboardDS.brassSubtle : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(DashboardGhostButtonStyle())
                    .fixedSize()
                Button("Export…") { onExport(mode) }
                    .buttonStyle(DashboardPrimaryButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(DashboardDS.bg)
    }
}
