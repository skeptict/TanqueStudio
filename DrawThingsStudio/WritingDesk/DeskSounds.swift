import AVFoundation

/// The machine's noises: a key click, a breaker clunk and soft gear ticking.
///
/// TODO: these are generated tones standing in for real samples (a typewriter
/// key, a relay or knife switch, a clock escapement). Swap in recordings.
@MainActor
final class DeskSounds {
    var muted = false
    /// True when the audio engine would not start, so the sound button can say so.
    private(set) var unavailable = false

    private let engine = AVAudioEngine()
    private let keyPlayer = AVAudioPlayerNode()
    private let tickPlayer = AVAudioPlayerNode()
    private let clunkPlayer = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var click: AVAudioPCMBuffer?
    private var tick: AVAudioPCMBuffer?
    private var clunk: AVAudioPCMBuffer?
    private var started = false

    init() {
        var noise = SeededRandom(seed: 42)
        click = buffer(seconds: 0.035) { t in
            let hiss = (noise.unit() * 2 - 1) * exp(-t / 0.004) * 0.45
            let ping = sin(2 * .pi * 1_900 * t) * exp(-t / 0.007) * 0.25
            return hiss + ping
        }
        tick = buffer(seconds: 0.014) { t in
            sin(2 * .pi * 3_100 * t) * exp(-t / 0.0018) * 0.10 + (noise.unit() * 2 - 1) * exp(-t / 0.001) * 0.05
        }
        clunk = buffer(seconds: 0.22) { t in
            let thump = sin(2 * .pi * 92 * t) * exp(-t / 0.05) * 0.7
            let snap = (noise.unit() * 2 - 1) * exp(-t / 0.009) * 0.4
            return thump + snap
        }
    }

    private func buffer(seconds: Float, _ sample: (Float) -> Float) -> AVAudioPCMBuffer? {
        guard let format else { return nil }
        let frames = AVAudioFrameCount(seconds * Float(format.sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            channel[i] = sample(Float(i) / Float(format.sampleRate))
        }
        return buffer
    }

    private func start() -> Bool {
        if started { return true }
        guard !unavailable, let format else { return false }
        for player in [keyPlayer, tickPlayer, clunkPlayer] {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        do {
            try engine.start()
            started = true
            return true
        } catch {
            unavailable = true
            return false
        }
    }

    private func play(_ buffer: AVAudioPCMBuffer?, on player: AVAudioPlayerNode) {
        guard !muted, let buffer, start() else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    func key() { play(click, on: keyPlayer) }
    func gearTick() { play(tick, on: tickPlayer) }
    func breaker() { play(clunk, on: clunkPlayer) }

    func stop() {
        guard started else { return }
        engine.stop()
        started = false
        for player in [keyPlayer, tickPlayer, clunkPlayer] { engine.detach(player) }
    }
}
