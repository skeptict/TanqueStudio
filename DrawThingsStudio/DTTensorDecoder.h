//
//  DTTensorDecoder.h
//  DrawThingsStudio
//
//  Objective-C interface for decoding Draw Things NNC tensor blobs into NSImage.
//  The implementation (DTTensorDecoder.mm) calls the fpzip C++ library.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

/// Appends a pixel buffer to an AVAssetWriterInputPixelBufferAdaptor, catching any
/// Objective-C exceptions thrown by AVFoundation (e.g. the appendTaggedPixelBufferGroup
/// code path on macOS 26 beta) so they don't abort the process.
///
/// @return YES on success, NO if the append failed or an exception was thrown.
#ifdef __cplusplus
extern "C" {
#endif
BOOL DTAppendPixelBufferSafely(AVAssetWriterInputPixelBufferAdaptor *adaptor,
                                CVPixelBufferRef pixelBuffer,
                                CMTime presentationTime);
#ifdef __cplusplus
}
#endif

/// Decodes a raw tensor BLOB from the Draw Things project database `tensors` table
/// into a full-resolution NSImage suitable for PNG export.
@interface DTTensorDecoder : NSObject

/// Decode a tensor BLOB.
///
/// @param data     The raw `data` column from the `tensors` table.
/// @param typeCol  The `type` column (int64): upper 32 bits = codec ID, lower 32 = tensor type.
/// @param datatype The `datatype` column (int64): lower 32 bits = CCV element type (CCV_16F = 0x20000, CCV_32F = 0x04000).
/// @param dim      The `dim` column (raw bytes): 12 × little-endian Int32 shape array.
/// @return         An NSImage at full resolution, or nil if decoding fails.
+ (nullable NSImage *)decodeBlob:(NSData *)data
                         typeCol:(int64_t)typeCol
                        datatype:(int64_t)datatype
                             dim:(NSData *)dim;

/// Decode a Float32 tensor BLOB to raw samples, with no image interpretation.
///
/// Draw Things stores a clip's audio in the same `tensors` table as image
/// tensors, fpzip-compressed Float32, shaped [channels, samples] — so the
/// decompression is shared but nothing about the image layout applies.
///
/// @param data          The raw `data` column.
/// @param typeCol       The `type` column; upper 32 bits select the codec.
/// @param datatype      The `datatype` column; must be CCV_32F.
/// @param elementCount  Expected number of floats, from the `dim` column. The
///                      result is rejected unless it holds exactly this many —
///                      a short decode would otherwise play as truncated noise.
/// @return              `elementCount` float32 values, or nil.
+ (nullable NSData *)decodeFloatBlob:(NSData *)data
                             typeCol:(int64_t)typeCol
                            datatype:(int64_t)datatype
                        elementCount:(NSUInteger)elementCount;

@end

NS_ASSUME_NONNULL_END
