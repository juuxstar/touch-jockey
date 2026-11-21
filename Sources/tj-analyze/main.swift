import Foundation
import TJCore

// Usage: tj-analyze <audio file>...
// Prints the detected BPM and first downbeat for each file.
let paths = CommandLine.arguments.dropFirst()
if paths.isEmpty {
    print("usage: tj-analyze <audio file>...")
    exit(1)
}
for path in paths {
    let url = URL(fileURLWithPath: path)
    let start = Date()
    do {
        let a = try BeatAnalyzer.analyzeTrack(url: url), g = a.grid
        print(String(format: "%7.2f BPM  conf %.2f  key %@ (%@, %.2f)  first beat %6.3fs  %5.1fs  (%.1fs)  %@",
                     g.bpm, g.confidence, a.key?.camelot ?? "-", a.key?.name ?? "-", a.key?.confidence ?? 0, g.firstBeat, g.duration, Date().timeIntervalSince(start), url.lastPathComponent))
    } catch {
        print("failed: \(url.lastPathComponent): \(error)")
    }
}
