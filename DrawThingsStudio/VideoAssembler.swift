//
//  VideoAssembler.swift
//  DrawThingsStudio
//
//  Assembles a video frame series into an H.264 .mp4 with AVAssetWriter.
//  Ported from DTS-AppleTV/Services/VideoAssembler.swift (UIImage → NSImage/CGImage);
//  adapted to stream frames from disk one at a time instead of taking [UIImage],
//  so a 450-frame series never sits in memory all at once.
//

import AVFoundation
import AppKit

enum VideoAssemblerError: Error {
    case noFrames
    case setupFailed
    case frameLoadFailed(Int)
    case pixelBufferFailed
    case writeFailed(String)
    case audioReadFailed(String)
}

struct VideoAssembler {

    /// A clip's soundtrack, ready to mux.
    ///
    /// Carried as a WAV container rather than raw samples because that is what
    /// `DTClipAudio.wav(from:sampleRate:)` already produces for playback, and what
    /// `AVAssetReader` can open without us hand-building format descriptions.
    struct Audio {
        let wav: Data
        let channels: Int
        let sampleRate: Double
    }

    /// Target bits per pixel per frame.
    ///
    /// dtm asks x264 for `-crf 18` — near-visually-lossless — which AVFoundation's
    /// H.264 encoder has no equivalent for; it wants an average bitrate. 0.25 bpp is
    /// generous for diffusion output, which is smooth and compresses well, and these
    /// clips are seconds long rather than minutes. A floor keeps very small canvases
    /// from being starved.
    private static let bitsPerPixel = 0.25
    private static let minimumBitRate = 2_000_000

    /// Writes `frameURLs` (in order) to `outputURL` as an H.264 .mp4 at `fps`,
    /// optionally muxing `audio` alongside and tagging `metadataComment`.
    /// Cancellable: a partial file is cleaned up when the task is cancelled or a
    /// frame fails mid-write.
    static func assemble(frameURLs: [URL],
                         fps: Int32,
                         audio: Audio? = nil,
                         metadataComment: String? = nil,
                         to outputURL: URL) async throws {
        guard !frameURLs.isEmpty else { throw VideoAssemblerError.noFrames }
        guard let firstFrame = loadCGImage(at: frameURLs[0]) else {
            throw VideoAssemblerError.frameLoadFailed(0)
        }
        let size = CGSize(width: firstFrame.width, height: firstFrame.height)

        // AVAssetWriter refuses to write over an existing file.
        try? FileManager.default.removeItem(at: outputURL)

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            throw VideoAssemblerError.setupFailed
        }

        let pixelsPerFrame = Double(Int(size.width) * Int(size.height))
        let bitRate = max(minimumBitRate,
                          Int(pixelsPerFrame * Double(fps) * bitsPerPixel))

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            // Without these the file carries no colour tags at all and every player
            // guesses — and they guess by frame height, so a 576-tall clip can be
            // decoded as BT.601 and come back visibly shifted. dtm tags BT.709 for
            // the same reason.
            //
            // ⚠️ dtm additionally passes `-color_range pc` (full range). We stay at
            // the H.264 default of video range: matching it properly means feeding
            // the encoder full-range YCbCr buffers rather than just relabelling
            // them, and a wrong label is worse than the honest default. The
            // primaries/transfer/matrix tags are what fix the guessing.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoAllowFrameReorderingKey: true,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: bufferAttributes
        )

        writer.add(writerInput)

        // Audio input has to exist before startWriting, so the reader is opened first
        // even though nothing is pumped through it until the frames are done.
        var audioInput: AVAssetWriterInput?
        var audioReader: AVAssetReader?
        var audioOutput: AVAssetReaderTrackOutput?
        var scratchWAV: URL?

        if let audio {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("tanque-mux-\(UUID().uuidString).wav")
            do {
                try audio.wav.write(to: temp)
                scratchWAV = temp
                let asset = AVURLAsset(url: temp)
                guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                    throw VideoAssemblerError.audioReadFailed("no audio track in the decoded WAV")
                }
                let reader = try AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ])
                guard reader.canAdd(output) else {
                    throw VideoAssemblerError.audioReadFailed("reader rejected the PCM output")
                }
                reader.add(output)

                var layout = AudioChannelLayout()
                layout.mChannelLayoutTag = audio.channels == 1
                    ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: audio.channels,
                    AVSampleRateKey: audio.sampleRate,
                    AVEncoderBitRateKey: 192_000,   // dtm's `-b:a 192k`
                    AVChannelLayoutKey: Data(bytes: &layout,
                                             count: MemoryLayout<AudioChannelLayout>.size)
                ])
                input.expectsMediaDataInRealTime = false
                guard writer.canAdd(input) else {
                    throw VideoAssemblerError.audioReadFailed("writer rejected the AAC input")
                }
                writer.add(input)
                audioInput = input
                audioReader = reader
                audioOutput = output
            } catch {
                if let scratchWAV { try? FileManager.default.removeItem(at: scratchWAV) }
                throw error
            }
        }

        defer { if let scratchWAV { try? FileManager.default.removeItem(at: scratchWAV) } }

        // The DT config that produced the render, mirroring dtm's `-metadata comment=`.
        if let metadataComment {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierDescription
            item.value = metadataComment as NSString
            item.extendedLanguageTag = "und"
            writer.metadata = [item]
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        audioReader?.startReading()

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        do {
            // ⚠️ FEED BOTH INPUTS GREEDILY. Do NOT write all the video and then all the
            // audio, and do NOT gate either input on which track is "behind" in
            // presentation time. Both were tried and both deadlock.
            //
            // AVAssetWriter will not drain an input while another input it is
            // interleaving against sits unfed. Measured on the failing case: stalled at
            // frame 30 of 120 with the video input permanently not-ready and the audio
            // input *ready and asking for data* that the behind-check was withholding
            // because audio led video by 165ms.
            //
            // ⚠️ IT DEADLOCKS BY SIZE, which is what makes it easy to ship. 25 frames of
            // 128×64 fit inside the writer's buffer and passed cleanly; a real 121-frame
            // 704×832 clip hung forever. `testLongClipWithAudioDoesNotDeadlock` is sized
            // to exceed the buffer on purpose.
            //
            // The correct rule is the one `requestMediaDataWhenReady` implements: give
            // each input as much as it will take, whenever it will take it, and let the
            // writer handle interleaving. It has both tracks' timestamps; it does not
            // need us to schedule them.
            var frameIndex = 0
            var pendingAudio: CMSampleBuffer? = audioOutput?.copyNextSampleBuffer()
            var videoDone = false
            var audioDone = (audioInput == nil)

            while !videoDone || !audioDone {
                try Task.checkCancellation()
                var didWork = false

                if !audioDone, let input = audioInput {
                    while !audioDone, input.isReadyForMoreMediaData {
                        guard let buffer = pendingAudio else {
                            if audioReader?.status == .failed {
                                throw VideoAssemblerError.audioReadFailed(
                                    audioReader?.error?.localizedDescription ?? "unknown reader failure")
                            }
                            input.markAsFinished()
                            audioDone = true
                            didWork = true
                            break
                        }
                        input.append(buffer)
                        pendingAudio = audioOutput?.copyNextSampleBuffer()
                        didWork = true
                    }
                }

                if !videoDone, writerInput.isReadyForMoreMediaData {
                    guard let cgImage = frameIndex == 0 ? firstFrame : loadCGImage(at: frameURLs[frameIndex]) else {
                        throw VideoAssemblerError.frameLoadFailed(frameIndex)
                    }
                    guard let pb = makePixelBuffer(from: cgImage, size: size, pool: adaptor.pixelBufferPool) else {
                        throw VideoAssemblerError.pixelBufferFailed
                    }
                    adaptor.append(pb, withPresentationTime:
                        CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex)))
                    frameIndex += 1
                    didWork = true
                    if frameIndex == frameURLs.count {
                        writerInput.markAsFinished()
                        videoDone = true
                    }
                }

                // Neither input would take anything this pass — yield rather than spin.
                if !didWork { try await Task.sleep(nanoseconds: 5_000_000) }
            }
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }

        if writer.status == .failed, let error = writer.error {
            throw VideoAssemblerError.writeFailed(error.localizedDescription)
        }
    }

    /// Loads one frame from disk through the security-scope-aware reader
    /// (frames may live in a user-selected custom image folder).
    private static func loadCGImage(at url: URL) -> CGImage? {
        guard let data = try? ImageFolderAccess.readData(at: url),
              let image = NSImage(data: data) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func makePixelBuffer(from cgImage: CGImage, size: CGSize, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb)
        } else {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
            CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                                kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        }
        guard let pb else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pb),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        )
        else { return nil }

        ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return pb
    }
}
