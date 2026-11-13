import Foundation
import simd

/// A round tube swept along a cubic Bezier curve: the copper wiring.
enum TubeMesh {
    static func point(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>,
                      at t: Float) -> SIMD3<Float> {
        let u = 1 - t
        return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
    }

    static func tangent(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>,
                        at t: Float) -> SIMD3<Float> {
        let u = 1 - t
        let d = (p1 - p0) * (3 * u * u) + (p2 - p1) * (6 * u * t) + (p3 - p2) * (3 * t * t)
        return simd_length(d) > 1e-6 ? simd_normalize(d) : [0, 1, 0]
    }

    static func add(to b: inout MeshBuilder,
                    _ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>,
                    radius: Float, segments: Int = 24, sides: Int = 8) {
        let t0 = tangent(p0, p1, p2, p3, at: 0)
        // Any vector not parallel to the first tangent seeds the frame; after
        // that it is carried along the curve so the tube never twists.
        let seed: SIMD3<Float> = abs(t0.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        var normal = simd_normalize(seed - t0 * simd_dot(seed, t0))

        var rings: [[UInt32]] = []
        for s in 0...segments {
            let t = Float(s) / Float(segments)
            let centre = point(p0, p1, p2, p3, at: t)
            let tan = tangent(p0, p1, p2, p3, at: t)
            let carried = normal - tan * simd_dot(normal, tan)
            if simd_length(carried) > 1e-5 { normal = simd_normalize(carried) }
            let binormal = simd_cross(tan, normal)

            var ring: [UInt32] = []
            for k in 0..<sides {
                let a = Float(k) / Float(sides) * 2 * .pi
                let radial = normal * cos(a) + binormal * sin(a)
                ring.append(b.vertex(centre + radial * radius, radial, [Float(k) / Float(sides), t]))
            }
            rings.append(ring)
        }
        for s in 0..<segments {
            for k in 0..<sides {
                let k1 = (k + 1) % sides
                b.triangle(rings[s][k], rings[s][k1], rings[s + 1][k])
                b.triangle(rings[s][k1], rings[s + 1][k1], rings[s + 1][k])
            }
        }
    }
}
