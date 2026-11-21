import AVFoundation
import Foundation

/// Two decks and a handoff from the outgoing deck to the incoming one.
///
/// Decks have fixed positions, like a hardware mixer: each band's lane runs from
/// deck A (0) to deck B (1). The band gains follow an equal-power curve, so a lane
/// at 0.5 is as loud as either end. When every lane reaches the incoming deck's
/// side, the handoff finishes on the next bar: the outgoing deck stops and the
/// roles swap, with the lanes left where they are, so the next blend runs the
/// other way.
///
/// On top of the lanes sits a conventional two-channel mixer: per-deck EQ (high, mid,
/// low), a channel fader per deck and a crossfader. The layers multiply:
///
///     band gain   = lane gain × EQ gain
///     deck volume = channel fader gain × crossfader gain
///
/// The mixer never affects when a handoff finishes; that stays tied to the lanes.
public final class MixEngine {
    public let engine = AVAudioEngine()
    public let decks: [Deck]
    public private(set) var outgoing = 0
    public var incoming: Int { 1 - outgoing }
    public private(set) var lanes: [Band: Double] = [.low: 0, .mid: 0, .high: 0]
    /// Beat on the outgoing deck at which the incoming deck is scheduled to start.
    public private(set) var incomingStartBeat: Double?
    /// Called on the main queue whenever roles, lanes or tracks change.
    public var onChange: (() -> Void)?

    private var finishScheduled = false
    /// SYNC: the incoming deck follows the outgoing deck's tempo and beat. On by default.
    public private(set) var syncOn = true
    /// Decks currently previewing from the cue point while CUE is held.
    public private(set) var previewing: Set<Int> = []

    /// EQ control positions per deck and band, 0...1: 0 = kill, 0.5 = unity (0 dB), 1 = +6 dB.
    public private(set) var eq: [[Band: Double]] = [[.low: 0.5, .mid: 0.5, .high: 0.5], [.low: 0.5, .mid: 0.5, .high: 0.5]]
    /// Channel fader positions per deck, 0...1 (1 = full, the default).
    public private(set) var volumes: [Double] = [1, 1]
    /// Crossfader position, 0 = deck A only, 0.5 = both full, 1 = deck B only.
    public private(set) var crossfader: Double = 0.5

    public init() {
        decks = [Deck(name: "A"), Deck(name: "B")]
        for d in decks { d.attach(to: engine) }
        // Wire each deck with a default format so the engine can start before any track is loaded.
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        for d in decks { d.connect(in: engine, format: fmt) }
        applyGains()
    }

    public func start() throws {
        engine.prepare()
        try engine.start()
    }

    // MARK: Tracks

    /// Analyses and loads a track into a deck. Analysis runs off the main thread.
    public func load(url: URL, into deckIndex: Int, completion: @escaping (Result<BeatGrid, Error>) -> Void) {
        AnalysisPriority.beginForeground()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try AnalysisCache.analysis(for: url) }
            AnalysisPriority.endForeground()
            DispatchQueue.main.async {
                switch result {
                case .success(let analysis):
                    do {
                        let grid = analysis.grid
                        try self.decks[deckIndex].load(url: url, analysis: analysis, in: self.engine)
                        if deckIndex == self.incoming { self.incomingStartBeat = nil }
                        self.applyGains()
                        completion(.success(grid))
                    } catch { completion(.failure(error)) }
                case .failure(let e): completion(.failure(e))
                }
                self.onChange?()
            }
        }
    }

    // MARK: Transport

    /// Starts the outgoing deck from its first downbeat at its natural tempo.
    public func playOutgoing() {
        let d = decks[outgoing]
        d.timePitch.rate = 1
        d.play(fromBeat: 0, atHostTime: nil)
        onChange?()
    }

    /// Starts the incoming deck, synced and phase-aligned, on the outgoing deck's next
    /// boundary of `every` beats (4 = next bar, 32 = next phrase).
    public func cueIncoming(every beats: Double = 32) {
        let inc = decks[incoming], out = decks[outgoing]
        guard let outBPM = out.playingBPM, let inGrid = inc.grid,
              let (host, beat) = hostTime(ofNextBoundary: beats) else { return }
        baseRatio = outBPM / inGrid.bpm
        phaseIntegral = 0
        inc.timePitch.rate = Float(baseRatio)
        inc.play(fromBeat: 0, atHostTime: host)
        incomingStartBeat = beat
        onChange?()
    }

    /// Play or resume one deck from where it was paused (bar 1 if stopped).
    ///
    /// The outgoing deck plays at its own tempo. The incoming deck, if the outgoing one is
    /// playing, starts synced and lands on the outgoing deck's next beat, so it is never
    /// out of time; otherwise it plays at its own tempo too.
    public func play(deck i: Int) {
        let d = decks[i]
        guard d.grid != nil, !d.isPlaying else { return }
        let from = d.pausedBeat ?? d.cueBeat
        if i == incoming, syncOn, decks[outgoing].isPlaying, let outBPM = decks[outgoing].playingBPM, let g = d.grid,
           let (host, beat) = hostTime(ofNextBoundary: 1) {
            baseRatio = outBPM / g.bpm
            phaseIntegral = 0
            d.timePitch.rate = Float(baseRatio)
            d.play(fromBeat: from.rounded(), atHostTime: host)   // whole beat, so it lands on the beat
            incomingStartBeat = beat
        } else {
            if i == outgoing && !decks[incoming].isPlaying { d.timePitch.rate = 1 }
            d.play(fromBeat: from, atHostTime: nil)
        }
        d.pausedBeat = nil
        onChange?()
    }

    // MARK: CUE (CDJ behaviour)

    /// CUE pressed. Playing: back to the cue point and pause. Paused away from the cue point:
    /// set the cue point here (snapped to the nearest beat). Paused on the cue point: preview
    /// from it until CUE is released.
    public func cueDown(deck i: Int) {
        let d = decks[i]
        guard d.grid != nil else { return }
        if d.isPlaying {
            d.stop()
            d.pausedBeat = nil
            if i == incoming { incomingStartBeat = nil }
        } else {
            let pos = d.pausedBeat ?? d.cueBeat
            if abs(pos - d.cueBeat) > 0.05 {
                d.cueBeat = max(0, pos.rounded())
                d.pausedBeat = nil
            } else {
                previewing.insert(i)
                d.pausedBeat = nil
                play(deck: i)
            }
        }
        onChange?()
    }

    /// CUE released: a preview stops and returns to the cue point.
    public func cueUp(deck i: Int) {
        guard previewing.remove(i) != nil else { return }
        let d = decks[i]
        d.stop()
        d.pausedBeat = nil
        if i == incoming { incomingStartBeat = nil }
        onChange?()
    }

    /// PLAY pressed while CUE is held: keep playing after CUE is released (CDJ behaviour).
    public func keepPreviewPlaying(deck i: Int) { previewing.remove(i); onChange?() }

    // MARK: SYNC

    public func setSync(_ on: Bool) {
        syncOn = on
        let inc = decks[incoming]
        if on, let outBPM = decks[outgoing].playingBPM, let g = inc.grid {
            baseRatio = outBPM / g.bpm
            phaseIntegral = 0
            inc.timePitch.rate = Float(baseRatio)
        } else if !on {
            inc.timePitch.rate = 1
        }
        onChange?()
    }

    /// Pause one deck, remembering its position.
    public func pause(deck i: Int) {
        let d = decks[i]
        guard d.isPlaying else { return }
        d.pausedBeat = d.currentBeat()
        d.stop()
        if i == incoming { incomingStartBeat = nil }
        onChange?()
    }

    /// Stop one deck and return it to bar 1.
    public func stop(deck i: Int) {
        let d = decks[i]
        d.stop()
        d.pausedBeat = nil
        if i == incoming { incomingStartBeat = nil }
        onChange?()
    }

    public func stopAll() {
        previewing.removeAll()
        for d in decks { d.stop(); d.pausedBeat = nil }
        incomingStartBeat = nil
        finishScheduled = false
        let end = laneEnd(forDeck: outgoing)
        lanes = [.low: end, .mid: end, .high: end]
        applyGains()
        onChange?()
    }

    // MARK: Handoff lanes

    public func setLane(_ band: Band, _ value: Double) {
        lanes[band] = min(1, max(0, value))
        applyGains()
        checkFinish()
        onChange?()
    }

    /// A flick: the band jumps to `target` (0 = A, 1 = B) exactly on the outgoing deck's next bar.
    public func flick(_ band: Band, to target: Double) {
        guard let (host, _) = hostTime(ofNextBoundary: 4) else { setLane(band, target); return }
        at(hostTime: host) { self.setLane(band, target) }
    }

    /// Back to the last stable mix: everything on the outgoing deck.
    public func backToStable() {
        for b in Band.allCases { lanes[b] = laneEnd(forDeck: outgoing) }
        applyGains()
        onChange?()
    }

    private func applyGains() {
        for b in Band.allCases {
            let x = lanes[b] ?? 0
            let lane = [cos(x * .pi / 2), sin(x * .pi / 2)]   // A, B: equal power
            for i in 0..<2 {
                decks[i].setGain(Float(lane[i] * Self.eqGain(eq[i][b] ?? 0.5)), band: b)
            }
        }
        let xf = Self.crossfaderGains(crossfader)
        decks[0].setVolume(Float(Self.faderGain(volumes[0]) * xf.a))
        decks[1].setVolume(Float(Self.faderGain(volumes[1]) * xf.b))
    }

    // MARK: Mixer (EQ, channel faders, crossfader)

    /// Sets one EQ control, 0...1 (0 = kill, 0.5 = unity, 1 = +6 dB).
    public func setEQ(deck i: Int, band: Band, _ value: Double) {
        guard decks.indices.contains(i) else { return }
        eq[i][band] = min(1, max(0, value))
        applyGains()
        onChange?()
    }

    /// Sets a channel fader, 0...1 (1 = full).
    public func setVolume(deck i: Int, _ value: Double) {
        guard decks.indices.contains(i) else { return }
        volumes[i] = min(1, max(0, value))
        applyGains()
        onChange?()
    }

    /// Sets the crossfader, 0 (A) ... 0.5 (both full) ... 1 (B).
    public func setCrossfader(_ value: Double) {
        crossfader = min(1, max(0, value))
        applyGains()
        onChange?()
    }

    /// Range of the EQ's lower half: from unity down to this many dB just above the kill.
    public static let eqCutRange = 30.0
    /// Boost at the top of the EQ.
    public static let eqMaxBoost = 6.0

    /// EQ control position → linear gain.
    ///
    /// Upper half: 0 dB to +6 dB, linear in dB. Lower half: 0 dB down to −30 dB, linear
    /// in dB, and the bottom 2% of travel is a full kill (silence), like an isolator EQ.
    public static func eqGain(_ v: Double) -> Double {
        let v = min(1, max(0, v))
        if v <= 0.02 { return 0 }
        let db = v >= 0.5 ? (v - 0.5) / 0.5 * eqMaxBoost : (v / 0.5 - 1) * eqCutRange
        return pow(10, db / 20)
    }

    /// Channel fader position → linear gain: a squared taper, so half-way is about −12 dB,
    /// close to the feel of a hardware fader.
    public static func faderGain(_ v: Double) -> Double {
        let v = min(1, max(0, v))
        return v * v
    }

    /// Crossfader position → gains for A and B.
    ///
    /// Both decks are at full volume in the centre. Moving towards one side fades the
    /// other deck out over that half of the travel with an equal-power (quarter-sine)
    /// curve: smooth, with no dip in the middle and no click at the ends.
    public static func crossfaderGains(_ x: Double) -> (a: Double, b: Double) {
        let x = min(1, max(0, x))
        let a = x <= 0.5 ? 1 : cos((x - 0.5) * .pi)   // 1 at the centre, 0 at B's end
        let b = x >= 0.5 ? 1 : sin(x * .pi)           // 0 at A's end, 1 at the centre
        return (a, b)
    }

    /// Lane value meaning "all on this deck": 0 for A, 1 for B.
    public func laneEnd(forDeck i: Int) -> Double { i == 0 ? 0 : 1 }

    private var allOnIncoming: Bool {
        let end = laneEnd(forDeck: incoming)
        return Band.allCases.allSatisfy { abs((lanes[$0] ?? 0) - end) <= 0.001 }
    }

    private func checkFinish() {
        guard !finishScheduled, allOnIncoming,
              decks[incoming].isPlaying,
              let (host, _) = hostTime(ofNextBoundary: 4) else { return }
        finishScheduled = true
        at(hostTime: host) {
            self.finishScheduled = false
            guard self.allOnIncoming else { return }
            self.decks[self.outgoing].stop()
            self.outgoing = self.incoming
            self.incomingStartBeat = nil
            // Lanes stay where they are: the new outgoing deck is now fully up.
            self.onChange?()
        }
    }

    // MARK: Phase lock

    /// Base tempo ratio for the incoming deck, before phase correction.
    private var baseRatio: Double = 1
    private var phaseIntegral: Double = 0
    /// Latest phase error in beats (positive = incoming is behind), for display and tests.
    public private(set) var phaseError: Double = 0

    /// Keeps the incoming deck's beats on the outgoing deck's beats.
    ///
    /// The time-stretcher doesn't play at exactly the rate it is given (about 0.1% off
    /// in testing), so a fixed ratio drifts. This proportional-integral loop measures the
    /// offset to the nearest whole beat and trims the incoming rate by at most ±1%.
    /// Call it regularly (the app calls it 30 times a second).
    public func syncTick(interval dt: Double) {
        let inc = decks[incoming], out = decks[outgoing]
        guard syncOn, inc.isPlaying, out.isPlaying, incomingStartBeat == nil || (outgoingBeat() ?? 0) >= (incomingStartBeat ?? 0),
              let ib = inc.currentBeat(), let ob = out.currentBeat(), ib >= 0 else { return }
        let diff = ob - ib
        let e = diff - diff.rounded()
        phaseError = e
        phaseIntegral = max(-5, min(5, phaseIntegral + e * dt))
        // Gains for a damping ratio of about 0.75 and ~3 s settling at ~2 beats a second.
        let correction = max(-0.01, min(0.01, 0.3 * e + 0.08 * phaseIntegral))
        inc.timePitch.rate = Float(baseRatio * (1 + correction))
    }

    // MARK: Timing

    /// Host time and beat index of the outgoing deck's next multiple of `every` beats.
    public func hostTime(ofNextBoundary every: Double) -> (UInt64, Double)? {
        let out = decks[outgoing]
        guard let g = out.grid, let p = out.position(), p.renderTime.isHostTimeValid else { return nil }
        let beat = g.beat(atSeconds: p.seconds)
        let target = (floor(beat / every) + 1) * every
        let wallSeconds = (target - beat) * g.secondsPerBeat / Double(out.timePitch.rate)
        return (p.renderTime.hostTime + AVAudioTime.hostTime(forSeconds: wallSeconds), target)
    }

    /// Current beat on the outgoing deck.
    public func outgoingBeat() -> Double? { decks[outgoing].currentBeat() }

    /// Runs a block on the main queue at a host time.
    private func at(hostTime host: UInt64, _ block: @escaping () -> Void) {
        let now = mach_absolute_time()
        let delay = host > now ? AVAudioTime.seconds(forHostTime: host - now) : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }
}
