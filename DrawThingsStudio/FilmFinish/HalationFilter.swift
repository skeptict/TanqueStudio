import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Halation
//
// Film Finish prototype, part 2 of 2.
//
// On film, bright light passes through the emulsion, bounces off the film
// base and re-exposes the red-sensitive layer (the deepest one), so strong
// highlights grow a red-orange fringe. Digital and AI images don't have it,
// and edit models (Klein, Qwen Image, Fibo) tend to strip it out when they
// "clean up" an image, which is why this runs after the edit pass.
//
// Pipeline, all in Core Image's linear working space (halation is light, so
// linear is the right place to add it):
//
//   1. luminance          image → grey
//   2. highlight mask     ramp from (threshold − softness/2) to (threshold + softness/2)
//   3. bloom              two Gaussian blurs (wide + tight) of the mask, averaged,
//                         for a bright core that falls off slowly
//   4. protect core       subtract some of the unblurred mask, so the fringe shows
//                         *around* highlights instead of tinting them pink
//   5. tint               red-orange by default
//   6. composite          screen (gentle) or add (hotter), scaled by strength
//
// The radius is a fraction of the image's short side, so a preview rendered at
// 1600 px and an export at 4096 px look the same.
//
// Assumes opaque input, which Draw Things renders always are.

nonisolated struct HalationSettings: Codable, Equatable, Sendable {
    nonisolated enum Blend: String, Codable, CaseIterable, Sendable {
        case screen, add
    }

    /// Linear luminance where the highlight ramp is centred. 0.6 linear ≈ 0.8 in sRGB terms.
    var threshold: Float = 0.6
    /// Width of the ramp around the threshold; 0 is a hard cut.
    var softness: Float = 0.3
    /// Blur radius (Gaussian sigma) as a fraction of the image's short side.
    var radius: Float = 0.012
    /// 0 = off, 1 = full.
    var strength: Float = 0.6
    /// 0 = fringe also tints the highlight itself; 1 = fringe only around it.
    var coreProtection: Float = 0.5
    /// Linear RGB tint of the glow.
    var tint: SIMD3<Float> = SIMD3(1.0, 0.28, 0.08)
    var blend: Blend = .screen

    static let `default` = HalationSettings()
}

nonisolated enum HalationFilter {

    static func apply(_ s: HalationSettings, to image: CIImage) -> CIImage {
        guard s.strength > 0 else { return image }
        let extent = image.extent
        guard !extent.isInfinite, extent.width > 0, extent.height > 0 else { return image }

        let halo = haloLayer(s, for: image)

        switch s.blend {
        case .screen:
            return CIBlendKernel.screen.apply(foreground: halo, background: image)?
                .cropped(to: extent) ?? image
        case .add:
            // componentAdd sums alpha too (1 + 1); force it back to opaque.
            return (CIBlendKernel.componentAdd.apply(foreground: halo, background: image) ?? image)
                .cropped(to: extent)
                .settingAlphaOne(in: extent)
        }
    }

    /// The glow on its own (opaque, black where there is none). Exposed for
    /// tests and for a "show halation only" debug view.
    static func haloLayer(_ s: HalationSettings, for image: CIImage) -> CIImage {
        let extent = image.extent
        let shortSide = Float(min(extent.width, extent.height))

        // 1. Luminance (Rec.709 weights, linear).
        let luma = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        let grey = matrix(image, r: luma, g: luma, b: luma,
                          a: CIVector(x: 0, y: 0, z: 0, w: 1), bias: .zero4)

        // 2. Highlight ramp: (x − lo) / (hi − lo), clamped to 0…1.
        let half = max(s.softness, 0.001) / 2
        let lo = s.threshold - half
        let scale = 1 / (2 * half)
        let ramp = CIVector(x: CGFloat(-lo * scale), y: CGFloat(-lo * scale), z: CGFloat(-lo * scale), w: 0)
        let mask = clamp01(matrix(grey, r: CIVector(x: CGFloat(scale), y: 0, z: 0, w: 0),
                                        g: CIVector(x: 0, y: CGFloat(scale), z: 0, w: 0),
                                        b: CIVector(x: 0, y: 0, z: CGFloat(scale), w: 0),
                                        a: CIVector(x: 0, y: 0, z: 0, w: 1), bias: ramp))

        // 3. Two-scale bloom, averaged.
        let sigma = Double(max(0.5, s.radius * shortSide))
        let wide = blur(mask, sigma: sigma, extent: extent)
        let tight = blur(mask, sigma: sigma * 0.3, extent: extent)
        var bloom = scaleRGB(CIBlendKernel.componentAdd.apply(foreground: tight, background: wide) ?? wide, by: 0.5)
            .settingAlphaOne(in: extent)

        // 4. Protect the core: bloom − k·mask, floored at 0.
        if s.coreProtection > 0 {
            let negMask = scaleRGB(mask, by: -s.coreProtection)
            bloom = clamp01((CIBlendKernel.componentAdd.apply(foreground: negMask, background: bloom) ?? bloom)
                .settingAlphaOne(in: extent))
        }

        // 5 + strength: tint and scale in one matrix.
        let k = s.strength
        return clamp01(matrix(bloom,
                              r: CIVector(x: CGFloat(s.tint.x * k), y: 0, z: 0, w: 0),
                              g: CIVector(x: 0, y: CGFloat(s.tint.y * k), z: 0, w: 0),
                              b: CIVector(x: 0, y: 0, z: CGFloat(s.tint.z * k), w: 0),
                              a: CIVector(x: 0, y: 0, z: 0, w: 1), bias: .zero4))
            .cropped(to: extent)
    }

    // MARK: Helpers

    private static func matrix(_ image: CIImage, r: CIVector, g: CIVector, b: CIVector,
                               a: CIVector, bias: CIVector) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.rVector = r; f.gVector = g; f.bVector = b; f.aVector = a; f.biasVector = bias
        return f.outputImage ?? image
    }

    private static func scaleRGB(_ image: CIImage, by k: Float) -> CIImage {
        let c = CGFloat(k)
        return matrix(image, r: CIVector(x: c, y: 0, z: 0, w: 0), g: CIVector(x: 0, y: c, z: 0, w: 0),
                      b: CIVector(x: 0, y: 0, z: c, w: 0), a: CIVector(x: 0, y: 0, z: 0, w: 1), bias: .zero4)
    }

    private static func clamp01(_ image: CIImage) -> CIImage {
        let f = CIFilter.colorClamp()
        f.inputImage = image
        f.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        f.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return f.outputImage ?? image
    }

    private static func blur(_ image: CIImage, sigma: Double, extent: CGRect) -> CIImage {
        // Clamp first so the edges don't fade to black.
        image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
    }
}

private extension CIVector {
    nonisolated static var zero4: CIVector { CIVector(x: 0, y: 0, z: 0, w: 0) }
}
