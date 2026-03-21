//
//  DTTensorDecoder.mm
//  DrawThingsStudio
//
//  Decodes Draw Things NNC tensor blobs stored in the `tensors` SQLite table.
//
//  Storage format (from s4nnc / NNC / CCV):
//    CREATE TABLE tensors (name TEXT, type INTEGER, format INTEGER,
//                          datatype INTEGER, dim BLOB, data BLOB, PRIMARY KEY (name))
//
//  Codec IDs (upper 32 bits of the `type` column):
//    0x000f7217  fpzip   — floating-point lossy/lossless compression
//    0x00000217  zip     — zlib DEFLATE
//    0x00000511  ezm7    — exp + 7-bit mantissa (FP16 only)
//    0           none    — raw bytes
//
//  CCV datatype constants (lower 32 bits of `datatype`):
//    0x04000  CCV_32F   Float32
//    0x20000  CCV_16F   Float16
//
//  fpzip note: NNC encodes Float16 arrays as Float32 with prec=19 before feeding to
//  fpzip (since fpzip only handles float/double). After decoding we get Float32 values
//  that represent the original Float16 pixel values in [0, 1].
//

#import "DTTensorDecoder.h"
#include "fpzip.h"        // LLNL fpzip (bundled in DrawThingsStudio/fpzip/)
#include <zlib.h>
#include <cstring>
#include <cmath>

// ── CCV constants ────────────────────────────────────────────────────────────

static const int32_t CCV_16F  = 0x20000;
static const int32_t CCV_32F  = 0x04000;
static const int32_t CCV_8U   = 0x01000;

static const uint32_t CODEC_NONE  = 0x00000000;
static const uint32_t CODEC_FPZIP = 0x000f7217;
static const uint32_t CODEC_ZIP   = 0x00000217;
static const uint32_t CODEC_EZM7  = 0x00000511;

static const int32_t CCV_TENSOR_FORMAT_NHWC = 0; // channel-last (H×W×C)
static const int32_t CCV_TENSOR_FORMAT_NCHW = 1; // channel-first (C×H×W)

static const int NNC_MAX_DIM = 12;

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Half-precision IEEE 754 → float32.
static inline float fp16_to_f32(uint16_t h) {
    uint32_t sign     = (uint32_t)(h >> 15) << 31;
    uint32_t exponent = (uint32_t)((h >> 10) & 0x1F);
    uint32_t mantissa = (uint32_t)(h & 0x3FF);

    if (exponent == 31) {
        // Inf / NaN
        uint32_t bits = sign | 0x7F800000 | (mantissa << 13);
        float f; memcpy(&f, &bits, 4); return f;
    }
    if (exponent == 0) {
        // Denormal
        if (mantissa == 0) { float f = 0.f; if (sign) f = -0.f; return f; }
        exponent = 1;
        while (!(mantissa & 0x400)) { mantissa <<= 1; exponent--; }
        mantissa &= 0x3FF;
    }
    uint32_t bits = sign | ((exponent + 112) << 23) | (mantissa << 13);
    float f; memcpy(&f, &bits, 4); return f;
}

// ── Decompression ────────────────────────────────────────────────────────────

/// Decompress with zlib DEFLATE. Returns decompressed bytes or nil on failure.
static NSData * _Nullable zlibDecompress(const void *src, size_t srcLen, size_t expectedBytes) {
    NSMutableData *out = [NSMutableData dataWithLength:expectedBytes];
    uLongf destLen = (uLongf)expectedBytes;
    int rc = uncompress((Bytef *)out.mutableBytes, &destLen, (const Bytef *)src, (uLong)srcLen);
    if (rc != Z_OK) return nil;
    out.length = destLen;
    return out;
}

/// Decompress fpzip-encoded Float32 tensor. Returns raw float32 bytes or nil.
/// NNC encodes Float16 tensors as Float32 with prec=19 before fpzip compression.
static NSData * _Nullable fpzipDecompress(const void *src, size_t srcLen, int nx, int ny, int nz, int nf) {
    FPZ *fpz = fpzip_read_from_buffer(src);
    if (!fpz) return nil;

    if (!fpzip_read_header(fpz)) {
        fpzip_read_close(fpz);
        return nil;
    }

    // Allocate output for Float32 values
    size_t count = (size_t)fpz->nx * fpz->ny * fpz->nz * fpz->nf;
    if (count == 0) {
        // Header dimensions available; use them
        count = 1;
    }
    NSMutableData *out = [NSMutableData dataWithLength:count * sizeof(float)];
    size_t read = fpzip_read(fpz, out.mutableBytes);
    fpzip_read_close(fpz);

    if (read == 0) return nil;
    out.length = read;
    return out;
}

// ── ezm7 decompression (FP16 only) ──────────────────────────────────────────

/// Decompress the ezm7 codec used by NNC for FP16 data.
/// Format: [Int32: compressed_exponent_size] [compressed exponents] [n bytes: sign<<7 | 7-bit mantissa]
static NSData * _Nullable ezm7Decompress(const void *src, size_t srcLen, size_t elementCount) {
    if (srcLen < 4) return nil;
    const uint8_t *p = (const uint8_t *)src;
    int32_t zipExpSize;
    memcpy(&zipExpSize, p, 4);
    p += 4; srcLen -= 4;
    if ((size_t)zipExpSize > srcLen) return nil;

    // Decompress exponents
    NSMutableData *expData = [NSMutableData dataWithLength:elementCount];
    uLongf expLen = (uLongf)elementCount;
    if (uncompress((Bytef *)expData.mutableBytes, &expLen, (const Bytef *)p, (uLong)zipExpSize) != Z_OK) return nil;
    p += zipExpSize; srcLen -= zipExpSize;
    if (srcLen < elementCount) return nil;
    const uint8_t *mantSignBytes = p;

    const uint8_t *exponents = (const uint8_t *)expData.bytes;
    NSMutableData *out = [NSMutableData dataWithLength:elementCount * sizeof(uint16_t)];
    uint16_t *dst = (uint16_t *)out.mutableBytes;
    for (size_t i = 0; i < elementCount; i++) {
        uint8_t ms   = mantSignBytes[i];
        uint8_t sign = (ms >> 7) & 1;
        uint8_t mant = ms & 0x7F;
        uint16_t exp = exponents[i];
        // Reconstruct FP16: sign(1) | exp(5) | mantissa(10)
        // NNC stores exp as full 5-bit exponent, mantissa as top 7 bits of 10-bit mantissa
        dst[i] = (uint16_t)((sign << 15) | (exp << 10) | ((uint16_t)mant << 3));
    }
    return out;
}

// ── NSImage construction ─────────────────────────────────────────────────────

/// Build an NSImage from a Float32 RGB (or RGBA) buffer in [0, 1] range.
static NSImage * _Nullable imageFromFloat32(const float *pixels, int width, int height, int channels, BOOL isNHWC) {
    // We always output RGBA8 PNG
    NSMutableData *rgba = [NSMutableData dataWithLength:(size_t)width * height * 4];
    uint8_t *dst = (uint8_t *)rgba.mutableBytes;

    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            float r = 0, g = 0, b = 0;
            if (isNHWC) {
                int base = (y * width + x) * channels;
                r = pixels[base + 0];
                g = pixels[base + (channels >= 2 ? 1 : 0)];
                b = pixels[base + (channels >= 3 ? 2 : 0)];
            } else {
                // NCHW: plane-first
                int planeSize = width * height;
                r = pixels[0 * planeSize + y * width + x];
                g = pixels[(channels >= 2 ? 1 : 0) * planeSize + y * width + x];
                b = pixels[(channels >= 3 ? 2 : 0) * planeSize + y * width + x];
            }
            int idx = (y * width + x) * 4;
            dst[idx+0] = (uint8_t)(fminf(fmaxf(r, 0.f), 1.f) * 255.f + 0.5f);
            dst[idx+1] = (uint8_t)(fminf(fmaxf(g, 0.f), 1.f) * 255.f + 0.5f);
            dst[idx+2] = (uint8_t)(fminf(fmaxf(b, 0.f), 1.f) * 255.f + 0.5f);
            dst[idx+3] = 255;
        }
    }

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:width
                      pixelsHigh:height
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSDeviceRGBColorSpace
                     bytesPerRow:width * 4
                    bitsPerPixel:32];
    if (!rep) return nil;
    memcpy([rep bitmapData], dst, (size_t)width * height * 4);

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [image addRepresentation:rep];
    return image;
}

/// Build an NSImage from a Float16 (uint16_t) RGB buffer.
static NSImage * _Nullable imageFromFloat16(const uint16_t *pixels, int width, int height, int channels, BOOL isNHWC) {
    size_t count = (size_t)width * height * channels;
    NSMutableData *f32 = [NSMutableData dataWithLength:count * sizeof(float)];
    float *dst = (float *)f32.mutableBytes;
    for (size_t i = 0; i < count; i++) dst[i] = fp16_to_f32(pixels[i]);
    return imageFromFloat32(dst, width, height, channels, isNHWC);
}

// ── Public API ───────────────────────────────────────────────────────────────

@implementation DTTensorDecoder

+ (nullable NSImage *)decodeBlob:(NSData *)data
                         typeCol:(int64_t)typeCol
                        datatype:(int64_t)datatype
                             dim:(NSData *)dim {
    if (!data || data.length == 0 || !dim) return nil;

    // ── Parse dim array ──────────────────────────────────────────────────────
    // 12 × Int32 little-endian
    if (dim.length < NNC_MAX_DIM * 4) return nil;
    const int32_t *dimArr = (const int32_t *)dim.bytes;
    // Count valid (nonzero) dimensions
    int ndim = 0;
    for (int i = 0; i < NNC_MAX_DIM; i++) {
        if (dimArr[i] != 0) ndim = i + 1; else break;
    }
    if (ndim < 2) return nil;

    // Extract codec and format
    uint32_t codecId  = (uint32_t)((typeCol >> 32) & 0xFFFFFFFF);
    int32_t  elemType = (int32_t)(datatype & 0xFFFFFFFF);

    // Determine H, W, C from dim array.
    // NNC NHWC: dim[0]=H, dim[1]=W, dim[2]=C  (for 3D tensors, batch omitted)
    // NNC NCHW: dim[0]=C, dim[1]=H, dim[2]=W
    // We read format from the format column but it's not passed here; try NHWC first
    // (Draw Things stores images in NHWC = channel-last).
    // Since we rely on ndim to determine layout:
    //   ndim==3: [H, W, C] for NHWC or [C, H, W] for NCHW
    //   ndim==4: [N, H, W, C] for NHWC (N=1)
    int height = 0, width = 0, channels = 0;
    BOOL isNHWC = YES; // Draw Things uses NHWC for image tensors
    if (ndim == 3) {
        height   = dimArr[0];
        width    = dimArr[1];
        channels = dimArr[2];
    } else if (ndim == 4) {
        // [N, H, W, C] — skip batch dim
        height   = dimArr[1];
        width    = dimArr[2];
        channels = dimArr[3];
    } else if (ndim == 2) {
        height   = dimArr[0];
        width    = dimArr[1];
        channels = 1;
    } else {
        return nil;
    }
    if (width <= 0 || height <= 0 || channels < 1 || channels > 4) return nil;
    size_t elementCount = (size_t)height * width * channels;

    // ── Decompress data ──────────────────────────────────────────────────────
    const void *srcBytes = data.bytes;
    size_t      srcLen   = data.length;

    if (codecId == CODEC_FPZIP) {
        // fpzip stream: NNC encodes Float16 as Float32 with prec=19.
        // fpzip_read_from_buffer reads its own header for dimensions; we just
        // need to pass through. The result is always Float32 on decode.
        FPZ *fpz = fpzip_read_from_buffer(srcBytes);
        if (!fpz) return nil;
        if (!fpzip_read_header(fpz)) { fpzip_read_close(fpz); return nil; }

        size_t outCount = (size_t)fpz->nx * fpz->ny * fpz->nz * fpz->nf;
        if (outCount == 0) outCount = elementCount; // fallback
        NSMutableData *f32data = [NSMutableData dataWithLength:outCount * sizeof(float)];
        size_t readBytes = fpzip_read(fpz, f32data.mutableBytes);
        fpzip_read_close(fpz);
        if (readBytes == 0) return nil;

        // If decoded count matches elementCount, proceed; otherwise try to reshape
        size_t f32Count = readBytes / sizeof(float);
        if (f32Count < elementCount) return nil;

        return imageFromFloat32((const float *)f32data.bytes, width, height, channels, isNHWC);

    } else if (codecId == CODEC_ZIP) {
        size_t bytesPerElem = (elemType == CCV_16F) ? 2 : (elemType == CCV_32F) ? 4 : 1;
        NSData *raw = zlibDecompress(srcBytes, srcLen, elementCount * bytesPerElem);
        if (!raw) return nil;
        if (elemType == CCV_16F) {
            return imageFromFloat16((const uint16_t *)raw.bytes, width, height, channels, isNHWC);
        } else if (elemType == CCV_32F) {
            return imageFromFloat32((const float *)raw.bytes, width, height, channels, isNHWC);
        }

    } else if (codecId == CODEC_EZM7) {
        NSData *raw = ezm7Decompress(srcBytes, srcLen, elementCount);
        if (!raw) return nil;
        return imageFromFloat16((const uint16_t *)raw.bytes, width, height, channels, isNHWC);

    } else if (codecId == CODEC_NONE) {
        // Uncompressed raw bytes
        size_t bytesPerElem = (elemType == CCV_16F) ? 2 : (elemType == CCV_32F) ? 4 : 1;
        if (srcLen < elementCount * bytesPerElem) return nil;
        if (elemType == CCV_16F) {
            return imageFromFloat16((const uint16_t *)srcBytes, width, height, channels, isNHWC);
        } else if (elemType == CCV_32F) {
            return imageFromFloat32((const float *)srcBytes, width, height, channels, isNHWC);
        }
    }

    return nil;
}

@end

// MARK: - AVFoundation exception-safe helpers

extern "C" BOOL DTAppendPixelBufferSafely(AVAssetWriterInputPixelBufferAdaptor *adaptor,
                                           CVPixelBufferRef pixelBuffer,
                                           CMTime presentationTime) {
    @try {
        return [adaptor appendPixelBuffer:pixelBuffer withPresentationTime:presentationTime];
    } @catch (NSException *) {
        return NO;
    }
}
