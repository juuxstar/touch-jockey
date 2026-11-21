import AVFoundation
import Accelerate

/// Tempo and beat positions for one track.
public struct BeatGrid: Codable, Equatable {
    /// Beats per minute at the track's natural speed.
    public var bpm: Double
    /// Time in seconds of the first downbeat (bar 1, beat 1).
    public var firstBeat: Double
    /// Track length in seconds.
    public var duration: Double

    public var secondsPerBeat: Double { 60 / bpm }

    /// Beat index (fractional) at a position in the track. Beat 0 is the first downbeat.
    public func beat(atSeconds s: Double) -> Double { (s - firstBeat) / secondsPerBeat }
    /// Position in seconds of a beat index.
    public func seconds(atBeat b: Double) -> Double { firstBeat + b * secondsPerBeat }
}

/// Finds tempo and beat phase with an onset envelope and a comb search.
///
/// Built for steady four-on-the-floor dance music: it searches a fixed BPM range
/// (default 100 to 150) so it never picks half or double tempo, and assumes the
/// first beat after the music starts is a downbeat, which holds for most DJ edits.
public enum BeatAnalyzer {
    public enum Failure: Error { case unreadable, tooShort }

    public static func analyze(url: URL, minBPM: Double = 100, maxBPM: Double = 150) throws -> BeatGrid {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { throw Failure.unreadable }
        try file.read(into: buffer)
        let n = Int(buffer.frameLength)
        guard n > Int(sampleRate * 10), let channels = buffer.floatChannelData else { throw Failure.tooShort }

        // Mono mix.
        var mono = [Float](repeating: 0, count: n)
        for c in 0..<Int(format.channelCount) {
            vDSP_vadd(mono, 1, channels[c], 1, &mono, 1, vDSP_Length(n))
        }

        let (onset, lowEnergy, envRate) = onsetEnvelope(mono, sampleRate: sampleRate)
        let (bpm, phase) = combSearch(onset, envRate: envRate, minBPM: minBPM, maxBPM: maxBPM)

        // First downbeat: the first beat at or after the point where the music starts.
        let period = 60 / bpm * envRate
        let sorted = lowEnergy.sorted()
        let threshold = sorted[sorted.count / 2] * 0.15
        let musicStart = Double(lowEnergy.firstIndex(where: { $0 > threshold }) ?? 0)
        var beatFrame = phase
        while beatFrame + period * 0.5 < musicStart { beatFrame += period }

        return BeatGrid(bpm: bpm, firstBeat: beatFrame / envRate, duration: Double(n) / sampleRate)
    }

    /// Positive changes in log energy, weighted towards the kick drum, at about 200 frames a second.
    static func onsetEnvelope(_ x: [Float], sampleRate: Double) -> (onset: [Float], low: [Float], rate: Double) {
        let hop = max(1, Int(sampleRate / 200))
        let frames = x.count / hop
        let alpha = Float(1 - exp(-2 * Double.pi * 150 / sampleRate))   // one-pole low-pass at 150 Hz
        var lp: Float = 0
        var low = [Float](repeating: 0, count: frames)
        var full = [Float](repeating: 0, count: frames)
        for f in 0..<frames {
            var el: Float = 0, ef: Float = 0
            let base = f * hop
            for i in base..<(base + hop) {
                let s = x[i]
                lp += alpha * (s - lp)
                el += lp * lp
                ef += s * s
            }
            low[f] = el
            full[f] = ef
        }
        var onset = [Float](repeating: 0, count: frames)
        for f in 1..<frames {
            let dl = log(low[f] + 1e-6) - log(low[f - 1] + 1e-6)
            let df = log(full[f] + 1e-6) - log(full[f - 1] + 1e-6)
            onset[f] = max(0, dl) + 0.5 * max(0, df)
        }
        return (onset, low, sampleRate / Double(hop))
    }

    /// Score = onset strength summed at every predicted beat; best (bpm, phase in frames) wins.
    static func combSearch(_ onset: [Float], envRate: Double, minBPM: Double, maxBPM: Double) -> (Double, Double) {
        func score(bpm: Double, phase: Double) -> Float {
            let period = 60 / bpm * envRate
            var t = phase, sum: Float = 0
            let last = Double(onset.count - 2)
            while t < last {
                let i = Int(t), frac = Float(t - Double(i))
                sum += onset[i] * (1 - frac) + onset[i + 1] * frac
                t += period
            }
            return sum
        }
        func best(bpms: StrideThrough<Double>, phaseStep: Double, around: (Double, Double)? = nil) -> (Double, Double, Float) {
            var top = (0.0, 0.0, -Float.infinity)
            for b in bpms {
                let period = 60 / b * envRate
                var p = 0.0
                if let (_, ph) = around { p = max(0, ph - 2) }
                let end = around == nil ? period : min(period, (around?.1 ?? 0) + 2)
                while p < end {
                    let s = score(bpm: b, phase: p)
                    if s > top.2 { top = (b, p, s) }
                    p += phaseStep
                }
            }
            return top
        }
        let coarse = best(bpms: stride(from: minBPM, through: maxBPM, by: 0.1), phaseStep: 1)
        let fine = best(bpms: stride(from: coarse.0 - 0.12, through: coarse.0 + 0.12, by: 0.005),
                        phaseStep: 0.25, around: (coarse.0, coarse.1))
        return (fine.0, fine.1)
    }
}
