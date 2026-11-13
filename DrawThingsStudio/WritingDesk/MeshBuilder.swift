import RealityKit
import simd

/// Accumulates triangles for one generated mesh. Every triangle is re-oriented
/// to agree with the normals it was given, so callers never have to reason
/// about winding order.
struct MeshBuilder {
    private(set) var positions: [SIMD3<Float>] = []
    private(set) var normals: [SIMD3<Float>] = []
    private(set) var uvs: [SIMD2<Float>] = []
    private(set) var indices: [UInt32] = []

    var triangleCount: Int { indices.count / 3 }
    var isEmpty: Bool { indices.isEmpty }

    @discardableResult
    mutating func vertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ uv: SIMD2<Float> = .zero) -> UInt32 {
        positions.append(p)
        normals.append(simd_normalize(n))
        uvs.append(uv)
        return UInt32(positions.count - 1)
    }

    mutating func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        let pa = positions[Int(a)], pb = positions[Int(b)], pc = positions[Int(c)]
        let face = simd_cross(pb - pa, pc - pa)
        let wanted = normals[Int(a)] + normals[Int(b)] + normals[Int(c)]
        if simd_dot(face, wanted) >= 0 {
            indices += [a, b, c]
        } else {
            indices += [a, c, b]
        }
    }

    /// A flat quad. Corners run around the perimeter; `uvs` follow the same order.
    mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                       normal: SIMD3<Float>,
                       uvs q: [SIMD2<Float>] = [[0, 0], [1, 0], [1, 1], [0, 1]]) {
        let i0 = vertex(a, normal, q[0])
        let i1 = vertex(b, normal, q[1])
        let i2 = vertex(c, normal, q[2])
        let i3 = vertex(d, normal, q[3])
        triangle(i0, i1, i2)
        triangle(i0, i2, i3)
    }

    mutating func box(center c: SIMD3<Float>, size: SIMD3<Float>) {
        let h = size / 2
        func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { c + SIMD3(x * h.x, y * h.y, z * h.z) }
        quad(p(1, -1, 1), p(1, -1, -1), p(1, 1, -1), p(1, 1, 1), normal: [1, 0, 0])
        quad(p(-1, -1, -1), p(-1, -1, 1), p(-1, 1, 1), p(-1, 1, -1), normal: [-1, 0, 0])
        quad(p(-1, 1, 1), p(1, 1, 1), p(1, 1, -1), p(-1, 1, -1), normal: [0, 1, 0])
        quad(p(-1, -1, -1), p(1, -1, -1), p(1, -1, 1), p(-1, -1, 1), normal: [0, -1, 0])
        quad(p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1), normal: [0, 0, 1])
        quad(p(1, -1, -1), p(-1, -1, -1), p(-1, 1, -1), p(1, 1, -1), normal: [0, 0, -1])
    }

    /// A section of a cylinder wall seen from inside: the backdrop that carries
    /// the city. Centred on `center` in x/z, facing inward, with `u` running
    /// left to right for a viewer at the centre looking toward -z.
    mutating func arcWall(center: SIMD3<Float>, radius: Float, span: Float,
                          bottom: Float, height: Float, segments: Int = 48) {
        var column: [(UInt32, UInt32)] = []
        for i in 0...segments {
            let u = Float(i) / Float(segments)
            let a = (u - 0.5) * span
            let x = center.x + radius * sin(a)
            let z = center.z - radius * cos(a)
            let n = SIMD3<Float>(-sin(a), 0, cos(a))
            let lo = vertex([x, bottom, z], n, [u, 0])
            let hi = vertex([x, bottom + height, z], n, [u, 1])
            column.append((lo, hi))
        }
        for i in 0..<segments {
            let (a0, a1) = column[i], (b0, b1) = column[i + 1]
            triangle(a0, b0, b1)
            triangle(a0, b1, a1)
        }
    }

    /// A capped cylinder standing on the Y axis.
    mutating func cylinder(center c: SIMD3<Float> = .zero, radius: Float, height: Float, segments: Int = 20) {
        let h = height / 2
        var lower: [UInt32] = [], upper: [UInt32] = []
        for i in 0..<segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            let n = SIMD3<Float>(cos(a), 0, sin(a))
            lower.append(vertex(c + n * radius - [0, h, 0], n))
            upper.append(vertex(c + n * radius + [0, h, 0], n))
        }
        let top = vertex(c + [0, h, 0], [0, 1, 0])
        let bottom = vertex(c - [0, h, 0], [0, -1, 0])
        for i in 0..<segments {
            let j = (i + 1) % segments
            triangle(lower[i], lower[j], upper[j])
            triangle(lower[i], upper[j], upper[i])
            let a0 = positions[Int(upper[i])], a1 = positions[Int(upper[j])]
            let b0 = positions[Int(lower[i])], b1 = positions[Int(lower[j])]
            triangle(top, vertex(a0, [0, 1, 0]), vertex(a1, [0, 1, 0]))
            triangle(bottom, vertex(b0, [0, -1, 0]), vertex(b1, [0, -1, 0]))
        }
    }

    /// A cylinder on the Y axis whose top rim is rounded over by `bevel`, so
    /// the edge catches a line of light. The top can be dished by `dish`.
    mutating func bevelledCylinder(center c: SIMD3<Float> = .zero, radius: Float, height: Float,
                                   bevel: Float, dish: Float = 0, segments: Int = 16, steps: Int = 2) {
        let h = height / 2
        // The outline from the bottom edge up and over the rim: radius, height, normal.
        var outline: [(r: Float, y: Float, n: SIMD2<Float>)] = [(radius, -h, [1, 0]), (radius, h - bevel, [1, 0])]
        for k in 1...steps {
            let a = Float(k) / Float(steps) * .pi / 2
            outline.append((radius - bevel + bevel * cos(a), h - bevel + bevel * sin(a), [cos(a), sin(a)]))
        }
        if dish > 0 { outline.append((0, h - dish, [0, 1])) }
        var rings: [[UInt32]] = []
        for point in outline {
            var ring: [UInt32] = []
            for i in 0...segments {
                let a = Float(i) / Float(segments) * 2 * .pi
                let out = SIMD3<Float>(cos(a), 0, sin(a))
                ring.append(vertex(c + out * point.r + [0, point.y, 0], out * point.n.x + [0, point.n.y, 0]))
            }
            rings.append(ring)
        }
        for r in 0..<(rings.count - 1) {
            for i in 0..<segments {
                triangle(rings[r][i], rings[r][i + 1], rings[r + 1][i + 1])
                triangle(rings[r][i], rings[r + 1][i + 1], rings[r + 1][i])
            }
        }
        // Flat top and bottom.
        let inner = radius - bevel
        let top = vertex(c + [0, h, 0], [0, 1, 0]), bottom = vertex(c - [0, h, 0], [0, -1, 0])
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi, a1 = Float(i + 1) / Float(segments) * 2 * .pi
            if dish <= 0 {
                triangle(top, vertex(c + [inner * cos(a0), h, inner * sin(a0)], [0, 1, 0]),
                         vertex(c + [inner * cos(a1), h, inner * sin(a1)], [0, 1, 0]))
            }
            triangle(bottom, vertex(c + [radius * cos(a0), -h, radius * sin(a0)], [0, -1, 0]),
                     vertex(c + [radius * cos(a1), -h, radius * sin(a1)], [0, -1, 0]))
        }
    }

    /// A box with every edge and corner rounded over by `bevel`.
    mutating func roundedBox(center c: SIMD3<Float>, size: SIMD3<Float>, bevel: Float, steps: Int = 3) {
        let core = size / 2 - SIMD3(repeating: bevel)
        // Directions round a sphere, each tagged with the corner it belongs
        // to. Neighbouring corners repeat a direction, and the gap between
        // the two copies is a flat face.
        let quadrants: [SIMD2<Float>] = [[1, 1], [-1, 1], [-1, -1], [1, -1]]
        var rows: [[UInt32]] = []
        for half in 0..<2 {
            for j in 0...steps {
                let phi = (Float(half) + Float(j) / Float(steps)) * .pi / 2
                let sy: Float = half == 0 ? 1 : -1
                var row: [UInt32] = []
                for (q, corner) in quadrants.enumerated() {
                    for k in 0...steps {
                        let theta = (Float(q) + Float(k) / Float(steps)) * .pi / 2
                        let n = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                        row.append(vertex(c + SIMD3(corner.x, sy, corner.y) * core + n * bevel, n))
                    }
                }
                rows.append(row)
            }
        }
        let count = rows[0].count
        for r in 0..<(rows.count - 1) {
            for i in 0..<count {
                let j = (i + 1) % count
                triangle(rows[r][i], rows[r][j], rows[r + 1][j])
                triangle(rows[r][i], rows[r + 1][j], rows[r + 1][i])
            }
        }
        // Top and bottom faces, inside the rounded edges.
        let h = size.y / 2
        for sy in [1, -1] as [Float] {
            quad(c + [-core.x, sy * h, core.z], c + [core.x, sy * h, core.z],
                 c + [core.x, sy * h, -core.z], c + [-core.x, sy * h, -core.z],
                 normal: [0, sy, 0], uvs: [.zero, .zero, .zero, .zero])
        }
    }

    /// A latitude/longitude sphere.
    mutating func sphere(center c: SIMD3<Float> = .zero, radius: Float, segments: Int = 16, rings: Int = 10) {
        var grid: [[UInt32]] = []
        for r in 0...rings {
            let phi = Float(r) / Float(rings) * .pi
            var row: [UInt32] = []
            for s in 0...segments {
                let theta = Float(s) / Float(segments) * 2 * .pi
                let n = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                row.append(vertex(c + n * radius, n, [Float(s) / Float(segments), 1 - Float(r) / Float(rings)]))
            }
            grid.append(row)
        }
        for r in 0..<rings {
            for s in 0..<segments {
                if r > 0 { triangle(grid[r][s], grid[r][s + 1], grid[r + 1][s]) }
                if r < rings - 1 { triangle(grid[r][s + 1], grid[r + 1][s + 1], grid[r + 1][s]) }
            }
        }
    }

    /// An upright rectangle facing +z that bulges toward the viewer in the
    /// middle: the tube face. `u` runs left to right, `v` bottom to top.
    mutating func domedPanel(width: Float, height: Float, bulge: Float, columns: Int = 16, rows: Int = 12) {
        var grid: [[UInt32]] = []
        for r in 0...rows {
            var row: [UInt32] = []
            for col in 0...columns {
                let u = Float(col) / Float(columns), v = Float(r) / Float(rows)
                let x = (u - 0.5) * 2, y = (v - 0.5) * 2
                let z = bulge * (1 - x * x) * (1 - y * y)
                // Slope of the bulge gives the normal.
                let dzdx = bulge * (-2 * x) * (1 - y * y) / (width / 2)
                let dzdy = bulge * (1 - x * x) * (-2 * y) / (height / 2)
                row.append(vertex([x * width / 2, y * height / 2, z], [-dzdx, -dzdy, 1], [u, v]))
            }
            grid.append(row)
        }
        for r in 0..<rows {
            for col in 0..<columns {
                triangle(grid[r][col], grid[r][col + 1], grid[r + 1][col + 1])
                triangle(grid[r][col], grid[r + 1][col + 1], grid[r + 1][col])
            }
        }
    }

    /// How much surface one repeat of a texture covers, in metres, on parts
    /// that were built without texture coordinates of their own.
    static let defaultTile: Float = 0.22

    /// Texture coordinates laid flat onto each face from whichever side it
    /// mostly faces, so a texture keeps one scale across parts of any size.
    private func projected(tile: Float) -> [SIMD2<Float>] {
        zip(positions, normals).map { p, n in
            let a = simd_abs(n)
            if a.y >= a.x && a.y >= a.z { return SIMD2(p.x, p.z) / tile }
            if a.x >= a.z { return SIMD2(p.z, p.y) / tile }
            return SIMD2(p.x, p.y) / tile
        }
    }

    /// Pass `tile` to lay the texture on by size. Parts that set no texture
    /// coordinates at all get that treatment at the default size.
    @MainActor
    func build(name: String, tile: Float? = nil) throws -> MeshResource {
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(positions)
        d.normals = MeshBuffers.Normals(normals)
        let size = tile ?? (uvs.allSatisfy { $0 == .zero } ? Self.defaultTile : nil)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(size.map { projected(tile: $0) } ?? uvs)
        d.primitives = .triangles(indices)
        return try MeshResource.generate(from: [d])
    }
}

/// Small deterministic generator so the shelves look the same on every launch.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
    mutating func range(_ lo: Float, _ hi: Float) -> Float { lo + (hi - lo) * unit() }
    mutating func index(_ count: Int) -> Int { Int(next() % UInt64(count)) }
}

@available(macOS 15, *)
extension MeshResource {
    /// Low-polygon stand-ins for the built-in primitives, which are far denser
    /// than parts a few centimetres across need.
    @MainActor
    static func deskCylinder(height: Float, radius: Float, segments: Int = 20) -> MeshResource {
        var b = MeshBuilder()
        b.cylinder(radius: radius, height: height, segments: segments)
        return (try? b.build(name: "cylinder")) ?? .generateCylinder(height: height, radius: radius)
    }

    /// A box with rounded edges, far lighter than the built-in rounded box.
    @MainActor
    static func deskBox(size: SIMD3<Float>, bevel: Float) -> MeshResource {
        var b = MeshBuilder()
        b.roundedBox(center: .zero, size: size, bevel: min(bevel, size.min() / 2 * 0.95), steps: 2)
        return (try? b.build(name: "box", tile: 0.33)) ?? .generateBox(size: size, cornerRadius: bevel)
    }

    /// A cylinder with its top rim rounded over, optionally with a dished top.
    @MainActor
    static func deskCylinder(height: Float, radius: Float, bevel: Float, dish: Float = 0) -> MeshResource {
        var b = MeshBuilder()
        b.bevelledCylinder(radius: radius, height: height, bevel: bevel, dish: dish)
        return (try? b.build(name: "bevelled-cylinder")) ?? .generateCylinder(height: height, radius: radius)
    }

    @MainActor
    static func deskSphere(radius: Float, segments: Int = 16, rings: Int = 10) -> MeshResource {
        var b = MeshBuilder()
        b.sphere(radius: radius, segments: segments, rings: rings)
        return (try? b.build(name: "sphere")) ?? .generateSphere(radius: radius)
    }
}
