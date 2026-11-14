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

    /// A material whose colour and roughness vary across the surface. The
    /// tint is multiplied by the colour image, and `roughness` is the level
    /// reached where the roughness image is mid-grey.
    static func surfaced(_ maps: SurfaceTextures.Pair?, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                         metallic: Float, roughness: Float) -> PhysicallyBasedMaterial {
        var m = pbr(r, g, b, metallic: metallic, roughness: roughness)
        guard let maps else { return m }
        m.baseColor = .init(tint: NSColor(srgbRed: r, green: g, blue: b, alpha: 1),
                            texture: SurfaceTextures.repeating(maps.colour))
        m.roughness = .init(scale: roughness * 2, texture: SurfaceTextures.repeating(maps.roughness))
        return m
    }

    // Brass and copper are kept for the working parts and trim; the casing is
    // dark, oxidised bronze, so the bright metal reads against it.
    static let brass = surfaced(SurfaceTextures.metal, 0.80, 0.61, 0.30, metallic: 1, roughness: 0.32)
    static let copper = surfaced(SurfaceTextures.metal, 0.74, 0.43, 0.28, metallic: 1, roughness: 0.32)
    static let bronze = surfaced(SurfaceTextures.metal, 0.39, 0.27, 0.14, metallic: 1, roughness: 0.48)
    static let darkBronze = surfaced(SurfaceTextures.metal, 0.20, 0.15, 0.10, metallic: 1, roughness: 0.52)
    static let leather = pbr(0.20, 0.07, 0.05, metallic: 0, roughness: 0.62)
    static let paper = pbr(0.62, 0.56, 0.44, metallic: 0, roughness: 0.9)
    static let iron = surfaced(SurfaceTextures.metal, 0.08, 0.08, 0.085, metallic: 0.9, roughness: 0.5)
    /// Aged bone, kept well short of white so the key light does not blow it out.
    static let ivory = surfaced(SurfaceTextures.ivory, 0.50, 0.44, 0.32, metallic: 0, roughness: 0.6)
    static let darkWood: PhysicallyBasedMaterial = {
        var m = surfaced(SurfaceTextures.wood, 0.21, 0.115, 0.065, metallic: 0, roughness: 0.5)
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
    /// Centre of the glass screen at rest, and its size, in the machine's own
    /// space. The zoom aims here, and `steady` brings the screen to it.
    private(set) var screenCentre: SIMD3<Float> = .zero
    private(set) var screenSize: SIMD2<Float> = .zero
    /// Where the screen is this frame: it rides up and down on its pistons.
    var liveScreenCentre: SIMD3<Float> { screenCentre + [0, crtLift, 0] }
    /// Holds the screen still at its rest height, for reading up close.
    var steady = false

    // Layout, in metres.
    private let plinthHeight: Float = 0.03
    /// The outline of the cabinet: a low deck, a tower on the right and a
    /// spine across the back, with the screen hung in the open corner.
    private let bodySize = SIMD3<Float>(0.42, 0.34, 0.22)
    private let deckHeight: Float = 0.10
    private var deckTop: Float { plinthHeight + deckHeight }
    private let towerWidth: Float = 0.10
    private let spineDepth: Float = 0.06

    /// The screen and its housing, which move as one.
    private let crt = Entity()
    private let crtRest = SIMD3<Float>(-0.07, 0.305, 0.07)
    private var crtSize = SIMD2<Float>(0.31, 0.25)
    private var crtLift: Float = 0
    private var pinion: Entity?
    private let pinionTeeth = 8
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
    private let filamentScale = SIMD3<Float>(0.8, 1.5, 0.8)
    private let bulbLight = Entity()
    private var fittings: MachineFittings?
    private let bulbLightBase: Float = 4500

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
        buildMount()
        buildGears()
        buildBulbs()
        buildBreakers()
        fittings = MachineFittings(root: root, layout: .init(
            plinthHeight: plinthHeight, topY: topY, deckTop: deckTop, frontZ: frontZ, bodyHalfWidth: bodySize.x / 2,
            breakerX: breakerX, breakerY: (0..<3).map(breakerY),
            bulbParent: crt, bulbSockets: (0..<5).map(bulbSocket),
            bulbFeed: [0, crtSize.y * 0.39, -0.135]))
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
        _ = add(.deskBox(size: [0.62, plinthHeight, 0.54], bevel: 0.006), DeskMaterials.bronze,
                at: [0, plinthHeight / 2, 0.04])
        let back = bodyCentre.z - bodySize.z / 2
        _ = add(.deskBox(size: [bodySize.x, deckHeight, bodySize.z], bevel: 0.010), DeskMaterials.darkBronze,
                at: [0, plinthHeight + deckHeight / 2, bodyCentre.z])
        _ = add(.deskBox(size: [towerWidth, bodySize.y, bodySize.z], bevel: 0.010), DeskMaterials.darkBronze,
                at: [bodySize.x / 2 - towerWidth / 2, bodyCentre.y, bodyCentre.z])
        _ = add(.deskBox(size: [bodySize.x, bodySize.y, spineDepth], bevel: 0.010), DeskMaterials.darkBronze,
                at: [0, bodyCentre.y, back + spineDepth / 2])

        // Soft pools of shade where each piece stands on the one below.
        let pools: [(String, SIMD2<Float>, Float, Float, SIMD3<Float>)] = [
            ("shade-plinth", [0.62, 0.54], 0.006, 0.09, [0, 0.0008, 0.04]),
            ("shade-body", [bodySize.x, bodySize.z], 0.012, 0.035, [0, plinthHeight + 0.0006, bodyCentre.z]),
            ("shade-keyboard", [0.42, 0.185], 0.005, 0.022, [0, plinthHeight + 0.0006, 0.195]),
        ]
        for (name, size, corner, spread, position) in pools {
            guard let pool = SurfaceTextures.contactShadow(name, size: size, corner: corner, spread: spread) else { continue }
            pool.position = position
            root.addChild(pool)
        }

        // Riveted straps.
        // The right one goes over the tower; the left one only round the deck.
        _ = add(.deskBox(size: [0.018, bodySize.y + 0.004, bodySize.z + 0.006], bevel: 0.003), DeskMaterials.brass,
                at: [0.19, bodyCentre.y, bodyCentre.z])
        _ = add(.deskBox(size: [0.018, deckHeight + 0.004, bodySize.z + 0.006], bevel: 0.003), DeskMaterials.brass,
                at: [-0.19, plinthHeight + deckHeight / 2, bodyCentre.z])
        // Back plate that carries the main gear train.
        // It is near-black and sits inside a raised brass frame, so the gears
        // work in a shallow recess.
        _ = add(.deskBox(size: [0.50, 0.25, 0.012], bevel: 0.004), DeskMaterials.iron,
                at: [0.02, topY + 0.125, -0.12])
        let rail: Float = 0.016, deep: Float = 0.030
        let frame: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([0.02, topY + 0.25 - rail / 2, -0.111], [0.50, rail, deep]),
            ([0.02, topY + rail / 2, -0.111], [0.50, rail, deep]),
            ([0.02 - 0.25 + rail / 2, topY + 0.125, -0.111], [rail, 0.25, deep]),
            ([0.02 + 0.25 - rail / 2, topY + 0.125, -0.111], [rail, 0.25, deep]),
        ]
        for (position, size) in frame {
            _ = add(.deskBox(size: size, bevel: 0.004), DeskMaterials.darkBronze, at: position)
        }
        // Side wing for the second train.
        // Tall enough to carry the pinion that the screen's rack runs on.
        _ = add(.deskBox(size: [0.16, 0.33, 0.010], bevel: 0.004), DeskMaterials.iron,
                at: [-0.285, 0.195, -0.02])
    }

    /// The cathode-ray tube: a glass face in a brass bezel, a bronze housing
    /// that narrows to the tube's neck, and the coils round it.
    private func buildScreen() {
        let width: Float = 0.262
        let height = width / ScreenTextRenderer.aspect
        screenCentre = crtRest + [0, 0, 0.004]
        screenSize = [width, height]
        crt.position = crtRest
        root.addChild(crt)

        // The tube face bulges slightly; a second, clear skin over it catches highlights.
        var face = MeshBuilder()
        face.domedPanel(width: width, height: height, bulge: 0.010)
        if let mesh = try? face.build(name: "screen") {
            screen = add(mesh, DeskMaterials.iron, at: [0, 0, 0.004], to: crt)
            // Kept very thin: under the key light a thicker skin fogs the type.
            _ = add(mesh, DeskMaterials.glass(opacity: 0.02), at: [0, 0, 0.006], to: crt)
        }

        // Bezel.
        let t: Float = 0.018
        let z: Float = 0.010
        let bars: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([0, height / 2 + t / 2, z], [width + 2 * t, t, 0.026]),
            ([0, -height / 2 - t / 2, z], [width + 2 * t, t, 0.026]),
            ([-width / 2 - t / 2, 0, z], [t, height, 0.026]),
            ([width / 2 + t / 2, 0, z], [t, height, 0.026]),
        ]
        for (position, size) in bars {
            _ = add(.deskBox(size: size, bevel: 0.004), DeskMaterials.brass, at: position, to: crt)
        }

        // Housing: a deep front box, a smaller one behind it, then the neck.
        let w = width + 2 * t + 0.014, h = height + 2 * t + 0.014
        crtSize = [w, h]
        _ = add(.deskBox(size: [w, h, 0.09], bevel: 0.012), DeskMaterials.darkBronze, at: [0, 0, -0.045], to: crt)
        _ = add(.deskBox(size: [w * 0.78, h * 0.78, 0.05], bevel: 0.014), DeskMaterials.darkBronze,
                at: [0, 0, -0.112], to: crt)
        _ = addAxial(radius: 0.040, length: 0.04, DeskMaterials.iron, at: [0, 0, -0.150], to: crt)
        _ = addAxial(radius: 0.052, length: 0.010, DeskMaterials.brass, at: [0, 0, -0.139], to: crt)
        _ = addAxial(radius: 0.047, length: 0.014, DeskMaterials.copper, at: [0, 0, -0.154], to: crt)
        _ = addAxial(radius: 0.022, length: 0.012, DeskMaterials.brass, at: [0, 0, -0.174], to: crt)
        // A brass band where the two boxes meet, and studs at the bezel's corners.
        _ = add(.deskBox(size: [w * 0.80, h * 0.80, 0.008], bevel: 0.003), DeskMaterials.brass,
                at: [0, 0, -0.091], to: crt)
        // Close-up detail: a dark gasket where the glass meets the brass, a
        // copper bead round the outside, slotted screws and a maker's plate.
        let rubber = DeskMaterials.pbr(0.025, 0.022, 0.02, metallic: 0, roughness: 0.85)
        let g: Float = 0.0045
        let gasket: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([0, height / 2 - g / 2, 0.016], [width, g, 0.012]),
            ([0, -height / 2 + g / 2, 0.016], [width, g, 0.012]),
            ([-width / 2 + g / 2, 0, 0.016], [g, height, 0.012]),
            ([width / 2 - g / 2, 0, 0.016], [g, height, 0.012]),
        ]
        for (position, size) in gasket {
            _ = add(.deskBox(size: size, bevel: 0.0015), rubber, at: position, to: crt)
        }
        let bead: Float = 0.004
        let outerW = width + 2 * t, outerH = height + 2 * t
        let beads: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([0, outerH / 2 + bead / 2, 0.004], [outerW + 2 * bead, bead, 0.020]),
            ([0, -outerH / 2 - bead / 2, 0.004], [outerW + 2 * bead, bead, 0.020]),
            ([-outerW / 2 - bead / 2, 0, 0.004], [bead, outerH, 0.020]),
            ([outerW / 2 + bead / 2, 0, 0.004], [bead, outerH, 0.020]),
        ]
        for (position, size) in beads {
            _ = add(.deskBox(size: size, bevel: 0.0018), DeskMaterials.copper, at: position, to: crt)
        }
        let head = MeshResource.deskCylinder(height: 0.0026, radius: 0.0052, bevel: 0.0008)
        let slot = MeshResource.generateBox(size: [0.0088, 0.0012, 0.0012])
        var screwAt: [SIMD2<Float>] = []
        for sx in [-1, 0, 1] as [Float] {
            for sy in [-1, 1] as [Float] {
                screwAt.append([sx * (width / 2 + t / 2), sy * (height / 2 + t / 2)])
            }
        }
        for sy in [-1, 1] as [Float] {
            screwAt.append([-(width / 2 + t / 2), sy * height * 0.2])
            screwAt.append([width / 2 + t / 2, sy * height * 0.2])
        }
        for at in screwAt {
            // The bottom middle is taken by the maker's plate.
            if at.x == 0, at.y < 0 { continue }
            let screw = add(head, DeskMaterials.bronze, at: [at.x, at.y, 0.0238], to: crt)
            screw.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            let cut = add(slot, rubber, at: [at.x, at.y, 0.0250], to: crt)
            cut.orientation = simd_quatf(angle: rng.range(0, .pi), axis: [0, 0, 1])
        }
        if let plate = engravedPlate("TANQUE & CO.  ·  WRITING ENGINE No. 7", size: [0.105, 0.009]) {
            plate.position = [0, -height / 2 - t / 2, 0.0236]
            crt.addChild(plate)
        }
    }

    /// A small brass plate with words cut into it, facing the writer.
    private func engravedPlate(_ words: String, size: SIMD2<Float>) -> ModelEntity? {
        let pixelsWide = 768
        let pixelsHigh = max(16, Int((Float(pixelsWide) * size.y / size.x).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixelsWide, height: pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let full = CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh)
        ctx.setFillColor(CGColor(srgbRed: 0.78, green: 0.62, blue: 0.34, alpha: 1))
        ctx.fill(full)
        // A scribed border, then the words, both dark as if filled with old ink.
        let ink = CGColor(srgbRed: 0.10, green: 0.07, blue: 0.04, alpha: 1)
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(max(1.5, CGFloat(pixelsHigh) * 0.04))
        ctx.stroke(full.insetBy(dx: CGFloat(pixelsHigh) * 0.12, dy: CGFloat(pixelsHigh) * 0.12))
        let font = CTFontCreateWithName("Copperplate" as CFString, CGFloat(pixelsHigh) * 0.52, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: words, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink,
            NSAttributedString.Key(kCTKernAttributeName as String): CGFloat(pixelsHigh) * 0.04,
        ]))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        // Shrink to fit a long line.
        let fit = min(1, (CGFloat(pixelsWide) * 0.88) / max(bounds.width, 1))
        ctx.translateBy(x: CGFloat(pixelsWide) / 2, y: CGFloat(pixelsHigh) / 2)
        ctx.scaleBy(x: fit, y: fit)
        ctx.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        CTLineDraw(line, ctx)
        guard let image = ctx.makeImage(),
              let texture = try? TextureResource(image: image, withName: "plate-\(words)", options: .init(semantic: .color))
        else { return nil }
        var material = DeskMaterials.pbr(1, 1, 1, metallic: 1, roughness: 0.38)
        material.baseColor = .init(tint: .white, texture: .init(texture))
        let plate = ModelEntity(mesh: .generatePlane(width: size.x, height: size.y, cornerRadius: size.y * 0.15),
                                materials: [material])
        plate.components.set(DynamicLightShadowComponent(castsShadow: false))
        return plate
    }

    /// What carries the screen: two pistons under it, and a toothed rack down
    /// its left side that turns a pinion on the wing plate as it rises.
    private func buildMount() {
        let steel = DeskMaterials.pbr(0.55, 0.55, 0.57, metallic: 1, roughness: 0.22)
        let under = -crtSize.y / 2
        for side in [-1, 1] as [Float] {
            let x = side * 0.10, z: Float = -0.045
            // Sleeve and collar stand on the deck; the rod hangs from the housing and slides in them.
            _ = add(.deskCylinder(height: 0.032, radius: 0.014, bevel: 0.002), DeskMaterials.brass,
                    at: [crtRest.x + x, deckTop + 0.016, crtRest.z + z])
            _ = add(.deskCylinder(height: 0.006, radius: 0.019, bevel: 0.0015), DeskMaterials.copper,
                    at: [crtRest.x + x, deckTop + 0.003, crtRest.z + z])
            _ = add(.deskCylinder(height: 0.08, radius: 0.0065), steel, at: [x, under - 0.04, z], to: crt)
            _ = add(.deskCylinder(height: 0.006, radius: 0.016, bevel: 0.0015), DeskMaterials.brass,
                    at: [x, under - 0.003, z], to: crt)
        }

        // Rack: a bar on the housing's left side with square teeth facing out.
        let rackZ: Float = -0.079
        let barX = -crtSize.x / 2 - 0.006
        var rack = MeshBuilder()
        rack.box(center: [barX, 0.0125, rackZ], size: [0.012, 0.145, 0.008])
        let pitch = Float.pi * gearModule
        for k in -2...3 {
            rack.box(center: [barX - 0.0105, Float(k) * pitch, rackZ], size: [0.009, pitch * 0.5, 0.008])
        }
        if let mesh = try? rack.build(name: "rack") { _ = add(mesh, DeskMaterials.brass, at: .zero, to: crt) }

        // Pinion, fixed to the wing plate.
        let radius = GearMesh.pitchRadius(teeth: pinionTeeth, module: gearModule)
        let centre = SIMD3<Float>(crtRest.x + barX - 0.0105 - radius, crtRest.y, crtRest.z + rackZ)
        var builder = MeshBuilder()
        GearMesh.add(to: &builder, teeth: pinionTeeth, module: gearModule, thickness: 0.008, holeRadius: radius * 0.3)
        if let mesh = try? builder.build(name: "pinion") {
            pinion = add(mesh, DeskMaterials.copper, at: centre)
        }
        _ = addAxial(radius: radius * 0.3, length: 0.018, DeskMaterials.bronze, at: centre)
        _ = addAxial(radius: radius * 0.42, length: 0.004, DeskMaterials.brass, at: centre + [0, 0, 0.006])
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
                         thickness: 0.008, holeRadius: radius * 0.3, spokes: spec.teeth >= 12 ? 5 : 0)
            guard let mesh = try? builder.build(name: "gear\(spec.teeth)") else { continue }
            let gear = add(mesh, spec.material, at: [centre.x, centre.y, spec.z])
            gear.orientation = simd_quatf(angle: start, axis: [0, 0, 1])
            gears.append(Gear(entity: gear, startAngle: start, rate: rate))

            // Fixed axle and boss.
            _ = addAxial(radius: radius * 0.3, length: 0.018, DeskMaterials.bronze, at: [centre.x, centre.y, spec.z])
            _ = addAxial(radius: radius * 0.42, length: 0.004, DeskMaterials.brass,
                         at: [centre.x, centre.y, spec.z + 0.006])
        }
    }

    /// Bulb sockets along the top of the screen's housing, in its own space.
    private func bulbSocket(_ i: Int) -> SIMD3<Float> { [Float(i - 2) * 0.062, crtSize.y / 2, -0.045] }

    private func buildBulbs() {
        for i in 0..<5 {
            let socket = bulbSocket(i)
            // Socket: a wide collar, then the narrower screw cap the glass sits in.
            _ = add(.deskCylinder(height: 0.008, radius: 0.016, bevel: 0.002), DeskMaterials.darkBronze,
                    at: socket + [0, 0.004, 0], to: crt)
            _ = add(.deskCylinder(height: 0.014, radius: 0.011, bevel: 0.0015), DeskMaterials.brass,
                    at: socket + [0, 0.015, 0], to: crt)
            let centre = socket + [0, 0.022 + 0.024, 0]
            // The wire itself: two posts and a looped filament between them.
            var wire = MeshBuilder()
            for side in [-1, 1] as [Float] {
                wire.cylinder(center: [side * 0.005, -0.012, 0], radius: 0.0006, height: 0.020, segments: 6)
            }
            TubeMesh.add(to: &wire, [-0.005, -0.002, 0], [-0.004, 0.020, 0.003], [0.004, 0.020, -0.003],
                         [0.005, -0.002, 0], radius: 0.0008, segments: 16, sides: 5)
            TubeMesh.add(to: &wire, [-0.005, -0.002, 0], [-0.001, 0.010, -0.004], [0.001, 0.010, 0.004],
                         [0.005, -0.002, 0], radius: 0.0008, segments: 12, sides: 5)
            if let mesh = try? wire.build(name: "filament") {
                _ = add(mesh, DeskMaterials.glow(1.0, 0.70, 0.30, intensity: 9), at: centre, to: crt)
            }
            // A soft bloom round the wire, which is what swells and shrinks.
            var bloom = DeskMaterials.glow(1.0, 0.62, 0.22, intensity: 1.5)
            bloom.blending = .transparent(opacity: .init(floatLiteral: 0.22))
            let filament = add(.deskSphere(radius: 0.008), bloom, at: centre + [0, 0.004, 0], to: crt)
            filament.scale = filamentScale
            filaments.append(filament)
            // Pear-shaped glass.
            let glass = add(.deskSphere(radius: 0.021), DeskMaterials.glass(opacity: 0.14), at: centre + [0, 0.003, 0], to: crt)
            glass.scale = [1, 1.28, 1]
        }
        bulbLight.position = [0, crtSize.y / 2 + 0.07, 0.03]
        bulbLight.components.set(PointLightComponent(cgColor: CGColor(srgbRed: 1.0, green: 0.80, blue: 0.58, alpha: 1),
                                                     intensity: bulbLightBase, attenuationRadius: 2.0))
        crt.addChild(bulbLight)
    }

    /// Level with the screen, so they stay in view when zoomed in on it.
    private func breakerY(_ i: Int) -> Float { 0.345 - Float(i) * 0.05 }
    private let breakerX: Float = 0.155

    private func buildBreakers() {
        _ = add(.deskBox(size: [0.07, 0.155, 0.006], bevel: 0.002), DeskMaterials.iron,
                at: [breakerX, 0.295, frontZ + 0.003])
        let tags = ["LINE", "FEED", "SHEET"]
        for i in 0..<3 {
            let y = breakerY(i)
            if let tag = engravedPlate(tags[i], size: [0.024, 0.007]) {
                tag.position = [breakerX - 0.018, y + 0.019, frontZ + 0.0065]
                root.addChild(tag)
            }
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
        _ = add(.deskBox(size: [0.42, baseHeight, 0.185], bevel: 0.005), DeskMaterials.darkBronze,
                at: [0, baseHeight / 2, 0], to: board)

        let rows: [(keys: String, indent: Float, z: Float)] = [
            ("1234567890", 0, -0.066),
            ("qwertyuiop", 0.008, -0.033),
            ("asdfghjkl;", 0.016, 0),
            ("zxcvbnm,.", 0.030, 0.033),
        ]
        let pitch: Float = 0.036
        let pedestal = MeshResource.deskCylinder(height: 0.008, radius: 0.0150, bevel: 0.0015)
        // Typewriter keys: a brass cup with a rolled rim, and an ivory button set into it.
        let capMesh = MeshResource.deskCylinder(height: 0.005, radius: 0.0128, bevel: 0.0014)
        let buttonMesh = MeshResource.deskCylinder(height: 0.002, radius: 0.0104, bevel: 0.0008, dish: 0.0007)
        for row in rows {
            for (i, ch) in row.keys.enumerated() {
                let x = -0.175 + row.indent + Float(i) * pitch
                _ = add(pedestal, DeskMaterials.copper, at: [x, baseHeight + 0.004, row.z], to: board)
                let rest = SIMD3<Float>(x, baseHeight + 0.008 + 0.0025, row.z)
                let cap = add(capMesh, DeskMaterials.brass, at: rest, to: board)
                _ = add(buttonMesh, DeskMaterials.ivory, at: [0, 0.0027, 0], to: cap)
                keyIndex[ch] = keys.count
                keys.append(Key(cap: cap, rest: rest))
            }
        }
        let barRest = SIMD3<Float>(0, baseHeight + 0.008, 0.066)
        _ = add(.deskBox(size: [0.19, 0.006, 0.020], bevel: 0.002), DeskMaterials.copper,
                at: [0, baseHeight + 0.003, 0.066], to: board)
        let bar = add(.deskBox(size: [0.18, 0.005, 0.016], bevel: 0.002), DeskMaterials.ivory,
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

        // The screen rides up on its pistons while the machine is worked, and
        // breathes a little at rest. The pinion turns with the rack.
        let wanted: Float = steady ? 0 : 0.0015 * sin(time * 0.9) + 0.004 * min(boost, 3.5)
        crtLift += (wanted - crtLift) * (1 - exp(-dt * 3))
        crt.position = crtRest + [0, crtLift, 0]
        pinion?.orientation = simd_quatf(
            angle: crtLift / GearMesh.pitchRadius(teeth: pinionTeeth, module: gearModule), axis: [0, 0, 1])

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
