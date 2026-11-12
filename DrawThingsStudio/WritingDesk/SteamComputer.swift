import AppKit
import RealityKit
import simd

/// Materials shared by the den and the machine.
@available(macOS 15, *)
@MainActor
enum DeskMaterials {
    static func pbr(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                    metallic: Float, roughness: Float) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: NSColor(srgbRed: r, green: g, blue: b, alpha: 1))
        m.metallic = .init(floatLiteral: metallic)
        m.roughness = .init(floatLiteral: roughness)
        return m
    }

    static func glow(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, intensity: Float) -> PhysicallyBasedMaterial {
        var m = pbr(0.02, 0.01, 0.0, metallic: 0, roughness: 0.6)
        m.emissiveColor = .init(color: NSColor(srgbRed: r, green: g, blue: b, alpha: 1))
        m.emissiveIntensity = intensity
        return m
    }

    static func glass(opacity: Float) -> PhysicallyBasedMaterial {
        var m = pbr(0.85, 0.92, 0.95, metallic: 0, roughness: 0.04)
        m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return m
    }

    static let brass = pbr(0.80, 0.58, 0.24, metallic: 1, roughness: 0.30)
    static let copper = pbr(0.82, 0.44, 0.27, metallic: 1, roughness: 0.28)
    static let bronze = pbr(0.36, 0.25, 0.13, metallic: 1, roughness: 0.48)
    static let iron = pbr(0.07, 0.07, 0.075, metallic: 0.9, roughness: 0.5)
    static let ivory = pbr(0.86, 0.80, 0.66, metallic: 0, roughness: 0.38)
    static let darkWood: PhysicallyBasedMaterial = {
        var m = pbr(0.13, 0.07, 0.04, metallic: 0, roughness: 0.6)
        m.clearcoat = .init(floatLiteral: 0.15)
        return m
    }()
}

/// The hero: a small brass-and-copper machine with turning gears, glowing
/// bulbs, toggle breakers, copper wiring, a keyboard and a glass screen.
///
/// Local space: origin on the desk under the machine, +z toward the writer.
@available(macOS 15, *)
@MainActor
final class SteamComputer {
    let root = Entity()
    /// Called once per tooth of the main gear, for the ticking sound.
    var onGearTick: (() -> Void)?
    private(set) var screenFailed = false
    /// Centre and size of the glass screen, in the machine's own space.
    private(set) var screenCentre: SIMD3<Float> = .zero
    private(set) var screenSize: SIMD2<Float> = .zero

    // Layout, in metres.
    private let plinthHeight: Float = 0.03
    private let bodySize = SIMD3<Float>(0.42, 0.30, 0.22)
    private var bodyCentre: SIMD3<Float> { [0, plinthHeight + bodySize.y / 2, -0.06] }
    private var frontZ: Float { bodyCentre.z + bodySize.z / 2 }
    private var topY: Float { plinthHeight + bodySize.y }
    private let gearModule: Float = 0.008

    private struct Gear {
        let entity: Entity
        let startAngle: Float
        /// Radians turned per radian of the main gear; negative runs backwards.
        let rate: Float
    }
    private var gears: [Gear] = []
    private var driverAngle: Float = 0
    private var boost: Float = 0
    private var tickTravel: Float = 0
    private let driverTeeth = 20

    private var filaments: [ModelEntity] = []
    private let filamentScale = SIMD3<Float>(0.6, 1.5, 0.6)
    private let bulbLight = Entity()
    private var fittings: MachineFittings?
    private let bulbLightBase: Float = 9000

    private struct Breaker {
        let pivot: Entity
        var isUp: Bool
        var angle: Float
    }
    private var breakers: [Breaker] = []
    private var nextBreaker = 0
    private let breakerThrow: Float = 0.6

    private struct Key {
        let cap: Entity
        let rest: SIMD3<Float>
        var press: Float = 0
    }
    private var keys: [Key] = []
    private var keyIndex: [Character: Int] = [:]
    private var rng = SeededRandom(seed: 1887)

    private let renderer = ScreenTextRenderer()
    private var screen: ModelEntity?
    private var page: ScreenTextLayout.Page?
    private var textureOn: TextureResource?
    private var textureOff: TextureResource?
    private var materialOn: UnlitMaterial?
    private var materialOff: UnlitMaterial?
    private var offIsStale = true
    private var cursorVisible = true
    private var blinkTimer: Float = 0

    init() {
        buildBody()
        buildScreen()
        buildGears()
        buildBulbs()
        buildBreakers()
        fittings = MachineFittings(root: root, layout: .init(
            plinthHeight: plinthHeight, topY: topY, frontZ: frontZ, bodyHalfWidth: bodySize.x / 2,
            breakerX: breakerX, breakerY: (0..<3).map(breakerY), bulbX: (0..<5).map(bulbX)))
        buildKeyboard()
        setText("")
    }

    // MARK: - Building

    private func add(_ mesh: MeshResource, _ material: any RealityKit.Material,
                     at position: SIMD3<Float>, to parent: Entity? = nil) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.position = position
        (parent ?? root).addChild(e)
        return e
    }

    /// A cylinder whose axis runs along Z instead of Y.
    private func addAxial(radius: Float, length: Float, _ material: any RealityKit.Material,
                          at position: SIMD3<Float>, to parent: Entity? = nil) -> ModelEntity {
        let e = add(.deskCylinder(height: length, radius: radius), material, at: position, to: parent)
        e.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        return e
    }

    private func buildBody() {
        _ = add(.generateBox(size: [0.62, plinthHeight, 0.54], cornerRadius: 0.006), DeskMaterials.bronze,
                at: [0, plinthHeight / 2, 0.04])
        _ = add(.generateBox(size: bodySize, cornerRadius: 0.012), DeskMaterials.brass, at: bodyCentre)

        // Riveted straps.
        for x in [-0.19, 0.19] as [Float] {
            _ = add(.generateBox(size: [0.018, bodySize.y + 0.004, bodySize.z + 0.006]), DeskMaterials.copper,
                    at: [x, bodyCentre.y, bodyCentre.z])
        }
        // Back plate that carries the main gear train.
        _ = add(.generateBox(size: [0.50, 0.25, 0.012]), DeskMaterials.bronze,
                at: [0.02, topY + 0.125, -0.12])
        // Side wing for the second train.
        _ = add(.generateBox(size: [0.16, 0.25, 0.010]), DeskMaterials.bronze,
                at: [-0.285, 0.155, -0.02])
    }

    private func buildScreen() {
        let width: Float = 0.262
        let height = width / ScreenTextRenderer.aspect
        let centre = SIMD3<Float>(-0.045, 0.185, frontZ)
        screenCentre = centre + [0, 0, 0.004]
        screenSize = [width, height]

        // The tube face bulges slightly; a second, clear skin over it catches highlights.
        var face = MeshBuilder()
        face.domedPanel(width: width, height: height, bulge: 0.010)
        if let mesh = try? face.build(name: "screen") {
            screen = add(mesh, DeskMaterials.iron, at: centre + [0, 0, 0.004])
            // Kept very thin: under the key light a thicker skin fogs the type.
            _ = add(mesh, DeskMaterials.glass(opacity: 0.02), at: centre + [0, 0, 0.006])
        }

        // Bezel.
        let t: Float = 0.018
        let z = centre.z + 0.010
        let bars: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([centre.x, centre.y + height / 2 + t / 2, z], [width + 2 * t, t, 0.026]),
            ([centre.x, centre.y - height / 2 - t / 2, z], [width + 2 * t, t, 0.026]),
            ([centre.x - width / 2 - t / 2, centre.y, z], [t, height, 0.026]),
            ([centre.x + width / 2 + t / 2, centre.y, z], [t, height, 0.026]),
        ]
        for (position, size) in bars {
            _ = add(.generateBox(size: size), DeskMaterials.copper, at: position)
        }
    }

    private func buildGears() {
        struct Spec {
            let teeth: Int
            /// Index of the gear that drives this one, or nil for a train's first gear.
            let parent: Int?
            /// For a first gear: its centre. Otherwise unused.
            let centre: SIMD2<Float>
            /// Angle from the parent's centre to this gear's centre, in degrees.
            let direction: Float
            let z: Float
            let rate: Float
            let material: PhysicallyBasedMaterial
        }
        let plateZ: Float = -0.12 + 0.006 + 0.006
        let wingZ: Float = -0.02 + 0.005 + 0.006
        let specs: [Spec] = [
            Spec(teeth: driverTeeth, parent: nil, centre: [-0.10, topY + 0.115], direction: 0, z: plateZ,
                 rate: 1, material: DeskMaterials.brass),
            Spec(teeth: 12, parent: 0, centre: .zero, direction: 12, z: plateZ, rate: 0, material: DeskMaterials.copper),
            Spec(teeth: 16, parent: 1, centre: .zero, direction: -30, z: plateZ, rate: 0, material: DeskMaterials.brass),
            Spec(teeth: 9, parent: 2, centre: .zero, direction: 65, z: plateZ, rate: 0, material: DeskMaterials.copper),
            Spec(teeth: 10, parent: 2, centre: .zero, direction: -5, z: plateZ, rate: 0, material: DeskMaterials.brass),
            Spec(teeth: 8, parent: 0, centre: .zero, direction: 140, z: plateZ, rate: 0, material: DeskMaterials.copper),
            Spec(teeth: 14, parent: nil, centre: [-0.29, 0.115], direction: 0, z: wingZ,
                 rate: -1.3, material: DeskMaterials.copper),
            Spec(teeth: 9, parent: 6, centre: .zero, direction: 75, z: wingZ, rate: 0, material: DeskMaterials.brass),
        ]

        var centres: [SIMD2<Float>] = []
        var starts: [Float] = []
        var rates: [Float] = []
        for spec in specs {
            let radius = GearMesh.pitchRadius(teeth: spec.teeth, module: gearModule)
            var centre = spec.centre
            var start: Float = 0
            var rate = spec.rate
            if let p = spec.parent {
                let parent = specs[p]
                let direction = spec.direction * .pi / 180
                let distance = GearMesh.pitchRadius(teeth: parent.teeth, module: gearModule) + radius
                centre = centres[p] + SIMD2(cos(direction), sin(direction)) * distance
                start = GearMesh.meshedAngle(direction: direction, driverAngle: starts[p],
                                             driverTeeth: parent.teeth, drivenTeeth: spec.teeth)
                rate = -rates[p] * Float(parent.teeth) / Float(spec.teeth)
            }
            centres.append(centre)
            starts.append(start)
            rates.append(rate)

            var builder = MeshBuilder()
            GearMesh.add(to: &builder, teeth: spec.teeth, module: gearModule,
                         thickness: 0.008, holeRadius: radius * 0.3)
            guard let mesh = try? builder.build(name: "gear\(spec.teeth)") else { continue }
            let gear = add(mesh, spec.material, at: [centre.x, centre.y, spec.z])
            gear.orientation = simd_quatf(angle: start, axis: [0, 0, 1])
            gears.append(Gear(entity: gear, startAngle: start, rate: rate))

            // Fixed axle and boss.
            _ = addAxial(radius: radius * 0.3, length: 0.018, DeskMaterials.iron, at: [centre.x, centre.y, spec.z])
            _ = addAxial(radius: radius * 0.42, length: 0.004, DeskMaterials.bronze,
                         at: [centre.x, centre.y, spec.z + 0.006])
        }
    }

    private func bulbX(_ i: Int) -> Float { Float(i - 2) * 0.08 }

    private func buildBulbs() {
        for i in 0..<5 {
            let x = bulbX(i)
            _ = add(.deskCylinder(height: 0.016, radius: 0.013), DeskMaterials.copper, at: [x, topY + 0.008, 0])
            let centre = SIMD3<Float>(x, topY + 0.016 + 0.019, 0)
            let filament = add(.deskSphere(radius: 0.007), DeskMaterials.glow(1.0, 0.62, 0.22, intensity: 3),
                               at: centre)
            filament.scale = filamentScale
            filaments.append(filament)
            _ = add(.deskSphere(radius: 0.021), DeskMaterials.glass(opacity: 0.16), at: centre)
        }
        bulbLight.position = [0, topY + 0.07, 0.07]
        bulbLight.components.set(PointLightComponent(cgColor: CGColor(srgbRed: 1.0, green: 0.68, blue: 0.36, alpha: 1),
                                                     intensity: bulbLightBase, attenuationRadius: 2.0))
        root.addChild(bulbLight)
    }

    private func breakerY(_ i: Int) -> Float { 0.245 - Float(i) * 0.06 }
    private let breakerX: Float = 0.155

    private func buildBreakers() {
        _ = add(.generateBox(size: [0.07, 0.20, 0.006]), DeskMaterials.iron,
                at: [breakerX, 0.185, frontZ + 0.003])
        for i in 0..<3 {
            let y = breakerY(i)
            _ = addAxial(radius: 0.012, length: 0.010, DeskMaterials.brass, at: [breakerX, y, frontZ + 0.010])
            let pivot = Entity()
            pivot.position = [breakerX, y, frontZ + 0.012]
            root.addChild(pivot)
            _ = addAxial(radius: 0.0038, length: 0.036, DeskMaterials.copper, at: [0, 0, 0.018], to: pivot)
            _ = add(.deskSphere(radius: 0.0075), DeskMaterials.ivory, at: [0, 0, 0.038], to: pivot)

            let isUp = i != 1
            let angle = isUp ? -breakerThrow : breakerThrow
            pivot.orientation = simd_quatf(angle: angle, axis: [1, 0, 0])
            breakers.append(Breaker(pivot: pivot, isUp: isUp, angle: angle))
        }
    }

    private func buildKeyboard() {
        let board = Entity()
        board.position = [0, plinthHeight + 0.004, 0.195]
        // Far edge raised, like a typewriter.
        board.orientation = simd_quatf(angle: 0.12, axis: [1, 0, 0])
        root.addChild(board)

        let baseHeight: Float = 0.020
        _ = add(.generateBox(size: [0.42, baseHeight, 0.185], cornerRadius: 0.005), DeskMaterials.brass,
                at: [0, baseHeight / 2, 0], to: board)

        let rows: [(keys: String, indent: Float, z: Float)] = [
            ("1234567890", 0, -0.066),
            ("qwertyuiop", 0.008, -0.033),
            ("asdfghjkl;", 0.016, 0),
            ("zxcvbnm,.", 0.030, 0.033),
        ]
        let pitch: Float = 0.036
        let pedestal = MeshResource.deskCylinder(height: 0.008, radius: 0.0150)
        let capMesh = MeshResource.deskCylinder(height: 0.005, radius: 0.0128)
        for row in rows {
            for (i, ch) in row.keys.enumerated() {
                let x = -0.175 + row.indent + Float(i) * pitch
                _ = add(pedestal, DeskMaterials.copper, at: [x, baseHeight + 0.004, row.z], to: board)
                let rest = SIMD3<Float>(x, baseHeight + 0.008 + 0.0025, row.z)
                let cap = add(capMesh, DeskMaterials.ivory, at: rest, to: board)
                keyIndex[ch] = keys.count
                keys.append(Key(cap: cap, rest: rest))
            }
        }
        let barRest = SIMD3<Float>(0, baseHeight + 0.008, 0.066)
        _ = add(.generateBox(size: [0.19, 0.006, 0.020]), DeskMaterials.copper,
                at: [0, baseHeight + 0.003, 0.066], to: board)
        let bar = add(.generateBox(size: [0.18, 0.005, 0.016]), DeskMaterials.ivory,
                      at: barRest, to: board)
        keyIndex[" "] = keys.count
        keys.append(Key(cap: bar, rest: barRest))
    }

    // MARK: - Reacting

    /// A key went down. Dips the matching cap, or a random one for characters
    /// the keyboard has no cap for, and kicks the gears.
    func keystroke(_ character: Character?) {
        boost = min(boost + 1.6, 6)
        fittings?.keystroke()
        guard !keys.isEmpty else { return }
        let lowered = character.flatMap { Character(String($0).lowercased()) }
        let index = lowered.flatMap { keyIndex[$0] } ?? rng.index(keys.count)
        keys[index].press = 1
    }

    /// Throws the next breaker over, or all of them for a new sheet.
    func flipBreakers(all: Bool = false) {
        guard !breakers.isEmpty else { return }
        boost = min(boost + 2.5, 6)
        if all {
            for i in breakers.indices {
                breakers[i].isUp.toggle()
                fittings?.breakerThrown(i)
            }
        } else {
            breakers[nextBreaker].isUp.toggle()
            fittings?.breakerThrown(nextBreaker)
            nextBreaker = (nextBreaker + 1) % breakers.count
        }
    }

    func setText(_ text: String) {
        let newPage = ScreenTextLayout.page(for: text)
        guard newPage != page else { return }
        page = newPage
        offIsStale = true
        cursorVisible = true
        blinkTimer = 0
        guard let image = renderer.image(for: newPage, showCursor: true) else {
            screenFailed = true
            return
        }
        show(image, cursorOn: true)
    }

    private func show(_ image: CGImage, cursorOn: Bool) {
        let options = TextureResource.CreateOptions(semantic: .color)
        do {
            if cursorOn {
                if let textureOn {
                    try textureOn.replace(withImage: image, options: options)
                } else {
                    let texture = try TextureResource(image: image, withName: "desk-screen-on", options: options)
                    textureOn = texture
                    materialOn = UnlitMaterial(texture: texture)
                }
            } else {
                if let textureOff {
                    try textureOff.replace(withImage: image, options: options)
                } else {
                    let texture = try TextureResource(image: image, withName: "desk-screen-off", options: options)
                    textureOff = texture
                    materialOff = UnlitMaterial(texture: texture)
                }
            }
            if let material = cursorOn ? materialOn : materialOff {
                screen?.model?.materials = [material]
            }
            screenFailed = false
        } catch {
            screenFailed = true
        }
    }

    // MARK: - Per frame

    func update(dt: Float, time: Float) {
        // Gears: idle turn, plus a kick from typing that dies away.
        boost *= exp(-dt / 0.35)
        let travel = 0.5 * (1 + boost) * dt
        driverAngle += travel
        for gear in gears {
            gear.entity.orientation = simd_quatf(angle: gear.startAngle + gear.rate * driverAngle, axis: [0, 0, 1])
        }
        tickTravel += travel
        let tooth = GearMesh.pitchAngle(teeth: driverTeeth)
        if tickTravel >= tooth {
            tickTravel = tickTravel.truncatingRemainder(dividingBy: tooth)
            onGearTick?()
        }

        // Bulbs: gentle, uneven flicker, a little brighter while typing.
        var total: Float = 0
        for (i, filament) in filaments.enumerated() {
            let phase = Float(i) * 1.7
            let flicker = 0.84 + 0.09 * sin(time * 7.3 + phase) + 0.07 * sin(time * 23.1 + phase * 2.4)
            let level = flicker + min(boost, 3) * 0.06
            total += level
            // The filament swells and shrinks with its level. Giving it a new
            // material each frame instead cost about 5 ms a frame.
            filament.scale = filamentScale * (0.55 + 0.5 * level)
        }
        if !filaments.isEmpty, var light = bulbLight.components[PointLightComponent.self] {
            light.intensity = bulbLightBase * total / Float(filaments.count)
            bulbLight.components.set(light)
        }

        fittings?.update(dt: dt, time: time, activity: boost)

        // Breakers ease to their thrown position.
        let ease = 1 - exp(-dt * 22)
        for i in breakers.indices {
            let target = breakers[i].isUp ? -breakerThrow : breakerThrow
            guard abs(target - breakers[i].angle) > 0.0005 else { continue }
            breakers[i].angle += (target - breakers[i].angle) * ease
            breakers[i].pivot.orientation = simd_quatf(angle: breakers[i].angle, axis: [1, 0, 0])
        }

        // Key caps spring back.
        for i in keys.indices where keys[i].press > 0 {
            keys[i].press = max(0, keys[i].press - dt * 9)
            keys[i].cap.position = keys[i].rest - [0, 0.004 * keys[i].press, 0]
        }

        // Cursor blink. The cursor-off image is drawn the first time it is
        // needed after the text changes, not on every keystroke.
        blinkTimer += dt
        if blinkTimer >= 0.53 {
            blinkTimer = 0
            cursorVisible.toggle()
            if !cursorVisible, offIsStale, let page, let image = renderer.image(for: page, showCursor: false) {
                show(image, cursorOn: false)
                offIsStale = false
            } else if let material = cursorVisible ? materialOn : materialOff {
                screen?.model?.materials = [material]
            }
        }
    }
}
