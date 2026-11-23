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
        /// Camelot key of the loaded track.
        var key: String?
        var paused = false
        var atCue = true
    }

    /// A connected phone or tablet, and which deck's mixer controls it shows.
    struct SurfaceDevice: Identifiable, Equatable {
        /// Stable id the page keeps in its own storage, so a reload keeps its assignment.
        let id: String
        let client: ControlServer.ClientID
        /// "iPhone", "iPad 2" … numbered when two of the same kind are connected.
        var name: String
        var deck: DeckAssignment
    }

    let mix = MixEngine()
    let library = LibraryModel()
    /// File loaded on each deck, for marking it in the library.
    @Published var loadedPaths: [String?] = [nil, nil]
    @Published var showSettings = false
    /// The built-in DJ guide. Opens by itself the first time the app runs.
    /// The guide chapter being practised: shown in the practice bar until the user stops or goes back.
    @Published var practiceChapter: GuideChapter?
    @Published var showGuide = !UserDefaults.standard.bool(forKey: GuideKey.seen) {
        didSet { if showGuide { UserDefaults.standard.set(true, forKey: GuideKey.seen) } }
    }
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
    /// Headphone cueing, mirrored from the engine: decks sent to the headphones, the cue mix,
    /// and the output devices in use (nil headphones = none).
    @Published var cue = [false, false]
    @Published var cueMix = 0.5
    @Published var speakers: AudioOutputs.Device?
    @Published var headphones: AudioOutputs.Device?
    /// The user's level per technique (the learning ladder), saved in UserDefaults.
    @Published var ladder = SkillLadder()
    @Published var beat: Double?
    @Published var surfaces = 0
    /// Surfaces that said hello, in the order they connected.
    @Published var devices: [SurfaceDevice] = []
    /// Assignments by device id, kept while the app runs so a phone that reloads gets its deck back.
    private var assignments: [String: DeckAssignment] = [:]
    @Published var status = "Load a track into each deck."
    @Published var connectURL: String?

    /// Which surface currently has a finger on each control (touch ownership). Keys are
    /// control ids: a lane's band ("low"), "eq:A:low", "vol:B" or "xfade".
    private var owners: [String: ControlServer.ClientID] = [:]
    private var keyMonitor: Any?
    private var ticker: Timer?
    /// The phone page's current version (see `ControlServer.pageVersion`), re-read every 2 s.
    private var pageVersion = ""
    private var pageCheckTicks = 0
    /// Held while a deck plays and Keep Mac awake is on, so the display doesn't sleep mid-set.
    private var awakeActivity: NSObjectProtocol?

    init() {
        // Space bar = Play all, unless someone is typing in a field or a sheet (Settings, Guide) is open.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.keyCode == 49, !e.isARepeat,
                  e.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  let w = e.window, w.attachedSheet == nil, w.sheetParent == nil,
                  !(w.firstResponder is NSText) else { return e }
            if self.canPlayAll { self.playAll() }
            return nil
        }
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
        let saved = UserDefaults.standard.dictionary(forKey: SettingsKey.skillLadder) as? [String: String] ?? [:]
        mix.setLadder(SkillLadder(dictionary: saved))
        mix.setCueMix(UserDefaults.standard.object(forKey: SettingsKey.cueMix) as? Double ?? 0.5)
        let ud = UserDefaults.standard
        if ud.string(forKey: SettingsKey.speakersDevice) != nil || ud.string(forKey: SettingsKey.headphonesDevice) != nil {
            applyOutputs()
        }
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
                self.library.noteLoaded(path: url.path, bpm: g.bpm, confidence: g.confidence, key: self.mix.decks[deck].key)
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
    func toggleCue(_ i: Int) { mix.setCue(deck: i, !mix.cue[i]) }
    func setCueMix(_ v: Double) {
        mix.setCueMix(v)
        UserDefaults.standard.set(mix.cueMix, forKey: SettingsKey.cueMix)
    }

    /// Chooses the output devices by UID (nil speakers = the system default, nil headphones = none)
    /// and remembers them. Playing decks pause while the audio moves to the new devices.
    func setOutputs(speakers: String?, headphones: String?) {
        let ud = UserDefaults.standard
        ud.set(speakers, forKey: SettingsKey.speakersDevice)
        ud.set(headphones, forKey: SettingsKey.headphonesDevice)
        applyOutputs()
    }

    private func applyOutputs() {
        let ud = UserDefaults.standard
        let hp = ud.string(forKey: SettingsKey.headphonesDevice)
        if !mix.setOutputs(speakers: ud.string(forKey: SettingsKey.speakersDevice), headphones: hp), hp != nil {
            status = AudioOutputs.device(uid: hp!) == nil
                ? "The headphones aren't connected. Plug them in, or choose others in Settings → Audio."
                : "Couldn't use those headphones with these speakers. Choose others in Settings → Audio."
        }
        refresh()
    }
    func playAll() { mix.playAll() }
    /// Play all would start something: a loaded deck is not playing.
    var canPlayAll: Bool { (0..<2).contains { loadedPaths[$0] != nil && !decks[$0].playing } }
    func setLane(_ b: Band, _ v: Double) { mix.setLane(b, v) }
    func flick(_ b: Band) { mix.flick(b, to: (mix.lanes[b] ?? 0) < 0.5 ? 1 : 0) }
    func setEQ(_ deck: Int, _ b: Band, _ v: Double) { mix.setEQ(deck: deck, band: b, v) }
    func setVolume(_ deck: Int, _ v: Double) { mix.setVolume(deck: deck, v) }
    func setCrossfader(_ v: Double) { mix.setCrossfader(v) }

    /// Moves one technique to a level, and remembers it. Phones follow on the next state broadcast.
    func setLevel(_ level: SkillLevel) {
        mix.setLevel(level)
        UserDefaults.standard.set(mix.ladder.dictionary, forKey: SettingsKey.skillLadder)
        owners.removeAll()   // the controls on the phones change; nobody holds the new ones yet
    }

    // MARK: Surfaces

    /// Which deck a surface's mixer screen controls. Only matters at the mixer blend level with
    /// two or more surfaces connected: one phone per deck gives each channel the whole screen.
    func assign(_ deviceID: String, _ deck: DeckAssignment) {
        assignments[deviceID] = deck
        if let i = devices.firstIndex(where: { $0.id == deviceID }) { devices[i].deck = deck }
    }

    private func hello(_ client: ControlServer.ClientID, deviceID: String, kind: String) {
        devices.removeAll { $0.client == client || $0.id == deviceID }
        let same = devices.filter { $0.name == kind || $0.name.hasPrefix(kind + " ") }.count
        devices.append(SurfaceDevice(id: deviceID, client: client, name: same == 0 ? kind : "\(kind) \(same + 1)",
                                     deck: assignments[deviceID] ?? .both))
        // Two surfaces, neither assigned yet: split them, first A, second B.
        if devices.count == 2, devices.allSatisfy({ assignments[$0.id] == nil }) {
            assign(devices[0].id, .a); assign(devices[1].id, .b)
        }
    }

    private func handle(_ id: ControlServer.ClientID, _ msg: [String: Any]) {
        let band = (msg["band"] as? String).flatMap(Band.init(rawValue:))
        // Mixer messages name the deck as 0/1 or "A"/"B".
        let deck = (msg["deck"] as? Int) ?? (msg["deck"] as? String).flatMap { ["A": 0, "B": 1][$0.uppercased()] }
        // Touch ownership: `grab` / `release` name a control id, or a lane's band.
        let control = (msg["control"] as? String) ?? band?.rawValue
        func free(_ c: String?) -> Bool { c.map { owners[$0] == nil || owners[$0] == id } ?? true }
        let deckName = deck.map { $0 == 0 ? "A" : "B" } ?? ""
        switch msg["t"] as? String {
        case "grab":
            if let control, owners[control] == nil { owners[control] = id }
        case "release":
            if let control, owners[control] == id { owners[control] = nil }
        case "lane":
            if let band, let v = msg["v"] as? Double, free(band.rawValue) {
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
            if let deck, let band, let v = msg["v"] as? Double, free("eq:\(deckName):\(band.rawValue)") {
                mix.setEQ(deck: deck, band: band, v)
            }
        case "volume":
            if let deck, let v = msg["v"] as? Double, free("vol:\(deckName)") { mix.setVolume(deck: deck, v) }
        case "xfade":
            if let v = msg["v"] as? Double, free("xfade") { mix.setCrossfader(v) }
        case "hello":
            if let device = msg["device"] as? String, !device.isEmpty {
                hello(id, deviceID: String(device.prefix(64)), kind: String(((msg["kind"] as? String) ?? "Phone").prefix(24)))
            }
        case "assign":
            if let device = devices.first(where: { $0.client == id }),
               let raw = msg["deck"] as? String, let a = DeckAssignment(rawValue: raw) { assign(device.id, a) }
        case "disconnect":
            for (b, owner) in owners where owner == id { owners[b] = nil }
            devices.removeAll { $0.client == id }
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
        if ladder != mix.ladder { ladder = mix.ladder }
        if cue != mix.cue { cue = mix.cue }
        if cueMix != mix.cueMix { cueMix = mix.cueMix }
        if speakers != mix.speakers { speakers = mix.speakers }
        if headphones != mix.headphones { headphones = mix.headphones }
        for i in 0..<2 {
            let d = mix.decks[i]
            decks[i].title = d.title
            decks[i].artist = d.artist
            decks[i].key = d.key
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

        if pageCheckTicks % 60 == 0, let v = server?.pageVersion() { pageVersion = v }
        pageCheckTicks += 1

        let out = mix.decks[mix.outgoing], inc = mix.decks[mix.incoming]
        var state: [String: Any] = [
            "t": "state",
            "out": out.name, "in": inc.name,
            "lanes": Dictionary(uniqueKeysWithValues: mix.lanes.map { ($0.key.rawValue, $0.value) }),
            "owners": owners,
            "decks": mix.decks.map { d -> [String: Any] in
                ["name": d.name, "title": d.title, "artist": d.artist, "bpm": d.playingBPM ?? 0, "playing": d.isPlaying, "loaded": d.grid != nil, "beat": d.currentBeat() ?? -1]
            },
            "surfaces": surfaces,
            // The phone page's version: a surface served an older one reloads itself.
            "page": pageVersion,
            // Each surface finds itself by its device id: [{"id", "name", "deck": "A" | "B" | "both"}].
            "devices": devices.map { ["id": $0.id, "name": $0.name, "deck": $0.deck.rawValue] },
            // Mixer: EQ per deck (0 kill, 0.5 unity, 1 +6 dB), channel faders, crossfader.
            "eq": mix.eq.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.key.rawValue, $0.value) }) },
            "volume": mix.volumes,
            "xfade": mix.crossfader,
            // The learning ladder: {"blend": "handoff" | "mixer", "timing": "snap" | "free", "tempo": "sync"}.
            "ladder": mix.ladder.dictionary,
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

/// Which deck's mixer controls a surface shows.
enum DeckAssignment: String, CaseIterable {
    case a = "A", both, b = "B"
    var label: String { self == .both ? "A + B" : rawValue }
}
