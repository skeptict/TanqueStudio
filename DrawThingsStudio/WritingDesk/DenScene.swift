import AppKit
import RealityKit
import simd

/// The penthouse den: a box room with a desk, a wall of books, a two-storey
/// window wall and the painted valley beyond it.
///
/// World space: floor at y = 0, windows on the -z wall, bookshelves on the -x
/// wall. The writer sits at the desk facing the windows.
@available(macOS 15, *)
@MainActor
final class DenScene {
    let root = Entity()
    let computer = SteamComputer()

    /// Pointer position over the view, -1...1 on each axis, +y up.
    var pointer: SIMD2<Float> = .zero
    var lookAround = false
    /// Width over height of the view, so a focused item can be fitted to it.
    var viewAspect: Float = 2.5
    /// Carries the camera and the screen's position to the painted look.
    let paint = PaintedLookState()

    /// Somewhere the camera can sit, and what it looks at from there.
    struct Viewpoint {
        var eye: SIMD3<Float>
        var target: SIMD3<Float>

        func blended(to other: Viewpoint, _ t: Float) -> Viewpoint {
            Viewpoint(eye: simd_mix(eye, other.eye, SIMD3(repeating: t)),
                      target: simd_mix(target, other.target, SIMD3(repeating: t)))
        }
    }
    /// True while the camera is at, or travelling to, something other than the seat.
    private(set) var isFocused = false

    private(set) var triangleCount = 0
    private(set) var lightCount = 0
    /// Backdrop files that were not found, so a gradient is standing in.
    private(set) var missingBackdrops: [String] = []

    // Room, in metres.
    private let halfWidth: Float = 4
    private let halfDepth: Float = 4.5
    private let height: Float = 7
    private let deskTop: Float = 0.76
    /// The desk sits left of centre so the book wall is in frame.
    private let deskX: Float = -1.4
    private var eye: SIMD3<Float> { [deskX, 1.22, 0.55] }
    private var target: SIMD3<Float> { [deskX, 1.12, -0.62] }
    /// The city image is centred this far right of straight ahead, so its
    /// middle is not hidden behind the machine.
    private let cityYaw: Float = 20 * .pi / 180

    private let camera = Entity()
    private let outside = Entity()
    private var cityEntity: ModelEntity?
    private var shelfPanels: [ModelEntity] = []
    private var time: Float = 0
    private var smoothedPointer: SIMD2<Float> = .zero
    private var lookBlend: Float = 0
    private let fieldOfView: Float = 42
    private var seat: Viewpoint { Viewpoint(eye: eye, target: target) }
    private var leaving = Viewpoint(eye: .zero, target: [0, 0, -1])
    private var arriving = Viewpoint(eye: .zero, target: [0, 0, -1])
    private var current = Viewpoint(eye: .zero, target: [0, 0, -1])
    private var travel: Float = 1
    private var focusBlend: Float = 0
    private let travelSeconds: Float = 0.9

    init() {
        buildShell()
        buildDesk()
        buildShelves()
        buildWindows()
        buildOutside()
        loadBackdrops()
        buildLights()

        computer.root.position = [deskX, deskTop, -0.62]
        root.addChild(computer.root)

        camera.components.set(PerspectiveCameraComponent(near: 0.05, far: 200, fieldOfViewInDegrees: fieldOfView))
        leaving = seat
        arriving = seat
        current = seat
        camera.look(at: target, from: eye, relativeTo: nil)
        root.addChild(camera)

        applyReflections()
        triangleCount = Self.triangles(in: root)
    }

    // MARK: - Building

    @discardableResult
    private func add(_ mesh: MeshResource, _ material: any RealityKit.Material,
                     at position: SIMD3<Float> = .zero, to parent: Entity? = nil) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.position = position
        (parent ?? root).addChild(e)
        return e
    }

    private func buildShell() {
        // Floor: tiled quads, so the board texture repeats without needing a
        // repeating sampler.
        var floor = MeshBuilder()
        let tiles = 5
        let tileW = 2 * halfWidth / Float(tiles), tileD = 2 * halfDepth / Float(tiles)
        for i in 0..<tiles {
            for j in 0..<tiles {
                let x0 = -halfWidth + Float(i) * tileW, z0 = -halfDepth + Float(j) * tileD
                floor.quad([x0, 0, z0 + tileD], [x0 + tileW, 0, z0 + tileD], [x0 + tileW, 0, z0], [x0, 0, z0],
                           normal: [0, 1, 0])
            }
        }
        var boards = DeskMaterials.pbr(0.5, 0.5, 0.5, metallic: 0, roughness: 0.35)
        if let image = BackdropLoader.floorboards(),
           let texture = try? TextureResource(image: image, withName: "desk-floor", options: .init(semantic: .color)) {
            boards.baseColor = .init(tint: .white, texture: .init(texture))
        } else {
            boards = DeskMaterials.darkWood
        }
        boards.clearcoat = .init(floatLiteral: 0.5)
        if let mesh = try? floor.build(name: "floor") { add(mesh, boards) }

        // Three walls and a ceiling; the fourth wall is glass.
        var shell = MeshBuilder()
        let t: Float = 0.1
        shell.box(center: [halfWidth + t / 2, height / 2, 0], size: [t, height, 2 * halfDepth])
        shell.box(center: [-halfWidth - t / 2, height / 2, 0], size: [t, height, 2 * halfDepth])
        shell.box(center: [0, height / 2, halfDepth + t / 2], size: [2 * halfWidth, height, t])
        shell.box(center: [0, height + t / 2, 0], size: [2 * halfWidth, t, 2 * halfDepth])
        if let mesh = try? shell.build(name: "shell") {
            add(mesh, DeskMaterials.pbr(0.11, 0.095, 0.085, metallic: 0, roughness: 0.9))
        }
    }

    private func buildDesk() {
        var desk = MeshBuilder()
        desk.box(center: [deskX, deskTop - 0.03, -0.55], size: [2.4, 0.06, 1.1])
        for side in [-0.85, 0.85] as [Float] {
            desk.box(center: [deskX + side, (deskTop - 0.06) / 2, -0.55], size: [0.5, deskTop - 0.06, 0.95])
        }
        desk.box(center: [deskX, deskTop - 0.13, -0.95], size: [1.2, 0.14, 0.02])
        if let mesh = try? desk.build(name: "desk") { add(mesh, DeskMaterials.darkWood) }

        // Banker's lamp at the left of the desk.
        let lamp = Entity()
        lamp.position = [deskX - 0.85, deskTop, -0.82]
        root.addChild(lamp)
        add(.deskCylinder(height: 0.016, radius: 0.075), DeskMaterials.brass, at: [0, 0.008, 0], to: lamp)
        add(.deskCylinder(height: 0.30, radius: 0.008), DeskMaterials.brass, at: [0, 0.16, 0], to: lamp)
        add(.generateCone(height: 0.10, radius: 0.12),
            DeskMaterials.pbr(0.05, 0.22, 0.14, metallic: 0, roughness: 0.25), at: [0, 0.35, 0], to: lamp)
        add(.deskSphere(radius: 0.022), DeskMaterials.glow(1.0, 0.78, 0.48, intensity: 4),
            at: [0, 0.305, 0], to: lamp)
    }

    private func buildShelves() {
        let depth: Float = 0.32
        let front = -halfWidth + depth
        let lowerTop: Float = 2.33
        let rowPitch: Float = 0.44
        let rows = 5
        let bays = Int(2 * halfDepth)

        var frame = MeshBuilder()
        frame.box(center: [-halfWidth + 0.01, lowerTop / 2, 0], size: [0.02, lowerTop, 2 * halfDepth])
        for i in 0...bays {
            let z = -halfDepth + Float(i)
            frame.box(center: [-halfWidth + depth / 2, lowerTop / 2, min(max(z, -halfDepth + 0.02), halfDepth - 0.02)],
                      size: [depth, lowerTop, 0.04])
        }
        for r in 0...rows {
            frame.box(center: [-halfWidth + depth / 2, 0.095 + Float(r) * rowPitch, 0],
                      size: [depth, 0.03, 2 * halfDepth])
        }
        if let mesh = try? frame.build(name: "shelf-frame") { add(mesh, DeskMaterials.darkWood) }

        // Books: one mesh per leather colour, so the whole wall is six draws.
        let leathers: [PhysicallyBasedMaterial] = [
            DeskMaterials.pbr(0.30, 0.07, 0.06, metallic: 0, roughness: 0.65),
            DeskMaterials.pbr(0.07, 0.17, 0.10, metallic: 0, roughness: 0.70),
            DeskMaterials.pbr(0.07, 0.10, 0.20, metallic: 0, roughness: 0.70),
            DeskMaterials.pbr(0.42, 0.28, 0.14, metallic: 0, roughness: 0.75),
            DeskMaterials.pbr(0.19, 0.11, 0.06, metallic: 0, roughness: 0.70),
            DeskMaterials.pbr(0.20, 0.19, 0.20, metallic: 0, roughness: 0.80),
        ]
        var books = Array(repeating: MeshBuilder(), count: leathers.count)
        var rng = SeededRandom(seed: 0x5EED_B00C)
        for r in 0..<rows {
            let shelfTop = 0.11 + Float(r) * rowPitch
            for bay in 0..<bays {
                var z = -halfDepth + Float(bay) + 0.045
                let end = -halfDepth + Float(bay) + 0.955
                while true {
                    if rng.unit() < 0.05 { z += rng.range(0.04, 0.14) }
                    let width = rng.range(0.022, 0.056)
                    guard z + width <= end else { break }
                    let tall = rng.range(0.22, 0.37)
                    let deep = rng.range(0.17, 0.25)
                    let spine = front - 0.015 - rng.range(0, 0.03)
                    books[rng.index(books.count)].box(center: [spine - deep / 2, shelfTop + tall / 2, z + width / 2],
                                                      size: [deep, tall, width])
                    z += width + 0.001
                }
            }
        }
        for (builder, leather) in zip(books, leathers) where !builder.isEmpty {
            if let mesh = try? builder.build(name: "books") { add(mesh, leather) }
        }

        // Upper shelves: three painted panels, the middle one mirrored so the
        // repeat is less obvious.
        let panelDepth = 2 * halfDepth / 3
        for i in 0..<3 {
            let z1 = halfDepth - Float(i) * panelDepth
            let z0 = z1 - panelDepth
            let mirrored = i == 1
            var panel = MeshBuilder()
            panel.quad([front, lowerTop, z1], [front, lowerTop, z0], [front, height, z0], [front, height, z1],
                       normal: [1, 0, 0],
                       uvs: mirrored ? [[1, 0], [0, 0], [0, 1], [1, 1]] : [[0, 0], [1, 0], [1, 1], [0, 1]])
            if let mesh = try? panel.build(name: "upper-shelves") {
                shelfPanels.append(add(mesh, DeskMaterials.darkWood))
            }
        }
    }

    private func buildWindows() {
        let z = -halfDepth
        var mullions = MeshBuilder()
        for i in 0...Int(2 * halfWidth) {
            let x = min(max(-halfWidth + Float(i), -halfWidth + 0.03), halfWidth - 0.03)
            mullions.box(center: [x, height / 2, z], size: [0.05, height, 0.08])
        }
        for y in [0.04, 1.2, 2.35, 4.65, 5.8, height - 0.04] as [Float] {
            mullions.box(center: [0, y, z], size: [2 * halfWidth, 0.05, 0.08])
        }
        // The heavier transom where the two storeys meet.
        mullions.box(center: [0, 3.5, z], size: [2 * halfWidth, 0.14, 0.10])
        if let mesh = try? mullions.build(name: "mullions") { add(mesh, DeskMaterials.iron) }

        add(.generatePlane(width: 2 * halfWidth, height: height), DeskMaterials.glass(opacity: 0.05),
            at: [0, height / 2, z - 0.02])
    }

    private func buildOutside() {
        // Centred on the writer and turned so the image's middle sits to the
        // right of the machine.
        outside.position = [eye.x, 0, eye.z]
        outside.orientation = simd_quatf(angle: -cityYaw, axis: [0, 1, 0])
        root.addChild(outside)

        var sky = MeshBuilder()
        sky.arcWall(center: .zero, radius: 14, span: 2.6, bottom: -6, height: 30)
        if let mesh = try? sky.build(name: "sky"), let image = BackdropLoader.duskSky(),
           let texture = try? TextureResource(image: image, withName: "desk-sky", options: .init(semantic: .color)) {
            add(mesh, UnlitMaterial(texture: texture), to: outside)
        }
    }

    /// Reads the backdrop images again. Call after dropping new files in the folder.
    func loadBackdrops() {
        missingBackdrops = []
        BackdropLoader.ensureFolders()

        if let city = BackdropLoader.backdrop(named: "city.png", fallback: BackdropLoader.duskCity) {
            if city.isFallback { missingBackdrops.append("city.png") }
            let radius: Float = 12
            let span: Float = 100 * .pi / 180
            let tall = radius * span / city.aspect
            var wall = MeshBuilder()
            // Middle of the image a little above eye level.
            wall.arcWall(center: .zero, radius: radius, span: span, bottom: 2.05 - tall / 2, height: tall)
            if let mesh = try? wall.build(name: "city") {
                cityEntity?.removeFromParent()
                cityEntity = add(mesh, UnlitMaterial(texture: city.texture), to: outside)
            }
        }

        if let shelves = BackdropLoader.backdrop(named: "shelves.png", fallback: BackdropLoader.shelfShadow) {
            if shelves.isFallback { missingBackdrops.append("shelves.png") }
            var material = UnlitMaterial(texture: shelves.texture)
            // Painted light would glow in a dark room, so it is knocked back.
            material.color = .init(tint: NSColor(white: 0.5, alpha: 1), texture: .init(shelves.texture))
            for panel in shelfPanels { panel.model?.materials = [material] }
        }
        triangleCount = Self.triangles(in: root)
    }

    private func buildLights() {
        // Dusk through the windows.
        let dusk = Entity()
        dusk.components.set(DirectionalLightComponent(color: NSColor(srgbRed: 0.55, green: 0.62, blue: 1.0, alpha: 1),
                                                      intensity: 250))
        dusk.look(at: [0, 0.8, 0], from: [1.5, 3.5, -6], relativeTo: nil)
        root.addChild(dusk)

        // Desk lamp.
        let lamp = Entity()
        lamp.position = [deskX - 0.85, deskTop + 0.27, -0.80]
        lamp.components.set(PointLightComponent(cgColor: CGColor(srgbRed: 1.0, green: 0.74, blue: 0.44, alpha: 1),
                                                intensity: 60_000, attenuationRadius: 6))
        root.addChild(lamp)

        // The third light is the machine's own bulb glow.
        lightCount = 3
    }

    /// Gives the metal something to reflect.
    private func applyReflections() {
        guard let image = BackdropLoader.reflections(),
              let environment = try? EnvironmentResource(equirectangular: image, withName: "desk-reflections")
        else { return }
        let source = Entity()
        source.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 1.0))
        root.addChild(source)
        Self.visit(root) { entity in
            if entity.components.has(ModelComponent.self) {
                entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: source))
            }
        }
    }

    private static func visit(_ entity: Entity, _ body: (Entity) -> Void) {
        body(entity)
        for child in entity.children { visit(child, body) }
    }

    private static func triangles(in entity: Entity) -> Int {
        var count = 0
        visit(entity) { e in
            guard let model = e.components[ModelComponent.self] else { return }
            for m in model.mesh.contents.models {
                for part in m.parts {
                    count += (part.triangleIndices?.count ?? 0) / 3
                }
            }
        }
        return count
    }

    // MARK: - Focus

    /// Glides the camera to a viewpoint, or back to the seat for `nil`.
    /// Anything in the room can be focused on by describing a viewpoint for it.
    func focus(on viewpoint: Viewpoint?) {
        leaving = current
        arriving = viewpoint ?? seat
        travel = 0
        isFocused = viewpoint != nil
    }

    /// A viewpoint square-on to a flat thing, close enough that it fills
    /// `fill` of the view in whichever direction is tighter.
    func viewpoint(facing centre: SIMD3<Float>, size: SIMD2<Float>, fill: Float = 0.84) -> Viewpoint {
        let half = tan(fieldOfView * .pi / 360)
        let forHeight = size.y / 2 / (fill * half)
        let forWidth = size.x / 2 / (fill * half * max(viewAspect, 0.1))
        return Viewpoint(eye: centre + [0, 0, max(forHeight, forWidth)], target: centre)
    }

    /// Close on the glass screen, for writing.
    var screenViewpoint: Viewpoint {
        viewpoint(facing: computer.root.position + computer.screenCentre, size: computer.screenSize)
    }

    private var screenCorners: [SIMD3<Float>] {
        let c = computer.root.position + computer.screenCentre
        let w = computer.screenSize.x / 2, h = computer.screenSize.y / 2
        return [c + [-w, h, 0], c + [w, h, 0], c + [w, -h, 0], c + [-w, -h, 0]]
    }

    // MARK: - Per frame

    func update(dt: Float) {
        guard dt > 0 else { return }
        time += dt
        computer.update(dt: dt, time: time)

        let follow = 1 - exp(-dt * 4)
        smoothedPointer += (pointer - smoothedPointer) * follow

        // Travel between viewpoints eases in and out.
        travel = min(1, travel + dt / travelSeconds)
        let eased = travel * travel * (3 - 2 * travel)
        current = leaving.blended(to: arriving, eased)
        focusBlend += ((isFocused ? 1 : 0) - focusBlend) * (1 - exp(-dt * 5))
        lookBlend += ((lookAround && !isFocused ? 1 : 0) - lookBlend) * (1 - exp(-dt * 3))

        let forward = simd_normalize(current.target - current.eye)
        let right = simd_normalize(simd_cross(forward, [0, 1, 0]))

        // Seated: the head shifts a few centimetres with the pointer. Close
        // on something, it barely moves.
        let lean = (right * smoothedPointer.x * 0.05 + SIMD3<Float>(0, 1, 0) * smoothedPointer.y * 0.03)
            * (1 - lookBlend) * (1 - 0.9 * focusBlend)
        // Looking around: the head turns instead.
        let yaw = simd_quatf(angle: -smoothedPointer.x * 1.25 * lookBlend, axis: [0, 1, 0])
        let pitch = simd_quatf(angle: smoothedPointer.y * 0.55 * lookBlend, axis: right)
        let gaze = yaw.act(pitch.act(forward))

        let position = current.eye + lean
        let reach = simd_length(current.target - current.eye)
        camera.look(at: lookBlend > 0.001 ? position + gaze * reach : current.target, from: position, relativeTo: nil)
        paint.set(view: camera.transformMatrix(relativeTo: nil).inverse, keepSharp: screenCorners)

        // The valley drifts very slightly, and leans against the pointer.
        let drift = sin(time * 0.07) * 0.004 - smoothedPointer.x * 0.003
        outside.orientation = simd_quatf(angle: -cityYaw + drift, axis: [0, 1, 0])
    }
}
