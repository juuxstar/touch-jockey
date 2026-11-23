import AVFoundation

/// The three frequency bands a handoff moves between decks.
public enum Band: String, CaseIterable, Codable {
    case low, mid, high
}

/// One track player: file → player → time-pitch (sync with key lock) → three band filters → deck output.
///
/// The bands are split in parallel with 24 dB/octave filters at 200 Hz and 2.5 kHz,
/// and each band has its own volume: the handoff lane's gain times the mixer's EQ gain.
/// The deck output's volume is the channel fader times the crossfader.
///
/// A **cue send** taps the track straight after the time-pitch, before the bands, lanes and
/// faders, so a deck sent to the headphones is heard there even while it's silent in the mix.
public final class Deck {
    public let name: String
    let player = AVAudioPlayerNode()
    let timePitch = AVAudioUnitTimePitch()
    let bandFilters: [Band: AVAudioUnitEQ]
    let bandGains: [Band: AVAudioMixerNode]
    let output = AVAudioMixerNode()
    /// The headphone cue send: 1 while the deck is cued, else 0.
    let cueSend = AVAudioMixerNode()
    /// A unity mixer right after the time-pitch, where the track splits to the bands and the cue send.
    /// (Splitting the time-pitch's own output to two paths makes it render twice per cycle, so the
    /// track would play at double speed.)
    let split = AVAudioMixerNode()
    /// Where the deck plays into: the speaker mix and the headphone cue bus (set by `MixEngine`).
    private weak var programBus: AVAudioMixerNode?
    private weak var cueBus: AVAudioMixerNode?
    private var busIndex: AVAudioNodeBus = 0

    public private(set) var file: AVAudioFile?
    public private(set) var title: String = ""
    public private(set) var artist: String = ""
    public private(set) var grid: BeatGrid?
    public private(set) var waveform: Waveform?
    /// Detected key, Camelot code (for example "8A").
    public private(set) var key: String?
    /// File frame where the currently scheduled segment starts.
    var segmentStartFrame: AVAudioFramePosition = 0
    public private(set) var isPlaying = false
    /// The beat the deck last started playing from (it may not be heard yet if the start is scheduled).
    public private(set) var startedFromBeat: Double = 0
    /// Where a paused deck resumes from (nil = from bar 1).
    public internal(set) var pausedBeat: Double?
    /// The cue point, as a beat index (0 = bar 1). CUE returns here.
    public internal(set) var cueBeat: Double = 0

    static let lowCrossover: Float = 200
    static let highCrossover: Float = 2500

    init(name: String) {
        self.name = name
        func eq(_ filters: [(AVAudioUnitEQFilterType, Float)]) -> AVAudioUnitEQ {
            let unit = AVAudioUnitEQ(numberOfBands: filters.count)
            for (i, (type, freq)) in filters.enumerated() {
                let band = unit.bands[i]
                band.filterType = type
                band.frequency = freq
                band.bypass = false
            }
            return unit
        }
        let lo = Deck.lowCrossover, hi = Deck.highCrossover
        bandFilters = [
            .low: eq([(.lowPass, lo), (.lowPass, lo)]),
            .mid: eq([(.highPass, lo), (.highPass, lo), (.lowPass, hi), (.lowPass, hi)]),
            .high: eq([(.highPass, hi), (.highPass, hi)]),
        ]
        bandGains = Dictionary(uniqueKeysWithValues: Band.allCases.map { ($0, AVAudioMixerNode()) })
        timePitch.pitch = 0   // key lock: tempo changes never change pitch
        cueSend.outputVolume = 0
    }

    func attach(to engine: AVAudioEngine, program: AVAudioMixerNode, cue: AVAudioMixerNode, bus: AVAudioNodeBus) {
        programBus = program; cueBus = cue; busIndex = bus
        engine.attach(player)
        engine.attach(timePitch)
        for b in Band.allCases {
            engine.attach(bandFilters[b]!)
            engine.attach(bandGains[b]!)
        }
        engine.attach(output)
        engine.attach(cueSend)
        engine.attach(split)
    }

    /// (Re)wires the chain for a file's format.
    func connect(in engine: AVAudioEngine, format: AVAudioFormat) {
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: split, format: format)
        let points = Band.allCases.map { AVAudioConnectionPoint(node: bandFilters[$0]!, bus: 0) }
            + [AVAudioConnectionPoint(node: cueSend, bus: 0)]
        engine.connect(split, to: points, fromBus: 0, format: format)
        for (i, b) in Band.allCases.enumerated() {
            engine.connect(bandFilters[b]!, to: bandGains[b]!, format: format)
            engine.connect(bandGains[b]!, to: output, fromBus: 0, toBus: AVAudioNodeBus(i), format: format)
        }
        if let programBus { engine.connect(output, to: programBus, fromBus: 0, toBus: busIndex, format: format) }
        if let cueBus { engine.connect(cueSend, to: cueBus, fromBus: 0, toBus: busIndex, format: format) }
    }

    func load(url: URL, analysis: TrackAnalysis, in engine: AVAudioEngine) throws {
        stop()
        pausedBeat = nil
        cueBeat = 0
        let f = try AVAudioFile(forReading: url)
        file = f
        grid = analysis.grid
        waveform = analysis.waveform
        key = analysis.key?.camelot
        (title, artist) = Deck.tags(url)
        connect(in: engine, format: f.processingFormat)
    }

    /// Title and artist from the file's tags, falling back to the file name.
    static func tags(_ url: URL) -> (String, String) {
        let items = AVURLAsset(url: url).commonMetadata
        func value(_ key: AVMetadataKey) -> String? {
            AVMetadataItem.metadataItems(from: items, withKey: key, keySpace: .common).first?.stringValue
        }
        let guess = LibraryStore.guessFromFileName(url)
        return (value(.commonKeyTitle) ?? guess.title, value(.commonKeyArtist) ?? guess.artist)
    }

    func setGain(_ gain: Float, band: Band) {
        bandGains[band]!.outputVolume = gain
    }

    /// The deck's overall volume (channel fader × crossfader), applied after the bands are summed.
    func setVolume(_ gain: Float) {
        output.outputVolume = gain
    }

    /// Current gain of one band (handoff lane × EQ), as set on its mixer node. For tests and meters.
    public func bandGain(_ band: Band) -> Float { bandGains[band]!.outputVolume }

    /// Current overall deck volume, as set on the deck's output mixer. For tests and meters.
    public var outputGain: Float { output.outputVolume }

    /// Plays from a beat index (0 = first downbeat), starting at a host time (nil = now).
    func play(fromBeat beat: Double, atHostTime host: UInt64?) {
        guard let f = file, let g = grid else { return }
        player.stop()
        let sr = f.processingFormat.sampleRate
        let start = AVAudioFramePosition(max(0, g.seconds(atBeat: beat)) * sr)
        guard start < f.length else { return }
        segmentStartFrame = start
        startedFromBeat = beat
        player.scheduleSegment(f, startingFrame: start, frameCount: AVAudioFrameCount(f.length - start), at: nil)
        if let host { player.play(at: AVAudioTime(hostTime: host)) } else { player.play() }
        isPlaying = true
    }

    func stop() {
        player.stop()
        isPlaying = false
    }

    /// Playback position in the track, in seconds, as of the last render cycle.
    func position() -> (seconds: Double, renderTime: AVAudioTime)? {
        guard isPlaying, let f = file,
              let nodeTime = player.lastRenderTime, nodeTime.isSampleTimeValid,
              let pt = player.playerTime(forNodeTime: nodeTime), pt.sampleTime >= 0
        else { return nil }
        return (Double(segmentStartFrame + pt.sampleTime) / f.processingFormat.sampleRate, nodeTime)
    }

    /// Where a stopped deck sits: its paused position, or its cue point.
    public var parkedBeat: Double { pausedBeat ?? cueBeat }

    /// Where to show the deck: playing, its current beat; started but waiting for a scheduled
    /// start (Next phrase, say), the beat it will start from; stopped, where it's parked.
    public var shownBeat: Double { currentBeat() ?? (isPlaying ? startedFromBeat : parkedBeat) }

    /// True once a stopped deck has been moved off bar 1 (jogged, paused or cued elsewhere).
    public var isParkedAway: Bool { !isPlaying && (pausedBeat != nil || cueBeat > 0) }

    /// Current beat index, or nil when stopped.
    public func currentBeat() -> Double? {
        guard let g = grid, let p = position() else { return nil }
        return g.beat(atSeconds: p.seconds)
    }

    /// How long after the player renders a moment it's heard: the time-stretcher's delay (seconds).
    public var soundDelay: Double { timePitch.latency }

    /// Current beat as heard (the player's beat less the time-stretcher's delay), or nil when stopped.
    public func heardBeat() -> Double? {
        guard let b = currentBeat(), let g = grid else { return nil }
        return b - soundDelay * Double(timePitch.rate) / g.secondsPerBeat
    }

    /// Effective tempo after sync.
    public var playingBPM: Double? { grid.map { $0.bpm * Double(timePitch.rate) } }
}
