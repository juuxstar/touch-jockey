import AppKit
import Foundation
import TJCore

/// The library as the window sees it: scanned tracks, search, recents, and background BPM analysis.
final class LibraryModel: ObservableObject {
    @Published private(set) var tracks: [LibraryTrack] = []
    @Published private(set) var recents: [String] = []      // paths, most recent first
    @Published var query = ""
    @Published var showRecent = false
    @Published private(set) var root: URL
    @Published private(set) var scanning = false
    @Published private(set) var scanned = 0
    @Published private(set) var analysing = 0                // tracks still waiting for a BPM

    private let store = LibraryStore()
    private let storeQueue = DispatchQueue(label: "tj.library.store")
    private let analysisQueue = DispatchQueue(label: "tj.library.analysis", qos: .utility)
    private var generation = 0
    private static let rootKey = "libraryRoot", recentsKey = "recentTracks", maxRecents = 30

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: Self.rootKey), FileManager.default.fileExists(atPath: saved) {
            root = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music", isDirectory: true)
        }
        recents = defaults.stringArray(forKey: Self.recentsKey) ?? []
        tracks = store.tracks
        showRecent = !recents.isEmpty
        rescan()
    }

    // MARK: Folder

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = root
        panel.prompt = "Use as library"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        root = url
        UserDefaults.standard.set(url.path, forKey: Self.rootKey)
        rescan()
    }

    func rescan() {
        generation += 1
        let gen = generation, root = root
        scanning = true
        scanned = 0
        storeQueue.async {
            let found = self.store.scan(root: root) { n in DispatchQueue.main.async { self.scanned = n } }
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                self.tracks = found
                self.scanning = false
                self.analyseMissing(generation: gen)
            }
        }
    }

    // MARK: Recents and analysis results

    /// Called when a track is loaded into a deck.
    func noteLoaded(path: String, bpm: Double, confidence: Double) {
        recents.removeAll { $0 == path }
        recents.insert(path, at: 0)
        if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
        UserDefaults.standard.set(recents, forKey: Self.recentsKey)
        apply(bpm: bpm, confidence: confidence, path: path, save: true)
    }

    private func apply(bpm: Double, confidence: Double, path: String, save: Bool) {
        if let i = tracks.firstIndex(where: { $0.path == path }) { tracks[i].bpm = bpm; tracks[i].bpmConfidence = confidence }
        storeQueue.async {
            self.store.setBPM(bpm, confidence: confidence, for: path)
            if save { self.store.save() }
        }
    }

    /// Analyses every track that has no BPM or no cached analysis, one at a time at low priority,
    /// so the BPM column fills in and later loads are instant.
    private func analyseMissing(generation gen: Int) {
        let todo = tracks.filter { $0.bpm == nil || !AnalysisCache.has($0.url) }.map(\.path)
        analysing = todo.count
        guard !todo.isEmpty else { return }
        analysisQueue.async {
            for (n, path) in todo.enumerated() {
                if gen != self.generation { return }
                AnalysisPriority.waitForForeground()
                // Full analysis, cached on disk, so loading the track later is instant.
                let grid = try? AnalysisCache.analysis(for: URL(fileURLWithPath: path)).grid
                DispatchQueue.main.async {
                    guard gen == self.generation else { return }
                    if let grid { self.apply(bpm: grid.bpm, confidence: grid.confidence, path: path, save: n % 10 == 9 || n == todo.count - 1) }
                    self.analysing = todo.count - n - 1
                }
            }
        }
    }

    // MARK: What the list shows

    var visible: [LibraryTrack] {
        let base: [LibraryTrack]
        if showRecent {
            let byPath = Dictionary(tracks.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
            base = recents.compactMap { byPath[$0] }
        } else {
            base = tracks
        }
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return base }
        return base.filter { t in
            let hay = "\(t.title) \(t.artist) \(t.album)".lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }
}
