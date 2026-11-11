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

    static func add(to b: inout MeshBuilder, teeth: Int, module m: Float,
                    thickness: Float, holeRadius: Float) {
        let r = pitchRadius(teeth: teeth, module: m)
        let tip = r + m * 0.9
        let root = r - m * 1.1
        let pitch = pitchAngle(teeth: teeth)

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
