import Observation
import RealityKit
import SwiftUI

/// Frame rate and scene size, kept apart from the main view so two updates a
/// second do not re-evaluate the whole tab.
@MainActor
@Observable
final class DeskReadout {
    var text = ""
    private var elapsed: Float = 0
    private var frames = 0
    private var slowest: Float = 0

    /// Counts whole frames over a second. Averaging 1/dt instead reads high
    /// and jumps about, because short frames count for more than long ones.
    @available(macOS 15, *)
    func sample(_ scene: DenScene, dt: Float) {
        elapsed += dt
        frames += 1
        slowest = max(slowest, dt)
        guard elapsed >= 1 else { return }
        let fps = Int((Float(frames) / elapsed).rounded())
        let worst = Int((slowest * 1000).rounded())
        let triangles = scene.triangleCount.formatted(.number)
        text = "\(fps) fps · slowest frame \(worst) ms · \(triangles) triangles · \(scene.lightCount) lights"
        elapsed = 0
        frames = 0
        slowest = 0
    }
}

private struct DeskReadoutLabel: View {
    let readout: DeskReadout
    var body: some View {
        Text(readout.text)
            .font(TanqueDS.Font.mono(10.5))
            .foregroundStyle(DashboardDS.muted)
    }
}

/// Labs → Writing Desk: a 3D den where typing appears on a steampunk machine.
/// A spike, to find out whether writing this way is any good.
@available(macOS 15, *)
struct WritingDeskView: View {
    @State private var session = WritingDeskSession.shared
    @State private var den: DenScene?
    @State private var updates: EventSubscription?
    @State private var sounds = DeskSounds()
    @State private var readout = DeskReadout()
    @State private var lookAround = false
    @State private var muted = false
    @State private var missingBackdrops: [String] = []
    @State private var confirmNewSheet = false
    @FocusState private var deskFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            statusLine
            desk
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 24)
        .confirmationDialog("Start a new sheet?", isPresented: $confirmNewSheet, titleVisibility: .visible) {
            Button("Save, then new sheet") {
                if session.save() { startNewSheet() }
                deskFocused = true
            }
            Button("Discard this sheet", role: .destructive) {
                startNewSheet()
                deskFocused = true
            }
            Button("Cancel", role: .cancel) { deskFocused = true }
        } message: {
            Text("This sheet has writing that isn't saved.")
        }
        .onDisappear {
            updates?.cancel()
            updates = nil
            sounds.stop()
        }
    }

    // MARK: - Chrome

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("New sheet") {
                if session.hasUnsavedText { confirmNewSheet = true } else { startNewSheet() }
                deskFocused = true
            }
            .buttonStyle(DashboardGhostButtonStyle()).fixedSize()

            Button("Save") {
                session.save()
                deskFocused = true
            }
            .buttonStyle(DashboardPrimaryButtonStyle())

            Button("Reveal in Finder") {
                session.revealInFinder()
                deskFocused = true
            }
            .buttonStyle(DashboardGhostButtonStyle()).fixedSize()

            Spacer(minLength: 16)

            Button("Backdrops folder") {
                WritingDeskSession.reveal(folder: BackdropLoader.backdropsFolder)
                deskFocused = true
            }
            .buttonStyle(DashboardGhostButtonStyle()).fixedSize()

            Button("Reload backdrops") {
                den?.loadBackdrops()
                missingBackdrops = den?.missingBackdrops ?? []
                deskFocused = true
            }
            .buttonStyle(DashboardGhostButtonStyle()).fixedSize()

            Button(lookAround ? "Look around: on" : "Look around: off") {
                lookAround.toggle()
                den?.lookAround = lookAround
                deskFocused = true
            }
            .buttonStyle(DashboardGhostButtonStyle()).fixedSize()

            Button(sounds.unavailable ? "Sound: unavailable" : (muted ? "Sound: off" : "Sound: on")) {
                muted.toggle()
                sounds.muted = muted
                deskFocused = true
            }
            .buttonStyle(DashboardGhostButtonStyle()).fixedSize()
        }
    }

    private var statusLine: some View {
        HStack(spacing: 14) {
            Text(statusText)
                .font(TanqueDS.Font.mono(10.5))
                .foregroundStyle(DashboardDS.muted2)
                .lineLimit(1)
            Spacer(minLength: 8)
            DeskReadoutLabel(readout: readout)
        }
    }

    private var statusText: String {
        var parts: [String] = []
        if !session.status.isEmpty { parts.append(session.status) }
        if !missingBackdrops.isEmpty {
            parts.append("Using a plain gradient for \(missingBackdrops.joined(separator: " and "))")
        }
        if den?.computer.screenFailed == true { parts.append("The screen could not be drawn") }
        if parts.isEmpty {
            parts.append(deskFocused ? "Type to write. Return throws a breaker." : "Click the desk to type.")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - The 3D view

    private var desk: some View {
        GeometryReader { geo in
            RealityView { content in
                let scene = DenScene()
                scene.computer.setText(session.text)
                scene.lookAround = lookAround
                scene.computer.onGearTick = { [sounds] in sounds.gearTick() }
                content.add(scene.root)
                updates = content.subscribe(to: SceneEvents.Update.self) { [readout] event in
                    MainActor.assumeIsolated {
                        let dt = Float(event.deltaTime)
                        scene.update(dt: dt)
                        readout.sample(scene, dt: dt)
                    }
                }
                den = scene
                missingBackdrops = scene.missingBackdrops
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p):
                    guard geo.size.width > 0, geo.size.height > 0 else { return }
                    den?.pointer = [Float(p.x / geo.size.width) * 2 - 1, 1 - Float(p.y / geo.size.height) * 2]
                case .ended:
                    den?.pointer = .zero
                }
            }
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DashboardDS.border2, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .focusable()
        .focusEffectDisabled()
        .focused($deskFocused)
        .onKeyPress(phases: [.down, .repeat]) { handle($0) }
        .simultaneousGesture(TapGesture().onEnded { deskFocused = true })
        .onAppear { deskFocused = true }
    }

    // MARK: - Typing

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.command) || press.modifiers.contains(.control) { return .ignored }

        switch press.key {
        case .return:
            session.newline()
            den?.computer.flipBreakers()
            sounds.breaker()
        case .delete:
            session.deleteBackward()
            den?.computer.keystroke(nil)
            sounds.key()
        case .tab:
            session.append("    ")
            den?.computer.keystroke(" ")
            sounds.key()
        default:
            let typed = String(press.characters.filter(Self.isPrintable))
            guard !typed.isEmpty else { return .ignored }
            session.append(typed)
            den?.computer.keystroke(typed.last)
            sounds.key()
        }
        session.status = ""
        den?.computer.setText(session.text)
        return .handled
    }

    nonisolated private static func isPrintable(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            // Arrow and function keys arrive as private-use scalars.
            scalar.value >= 0x20 && scalar.value != 0x7F && !(0xF700...0xF8FF).contains(scalar.value)
        }
    }

    private func startNewSheet() {
        session.newSheet()
        den?.computer.setText("")
        den?.computer.flipBreakers(all: true)
        sounds.breaker()
    }
}
