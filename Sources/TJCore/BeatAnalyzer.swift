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
    /// How clearly the beat stood out, 0 (guess) to 1 (clear). Below about 0.25 the tempo may be wrong.
    public var confidence: Double = 1

    public init(bpm: Double, firstBeat: Double, duration: Double, confidence: Double = 1) {
        self.bpm = bpm; self.firstBeat = firstBeat; self.duration = duration; self.confidence = confidence
    }

    public var secondsPerBeat: Double { 60 / bpm }

    /// Beat index (fractional) at a position in the track. Beat 0 is the first downbeat.
    public func beat(atSeconds s: Double) -> Double { (s - firstBeat) / secondsPerBeat }
    /// Position in seconds of a beat index.
    public func seconds(atBeat b: Double) -> Double { firstBeat + b * secondsPerBeat }
}

/// Finds tempo and beat phase with an onset envelope and a comb search.
///
/// Built for steady four-on-the-floor dance music: it searches 70 to 180 BPM, resolves
/// half/double-time with a preference for dance tempos, and assumes the first beat
/// after the music starts is a downbeat, which holds for most DJ edits.
public enum BeatAnalyzer {
    public enum Failure: Error { case unreadable, tooShort }

    public static func analyze(url: URL, minBPM: Double = 70, maxBPM: Double = 180) throws -> BeatGrid {
        try analyzeTrack(url: url, minBPM: minBPM, maxBPM: maxBPM).grid
    }

    /// Beat grid plus a waveform for drawing, from one read of the file.
    public static func analyzeTrack(url: URL, minBPM: Double = 70, maxBPM: Double = 180) throws -> TrackAnalysis {
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

        let (onset, lowEnergy, fullEnergy, envRate, midEnergy, highEnergy) = onsetEnvelope(mono, sampleRate: sampleRate)
        let (bpm, phase, confidence) = combSearch(onset, envRate: envRate, minBPM: minBPM, maxBPM: maxBPM)

        // First downbeat: the first beat at or after the point where the music starts.
        let period = 60 / bpm * envRate
        let sorted = lowEnergy.sorted()
        let threshold = sorted[sorted.count / 2] * 0.15
        let musicStart = Double(lowEnergy.firstIndex(where: { $0 > threshold }) ?? 0)
        var beatFrame = phase
        while beatFrame + period * 0.5 < musicStart { beatFrame += period }

        let grid = BeatGrid(bpm: bpm, firstBeat: beatFrame / envRate, duration: Double(n) / sampleRate, confidence: confidence)
        return TrackAnalysis(grid: grid, waveform: Waveform(full: fullEnergy, low: lowEnergy, mid: midEnergy, high: highEnergy, rate: envRate),
                             key: MusicalKey.detect(mono, sampleRate: sampleRate))
    }

    /// Positive changes in log energy, weighted towards the kick drum, at about 200 frames a second.
    /// Also returns mid (150 Hz–2.5 kHz) and high (above 2.5 kHz) energies, for the waveform's colours.
    static func onsetEnvelope(_ x: [Float], sampleRate: Double)
        -> (onset: [Float], low: [Float], full: [Float], rate: Double, mid: [Float], high: [Float]) {
        let hop = max(1, Int(sampleRate / 200))
        let frames = x.count / hop
        let alpha = Float(1 - exp(-2 * Double.pi * 150 / sampleRate))   // one-pole low-pass at 150 Hz
        let alphaHi = Float(1 - exp(-2 * Double.pi * 2500 / sampleRate)) // and at 2.5 kHz
        var lp: Float = 0, lp2: Float = 0
        var low = [Float](repeating: 0, count: frames)
        var full = [Float](repeating: 0, count: frames)
        var mid = [Float](repeating: 0, count: frames)
        var high = [Float](repeating: 0, count: frames)
        for f in 0..<frames {
            var el: Float = 0, ef: Float = 0, em: Float = 0, eh: Float = 0
            let base = f * hop
            for i in base..<(base + hop) {
                let s = x[i]
                lp += alpha * (s - lp)
                lp2 += alphaHi * (s - lp2)
                el += lp * lp
                ef += s * s
                let m = lp2 - lp, h = s - lp2
                em += m * m
                eh += h * h
            }
            low[f] = el
            full[f] = ef
            mid[f] = em
            high[f] = eh
        }
        var onset = [Float](repeating: 0, count: frames)
        for f in 1..<frames {
            let dl = log(low[f] + 1e-6) - log(low[f - 1] + 1e-6)
            let df = log(full[f] + 1e-6) - log(full[f - 1] + 1e-6)
            onset[f] = max(0, dl) + 0.5 * max(0, df)
        }
        return (onset, low, full, sampleRate / Double(hop), mid, high)
    }

    /// Score = onset strength summed at every predicted beat; best (bpm, phase in frames) wins.
    /// Finds the tempo and beat phase that best fit the onsets.
    ///
    /// Each candidate (bpm, phase) is scored by the *average* onset strength at its
    /// predicted beats. (A sum would favour fast tempos, which predict more beats.)
    /// Half and double tempo hit the same kicks and score alike, so a gentle preference
    /// for dance tempos, centred on 125 BPM, picks between them.
    /// Returns (bpm, phase in frames, confidence 0...1).
    static func combSearch(_ onset: [Float], envRate: Double, minBPM: Double, maxBPM: Double) -> (Double, Double, Double) {
        let n = onset.count
        let overall = max(1e-6, onset.reduce(0, +) / Float(n))
        func meanAtBeats(bpm: Double, phase: Double) -> Float {
            let period = 60 / bpm * envRate
            var t = phase, sum: Float = 0, count = 0
            let last = Double(n - 2)
            while t < last {
                let i = Int(t), frac = Float(t - Double(i))
                sum += onset[i] * (1 - frac) + onset[i + 1] * frac
                count += 1
                t += period
            }
            return count > 0 ? sum / Float(count) : 0
        }
        func prior(_ bpm: Double) -> Double {
            let octaves = log2(bpm / 125)
            return exp(-0.5 * (octaves / 0.45) * (octaves / 0.45))
        }
        func best(_ bpms: [Double], phaseStep: Double, phaseAround: Double? = nil) -> (bpm: Double, phase: Double, mean: Float, score: Double) {
            var top = (bpm: 0.0, phase: 0.0, mean: Float(0), score: -Double.infinity)
            for b in bpms {
                let period = 60 / b * envRate
                var p = phaseAround.map { max(0, $0 - 3) } ?? 0
                let end = phaseAround.map { min(period, $0 + 3) } ?? period
                let w = prior(b)
                while p < end {
                    let m = meanAtBeats(bpm: b, phase: p)
                    let sc = Double(m / overall) * w
                    if sc > top.score { top = (b, p, m, sc) }
                    p += phaseStep
                }
            }
            return top
        }
        let coarseBPMs = Array(stride(from: minBPM, through: maxBPM, by: 0.25))
        let coarse = best(coarseBPMs, phaseStep: 2)
        // The coarse phase is only meaningful at the coarse tempo (a quarter BPM off drifts by
        // most of a beat over a track), so the fine pass searches every phase again.
        let fineBPMs = Array(stride(from: coarse.bpm - 0.3, through: coarse.bpm + 0.3, by: 0.01))
        let mid = best(fineBPMs, phaseStep: 0.5)
        let fine = best(Array(stride(from: mid.bpm - 0.01, through: mid.bpm + 0.01, by: 0.002)),
                        phaseStep: 0.1, phaseAround: mid.phase)
        // Confidence: how much stronger the onsets are on the beats than on average (1x = none, 4x+ = clear).
        let contrast = Double(fine.mean / overall)
        let confidence = max(0, min(1, (contrast - 1) / 3))
        return (fine.bpm, fine.phase, confidence)
    }
}

/// Result of analysing a track.
public struct TrackAnalysis {
    public var grid: BeatGrid
    public var waveform: Waveform
    /// Detected musical key (nil if detection failed).
    public var key: MusicalKey.Result?
}

/// Loudness over time for drawing: whole-signal and bass levels, each 0...1, at `rate` values a second.
public struct Waveform {
    public let rate: Double
    public let full: [Float]
    public let low: [Float]
    /// Mid (150 Hz–2.5 kHz) and high (above 2.5 kHz) levels, for frequency colours.
    public let mid: [Float]
    public let high: [Float]

    /// Builds from per-frame energies; levels are RMS scaled so the loudest 0.5% reach 1.
    /// Each band is scaled on its own, so a band's colour shows when it's strong for that band.
    init(full fullEnergy: [Float], low lowEnergy: [Float], mid midEnergy: [Float], high highEnergy: [Float], rate: Double) {
        func levels(_ e: [Float]) -> [Float] {
            let rms = e.map { sqrt($0) }
            let sorted = rms.sorted()
            let ref = max(sorted[Int(Double(sorted.count - 1) * 0.995)], 1e-6)
            return rms.map { min(1, $0 / ref) }
        }
        self.rate = rate
        full = levels(fullEnergy)
        low = levels(lowEnergy)
        mid = levels(midEnergy)
        high = levels(highEnergy)
    }

    /// Builds from levels that are already 0...1 (used by the analysis cache).
    init(levelsFull: [Float], low: [Float], mid: [Float], high: [Float], rate: Double) {
        self.rate = rate
        full = levelsFull
        self.low = low
        self.mid = mid
        self.high = high
    }

    /// Peak levels over a span of seconds (used per drawn column).
    public func level(from a: Double, to b: Double) -> (full: Float, low: Float) {
        let b = bands(from: a, to: b)
        return (b.full, b.low)
    }

    /// Peak level of every band over a span of seconds.
    public func bands(from a: Double, to b: Double) -> (full: Float, low: Float, mid: Float, high: Float) {
        let i0 = max(0, Int(a * rate)), i1 = min(full.count, max(i0 + 1, Int(b * rate)))
        guard i0 < i1 else { return (0, 0, 0, 0) }
        var f: Float = 0, l: Float = 0, m: Float = 0, h: Float = 0
        let hasBands = mid.count == full.count && high.count == full.count
        for i in i0..<i1 {
            f = max(f, full[i]); l = max(l, low[i])
            if hasBands { m = max(m, mid[i]); h = max(h, high[i]) }
        }
        return (f, l, m, h)
    }
}
