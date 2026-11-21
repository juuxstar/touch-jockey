import Accelerate
import Foundation

/// Musical key detection and Camelot-wheel helpers.
///
/// Detection: the track is downsampled to about 11 kHz, cut into 4096-sample frames,
/// and each frame's spectrum (55 Hz–2 kHz) is folded into a 12-bin chroma (energy per
/// pitch class). The track's average chroma is correlated with the Krumhansl–Kessler
/// major and minor key profiles in all 12 transpositions; the best match wins.
/// It's a classic, simple method: good on clearly tonal tracks, unsure on drum-heavy ones,
/// so it reports a confidence too.
public enum MusicalKey {
    /// Camelot codes for major keys, indexed by pitch class (C = 0 … B = 11).
    static let camelotMajor = ["8B", "3B", "10B", "5B", "12B", "7B", "2B", "9B", "4B", "11B", "6B", "1B"]
    /// Camelot codes for minor keys, indexed by pitch class (C minor = 0 … B minor = 11).
    static let camelotMinor = ["5A", "12A", "7A", "2A", "9A", "4A", "11A", "6A", "1A", "8A", "3A", "10A"]
    static let names = ["C", "D♭", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

    static let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    static let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    public struct Result: Codable, Equatable {
        /// Camelot code, for example "8A" (A minor) or "8B" (C major).
        public var camelot: String
        /// Readable name, for example "A minor".
        public var name: String
        /// 0…1: how clearly the best key beat the runner-up.
        public var confidence: Double
    }

    /// Detects the key of a mono signal.
    public static func detect(_ mono: [Float], sampleRate: Double) -> Result? {
        // Downsample by averaging to about 11 kHz (a crude low-pass, fine for chroma).
        let factor = max(1, Int(sampleRate / 11025))
        let sr = sampleRate / Double(factor)
        let n = mono.count / factor
        guard n > 8192 else { return nil }
        var x = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var s: Float = 0
            for j in 0..<factor { s += mono[i * factor + j] }
            x[i] = s / Float(factor)
        }

        let log2n = vDSP_Length(12), size = 1 << 12, half = size / 2
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }
        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))

        // Pitch class for each FFT bin in range, precomputed.
        var binClass = [Int](repeating: -1, count: half)
        for k in 1..<half {
            let f = Double(k) * sr / Double(size)
            guard f >= 55, f <= 2000 else { continue }
            let midi = 69 + 12 * log2(f / 440)
            binClass[k] = ((Int(midi.rounded()) % 12) + 12) % 12
        }

        var chroma = [Float](repeating: 0, count: 12)
        var frame = [Float](repeating: 0, count: size)
        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)
        var start = 0
        while start + size <= n {
            vDSP_vmul(Array(x[start..<(start + size)]), 1, window, 1, &frame, 1, vDSP_Length(size))
            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBufferPointer { fp in
                        fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(half))
                }
            }
            // Log-compress so a loud bass note doesn't swamp everything else.
            var frameChroma = [Float](repeating: 0, count: 12)
            for k in 1..<half where binClass[k] >= 0 { frameChroma[binClass[k]] += log1p(mags[k]) }
            let total = frameChroma.reduce(0, +)
            if total > 0 { for c in 0..<12 { chroma[c] += frameChroma[c] / total } }
            start += size
        }

        func correlation(_ a: [Float], _ b: [Float]) -> Float {
            let ma = a.reduce(0, +) / 12, mb = b.reduce(0, +) / 12
            var num: Float = 0, da: Float = 0, db: Float = 0
            for i in 0..<12 { let u = a[i] - ma, v = b[i] - mb; num += u * v; da += u * u; db += v * v }
            return da > 0 && db > 0 ? num / sqrt(da * db) : 0
        }
        var scores: [(Float, Bool, Int)] = []   // (score, isMinor, tonic)
        for tonic in 0..<12 {
            let rotated = (0..<12).map { chroma[(tonic + $0) % 12] }
            scores.append((correlation(rotated, majorProfile), false, tonic))
            scores.append((correlation(rotated, minorProfile), true, tonic))
        }
        scores.sort { $0.0 > $1.0 }
        var best = scores[0]
        // A major key and its relative minor share every note, so the profiles often nearly tie.
        // Dance music is mostly in minor keys: prefer the relative minor when it's close.
        if !best.1, let rel = scores.first(where: { $0.1 && $0.2 == (best.2 + 9) % 12 }), best.0 - rel.0 < 0.06 {
            best = rel
        }
        let second = scores.first { !($0.1 == best.1 && $0.2 == best.2) } ?? scores[1]
        let confidence = Double(max(0, min(1, (best.0 - second.0) * 8)))
        let camelot = best.1 ? camelotMinor[best.2] : camelotMajor[best.2]
        return Result(camelot: camelot, name: "\(names[best.2]) \(best.1 ? "minor" : "major")", confidence: confidence)
    }

    // MARK: Camelot helpers

    /// Splits "8A" into (8, "A").
    static func parse(_ code: String) -> (Int, Character)? {
        guard let letter = code.last, letter == "A" || letter == "B", let num = Int(code.dropLast()), (1...12).contains(num) else { return nil }
        return (num, letter)
    }

    /// 0 = same key or a Camelot neighbour (±1, or the relative major/minor): blends cleanly.
    /// 1 = two steps away: usable with care. 2 = likely clash. Unknown keys count as a clash.
    public static func compatibility(_ a: String, _ b: String) -> Int {
        guard let (na, la) = parse(a), let (nb, lb) = parse(b) else { return 2 }
        let d = min((na - nb + 12) % 12, (nb - na + 12) % 12)
        if la == lb { return d <= 1 ? 0 : d == 2 ? 1 : 2 }
        return d == 0 ? 0 : d == 1 ? 1 : 2
    }

    /// Sort order around the wheel: 1A, 1B, 2A, 2B … unknown keys last.
    public static func sortIndex(_ code: String?) -> Int {
        guard let code, let (n, l) = parse(code) else { return 1000 }
        return n * 2 + (l == "B" ? 1 : 0)
    }
}
