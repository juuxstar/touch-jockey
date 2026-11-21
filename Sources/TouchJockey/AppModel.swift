import AppKit
import Foundation
import TJCore

/// Connects the mix engine to the window and to the touch surfaces.
final class AppModel: ObservableObject {
    struct DeckInfo: Equatable {
        var name: String
        var title = ""
        var artist = ""
        var bpm: Double?
        var playing = false
        var loading = false
        /// The tempo detection wasn't confident; sync may be off.
        var bpmUnsure = false
        var paused = false
        var atCue = true
    }

    let mix = MixEngine()
    let library = LibraryModel()
    /// File loaded on each deck, for marking it in the library.
    @Published var loadedPaths: [String?] = [nil, nil]
    @Published var showSettings = false
    @Published var settingsSection: SettingsSection = .connect
    @Published var syncOn = true
    private(set) var server: ControlServer?

    @Published var decks = [DeckInfo(name: "A"), DeckInfo(name: "B")]
    @Published var lanes: [Band: Double] = [.low: 0, .mid: 0, .high: 0]
    @Published var outgoing = 0
    /// Mixer controls, mirrored from the engine (see MixEngine for ranges).
    @Published var eq: [[Band: Double]] = [[.low: 0.5, .mid: 0.5, .high: 0.5], [.low: 0.5, .mid: 0.5, .high: 0.5]]
    @Published var volumes: [Double] = [1, 1]
    @Published var crossfader = 0.5
    @Published var beat: Double?
    @Published var surfaces = 0
    @Published var status = "Load a track into each deck."
    @Published var connectURL: String?

    /// Which surface currently has a finger on each lane (touch ownership).
    private var owners: [Band: ControlServer.ClientID] = [:]
    private var ticker: Timer?
    /// Held while a deck plays and Keep Mac awake is on, so the display doesn't sleep mid-set.
    private var awakeActivity: NSObjectProtocol?

    init() {
        do { try mix.start() } catch { status = "Audio engine failed to start: \(error.localizedDescription)" }
        mix.onChange = { [weak self] in self?.refresh() }

        let root = Self.surfaceFolder()
        let server = ControlServer(root: root)
        server.onMessage = { [weak self] id, msg in self?.handle(id, msg) }
        server.onClientsChanged = { [weak self] n in self?.surfaces = n }
        do {
            try server.start()
            self.server = server
            if let ip = ControlServer.lanAddress() { connectURL = "http://\(ip):\(server.httpPort)" }
        } catch {
            status = "Control server failed to start: \(error.localizedDescription)"
        }

        // ~30 state updates a second to every surface, and the beat readout in the window.
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        let sync = SettingsKey.bool(SettingsKey.syncOnByDefault, default: true)
        mix.setSync(sync)
        syncOn = sync
        refresh()
        applyLaunchArguments()
    }

    /// Developer shortcuts: `--a <file> --b <file> --volume 0.3` preload decks and set the master volume.
    private func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let v = value("--volume").flatMap(Float.init) { mix.engine.mainMixerNode.outputVolume = v }
        if let a = value("--a") { load(URL(fileURLWithPath: a), into: 0) }
        if let b = value("--b") { load(URL(fileURLWithPath: b), into: 1) }
    }

    static func surfaceFolder() -> URL {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Surface"),
           FileManager.default.fileExists(atPath: r.path) { return r }
        // Running the bare binary from a checkout.
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Surface")
    }

    // MARK: Window actions

    /// Shows the Settings sheet, on `section` if given, otherwise where it was last left.
    func openSettings(_ section: SettingsSection? = nil) {
        if let section { settingsSection = section }
        showSettings = true
    }

    func load(_ url: URL, into deck: Int) {
        decks[deck].loading = true
        status = "Analysing \(url.deletingPathExtension().lastPathComponent)…"
        mix.load(url: url, into: deck) { [weak self] result in
            guard let self else { return }
            self.decks[deck].loading = false
            switch result {
            case .success(let g):
                self.loadedPaths[deck] = url.path
                self.library.noteLoaded(path: url.path, bpm: g.bpm, confidence: g.confidence)
                self.decks[deck].bpmUnsure = g.confidence < 0.25
                self.status = String(format: "Deck %@: %.2f BPM, first downbeat at %.2fs.", self.mix.decks[deck].name, g.bpm, g.firstBeat)
            case .failure(let e): self.status = "Couldn't load that file: \(e.localizedDescription)"
            }
            self.refresh()
        }
    }

    /// Where a double-clicked track goes: the outgoing deck if it's empty, otherwise the incoming one.
    var incomingForLoading: Int { mix.decks[mix.outgoing].grid == nil ? mix.outgoing : mix.incoming }

    func playOutgoing() { mix.playOutgoing() }
    func togglePlay(_ i: Int) {
        if mix.previewing.contains(i) { mix.keepPreviewPlaying(deck: i); return }
        mix.decks[i].isPlaying ? mix.pause(deck: i) : mix.play(deck: i)
    }
    func cueDown(_ i: Int) { mix.cueDown(deck: i) }
    func cueUp(_ i: Int) { mix.cueUp(deck: i) }
    func toggleSync() { mix.setSync(!mix.syncOn); syncOn = mix.syncOn }
    func cueIncoming(every beats: Double) { mix.cueIncoming(every: beats) }
    func stopAll() { mix.stopAll() }
    func setLane(_ b: Band, _ v: Double) { mix.setLane(b, v) }
    func flick(_ b: Band) { mix.flick(b, to: (mix.lanes[b] ?? 0) < 0.5 ? 1 : 0) }
    func setEQ(_ deck: Int, _ b: Band, _ v: Double) { mix.setEQ(deck: deck, band: b, v) }
    func setVolume(_ deck: Int, _ v: Double) { mix.setVolume(deck: deck, v) }
    func setCrossfader(_ v: Double) { mix.setCrossfader(v) }

    // MARK: Surfaces

    private func handle(_ id: ControlServer.ClientID, _ msg: [String: Any]) {
        let band = (msg["band"] as? String).flatMap(Band.init(rawValue:))
        // Mixer messages name the deck as 0/1 or "A"/"B".
        let deck = (msg["deck"] as? Int) ?? (msg["deck"] as? String).flatMap { ["A": 0, "B": 1][$0.uppercased()] }
        switch msg["t"] as? String {
        case "grab":
            if let band, owners[band] == nil { owners[band] = id }
        case "release":
            if let band, owners[band] == id { owners[band] = nil }
        case "lane":
            if let band, let v = msg["v"] as? Double, owners[band] == nil || owners[band] == id {
                mix.setLane(band, v)
            }
        case "flick":
            if let band, let to = msg["to"] as? Double { mix.flick(band, to: to) }
        case "stable":
            mix.backToStable()
        case "play":
            mix.play(deck: mix.outgoing)
        case "cue":
            mix.cueIncoming(every: (msg["every"] as? Double) ?? 32)
        case "eq":
            if let deck, let band, let v = msg["v"] as? Double { mix.setEQ(deck: deck, band: band, v) }
        case "volume":
            if let deck, let v = msg["v"] as? Double { mix.setVolume(deck: deck, v) }
        case "xfade":
            if let v = msg["v"] as? Double { mix.setCrossfader(v) }
        case "disconnect":
            for (b, owner) in owners where owner == id { owners[b] = nil }
        default:
            break
        }
    }

    private func refresh() {
        outgoing = mix.outgoing
        lanes = mix.lanes
        if eq != mix.eq { eq = mix.eq }
        if volumes != mix.volumes { volumes = mix.volumes }
        if crossfader != mix.crossfader { crossfader = mix.crossfader }
        for i in 0..<2 {
            let d = mix.decks[i]
            decks[i].title = d.title
            decks[i].artist = d.artist
            decks[i].bpm = d.playingBPM
            decks[i].playing = d.isPlaying
            decks[i].paused = d.pausedBeat != nil
            decks[i].atCue = !d.isPlaying && d.pausedBeat == nil
        }
    }

    private func tick() {
        mix.syncTick(interval: 1.0 / 30)
        let b = mix.outgoingBeat()
        if (b == nil) != (beat == nil) || b.map({ Int($0 * 4) }) != beat.map({ Int($0 * 4) }) { beat = b }
        // A finished deck stops on its own; keep the play state honest.
        for i in 0..<2 where decks[i].playing != mix.decks[i].isPlaying { refresh() }
        updateKeepAwake()

        let out = mix.decks[mix.outgoing], inc = mix.decks[mix.incoming]
        var state: [String: Any] = [
            "t": "state",
            "out": out.name, "in": inc.name,
            "lanes": Dictionary(uniqueKeysWithValues: mix.lanes.map { ($0.key.rawValue, $0.value) }),
            "owners": Dictionary(uniqueKeysWithValues: owners.map { ($0.key.rawValue, $0.value) }),
            "decks": mix.decks.map { d -> [String: Any] in
                ["name": d.name, "title": d.title, "artist": d.artist, "bpm": d.playingBPM ?? 0, "playing": d.isPlaying, "loaded": d.grid != nil, "beat": d.currentBeat() ?? -1]
            },
            "surfaces": surfaces,
            // Mixer: EQ per deck (0 kill, 0.5 unity, 1 +6 dB), channel faders, crossfader.
            "eq": mix.eq.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.key.rawValue, $0.value) }) },
            "volume": mix.volumes,
            "xfade": mix.crossfader,
        ]
        if let b { state["beat"] = b; state["bpm"] = out.playingBPM ?? 0 }
        if let start = mix.incomingStartBeat, let b, b < start { state["startsIn"] = start - b }
        server?.broadcast(state)
    }

    private func updateKeepAwake() {
        let want = SettingsKey.bool(SettingsKey.keepAwake, default: true) && mix.decks.contains { $0.isPlaying }
        if want, awakeActivity == nil {
            awakeActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleDisplaySleepDisabled], reason: "A deck is playing")
        } else if !want, let a = awakeActivity {
            ProcessInfo.processInfo.endActivity(a)
            awakeActivity = nil
        }
    }
}
