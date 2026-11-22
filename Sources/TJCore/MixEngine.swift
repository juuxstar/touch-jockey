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
/// There is also a conventional two-channel mixer: per-deck EQ (high, mid, low), a
/// channel fader per deck and a crossfader. Which of the two blends depends on the
/// user's **blend** level on the `SkillLadder`:
///
/// - **Handoff** (beginner): the lanes drive the bands. The mixer is held neutral (EQ at
///   unity, faders full, crossfader centred) and ignores input. A handoff finishes when
///   every lane reaches the incoming side.
/// - **Mixer**: the lanes are bypassed and ignore input, so each band gain is that deck's
///   EQ gain. The roles swap when the outgoing deck stops or pauses while the incoming
///   deck plays, so the deck you hear becomes the master and SYNC keeps working.
///
///     band gain   = lane gain (handoff)  or  EQ gain (mixer)
///     deck volume = 1 (handoff)          or  channel fader gain × crossfader gain (mixer)
///
/// Switching level hands the current sound over to the other layer (see `setLadder`).
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

    /// The user's level on each technique (see `SkillLadder`). Beginner by default.
    public private(set) var ladder = SkillLadder()
    /// True when the user blends on the mixer rather than the handoff lanes.
    public var mixerMode: Bool { ladder.blend == .mixer }
    /// How long a Flick takes to land at the **free** timing level: short enough to feel
    /// instant, long enough not to click.
    public static let freeFlickRamp = 0.02
    /// Bumped per band to cancel a free Flick's ramp when the lane is moved again.
    private var rampGeneration: [Band: Int] = [:]

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
        checkMixerSwap()
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
        checkMixerSwap()
        onChange?()
    }

    /// CUE released: a preview stops and returns to the cue point.
    public func cueUp(deck i: Int) {
        guard previewing.remove(i) != nil else { return }
        let d = decks[i]
        d.stop()
        d.pausedBeat = nil
        if i == incoming { incomingStartBeat = nil }
        checkMixerSwap()
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

    /// Jog a stopped deck to a beat (it plays from there; CUE then sets the cue point there).
    /// Does nothing while the deck plays, so a jog can never knock a playing track out of sync.
    public func seek(deck i: Int, toBeat beat: Double) {
        let d = decks[i]
        guard let g = d.grid, !d.isPlaying else { return }
        d.pausedBeat = min(max(0, beat), g.beat(atSeconds: g.duration) - 1)
        onChange?()
    }

    /// Pause one deck, remembering its position.
    public func pause(deck i: Int) {
        let d = decks[i]
        guard d.isPlaying else { return }
        d.pausedBeat = d.currentBeat()
        d.stop()
        if i == incoming { incomingStartBeat = nil }
        checkMixerSwap()
        onChange?()
    }

    /// Stop one deck and return it to bar 1.
    public func stop(deck i: Int) {
        let d = decks[i]
        d.stop()
        d.pausedBeat = nil
        if i == incoming { incomingStartBeat = nil }
        checkMixerSwap()
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

    /// Moves a lane. Ignored at the **mixer** blend level, where the lanes are bypassed.
    public func setLane(_ band: Band, _ value: Double) {
        guard !mixerMode else { return }
        rampGeneration[band, default: 0] += 1   // a hand on the lane cancels a free Flick's ramp
        flickTokens.withLock { $0[band] = nil }  // … and a snapped Flick that hasn't landed yet
        moveLane(band, value)
    }

    private func moveLane(_ band: Band, _ value: Double) {
        guard !mixerMode else { return }
        lanes[band] = min(1, max(0, value))
        applyGains()
        checkFinish()
        onChange?()
    }

    /// A flick: the band jumps to `target` (0 = A, 1 = B). At the **snap** timing level it
    /// lands exactly on the outgoing deck's next bar; at **free** it lands now, over a
    /// `freeFlickRamp` ramp so it doesn't click. Ignored at the mixer blend level.
    public func flick(_ band: Band, to target: Double) {
        guard !mixerMode else { return }
        if ladder.timing == .free { rampLane(band, to: target, over: Self.freeFlickRamp); return }
        guard let timing = heardTime(ofNextBoundary: 4) else { setLane(band, target); return }
        // The gains are set on a precise timer thread, exactly at the bar (less the render lead);
        // the lane state catches up on the main queue just after. A hand on the lane before then
        // (`setLane`, which bumps the generation) cancels the flick.
        rampGeneration[band, default: 0] += 1
        let gen = rampGeneration[band] ?? 0
        let lead = timing.lead
        let token = flickTokens.withLock { t -> Int in t[band] = gen; return gen }
        let a = Float(cos(target * .pi / 2)), b = Float(sin(target * .pi / 2))
        let deckA = decks[0], deckB = decks[1]
        atPrecise(hostTime: timing.host, lead: lead) { [weak self] in
            guard let self, self.flickTokens.withLock({ $0[band] == token }) else { return }
            deckA.setGain(a, band: band)
            deckB.setGain(b, band: band)
            DispatchQueue.main.async {
                guard self.rampGeneration[band] == gen else { return }
                self.moveLane(band, target)
            }
        }
    }

    /// The flick each band is waiting to land (its generation). Read on the timing thread.
    private let flickTokens = Locked<[Band: Int]>([:])

    /// Moves a lane to `target` in a few steps over `seconds`.
    private func rampLane(_ band: Band, to target: Double, over seconds: Double) {
        let from = lanes[band] ?? 0
        rampGeneration[band, default: 0] += 1
        let gen = rampGeneration[band]
        let steps = 5
        for k in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds * Double(k) / Double(steps)) { [weak self] in
                guard let self, self.rampGeneration[band] == gen else { return }
                self.moveLane(band, from + (target - from) * Double(k) / Double(steps))
            }
        }
    }

    /// Back to the last stable mix: everything on the outgoing deck. Ignored at the mixer level.
    public func backToStable() {
        guard !mixerMode else { return }
        for b in Band.allCases { lanes[b] = laneEnd(forDeck: outgoing); rampGeneration[b, default: 0] += 1 }
        applyGains()
        onChange?()
    }

    private func applyGains() {
        let mixer = mixerMode
        for b in Band.allCases {
            let x = lanes[b] ?? 0
            // Handoff: the lanes, equal power (A = cos, B = sin). Mixer: the lanes are bypassed.
            let lane = mixer ? [1.0, 1.0] : [cos(x * .pi / 2), sin(x * .pi / 2)]
            for i in 0..<2 {
                let eqG = mixer ? Self.eqGain(eq[i][b] ?? 0.5) : 1
                decks[i].setGain(Float(lane[i] * eqG), band: b)
            }
        }
        // Handoff: the mixer is held neutral, so both decks are at full volume.
        let xf = mixer ? Self.crossfaderGains(crossfader) : (a: 1.0, b: 1.0)
        decks[0].setVolume(Float((mixer ? Self.faderGain(volumes[0]) : 1) * xf.a))
        decks[1].setVolume(Float((mixer ? Self.faderGain(volumes[1]) : 1) * xf.b))
    }

    // MARK: Skill ladder

    /// Puts one technique on a level (see `SkillLadder`).
    public func setLevel(_ level: SkillLevel) {
        var next = ladder
        next.set(level)
        setLadder(next)
    }

    /// Changes the user's levels. Changing the **blend** level hands the current sound
    /// over to the other layer, so nothing jumps:
    ///
    /// - **Handoff → mixer**: each deck's EQ is set to the gain its lane was giving that
    ///   band (a lane on A gives A unity and B a kill; half-way gives both −3 dB). Faders
    ///   stay full and the crossfader centred, as the handoff held them. Gains below the
    ///   EQ's lowest step (about −29 dB) round to a kill or that step.
    /// - **Mixer → handoff**: each lane is set to the balance between the decks the mixer
    ///   was giving that band (EQ × fader × crossfader), counting only decks that are
    ///   playing. A lane can only hold equal power, so a band turned down on both decks
    ///   comes back to full level; the balance between A and B is what's kept. A band that
    ///   is silent on every playing deck goes to a stopped deck's side, so it stays silent
    ///   (or to the outgoing side if nothing is playing). Then the mixer resets to neutral.
    public func setLadder(_ next: SkillLadder) {
        let wasMixer = mixerMode
        ladder = next
        if wasMixer != mixerMode {
            for b in Band.allCases { rampGeneration[b, default: 0] += 1 }
            if mixerMode { handOverToMixer() } else { handOverToLanes() }
        }
        applyGains()
        if !mixerMode { checkFinish() }
        checkMixerSwap()
        onChange?()
    }

    private func handOverToMixer() {
        for b in Band.allCases {
            let x = lanes[b] ?? 0
            eq[0][b] = Self.eqPosition(forGain: cos(x * .pi / 2))
            eq[1][b] = Self.eqPosition(forGain: sin(x * .pi / 2))
        }
        volumes = [1, 1]
        crossfader = 0.5
    }

    private func handOverToLanes() {
        let xf = Self.crossfaderGains(crossfader)
        let deckGain = [Self.faderGain(volumes[0]) * xf.a, Self.faderGain(volumes[1]) * xf.b]
        let silentSide = decks.indices.first { !decks[$0].isPlaying } ?? outgoing
        for b in Band.allCases {
            let g = (0..<2).map { decks[$0].isPlaying ? Self.eqGain(eq[$0][b] ?? 0.5) * deckGain[$0] : 0 }
            if g[0] + g[1] > 1e-6 {
                lanes[b] = atan2(g[1], g[0]) / (.pi / 2)
            } else {
                lanes[b] = laneEnd(forDeck: decks.contains { $0.isPlaying } ? silentSide : outgoing)
            }
        }
        eq = [[.low: 0.5, .mid: 0.5, .high: 0.5], [.low: 0.5, .mid: 0.5, .high: 0.5]]
        volumes = [1, 1]
        crossfader = 0.5
    }

    /// At the mixer level, the deck you hear is the master: when the outgoing deck has
    /// stopped or paused and the incoming one plays, they swap roles.
    private func checkMixerSwap() {
        guard mixerMode, !decks[outgoing].isPlaying, decks[incoming].isPlaying else { return }
        outgoing = incoming
        incomingStartBeat = nil
        phaseIntegral = 0
        finishScheduled = false
    }

    // MARK: Mixer (EQ, channel faders, crossfader)

    /// Sets one EQ control, 0...1 (0 = kill, 0.5 = unity, 1 = +6 dB). Ignored at the handoff level.
    public func setEQ(deck i: Int, band: Band, _ value: Double) {
        guard mixerMode, decks.indices.contains(i) else { return }
        eq[i][band] = min(1, max(0, value))
        applyGains()
        onChange?()
    }

    /// Sets a channel fader, 0...1 (1 = full). Ignored at the handoff level.
    public func setVolume(deck i: Int, _ value: Double) {
        guard mixerMode, decks.indices.contains(i) else { return }
        volumes[i] = min(1, max(0, value))
        applyGains()
        onChange?()
    }

    /// Sets the crossfader, 0 (A) ... 0.5 (both full) ... 1 (B). Ignored at the handoff level.
    public func setCrossfader(_ value: Double) {
        guard mixerMode else { return }
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

    /// Linear gain → the EQ position that gives it (the inverse of `eqGain`). Gains above
    /// +6 dB clamp to the top; gains below the lowest step above the kill (about −29 dB)
    /// round to that step or, below half of it, to the kill.
    public static func eqPosition(forGain g: Double) -> Double {
        if g >= 1 { return min(1, 0.5 + 0.5 * (20 * log10(g)) / eqMaxBoost) }
        let lowest = 0.021
        if g < eqGain(lowest) { return g < eqGain(lowest) / 2 ? 0 : lowest }
        return max(lowest, 0.5 * (1 + 20 * log10(g) / eqCutRange))
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
              let timing = heardTime(ofNextBoundary: 4) else { return }
        finishScheduled = true
        // The old track stops as the next bar is heard.
        Self.fire(at: timing.host, lead: timing.lead, on: .main) {
            self.finishScheduled = false
            guard !self.mixerMode, self.allOnIncoming else { return }
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
        if mixerMode, !decks[outgoing].isPlaying, decks[incoming].isPlaying { checkMixerSwap(); onChange?() }
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

    /// When the outgoing deck's next boundary is **heard**, as a true system-clock host time, and
    /// how early a gain change must be made to land on it: (host, lead seconds, target beat).
    ///
    /// Not `hostTime(ofNextBoundary:)`: a 44.1 kHz player's render timestamps drift against the
    /// system clock (about 1.5 ms a second, measured) when the output runs at 48 kHz. That's fine
    /// for `AVAudioPlayerNode.play(at:)`, which uses the same drifting clock, but timers need the
    /// real one. The output node's timestamps are true: each is when that buffer is heard.
    /// The time-stretcher delays the sound by its own latency, so the bar is heard that much later.
    func heardTime(ofNextBoundary every: Double) -> (host: UInt64, lead: Double, beat: Double)? {
        let out = decks[outgoing]
        guard let g = out.grid, let p = out.position(),
              let o = engine.outputNode.lastRenderTime, o.isHostTimeValid else { return nil }
        let beat = g.beat(atSeconds: p.seconds)
        let target = (floor(beat / every) + 1) * every
        let wall = (target - beat) * g.secondsPerBeat / Double(out.timePitch.rate) + out.timePitch.latency
        // A change made now is heard from the next buffer on: as far ahead as the last buffer
        // was rendered of being heard.
        let now = mach_absolute_time()
        let ahead = o.hostTime > now ? AVAudioTime.seconds(forHostTime: o.hostTime - now) : 0
        return (o.hostTime + AVAudioTime.hostTime(forSeconds: wall), ahead + renderLead, target)
    }

    /// Current beat on the outgoing deck.
    public func outgoingBeat() -> Double? { decks[outgoing].currentBeat() }

    /// Runs a block on the timing thread `lead` seconds before `host` (see `heardTime`).
    /// Only touch thread-safe things in the block (node volumes); hop to main for state.
    private func atPrecise(hostTime host: UInt64, lead: Double, _ block: @escaping () -> Void) {
        Self.fire(at: host, lead: lead, on: Self.timingQueue, block)
    }

    private static let timingQueue = DispatchQueue(label: "tj.timing", qos: .userInteractive)

    /// `asyncAfter` lets the system move a timer by up to ~10% of its delay (100+ ms on a bar), so
    /// beat-timed actions use a strict timer source with no leeway instead.
    private static func fire(at host: UInt64, lead: Double, on queue: DispatchQueue, _ block: @escaping () -> Void) {
        let now = mach_absolute_time()
        let delay = max(0, (host > now ? AVAudioTime.seconds(forHostTime: host - now) : 0) - lead)
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now() + delay, leeway: .nanoseconds(0))
        timer.setEventHandler {
            block()
            timer.setEventHandler(handler: nil)   // break the timer ↔ handler cycle
            timer.cancel()
        }
        timer.resume()
    }

    /// Extra lead (seconds) for beat-timed gain changes, on top of the measured render-ahead.
    /// Tuned with scripts/flick_timing.sh.
    public var renderLead: Double = 0
}

/// A value guarded by a lock, for state shared between the main and timing threads.
final class Locked<T> {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R { lock.lock(); defer { lock.unlock() }; return body(&value) }
}
