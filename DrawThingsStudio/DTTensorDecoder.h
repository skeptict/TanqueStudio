//
//  DTTensorDecoder.h
//  DrawThingsStudio
//
//  Objective-C interface for decoding Draw Things NNC tensor blobs into NSImage.
//  The implementation (DTTensorDecoder.mm) calls the fpzip C++ library.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

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

@end

NS_ASSUME_NONNULL_END
