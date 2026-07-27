//
//  DTClipAudio.swift
//  TanqueStudio
//
//  A Draw Things clip's soundtrack.
//
//  Draw Things has stored audio per clip since some time after our January
//  schema snapshot — `Clip.audio_id` points at an fpzip-compressed Float32
//  tensor in the same `tensors` table the images live in. Every clip measured on
//  this machine has one, and Tanque Studio ignored all of them until now.
//

import Foundation
import AVFoundation

enum DTClipAudio {

    /// The only rates Draw Things produces. They are 2× apart, which is what
    /// makes picking the nearest safe.
    static let candidateSampleRates: [Double] = [48_000, 24_000]

    /// Draw Things does not record the sample rate, so it has to be inferred
    /// from how long the clip runs and how many samples that covers.
    ///
    /// Measured over all 12 clips on this machine, the computed rate lands within
    /// **0.62%** of 48000 — the samples cover fractionally less time than
    /// `count / fps` implies. Snapping to the nearest candidate absorbs that;
    /// with the two candidates an octave apart, a sub-1% error cannot cross over
    /// and pick the wrong one. Using the raw computed rate instead would detune
    /// every clip by a few cents.
    static func sampleRate(framesPerChannel: Int, clipDuration: TimeInterval) -> Double {
        guard clipDuration > 0, framesPerChannel > 0 else { return 48_000 }
        let measured = Double(framesPerChannel) / clipDuration
        return candidateSampleRates.min { abs($0 - measured) < abs($1 - measured) } ?? 48_000
    }

    /// Wraps planar Float32 samples in a WAV container.
    ///
    /// A container rather than an `AVAudioPCMBuffer` because `AVAudioPlayer`
    /// takes `Data` and gives us `currentTime` for free — and that clock is what
    /// keeps the frames in step with the sound (see `DTClipPlaybackView`).
    ///
    /// The tensor is **planar** — all of the left channel, then all of the right —
    /// and WAV is interleaved, so this is a transpose, not a copy.
    static func wav(from track: DTProjectDatabase.AudioTrack, sampleRate: Double) -> Data? {
        let channels = track.channels
        let frames = track.framesPerChannel
        guard channels > 0, frames > 0 else { return nil }
        guard track.samples.count >= channels * frames * MemoryLayout<Float>.size else { return nil }

        let bitsPerSample = 32
        let bytesPerFrame = channels * bitsPerSample / 8
        let dataBytes = frames * bytesPerFrame

        var out = Data(capacity: 44 + dataBytes)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) }
        }

        out.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataBytes))
        out.append(contentsOf: Array("WAVE".utf8))
        out.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(3))                       // IEEE float, not PCM integer
        append(UInt16(channels))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * Double(bytesPerFrame)))
        append(UInt16(bytesPerFrame))
        append(UInt16(bitsPerSample))
        out.append(contentsOf: Array("data".utf8))
        append(UInt32(dataBytes))

        var interleaved = [Float](repeating: 0, count: frames * channels)
        track.samples.withUnsafeBytes { raw in
            let planar = raw.bindMemory(to: Float.self)
            for channel in 0..<channels {
                let base = channel * frames
                for frame in 0..<frames {
                    interleaved[frame * channels + channel] = planar[base + frame]
                }
            }
        }
        interleaved.withUnsafeBytes { out.append(contentsOf: $0) }
        return out
    }
}

// MARK: - Player

/// Plays a clip's audio and reports where it is, so playback can follow it.
///
/// **The audio is the clock when it is playing.** Frames derived from `Date`
/// and sound played by the audio hardware run on different oscillators, so over
/// a ten-second clip they visibly separate. Driving the frame index from
/// `currentTime` instead means the picture cannot drift from the sound — the
/// same reason dtm has an `AudioFrameSync` distinct from its plain `FrameSync`.
@MainActor
@Observable
final class DTClipAudioPlayer {

    private(set) var isAvailable = false
    /// Off by default. Hover previews stay silent (Ned, 2026-07-26); this only
    /// ever unmutes from the detail panel.
    var isMuted = true

    private var player: AVAudioPlayer?
    private var loadedKey: Int64?

    /// Seconds into the clip, or nil when there is nothing playing to follow.
    var currentTime: TimeInterval? {
        guard let player, player.isPlaying else { return nil }
        return player.currentTime
    }

    func load(clipKey: Int64, audioId: Int64, frameCount: Int, fps: Double, from url: URL) {
        guard loadedKey != clipKey else { return }
        unload()
        loadedKey = clipKey

        guard audioId > 0, fps > 0, frameCount > 0 else { return }
        guard let db = DTProjectDatabase(fileURL: url),
              let track = db.fetchAudio(audioId: audioId) else { return }

        let rate = DTClipAudio.sampleRate(framesPerChannel: track.framesPerChannel,
                                          clipDuration: Double(frameCount) / fps)
        guard let wav = DTClipAudio.wav(from: track, sampleRate: rate),
              let player = try? AVAudioPlayer(data: wav) else { return }

        player.numberOfLoops = -1          // matches the picture, which also loops
        player.prepareToPlay()
        self.player = player
        isAvailable = true
    }

    func unload() {
        player?.stop()
        player = nil
        loadedKey = nil
        isAvailable = false
    }

    func play() {
        guard let player, !isMuted else { return }
        player.currentTime = 0
        player.play()
    }

    func pause() { player?.pause() }

    func resume(fromFrame frame: Int, fps: Double) {
        guard let player, !isMuted, fps > 0 else { return }
        player.currentTime = Double(frame) / fps
        player.play()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
    }
}
