import AVFoundation

/// Synthesizes all Thread game sounds via AVAudioEngine.
/// No audio assets required — all tones are generated from sine waves.
/// Owned as a shared singleton because the engine must persist across
/// the game session to avoid teardown/restart latency on every sound.
final class SoundEngine {

    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()

    private init() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode,
                       format: engine.mainMixerNode.outputFormat(forBus: 0))
        startEngine()
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }

    // MARK: - Public events

    func playTap()     { play(notes: [(800, 0.03)], volume: 0.18) }
    func playSuccess() { play(notes: [(660, 0.06), (880, 0.07)], volume: 0.25) }
    func playHit()     { play(notes: [(180, 0.12)], volume: 0.35, waveform: .square) }
    func playGameOver(){ play(notes: [(330, 0.09), (220, 0.09), (165, 0.14)], volume: 0.30) }

    // MARK: - Synthesis

    enum Waveform { case sine, square }

    /// Plays a sequence of (frequency, duration) notes back to back.
    private func play(notes: [(Float, Double)], volume: Float, waveform: Waveform = .sine) {
        let sampleRate: Double = 44100
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }

        // Restart engine if it stopped (e.g. audio session interrupted).
        if !engine.isRunning { startEngine() }
        guard engine.isRunning else { return }

        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: mixer, format: format)
        playerNode.play()

        var scheduleOffset = AVAudioFramePosition(0)

        for (freq, dur) in notes {
            let frameCount = AVAudioFrameCount(sampleRate * dur)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
                  let data = buffer.floatChannelData?.pointee else { continue }
            buffer.frameLength = frameCount
            for i in 0..<Int(frameCount) {
                let t = Float(i) / Float(sampleRate)
                let phase = 2 * Float.pi * freq * t
                let raw: Float = waveform == .sine ? sin(phase) : (sin(phase) >= 0 ? 1 : -1)
                // Simple ADSR envelope to avoid clicks
                let attack  = Float(0.008)
                let release = Float(0.015)
                let totalDur = Float(dur)
                let env: Float
                if t < attack { env = t / attack }
                else if t > totalDur - release { env = (totalDur - t) / release }
                else { env = 1.0 }
                data[i] = raw * volume * max(0, env)
            }
            let when = AVAudioTime(sampleTime: scheduleOffset,
                                   atRate: sampleRate)
            playerNode.scheduleBuffer(buffer, at: when, completionHandler: nil)
            scheduleOffset += AVAudioFramePosition(frameCount)
        }

        // Detach the player after all notes finish
        let totalFrames = notes.reduce(0.0) { $0 + $1.1 }
        let detachDelay = totalFrames + 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + detachDelay) { [weak self] in
            self?.engine.detach(playerNode)
        }
    }
}
