import Foundation
import Metal
import RealityKit
import simd

/// What the painted look needs to know each frame, handed from the scene on
/// the main thread to the renderer's thread.
final class PaintedLookState: @unchecked Sendable {
    private let lock = NSLock()
    private var view = matrix_identity_float4x4
    private var corners: [SIMD3<Float>] = []
    private var style = Style.fine
    private var broken = false

    /// True when the shader could not be built, so frames are shown unpainted.
    var failed: Bool {
        get { lock.withLock { broken } }
        set { lock.withLock { broken = newValue } }
    }

    /// How heavily the frame is repainted.
    enum Style: String, CaseIterable, Sendable {
        case off, fine, bold

        /// Reach of one dab in pixels, and how far it stretches along an edge.
        fileprivate var brush: SIMD2<Float> {
            switch self {
            case .off: return .zero
            case .fine: return [1.8, 1.5]
            case .bold: return [2.8, 1.6]
            }
        }

        var next: Style {
            let all = Style.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    var look: Style {
        get { lock.withLock { style } }
        set { lock.withLock { style = newValue } }
    }

    /// `view` is world-to-camera. `keepSharp` is the four world-space corners
    /// (top left, top right, bottom right, bottom left) of the area that must
    /// stay unpainted: the glass screen, so the type stays readable.
    func set(view: simd_float4x4, keepSharp: [SIMD3<Float>]) {
        lock.withLock {
            self.view = view
            corners = keepSharp
        }
    }

    fileprivate func snapshot() -> (view: simd_float4x4, corners: [SIMD3<Float>], style: Style) {
        lock.withLock { (view, corners, style) }
    }
}

/// Repaints each finished frame so it reads as oil on canvas: flat dabs of
/// colour in place of smooth gradients (a Kuwahara filter), a little canvas
/// tooth, and richer colour. The glass screen is left alone.
@available(macOS 26, *)
struct PaintedLook: PostProcessEffect, @unchecked Sendable {
    let state: PaintedLookState
    private var library: (any MTLLibrary)?
    private var pipelines: [MTLPixelFormat: any MTLRenderPipelineState] = [:]

    init(state: PaintedLookState) { self.state = state }

    private struct Uniforms {
        var corners01: SIMD4<Float> = .zero
        var corners23: SIMD4<Float> = .zero
        var texel: SIMD2<Float> = .zero
        var amount: Float = 0
        var hasSharpArea: Float = 0
        /// Dab reach in pixels, stretch along edges, mottle, canvas weave.
        var brush: SIMD4<Float> = .zero
        var saturation: Float = 1
    }

    mutating func prepare(for device: any MTLDevice) {
        library = try? device.makeLibrary(source: Self.source, options: nil)
        if library == nil { state.failed = true }
    }

    private mutating func pipeline(for format: MTLPixelFormat, device: any MTLDevice) -> (any MTLRenderPipelineState)? {
        if let made = pipelines[format] { return made }
        guard let library else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "paintedVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "paintedFragment")
        descriptor.colorAttachments[0].pixelFormat = format
        let made = try? device.makeRenderPipelineState(descriptor: descriptor)
        pipelines[format] = made
        if made == nil { state.failed = true }
        return made
    }

    mutating func postProcess(context: borrowing PostProcessEffectContext<any MTLCommandBuffer>) {
        let source = context.sourceColorTexture
        let target = context.targetColorTexture
        guard let pipeline = pipeline(for: target.pixelFormat, device: context.device) else {
            // Without the shader the frame still has to reach the screen.
            if let blit = context.commandBuffer.makeBlitCommandEncoder() {
                blit.copy(from: source, to: target)
                blit.endEncoding()
            }
            return
        }

        let now = state.snapshot()
        var uniforms = Uniforms()
        uniforms.texel = [1 / Float(source.width), 1 / Float(source.height)]
        uniforms.amount = now.style == .off ? 0 : 1
        uniforms.brush = [now.style.brush.x, now.style.brush.y, 0.12, 0.03]
        uniforms.saturation = 1.2
        if now.corners.count == 4 {
            let projected = now.corners.map { context.projection * now.view * SIMD4<Float>($0, 1) }
            // Behind the camera there is nothing to keep sharp.
            if projected.allSatisfy({ $0.w > 0.01 }) {
                let uv = projected.map { SIMD2<Float>($0.x / $0.w * 0.5 + 0.5, 0.5 - $0.y / $0.w * 0.5) }
                uniforms.corners01 = [uv[0].x, uv[0].y, uv[1].x, uv[1].y]
                uniforms.corners23 = [uv[2].x, uv[2].y, uv[3].x, uv[3].y]
                uniforms.hasSharpArea = 1
            }
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Varying {
        float4 position [[position]];
        float2 uv;
    };

    struct Uniforms {
        float4 corners01;
        float4 corners23;
        float2 texel;
        float amount;
        float hasSharpArea;
        float4 brush;
        float saturation;
    };

    vertex Varying paintedVertex(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        Varying out;
        out.position = float4(p * 2 - 1, 0, 1);
        out.uv = float2(p.x, 1 - p.y);
        return out;
    }

    static float hash(float2 p) {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
    }

    static float noise(float2 p) {
        float2 i = floor(p), f = fract(p);
        f = f * f * (3 - 2 * f);
        return mix(mix(hash(i), hash(i + float2(1, 0)), f.x),
                   mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), f.x), f.y);
    }

    // Pixels inside the quad, measured from its nearest edge; negative outside.
    static float insideQuad(float2 p, float2 a, float2 b, float2 c, float2 d) {
        float2 corner[4] = { a, b, c, d };
        float turn = sign((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x));
        float nearest = 1e6;
        for (int i = 0; i < 4; i++) {
            float2 from = corner[i], edge = corner[(i + 1) % 4] - from;
            float side = (edge.x * (p.y - from.y) - edge.y * (p.x - from.x)) / max(length(edge), 1e-4);
            nearest = min(nearest, side * turn);
        }
        return nearest;
    }

    fragment float4 paintedFragment(Varying in [[stage_in]],
                                    texture2d<float> frame [[texture(0)]],
                                    constant Uniforms &u [[buffer(0)]]) {
        constexpr sampler smooth(filter::linear, address::clamp_to_edge);
        float4 original = frame.sample(smooth, in.uv);
        if (u.amount <= 0) { return original; }

        float2 size = 1 / u.texel;
        float2 pixel = in.uv * size;
        float sharp = 0;
        if (u.hasSharpArea > 0) {
            float inside = insideQuad(pixel, u.corners01.xy * size, u.corners01.zw * size,
                                      u.corners23.xy * size, u.corners23.zw * size);
            sharp = smoothstep(-2.0, 4.0, inside);
            if (sharp >= 1) { return original; }
        }

        float reach = u.brush.x, stretch = u.brush.y;

        // Which way the picture runs here: dabs are laid along edges, not
        // across them, the way a brush follows a form.
        const float3 luma = float3(0.299, 0.587, 0.114);
        float2 probe = u.texel * reach * 2;
        float gx = dot(frame.sample(smooth, in.uv + float2(probe.x, 0)).rgb
                       - frame.sample(smooth, in.uv - float2(probe.x, 0)).rgb, luma);
        float gy = dot(frame.sample(smooth, in.uv + float2(0, probe.y)).rgb
                       - frame.sample(smooth, in.uv - float2(0, probe.y)).rgb, luma);
        float2 along = float2(-gy, gx);
        float strength = length(along);
        // Where nothing much is happening the hand falls back to one slant.
        along = normalize(mix(float2(0.8, -0.6), along / max(strength, 1e-5), smoothstep(0.004, 0.03, strength)));
        float2 across = float2(-along.y, along.x);

        // Kuwahara: of the four quarters around this pixel, take the mean of
        // the one that varies least. Edges survive; everything between them
        // collapses into flat dabs.
        const int taps = 5;
        float3 best = original.rgb;
        float calmest = 1e9;
        for (int q = 0; q < 4; q++) {
            float2 dir = float2((q & 1) ? 1.0 : -1.0, (q & 2) ? 1.0 : -1.0);
            float3 sum = float3(0), squares = float3(0);
            for (int i = 0; i < taps; i++) {
                for (int j = 0; j < taps; j++) {
                    float2 step = along * (dir.x * float(i) * reach * stretch) + across * (dir.y * float(j) * reach);
                    float3 c = frame.sample(smooth, in.uv + step * u.texel).rgb;
                    sum += c;
                    squares += c * c;
                }
            }
            float3 mean = sum / float(taps * taps);
            float3 variance = squares / float(taps * taps) - mean * mean;
            float spread = variance.r + variance.g + variance.b;
            if (spread < calmest) {
                calmest = spread;
                best = mean;
            }
        }

        // Uneven paint in slanted strokes, and canvas tooth, both fixed to
        // the picture plane.
        float2 slanted = float2(dot(pixel, float2(0.8, -0.6)), dot(pixel, float2(0.6, 0.8)));
        float mottle = noise(slanted * float2(0.02, 0.11)) + 0.5 * noise(slanted * float2(0.07, 0.3));
        float weave = sin(pixel.x * 1.15) * sin(pixel.y * 1.15);
        best *= 1 + u.brush.w * weave + u.brush.z * (mottle - 0.75);

        float grey = dot(best, luma);
        best = max(mix(float3(grey), best, u.saturation), float3(0));

        return float4(mix(best, original.rgb, sharp), original.a);
    }
    """
}
