import CryptoKit
import Foundation

/// Analysis results (beat grid + waveform) saved per file, so a track that has been
/// analysed once loads instantly. Entries are keyed by path, size and modification
/// date, so an edited file is analysed again.
///
/// Stored in `~/Library/Application Support/TouchJockey/analysis/`, about 150 KB per track
/// (waveform levels quantised to one byte at 200 values a second).
public enum AnalysisCache {
    private static let version = 4   // 2: averaged comb score, 70-180 BPM, confidence. 3: musical key. 4: mid and high waveform bands
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TouchJockey/analysis", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private struct Entry: Codable {
        var version: Int
        var bpm: Double, firstBeat: Double, duration: Double
        var confidence: Double?
        var key: MusicalKey.Result?
        var rate: Double
        var full: Data, low: Data
        var mid: Data?, high: Data?
    }

    private static func file(for url: URL) -> URL? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = a[.size] as? Int, let mod = a[.modificationDate] as? Date else { return nil }
        let key = "\(url.path)|\(size)|\(mod.timeIntervalSince1970)|v\(version)"
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(String(hash.prefix(32)) + ".json")
    }

    public static func load(_ url: URL) -> TrackAnalysis? {
        guard let f = file(for: url), let data = try? Data(contentsOf: f),
              let e = try? JSONDecoder().decode(Entry.self, from: data), e.version == version else { return nil }
        let unq: (Data) -> [Float] = { d in d.map { Float($0) / 255 } }
        return TrackAnalysis(grid: BeatGrid(bpm: e.bpm, firstBeat: e.firstBeat, duration: e.duration, confidence: e.confidence ?? 1),
                             waveform: Waveform(levelsFull: unq(e.full), low: unq(e.low), mid: e.mid.map(unq) ?? [], high: e.high.map(unq) ?? [], rate: e.rate), key: e.key)
    }

    public static func store(_ a: TrackAnalysis, for url: URL) {
        guard let f = file(for: url) else { return }
        let q: ([Float]) -> Data = { Data($0.map { UInt8(max(0, min(255, ($0 * 255).rounded()))) }) }
        let e = Entry(version: version, bpm: a.grid.bpm, firstBeat: a.grid.firstBeat, duration: a.grid.duration,
                      confidence: a.grid.confidence, key: a.key,
                      rate: a.waveform.rate, full: q(a.waveform.full), low: q(a.waveform.low),
                      mid: q(a.waveform.mid), high: q(a.waveform.high))
        if let data = try? JSONEncoder().encode(e) { try? data.write(to: f, options: .atomic) }
    }

    /// Cached analysis if there is one, otherwise analyse now and cache the result.
    public static func analysis(for url: URL) throws -> TrackAnalysis {
        if let cached = load(url) { return cached }
        let fresh = try BeatAnalyzer.analyzeTrack(url: url)
        store(fresh, for: url)
        return fresh
    }

    public static func has(_ url: URL) -> Bool {
        guard let f = file(for: url) else { return false }
        return FileManager.default.fileExists(atPath: f.path)
    }

    /// Deletes every cached analysis, so each track is analysed again from scratch.
    public static func clearAll() {
        let fm = FileManager.default
        for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "json" {
            try? fm.removeItem(at: f)
        }
    }
}

/// Lets background analysis step aside while a deck is loading.
public enum AnalysisPriority {
    private static let lock = NSLock()
    private static var foreground = 0

    public static func beginForeground() { lock.lock(); foreground += 1; lock.unlock() }
    public static func endForeground() { lock.lock(); foreground = max(0, foreground - 1); lock.unlock() }

    /// Background work calls this between tracks; it waits while any deck load is running.
    public static func waitForForeground() {
        while true {
            lock.lock(); let busy = foreground > 0; lock.unlock()
            if !busy { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}
