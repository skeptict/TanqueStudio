//
//  RenderAudio.swift
//  TanqueStudio
//
//  Turns the audio Draw Things emits during a render into something
//  `VideoAssembler` can mux.
//
//  Until 0.9.47 the app never asked for this at all: every render path called
//  `generateImage`, which passes a no-op audio handler, so LTX's soundtrack was
//  decoded by the client library and dropped on the floor. `VideoAssembler` has
//  accepted an audio track since 0.9.34 — but only the DT Project Browser export
//  ever passed one, and that reads the track out of Draw Things' own database
//  rather than from a live render.
//

import Foundation
import AVFoundation
import DrawThingsClient
import os

enum RenderAudio {

    private static let logger = Logger(subsystem: "tanque.org.TanqueStudio", category: "RenderAudio")

    /// Build a muxable track from the raw ccv tensors a generate emitted.
    ///
    /// Returns nil when there is no audio, when it will not decode, or when the
    /// frame count is too small to derive a rate — in every case the caller should
    /// carry on and write a silent movie rather than fail. A clip without sound is
    /// worth having; a failed export is not.
    ///
    /// - Parameters:
    ///   - tensors: what the generate's audio handler collected. LTX sends one
    ///     tensor for the whole clip, not one per frame; extra tensors are ignored
    ///     rather than concatenated, because nothing has been seen to send them and
    ///     guessing at the join is worse than dropping them loudly in the log.
    ///   - frameCount: frames in the clip — with `fps`, this is what fixes the rate.
    static func track(fromTensors tensors: [Data], frameCount: Int, fps: Int32) -> VideoAssembler.Audio? {
        guard let tensor = tensors.first else { return nil }
        if tensors.count > 1 {
            logger.warning("\(tensors.count) audio tensors for one clip; using the first only")
        }
        guard frameCount > 1, fps > 0 else { return nil }

        // Two decodes on purpose. The first is only to learn the sample count,
        // because the rate has to be derived from it — and the rate has to be
        // right *before* the WAV header is written, since that header is the only
        // thing telling AVFoundation how fast to play the samples back.
        guard let probe = try? AudioHelpers.ccvTensorToAudioBuffer(tensor) else {
            logger.error("audio tensor (\(tensor.count) bytes) would not decode")
            return nil
        }
        let samplesPerChannel = Int(probe.frameLength)
        guard samplesPerChannel > 0 else { return nil }

        let rate = sampleRate(samplesPerChannel: samplesPerChannel, frameCount: frameCount, fps: fps)
        guard let buffer = try? AudioHelpers.ccvTensorToAudioBuffer(tensor, sampleRate: rate),
              let wav = try? AudioHelpers.audioBufferToWAVData(buffer) else {
            logger.error("audio would not re-encode at \(rate) Hz")
            return nil
        }
        logger.info("""
            audio: \(Int(buffer.format.channelCount))ch × \(samplesPerChannel) \
            samples @ \(Int(rate))Hz over \(frameCount) frames
            """)
        return VideoAssembler.Audio(wav: wav,
                                    channels: Int(buffer.format.channelCount),
                                    sampleRate: rate)
    }

    /// Draw Things does not send the sample rate, so it has to be inferred.
    ///
    /// **The duration is `(frameCount - 1) / fps`, not `frameCount / fps`** — N
    /// frames span N-1 intervals. Measured across eight clips from Draw Things'
    /// own databases (121 to 1121 frames), that lands every one within **0.21%**
    /// of 48 kHz or 24 kHz; dividing by `frameCount / fps` instead spreads them to
    /// 0.62%. Both snap to the right candidate, but the tighter one is the true
    /// model, and it is independent corroboration that LTX runs at 25 fps
    /// (`DrawThingsGenerationConfig.playbackFPS`).
    ///
    /// Snapping to a candidate rather than using the measured number is deliberate
    /// and copied from `DTClipAudio.sampleRate`: the two candidates are an octave
    /// apart, so a sub-1% error cannot pick the wrong one, while using the raw
    /// figure would detune every clip by a few cents.
    ///
    /// ⚠️ Short clips are the loose end. A live 25-frame render measured 48500 Hz —
    /// 1.04% high, the worst of any sample seen, apparently because padding is a
    /// larger fraction of a short clip. It still snaps to 48 kHz correctly, but do
    /// not tighten these candidates without re-measuring short clips.
    static func sampleRate(samplesPerChannel: Int, frameCount: Int, fps: Int32) -> Double {
        let duration = Double(frameCount - 1) / Double(fps)
        guard duration > 0 else { return 48_000 }
        let measured = Double(samplesPerChannel) / duration
        return DTClipAudio.candidateSampleRates
            .min { abs($0 - measured) < abs($1 - measured) } ?? 48_000
    }
}
