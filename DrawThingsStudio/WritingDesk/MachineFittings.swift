import AppKit
import RealityKit
import simd

/// A run of ready-made materials from cold to fully lit. Something that glows
/// picks the nearest one, and is given a new material only when that changes:
/// building a material every frame is far too slow.
@available(macOS 15, *)
@MainActor
struct GlowRamp {
    private let steps: [PhysicallyBasedMaterial]

    /// `floor` is the glow at level 0, `peak` the glow at level 1.
    init(base: PhysicallyBasedMaterial, glow: NSColor, floor: Float, peak: Float, count: Int = 20) {
        steps = (0..<count).map { i in
            var m = base
            m.emissiveColor = .init(color: glow)
            m.emissiveIntensity = floor + (peak - floor) * Float(i) / Float(count - 1)
            return m
        }
    }

    func step(for level: Float) -> Int {
        Int((min(max(level, 0), 1) * Float(steps.count - 1)).rounded())
    }

    subscript(step: Int) -> PhysicallyBasedMaterial { steps[step] }
}

/// The machine's finer parts: glass tubes that slowly pulse, copper wires that
/// glow as they heat and fade as they cool, pressure gauges, pipes and rivets.
///
/// Shares the machine's local space: origin on the desk, +z toward the writer.
@available(macOS 15, *)
@MainActor
final class MachineFittings {
    struct Layout {
        var plinthHeight: Float
        var topY: Float
        var frontZ: Float
        var bodyHalfWidth: Float
        var breakerX: Float
        var breakerY: [Float]
        var bulbX: [Float]
    }

    private struct Glowing {
        let entity: ModelEntity
        let ramp: GlowRamp
        var step = -1

        mutating func show(_ level: Float) {
            let wanted = ramp.step(for: level)
            guard wanted != step else { return }
            step = wanted
            entity.model?.materials = [ramp[wanted]]
        }
    }

    private struct Tube {
        var core: Glowing
        var feed: Glowing
        let period: Float
        let phase: Float
    }

    private let root: Entity
    private let layout: Layout
    private var tubes: [Tube] = []
    private var breakerWires: [Glowing] = []
    private var breakerHeat: [Float] = []
    private var bulbWires: Glowing?
    private var bulbHeat: Float = 0
    private var wingWire: Glowing?
    private var wingHeat: Float = 0
    private var needles: [Entity] = []
    private var needleLevels: [Float] = [0.2, 0.15]

    private let hotCopper = GlowRamp(base: DeskMaterials.copper,
                                     glow: NSColor(srgbRed: 1.0, green: 0.33, blue: 0.07, alpha: 1),
                                     floor: 0, peak: 3.2)

    init(root: Entity, layout: Layout) {
        self.root = root
        self.layout = layout
        buildWires()
        buildTubes()
        buildGauges()
        buildRivets()
    }

    // MARK: - Building

    @discardableResult
    private func add(_ mesh: MeshResource, _ material: any RealityKit.Material,
                     at position: SIMD3<Float>, to parent: Entity? = nil) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.position = position
        (parent ?? root).addChild(e)
        return e
    }

    private func wire(_ builder: MeshBuilder, name: String) -> Glowing? {
        guard let mesh = try? builder.build(name: name) else { return nil }
        var glowing = Glowing(entity: add(mesh, DeskMaterials.copper, at: .zero), ramp: hotCopper)
        glowing.show(0)
        return glowing
    }

    private func buildWires() {
        // Back plate down to each bulb socket: these warm with typing.
        var toBulbs = MeshBuilder()
        for x in layout.bulbX {
            let from = SIMD3<Float>(x * 0.7 + 0.02, layout.topY + 0.012, -0.112)
            let to = SIMD3<Float>(x, layout.topY + 0.006, -0.012)
            TubeMesh.add(to: &toBulbs, from, from + [0, 0.035, 0.045], to + [0, 0.045, -0.035], to, radius: 0.0032)
        }
        bulbWires = wire(toBulbs, name: "bulb-wires")

        // Out of the side of the body and round to each breaker: each one
        // runs hot when its breaker is thrown.
        for y in layout.breakerY {
            var builder = MeshBuilder()
            let from = SIMD3<Float>(layout.bodyHalfWidth, y - 0.03, -0.10)
            let to = SIMD3<Float>(layout.breakerX + 0.034, y, layout.frontZ + 0.004)
            TubeMesh.add(to: &builder, from, from + [0.075, 0.01, 0.02], to + [0.07, 0.03, 0.06], to, radius: 0.0036)
            if let made = wire(builder, name: "breaker-wire") {
                breakerWires.append(made)
                breakerHeat.append(0)
            }
        }

        // Wing gears back to the body.
        var wing = MeshBuilder()
        TubeMesh.add(to: &wing, [-0.33, 0.27, -0.014], [-0.33, 0.36, 0.03], [-0.22, 0.38, 0.0],
                     [-0.20, layout.topY - 0.02, -0.04], radius: 0.0036)
        wingWire = wire(wing, name: "wing-wire")
    }

    private func buildTubes() {
        struct Spec {
            let z: Float
            let height: Float
            let colour: NSColor
            let period: Float
            let phase: Float
        }
        // Tallest at the back, so all three show from the seat.
        let specs = [
            Spec(z: 0.13, height: 0.17, colour: NSColor(srgbRed: 1.0, green: 0.56, blue: 0.16, alpha: 1), period: 7.0, phase: 0),
            Spec(z: 0.19, height: 0.135, colour: NSColor(srgbRed: 0.45, green: 0.95, blue: 0.85, alpha: 1), period: 9.5, phase: 2.1),
            Spec(z: 0.25, height: 0.10, colour: NSColor(srgbRed: 1.0, green: 0.30, blue: 0.10, alpha: 1), period: 5.5, phase: 4.0),
        ]
        let x: Float = 0.275
        let radius: Float = 0.017
        let base = layout.plinthHeight
        let dark = DeskMaterials.pbr(0.03, 0.02, 0.015, metallic: 0, roughness: 0.6)

        for (i, spec) in specs.enumerated() {
            let socket: Float = 0.018
            add(.deskCylinder(height: socket, radius: radius * 1.35), DeskMaterials.brass, at: [x, base + socket / 2, spec.z])
            add(.deskCylinder(height: 0.005, radius: radius * 1.5), DeskMaterials.copper, at: [x, base + 0.0025, spec.z])

            let floor = base + socket
            // Glass envelope with a domed top and a brass tip.
            add(.deskCylinder(height: spec.height, radius: radius), DeskMaterials.glass(opacity: 0.13),
                at: [x, floor + spec.height / 2, spec.z])
            add(.deskSphere(radius: radius), DeskMaterials.glass(opacity: 0.13), at: [x, floor + spec.height, spec.z])
            add(.deskSphere(radius: 0.004), DeskMaterials.brass, at: [x, floor + spec.height + radius, spec.z])

            // Inside: two support rods, a plate, and the column that glows.
            for side in [-1, 1] as [Float] {
                add(.deskCylinder(height: spec.height * 0.8, radius: 0.0012, segments: 6), DeskMaterials.iron,
                    at: [x + side * radius * 0.55, floor + spec.height * 0.4, spec.z])
            }
            add(.deskCylinder(height: 0.003, radius: radius * 0.62), DeskMaterials.bronze,
                at: [x, floor + spec.height * 0.8, spec.z])
            let ramp = GlowRamp(base: dark, glow: spec.colour, floor: 0.5, peak: 5.5)
            let column = add(.deskCylinder(height: spec.height * 0.66, radius: radius * 0.34), dark,
                             at: [x, floor + spec.height * 0.42, spec.z])

            // A copper feed from the body, which heats as the tube brightens.
            var feed = MeshBuilder()
            let from = SIMD3<Float>(layout.bodyHalfWidth, 0.055 + Float(i) * 0.014, 0.02)
            let to = SIMD3<Float>(x - radius * 1.35, base + 0.011, spec.z)
            TubeMesh.add(to: &feed, from, from + [0.04, 0, 0.01], to + [-0.035, 0.012, -0.02], to, radius: 0.003)
            guard let feedWire = wire(feed, name: "tube-feed") else { continue }

            tubes.append(Tube(core: Glowing(entity: column, ramp: ramp), feed: feedWire,
                              period: spec.period, phase: spec.phase))
        }
    }

    private func buildGauges() {
        let x: Float = -0.275
        let base = layout.plinthHeight
        // The dial leans back toward the writer.
        let facing = simd_normalize(SIMD3<Float>(0, 0.55, 0.83))
        let needleRed = DeskMaterials.pbr(0.50, 0.07, 0.05, metallic: 0, roughness: 0.5)

        var dots = MeshBuilder()
        for z in [0.15, 0.235] as [Float] {
            add(.deskCylinder(height: 0.05, radius: 0.006, segments: 10), DeskMaterials.brass, at: [x, base + 0.025, z])
            add(.deskCylinder(height: 0.006, radius: 0.011, segments: 12), DeskMaterials.copper, at: [x, base + 0.003, z])

            let gauge = Entity()
            gauge.position = SIMD3<Float>(x, base + 0.062, z) + facing * 0.004
            gauge.orientation = simd_quatf(from: [0, 1, 0], to: facing)
            root.addChild(gauge)
            add(.deskCylinder(height: 0.016, radius: 0.030), DeskMaterials.brass, at: .zero, to: gauge)
            add(.deskCylinder(height: 0.006, radius: 0.033), DeskMaterials.copper, at: [0, 0.006, 0], to: gauge)
            add(.deskCylinder(height: 0.002, radius: 0.027), DeskMaterials.ivory, at: [0, 0.0093, 0], to: gauge)

            // Scale marks round the upper three quarters of the dial.
            dots = MeshBuilder()
            for k in 0...8 {
                let a = (220 - 260 * Float(k) / 8) * .pi / 180
                dots.cylinder(center: [cos(a) * 0.021, 0, -sin(a) * 0.021], radius: k % 4 == 0 ? 0.0022 : 0.0014,
                              height: 0.001, segments: 6)
            }
            if let mesh = try? dots.build(name: "gauge-marks") {
                add(mesh, DeskMaterials.iron, at: [0, 0.0106, 0], to: gauge)
            }

            let pivot = Entity()
            pivot.position = [0, 0.0118, 0]
            gauge.addChild(pivot)
            add(.generateBox(size: [0.024, 0.0012, 0.0022]), needleRed, at: [0.008, 0, 0], to: pivot)
            add(.deskCylinder(height: 0.003, radius: 0.004, segments: 10), DeskMaterials.brass, at: .zero, to: pivot)
            needles.append(pivot)
        }

        // Pipework: from the side of the body to the first gauge, and on to the second.
        var pipes = MeshBuilder()
        let stalk = SIMD3<Float>(x, base + 0.03, 0.15)
        let port = SIMD3<Float>(-layout.bodyHalfWidth, 0.085, 0.03)
        TubeMesh.add(to: &pipes, port, port + [-0.07, 0, 0], stalk + [0, 0.05, -0.09], stalk, radius: 0.0058)
        TubeMesh.add(to: &pipes, [x, base + 0.012, 0.15], [x - 0.02, base + 0.012, 0.18],
                     [x - 0.02, base + 0.012, 0.21], [x, base + 0.012, 0.235], radius: 0.0048)
        if let mesh = try? pipes.build(name: "pipes") { add(mesh, DeskMaterials.brass, at: .zero) }
        // A collar where the pipe leaves the body.
        let collar = add(.deskCylinder(height: 0.008, radius: 0.011, segments: 12), DeskMaterials.copper,
                         at: port + [-0.004, 0, 0])
        collar.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
    }

    private func buildRivets() {
        var rivets = MeshBuilder()
        func rivet(_ p: SIMD3<Float>, _ r: Float = 0.0042) {
            rivets.sphere(center: p, radius: r, segments: 8, rings: 5)
        }
        // Round the back plate that carries the gears.
        let plateFront: Float = -0.113
        let left: Float = 0.02 - 0.25 + 0.012, right: Float = 0.02 + 0.25 - 0.012
        let low = layout.topY + 0.012, high = layout.topY + 0.25 - 0.012
        for i in 0...10 {
            let x = left + (right - left) * Float(i) / 10
            rivet([x, high, plateFront])
        }
        for i in 1...4 {
            let y = low + (high - low) * Float(i) / 5
            rivet([left, y, plateFront])
            rivet([right, y, plateFront])
        }
        // Along the copper straps, over the top of the body.
        for x in [-0.19, 0.19] as [Float] {
            for i in 0...4 {
                rivet([x, layout.topY + 0.002, -0.16 + 0.05 * Float(i)], 0.0036)
            }
        }
        // Down the front of the left strap; the right one is behind the breakers.
        for i in 0...6 {
            rivet([-0.19, 0.05 + 0.043 * Float(i), layout.frontZ + 0.003], 0.0036)
        }
        // Along both edges of the plinth.
        for x in [-0.298, 0.298] as [Float] {
            for i in 0...10 {
                rivet([x, layout.plinthHeight, -0.21 + 0.05 * Float(i)], 0.0036)
            }
        }
        if let mesh = try? rivets.build(name: "rivets") { add(mesh, DeskMaterials.brass, at: .zero) }
    }

    // MARK: - Reacting

    /// A key went down: the bulb wiring and the wing wire take a little heat.
    func keystroke() {
        bulbHeat = min(1, bulbHeat + 0.16)
        wingHeat = min(1, wingHeat + 0.10)
    }

    /// A breaker was thrown: its wire runs hot.
    func breakerThrown(_ index: Int) {
        guard breakerHeat.indices.contains(index) else { return }
        breakerHeat[index] = 1
    }

    // MARK: - Per frame

    /// `activity` is the machine's typing boost, 0 at rest.
    func update(dt: Float, time: Float, activity: Float) {
        let busy = min(activity / 3, 1)

        // Tubes breathe slowly, each at its own pace. The feed wire follows a
        // little behind, glowing only near the top of the swell.
        var brightest: Float = 0
        for i in tubes.indices {
            let turn = 2 * Float.pi / tubes[i].period
            let wave = 0.5 + 0.5 * sin(time * turn + tubes[i].phase)
            let level = min(1, 0.12 + 0.76 * wave * wave + 0.12 * busy)
            tubes[i].core.show(level)
            let lagged = 0.5 + 0.5 * sin((time - 0.9) * turn + tubes[i].phase)
            tubes[i].feed.show(max(0, lagged - 0.45) / 0.55)
            brightest = max(brightest, level)
        }

        // Hot wires cool: quickly at first, then slowly.
        let cooling = exp(-dt / 2.4)
        var hottest: Float = 0
        for i in breakerWires.indices {
            breakerHeat[i] *= cooling
            breakerWires[i].show(breakerHeat[i])
            hottest = max(hottest, breakerHeat[i])
        }
        bulbHeat *= exp(-dt / 1.6)
        bulbWires?.show(bulbHeat * 0.8)
        wingHeat *= exp(-dt / 2.0)
        wingWire?.show(wingHeat * 0.8)

        // Gauges: pressure rises with typing; temperature follows the hottest wire.
        let wanted: [Float] = [
            0.22 + 0.62 * busy + 0.015 * sin(time * 9.0),
            0.14 + 0.5 * max(hottest, bulbHeat) + 0.2 * brightest + 0.01 * sin(time * 6.3),
        ]
        let settle = 1 - exp(-dt * 3.5)
        for i in needles.indices {
            needleLevels[i] += (wanted[i] - needleLevels[i]) * settle
            let degrees = 220 - 260 * min(max(needleLevels[i], 0), 1)
            needles[i].orientation = simd_quatf(angle: degrees * .pi / 180, axis: [0, 1, 0])
        }
    }
}
