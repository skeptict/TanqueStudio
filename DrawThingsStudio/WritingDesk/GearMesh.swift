import Foundation
import simd

/// A spur gear lying in the XY plane with its axle along Z.
///
/// All gears share one `module` (tooth size), so any two placed with their
/// centres `pitchRadius(a) + pitchRadius(b)` apart mesh. The tooth profile is a
/// plain trapezoid, loose enough that meshed teeth never intersect.
enum GearMesh {
    /// Where each outline point of one tooth sits, as a fraction of the tooth
    /// pitch, and whether it is on the tip circle.
    private static let outline: [(fraction: Float, tip: Bool)] = [
        (0.00, false), (0.20, false), (0.32, true), (0.58, true), (0.70, false), (0.85, false),
    ]
    /// Fraction of a pitch from a tooth's first outline point to its centre line.
    static let toothCentre: Float = 0.45

    static func pitchRadius(teeth: Int, module: Float) -> Float { module * Float(teeth) / 2 }
    static func pitchAngle(teeth: Int) -> Float { 2 * .pi / Float(teeth) }

    /// With `spokes` above zero, and room for them, the gear is a toothed rim
    /// joined to a hub by that many arms, with open gaps between.
    static func add(to b: inout MeshBuilder, teeth: Int, module m: Float,
                    thickness: Float, holeRadius: Float, spokes: Int = 0) {
        let r = pitchRadius(teeth: teeth, module: m)
        let tip = r + m * 0.9
        let root = r - m * 1.1
        let pitch = pitchAngle(teeth: teeth)
        let hub = holeRadius * 1.5
        let rimInner = root - m
        let open = spokes > 0 && rimInner > hub + m * 0.8
        let solidInner = holeRadius
        let holeRadius = open ? rimInner : solidInner

        var outer: [SIMD2<Float>] = []
        var inner: [SIMD2<Float>] = []
        for t in 0..<teeth {
            for point in outline {
                let a = (Float(t) + point.fraction) * pitch
                let dir = SIMD2<Float>(cos(a), sin(a))
                outer.append(dir * (point.tip ? tip : root))
                inner.append(dir * holeRadius)
            }
        }

        let zf = thickness / 2, zb = -thickness / 2
        let count = outer.count
        for i in 0..<count {
            let j = (i + 1) % count
            let o0 = outer[i], o1 = outer[j], i0 = inner[i], i1 = inner[j]
            // Faces.
            b.quad([i0.x, i0.y, zf], [o0.x, o0.y, zf], [o1.x, o1.y, zf], [i1.x, i1.y, zf], normal: [0, 0, 1])
            b.quad([i0.x, i0.y, zb], [o0.x, o0.y, zb], [o1.x, o1.y, zb], [i1.x, i1.y, zb], normal: [0, 0, -1])
            // Rim: flat-shaded, so each tooth flank catches the light separately.
            let edge = o1 - o0
            let out = simd_normalize(SIMD2<Float>(edge.y, -edge.x))
            b.quad([o0.x, o0.y, zb], [o1.x, o1.y, zb], [o1.x, o1.y, zf], [o0.x, o0.y, zf],
                   normal: [out.x, out.y, 0])
            // Bore.
            let mid = simd_normalize(i0 + i1)
            b.quad([i0.x, i0.y, zb], [i1.x, i1.y, zb], [i1.x, i1.y, zf], [i0.x, i0.y, zf],
                   normal: [-mid.x, -mid.y, 0])
        }
        guard open else { return }

        // Hub: a ring round the axle.
        let steps = 20
        for i in 0..<steps {
            let a0 = Float(i) / Float(steps) * 2 * .pi, a1 = Float(i + 1) / Float(steps) * 2 * .pi
            let d0 = SIMD2<Float>(cos(a0), sin(a0)), d1 = SIMD2<Float>(cos(a1), sin(a1))
            let i0 = d0 * solidInner, i1 = d1 * solidInner, o0 = d0 * hub, o1 = d1 * hub
            b.quad([i0.x, i0.y, zf], [o0.x, o0.y, zf], [o1.x, o1.y, zf], [i1.x, i1.y, zf], normal: [0, 0, 1])
            b.quad([i0.x, i0.y, zb], [o0.x, o0.y, zb], [o1.x, o1.y, zb], [i1.x, i1.y, zb], normal: [0, 0, -1])
            let mid = simd_normalize(d0 + d1)
            b.quad([o0.x, o0.y, zb], [o1.x, o1.y, zb], [o1.x, o1.y, zf], [o0.x, o0.y, zf], normal: [mid.x, mid.y, 0])
            b.quad([i0.x, i0.y, zb], [i1.x, i1.y, zb], [i1.x, i1.y, zf], [i0.x, i0.y, zf], normal: [-mid.x, -mid.y, 0])
        }
        // Arms from hub to rim, a little thinner than the rim.
        let sf = zf * 0.7, sb = zb * 0.7
        let halfWide = m * 0.55
        for k in 0..<spokes {
            let a = (Float(k) + 0.5) / Float(spokes) * 2 * .pi
            let d = SIMD2<Float>(cos(a), sin(a)), side = SIMD2<Float>(-sin(a), cos(a))
            let near = d * (hub * 0.95), far = d * (rimInner * 1.03)
            let n0 = near - side * halfWide, n1 = near + side * halfWide
            let f0 = far - side * halfWide, f1 = far + side * halfWide
            b.quad([n0.x, n0.y, sf], [f0.x, f0.y, sf], [f1.x, f1.y, sf], [n1.x, n1.y, sf], normal: [0, 0, 1])
            b.quad([n0.x, n0.y, sb], [f0.x, f0.y, sb], [f1.x, f1.y, sb], [n1.x, n1.y, sb], normal: [0, 0, -1])
            b.quad([n0.x, n0.y, sb], [f0.x, f0.y, sb], [f0.x, f0.y, sf], [n0.x, n0.y, sf], normal: [-side.x, -side.y, 0])
            b.quad([n1.x, n1.y, sb], [f1.x, f1.y, sb], [f1.x, f1.y, sf], [n1.x, n1.y, sf], normal: [side.x, side.y, 0])
        }
    }

    /// Starting angle for a driven gear so its teeth sit in the driver's gaps.
    ///
    /// - Parameters:
    ///   - direction: angle from the driver's centre to the driven gear's centre.
    ///   - driverAngle: the driver's own starting angle.
    static func meshedAngle(direction: Float, driverAngle: Float,
                            driverTeeth: Int, drivenTeeth: Int) -> Float {
        let pDriver = pitchAngle(teeth: driverTeeth)
        let pDriven = pitchAngle(teeth: drivenTeeth)
        // Position of the contact point within the driver's tooth cycle (0 = tooth centre).
        let driverPhase = (direction - driverAngle) / pDriver - toothCentre
        // The driven gear must present a gap centre (half a pitch from a tooth
        // centre) when the driver presents a tooth centre.
        return direction + .pi - pDriven * (toothCentre + 0.5 - driverPhase)
    }
}
