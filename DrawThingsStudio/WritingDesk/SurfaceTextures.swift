import CoreGraphics
import Foundation
import Metal
import RealityKit

/// Painted-in-code surface detail: tarnish, brushing and scratches for the
/// metals, grain for the wood, yellowing for the ivory. Every image tiles, so
/// it can repeat across a part of any size.
///
/// Each surface is a pair: a colour image that multiplies the material's tint,
/// and a roughness image, where brighter is duller.
@available(macOS 15, *)
@MainActor
enum SurfaceTextures {
    struct Pair {
        let colour: TextureResource
        let roughness: TextureResource
    }

    static let metal: Pair? = make("desk-metal", paint: paintMetal)
    static let wood: Pair? = make("desk-wood", paint: paintWood)
    static let ivory: Pair? = make("desk-ivory", paint: paintIvory)

    /// Wraps a texture so it repeats instead of smearing its edge pixels.
    static func repeating(_ texture: TextureResource) -> MaterialParameters.Texture {
        let descriptor = MTLSamplerDescriptor()
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .repeat
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.maxAnisotropy = 8
        return .init(texture, sampler: .init(descriptor))
    }

    // MARK: - Painting

    private static let side = 512

    /// One texel: a colour multiplier and a roughness, all 0 to 1.
    private struct Texel {
        var r: Float, g: Float, b: Float, rough: Float
    }

    private static func make(_ name: String, paint: (Float, Float) -> Texel) -> Pair? {
        var colour = [UInt8](repeating: 255, count: side * side * 4)
        var rough = [UInt8](repeating: 255, count: side * side * 4)
        func byte(_ v: Float) -> UInt8 { UInt8(max(0, min(255, v * 255))) }
        for y in 0..<side {
            for x in 0..<side {
                let t = paint(Float(x) / Float(side), Float(y) / Float(side))
                let i = (y * side + x) * 4
                colour[i] = byte(t.r); colour[i + 1] = byte(t.g); colour[i + 2] = byte(t.b)
                let k = byte(t.rough)
                rough[i] = k; rough[i + 1] = k; rough[i + 2] = k
            }
        }
        guard let colourImage = image(colour), let roughImage = image(rough),
              let a = try? TextureResource(image: colourImage, withName: name, options: .init(semantic: .color)),
              let b = try? TextureResource(image: roughImage, withName: name + "-rough", options: .init(semantic: .raw))
        else { return nil }
        return Pair(colour: a, roughness: b)
    }

    private static func image(_ bytes: [UInt8]) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    // MARK: - Noise that tiles

    private static func hash(_ x: Int, _ y: Int, _ seed: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 2_147_483_647)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Float(h & 0xFFFF) / 65535
    }

    /// Smooth noise over the unit square that repeats after `px` by `py` cells.
    private static func noise(_ u: Float, _ v: Float, _ px: Int, _ py: Int, _ seed: Int) -> Float {
        let x = u * Float(px), y = v * Float(py)
        let ix = Int(floor(x)), iy = Int(floor(y))
        var fx = x - Float(ix), fy = y - Float(iy)
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        func at(_ i: Int, _ j: Int) -> Float {
            hash(((i % px) + px) % px, ((j % py) + py) % py, seed)
        }
        let top = at(ix, iy) + (at(ix + 1, iy) - at(ix, iy)) * fx
        let bottom = at(ix, iy + 1) + (at(ix + 1, iy + 1) - at(ix, iy + 1)) * fx
        return top + (bottom - top) * fy
    }

    /// Several layers of `noise`, each twice as fine and half as strong. 0 to 1.
    private static func cloud(_ u: Float, _ v: Float, _ px: Int, _ py: Int, _ seed: Int, layers: Int = 4) -> Float {
        var sum: Float = 0, weight: Float = 1, total: Float = 0
        var cx = px, cy = py
        for layer in 0..<layers {
            sum += noise(u, v, cx, cy, seed + layer * 17) * weight
            total += weight
            weight *= 0.5
            cx *= 2
            cy *= 2
        }
        return sum / total
    }

    private static func smooth(_ lo: Float, _ hi: Float, _ x: Float) -> Float {
        let t = max(0, min(1, (x - lo) / (hi - lo)))
        return t * t * (3 - 2 * t)
    }

    // MARK: - The surfaces

    /// Brass, copper, bronze and iron share this: brushed along `u`, with
    /// patches of tarnish, fine pitting and a few bright scratches.
    private static func paintMetal(_ u: Float, _ v: Float) -> Texel {
        let tarnish = smooth(0.50, 0.72, cloud(u, v, 5, 5, 1))
        let grime = smooth(0.55, 0.80, cloud(u, v, 9, 9, 40)) * 0.5
        let brushed = cloud(u, v, 3, 160, 7, layers: 3) - 0.5
        let pits = smooth(0.80, 0.95, noise(u, v, 96, 96, 23))
        // Long shallow scratches that wander a little off the brushing.
        let slant = v + 0.012 * sin(u * 2 * Float.pi)
        let scratch = smooth(0.965, 0.99, noise(u, slant, 2, 220, 61)) * smooth(0.45, 0.6, cloud(u, v, 6, 6, 77))

        let dull = min(1, tarnish * 0.75 + grime)
        var level = 1 - 0.24 * dull + 0.10 * brushed - 0.06 * pits + 0.10 * scratch
        level = max(0.4, min(1, level))
        // Tarnish cools the colour a little toward brown-green.
        let r = level * (1 - 0.10 * dull)
        let g = level * (1 - 0.04 * dull)
        let b = level * (1 - 0.14 * dull)
        let rough = 0.40 + 0.42 * dull + 0.16 * brushed + 0.08 * pits - 0.12 * scratch
        return Texel(r: r, g: g, b: b, rough: max(0.15, min(1, rough)))
    }

    /// Dark hardwood with the grain running along `u`.
    private static func paintWood(_ u: Float, _ v: Float) -> Texel {
        // Growth rings: bands across `v`, pushed about by a slow wander.
        let wander = cloud(u, v, 2, 3, 3) * 2.2
        let bandPhase = (v * 14 + wander) * 2 * Float.pi
        let bands = 0.5 + 0.5 * sin(bandPhase)
        let fibre = cloud(u, v, 4, 220, 11, layers: 3)
        let pores = smooth(0.78, 0.92, noise(u, v, 24, 300, 29))
        let blotch = cloud(u, v, 3, 3, 53)

        var level = 0.66 + 0.12 * bands + 0.22 * (fibre - 0.5) + 0.16 * (blotch - 0.5) - 0.25 * pores
        level = max(0.25, min(1, level))
        let rough = 0.60 + 0.07 * (1 - bands) + 0.25 * pores + 0.10 * (fibre - 0.5)
        // Lighter bands run a touch redder.
        return Texel(r: level, g: level * (0.94 + 0.04 * bands), b: level * (0.88 + 0.06 * bands),
                     rough: max(0.3, min(1, rough)))
    }

    /// Old ivory: faint grain, yellowed patches, the odd hairline.
    private static func paintIvory(_ u: Float, _ v: Float) -> Texel {
        let grain = cloud(u, v, 6, 90, 5, layers: 3) - 0.5
        let yellowed = smooth(0.45, 0.75, cloud(u, v, 4, 4, 19))
        let hairline = smooth(0.97, 0.995, noise(u, v, 3, 140, 31))
        let level = 1 - 0.10 * yellowed + 0.08 * grain - 0.25 * hairline
        return Texel(r: level, g: level * (1 - 0.05 * yellowed), b: level * (1 - 0.16 * yellowed),
                     rough: max(0.3, min(1, 0.6 + 0.2 * yellowed + 0.3 * hairline)))
    }
}
