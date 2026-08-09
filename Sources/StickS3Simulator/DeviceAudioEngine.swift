import AVFoundation

@MainActor
final class DeviceAudioEngine {
    private struct Segment {
        let frequency: Double
        let durationMs: Int
    }

    private let sampleRate = 16_000.0
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var ready = false

    init() {
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                               sampleRate: sampleRate,
                               channels: 1,
                               interleaved: false)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            ready = true
        } catch {
            ready = false
        }
    }

    func stop() {
        player.stop()
    }

    // 与 Neon Brick 真机 GameAudio.cpp 使用相同的音符、时长和包络。
    func playBreakout(sound: Int32) {
        let segments: [Segment]
        switch sound {
        case 0: segments = [Segment(frequency: 720, durationMs: 28)]
        case 1: segments = [Segment(frequency: 1180, durationMs: 22)]
        case 2: segments = [Segment(frequency: 420, durationMs: 80),
                            Segment(frequency: 290, durationMs: 130)]
        case 3: segments = [Segment(frequency: 523, durationMs: 65),
                            Segment(frequency: 659, durationMs: 65),
                            Segment(frequency: 784, durationMs: 70),
                            Segment(frequency: 1047, durationMs: 150)]
        case 4: segments = [Segment(frequency: 440, durationMs: 100),
                            Segment(frequency: 370, durationMs: 100),
                            Segment(frequency: 294, durationMs: 160)]
        default: return
        }
        schedule(segments: segments, amplitude: 0.11, envelope: .breakout)
    }

    // 与 VibeStick-Codex 真机 vibe_audio.c 使用相同的 16 kHz 正弦波。
    func playCodex(status: String) {
        let segments: [Segment]
        let volumeScale: Double
        switch status {
        case "DONE":
            segments = [Segment(frequency: 880, durationMs: 80),
                        Segment(frequency: 0, durationMs: 40),
                        Segment(frequency: 1320, durationMs: 120)]
            volumeScale = 0.30
        case "WAIT":
            segments = [Segment(frequency: 660, durationMs: 90),
                        Segment(frequency: 0, durationMs: 45),
                        Segment(frequency: 440, durationMs: 110)]
            volumeScale = 0.30
        case "APPROVAL":
            segments = [Segment(frequency: 600, durationMs: 100),
                        Segment(frequency: 0, durationMs: 60),
                        Segment(frequency: 800, durationMs: 100)]
            volumeScale = 1.0
        case "ERROR":
            segments = [Segment(frequency: 240, durationMs: 100),
                        Segment(frequency: 0, durationMs: 60),
                        Segment(frequency: 240, durationMs: 100),
                        Segment(frequency: 0, durationMs: 60),
                        Segment(frequency: 240, durationMs: 100)]
            volumeScale = 1.0
        default: return
        }
        schedule(segments: segments + [Segment(frequency: 0, durationMs: 20)],
                 amplitude: 0.40 * volumeScale, envelope: .codex)
    }

    // 液态沙漏 hourglass_chime.c 的完成旋律。
    func playHourglassCompletion() {
        let notes = [(659.0, 115), (0, 28), (784, 135), (0, 28), (1047, 240), (0, 35)]
        schedule(segments: notes.map { Segment(frequency: $0.0, durationMs: $0.1) },
                 amplitude: 0.13, envelope: .liquid)
    }

    // Fruit Machine's private QEMU adapter reports the same fruit_sound_t
    // value used by the physical ES8311 path. Recreate those short cues on the
    // Mac so game timing never waits for unsupported virtual I2S hardware.
    func playFruit(sound: Int) {
        if sound == 0 {
            playFruitBellTick()
            return
        }
        let notes: [(Double, Int)]
        switch sound {
        case 1: notes = [(440, 55), (660, 70)]
        case 2: notes = [(523, 90), (659, 90), (784, 100), (1047, 180)]
        case 3: notes = [(2093, 42), (0, 18), (1047, 58), (1319, 90)]
        case 4: notes = [(2093, 42), (0, 16), (1047, 55), (1319, 55), (1661, 110)]
        case 5: notes = [(2349, 42), (0, 14), (1175, 48), (1568, 48), (1976, 55), (2637, 130)]
        case 6: notes = [(2637, 45), (0, 12), (1319, 42), (1661, 42),
                         (2093, 48), (2637, 60), (0, 22), (2093, 42),
                         (2637, 42), (3136, 170)]
        case 7: notes = [(2637, 28), (0, 12), (2093, 26), (0, 13),
                         (2349, 29), (0, 14), (1760, 27), (0, 15),
                         (1976, 32), (0, 18), (1319, 42)]
        case 8: notes = [(784, 70), (988, 70), (1175, 70), (1568, 190),
                         (1175, 80), (1568, 210)]
        case 9: notes = [(2093, 42), (0, 20), (392, 65), (330, 90)]
        case 10: notes = [(523, 65), (659, 65), (784, 65), (1047, 130),
                          (0, 45), (784, 55), (988, 55), (1175, 55),
                          (1568, 145), (0, 35), (1319, 70), (1568, 70),
                          (2093, 260)]
        case 11: notes = [(147, 60), (196, 60), (294, 60), (440, 70),
                          (659, 75), (988, 90), (1319, 220)]
        default: return
        }
        schedule(segments: notes.map { Segment(frequency: $0.0, durationMs: $0.1) },
                 amplitude: 0.12, envelope: .fruit)
    }

    private enum Envelope { case breakout, codex, liquid, fruit }

    private func schedule(segments: [Segment], amplitude: Double, envelope: Envelope) {
        guard ready else { return }
        let sampleCounts = segments.map { Int(sampleRate * Double($0.durationMs) / 1000.0) }
        let total = sampleCounts.reduce(0, +)
        guard total > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                             frameCapacity: AVAudioFrameCount(total)),
              let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(total)

        var offset = 0
        for (segment, count) in zip(segments, sampleCounts) {
            for index in 0..<count {
                guard segment.frequency > 0 else { samples[offset + index] = 0; continue }
                let edge: Double
                switch envelope {
                case .breakout:
                    let head = min(1.0, Double(index) / 50.0)
                    let tail = min(1.0, Double(count - index) / 100.0)
                    edge = head * tail
                case .codex:
                    let fade = Int(sampleRate * 0.008)
                    if index < fade { edge = Double(index) / Double(fade) }
                    else if count - index - 1 < fade {
                        edge = Double(max(0, count - index - 1)) / Double(fade)
                    } else { edge = 1.0 }
                case .fruit:
                    if index < 100 { edge = Double(index) / 100.0 }
                    else if count - index < 100 { edge = Double(count - index) / 100.0 }
                    else { edge = 1.0 }
                case .liquid:
                    let fade = Int(sampleRate * 0.012)
                    if index < fade { edge = Double(index) / Double(fade) }
                    else if count - index - 1 < fade {
                        edge = Double(max(0, count - index - 1)) / Double(fade)
                    } else { edge = 1.0 }
                }
                let phase = 2.0 * Double.pi * segment.frequency * Double(index) / sampleRate
                samples[offset + index] = Float(sin(phase) * edge * amplitude)
            }
            offset += count
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    // Exact three-harmonic bell used by fruit_audio.c on the physical StickS3.
    private func playFruitBellTick() {
        let count = Int(sampleRate * 0.024)
        guard ready,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        for sample in 0..<count {
            let position = Double(sample) / Double(count)
            let attack = sample < 32 ? Double(sample) / 32.0 : 1.0
            let envelope = attack * (1.0 - position) * (1.0 - position)
            let time = Double(sample) / sampleRate
            let tone = sin(2 * .pi * 1760 * time) * 0.10
                + sin(2 * .pi * 2640 * time) * 0.055
                + sin(2 * .pi * 3520 * time) * 0.03
            samples[sample] = Float(tone * envelope)
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}
