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
}

struct VideoAssembler {
    /// Writes `frameURLs` (in order) to `outputURL` as an H.264 .mp4 at `fps`.
    /// Cancellable: a partial file is cleaned up when the task is cancelled or a
    /// frame fails mid-write.
    static func assemble(frameURLs: [URL], fps: Int32, to outputURL: URL) async throws {
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

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
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
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        do {
            for (index, frameURL) in frameURLs.enumerated() {
                try Task.checkCancellation()
                while !writerInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                guard let cgImage = index == 0 ? firstFrame : loadCGImage(at: frameURL) else {
                    throw VideoAssemblerError.frameLoadFailed(index)
                }
                guard let pb = makePixelBuffer(from: cgImage, size: size, pool: adaptor.pixelBufferPool) else {
                    throw VideoAssemblerError.pixelBufferFailed
                }
                let pts = CMTimeMultiply(frameDuration, multiplier: Int32(index))
                adaptor.append(pb, withPresentationTime: pts)
            }
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        writerInput.markAsFinished()
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
