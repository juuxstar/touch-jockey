import Foundation

/// How one handoff went: the checks a clean handoff passes, and what was measured.
///
/// A handoff is **clean** when it passes every check. Clean handoffs are how a beginner
/// shows they're ready for the next level (see `SkillProgress`).
public struct HandoffReport: Equatable {
    public struct Check: Equatable {
        public var title: String
        public var passed: Bool
        /// What was measured, in words: "on bar 65, 3 bars before a phrase line".
        public var detail: String
        /// For a missed check: what to try next time.
        public var advice: String? = nil
    }

    /// The checks in the order they happen in a handoff.
    public var checks: [Check]
    /// From the first lane leaving the old track to the last one reaching the new one, in bars.
    public var blendBars: Double
    /// How long both basslines played together, in bars.
    public var bassOverlapBars: Double
    /// At the **free** timing level: how far the bass swap landed from the nearest bar line,
    /// in milliseconds (negative = early). Nil at **snap**, where it always lands on the bar.
    public var bassSwapOffsetMs: Double?
    /// The timing level the handoff was done at.
    public var timing: SkillLevel

    public var clean: Bool { checks.allSatisfy(\.passed) }
}

/// Watches a handoff at the **handoff** blend level and scores it.
///
/// The engine feeds it: `begin` when the incoming track starts, `sample` on every lane move
/// and tick, then `finish` when the roles swap or `ranOut` when the old track ended first.
/// Everything is in the outgoing deck's beats, so it needs no audio and tests run instantly.
public struct HandoffCoach {
    /// A clean blend takes at least this many bars, from the first lane moving to the last arriving.
    public static let minBlendBars = 8.0
    /// Both basslines together for less than this many bars, or they sound muddy.
    public static let maxBassOverlapBars = 1.0
    /// How far (in beats) the incoming track's start may be from a phrase line and still count as on it.
    /// Next phrase starts it exactly on the line; this allows for a start by hand.
    public static let phraseTolerance = 1.0
    /// How far (in beats) the bass swap may be from a phrase line and still pass: a bar either way.
    /// Right on the line sounds tightest, and the scorecard says so, but a bar early is a common
    /// deliberate move (a bar of tension) and a bar late is not a train wreck.
    public static let bassSwapTolerance = 4.0
    /// A lane counts as moved once it is this far from the outgoing side, and as arrived this close to the incoming side.
    static let moved = 0.05
    /// The LOWS lane between these (as a fraction of the way over) means both basslines are clearly audible.
    static let overlapRange = 0.2...0.8

    /// The checks' titles, in the order the report lists them.
    public static let checkTitles = ["Came in on a phrase line", "Bass swap on a phrase line",
                                     "Basslines together under a bar", "Blend over 8 bars or more",
                                     "Finished before the track ran out"]

    public private(set) var active = false
    private var entryBeat = 0.0
    private var firstMoveBeat: Double?
    private var bassSwapBeat: Double?
    private var bassSwapOffsetMs: Double?
    private var overlapBeats = 0.0
    private var lastBeat: Double?
    private var lastLow = 0.0
    private var timing: SkillLevel = .snap

    public init() {}

    /// The incoming track has started, on the outgoing deck's beat `entryBeat`.
    public mutating func begin(entryBeat: Double, timing: SkillLevel) {
        self = HandoffCoach()
        active = true
        self.entryBeat = entryBeat
        self.timing = timing
    }

    /// Forget the handoff without a report (stopped, sent back to the old track, or the level changed).
    public mutating func cancel() { self = HandoffCoach() }

    /// The lanes at the outgoing deck's beat `beat`, each as progress from the old track (0)
    /// to the new one (1). `secondsPerBeat` converts a free bass swap's offset to milliseconds.
    public mutating func sample(beat: Double, progress: [Band: Double], secondsPerBeat: Double) {
        guard active else { return }
        let low = progress[.low] ?? 0
        if firstMoveBeat == nil, Band.allCases.contains(where: { (progress[$0] ?? 0) > Self.moved }) {
            firstMoveBeat = beat
        }
        if let last = lastBeat, beat > last {
            // Count the time since the last sample as overlap if the bass sat in the middle for it.
            if Self.overlapRange.contains(lastLow) || Self.overlapRange.contains(low) {
                overlapBeats += beat - last
            }
        }
        // The bass swap is the moment LOWS crosses half-way towards the new track. Moving it back
        // and over again counts the last crossing.
        if lastLow < 0.5, low >= 0.5 {
            bassSwapBeat = beat
            if timing == .free {
                let bar = (beat / 4).rounded() * 4
                bassSwapOffsetMs = (beat - bar) * secondsPerBeat * 1000
            }
        } else if low < 0.5 {
            bassSwapBeat = nil
            bassSwapOffsetMs = nil
        }
        lastLow = low
        lastBeat = beat
    }

    /// Every lane reached the new track and the old one stopped, at beat `beat`.
    public mutating func finish(atBeat beat: Double) -> HandoffReport? {
        report(endBeat: beat, finished: true)
    }

    /// The old track ended before the handoff finished, noticed at beat `beat`. `trackEndBeat`
    /// is where it ended, if known: at or before the entry means it was over before the new
    /// track even came in.
    public mutating func ranOut(atBeat beat: Double, trackEndBeat: Double? = nil) -> HandoffReport? {
        report(endBeat: beat, finished: false, endedBeforeEntry: trackEndBeat.map { $0 <= entryBeat } ?? false)
    }

    private mutating func report(endBeat: Double, finished: Bool, endedBeforeEntry: Bool = false) -> HandoffReport? {
        guard active else { return nil }
        defer { self = HandoffCoach() }
        func phraseDistance(_ b: Double) -> Double { abs(b - (b / 32).rounded() * 32) }
        func bar(_ b: Double) -> Int { Int(floor(b / 4)) + 1 }
        let blendBars = firstMoveBeat.map { max(0, endBeat - $0) / 4 } ?? 0
        let overlapBars = overlapBeats / 4

        var checks: [HandoffReport.Check] = []
        let entryOK = phraseDistance(entryBeat) <= Self.phraseTolerance
        checks.append(.init(title: Self.checkTitles[0], passed: entryOK,
                            detail: entryOK ? "Started on bar \(bar(entryBeat))."
                                            : "Started on bar \(bar(entryBeat)), in the middle of a phrase.",
                            advice: "Bring the new track in with Next phrase: it waits for the phrase line for you."))
        if let s = bassSwapBeat {
            let line = (s / 32).rounded() * 32               // the nearest phrase line
            let ok = phraseDistance(s) <= Self.bassSwapTolerance
            let barsOff = Int(((s - line) / 4).rounded())    // negative = early
            let off = barsOff == 0 ? "" : abs(barsOff) == 1 ? "a bar" : "\(abs(barsOff)) bars"
            let when = barsOff < 0 ? "early" : "late"
            checks.append(.init(title: Self.checkTitles[1], passed: ok,
                                detail: barsOff == 0 ? "Swapped on bar \(bar(s)), right on the phrase line."
                                      : ok ? "Swapped on bar \(bar(s)), \(off) \(when) for the phrase line at bar \(bar(line)). Close enough; right on the line sounds tightest."
                                      : "Swapped on bar \(bar(s)), \(off) \(when) for the phrase line at bar \(bar(line)).",
                                advice: timing == .free
                                    ? "Count the bars along with the music and flick LOWS on the ONE of a new phrase, a touch early rather than late."
                                    : "Wait until the phrase bar on the deck is nearly full, then flick LOWS during the last bar: the snap lands it right on the phrase line."))
        } else {
            checks.append(.init(title: Self.checkTitles[1], passed: false,
                                detail: "The bass never moved to the new track.",
                                advice: "Move LOWS all the way to the new track, on a phrase line. That's the bass swap."))
        }
        let overlapOK = overlapBars < Self.maxBassOverlapBars
        checks.append(.init(title: Self.checkTitles[2], passed: overlapOK,
                            detail: String(format: "Both basslines played for %@.", Self.bars(overlapBars)),
                            advice: "Swap the bass in one move: flick LOWS instead of sliding it, so the two basslines never play over each other."))
        let blendOK = blendBars >= Self.minBlendBars
        checks.append(.init(title: Self.checkTitles[3], passed: blendOK,
                            detail: String(format: "The blend took %@.", Self.bars(blendBars)),
                            advice: "Take your time: slide the highs, then the mids, across over a whole phrase (8 bars) or more before the bass swap."))
        checks.append(.init(title: Self.checkTitles[4], passed: finished,
                            detail: finished ? "The old track stopped on the bar after the last lane arrived."
                                  : endedBeforeEntry ? "The old track had already ended when the new one came in."
                                  : "The old track ended in the middle of the blend.",
                            advice: endedBeforeEntry
                                ? "Bring the new track in while the old one has a few phrases left. With less than a phrase to go, Next phrase waits for a line past its end."
                                : "Start sooner: bring the new track in at least four phrases before the old one ends. Go practice parks it there for you."))
        // Advice only where it's needed.
        for i in checks.indices where checks[i].passed { checks[i].advice = nil }
        return HandoffReport(checks: checks, blendBars: blendBars, bassOverlapBars: overlapBars,
                             bassSwapOffsetMs: bassSwapOffsetMs, timing: timing)
    }

    static func bars(_ b: Double) -> String {
        if b < 0.05 { return "no time at all" }
        let r = floor(b * 2) / 2   // down, so a check that just missed 8 bars never reads "8 bars"
        if r <= 0 { return "less than half a bar" }
        let n = r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
        return r == 1 ? "1 bar" : "\(n) bars"
    }
}

/// What the user has shown they can do, and which controls that has unlocked.
///
/// Touch Jockey starts everyone on the simplest controls. Clean handoffs (see `HandoffReport`)
/// unlock the next ones. **Unlock everything** is there for people who already DJ.
public struct SkillProgress: Equatable {
    /// Something that is locked until earned.
    public enum Unlock: String, CaseIterable, Codable {
        /// The **free** level of bass-swap timing.
        case freeTiming
        /// The CUE buttons: setting a cue point and previewing from it.
        case cue

        /// Clean handoffs needed to unlock it.
        public var cleanHandoffsNeeded: Int {
            switch self {
            case .freeTiming: return 5
            case .cue: return 10
            }
        }
    }

    public private(set) var cleanHandoffs = 0
    public private(set) var handoffs = 0
    public private(set) var earned: Set<Unlock> = []
    public var unlockEverything = false

    public init() {}

    public func isUnlocked(_ u: Unlock) -> Bool { unlockEverything || earned.contains(u) }

    /// Whether the user may choose a ladder level. Locked levels show their progress instead.
    public func allows(_ level: SkillLevel) -> Bool {
        level == .free ? isUnlocked(.freeTiming) : true
    }

    /// The unlock a ladder level waits for, if any.
    public static func unlock(for level: SkillLevel) -> Unlock? { level == .free ? .freeTiming : nil }

    /// Counts a handoff, and returns what it newly unlocked.
    public mutating func record(_ r: HandoffReport) -> [Unlock] {
        handoffs += 1
        guard r.clean else { return [] }
        cleanHandoffs += 1
        let new = Unlock.allCases.filter { !earned.contains($0) && cleanHandoffs >= $0.cleanHandoffsNeeded }
        earned.formUnion(new)
        return unlockEverything ? [] : new
    }

    /// Marks something as earned without the handoffs (for someone already on that level).
    public mutating func grant(_ u: Unlock) { earned.insert(u) }

    // MARK: Storage

    /// From the stored form (`{"cleanHandoffs": 3, "handoffs": 4, "earned": ["freeTiming"], "unlockEverything": false}`).
    public init(dictionary d: [String: Any]) {
        cleanHandoffs = d["cleanHandoffs"] as? Int ?? 0
        handoffs = d["handoffs"] as? Int ?? 0
        earned = Set((d["earned"] as? [String] ?? []).compactMap(Unlock.init(rawValue:)))
        unlockEverything = d["unlockEverything"] as? Bool ?? false
    }

    public var dictionary: [String: Any] {
        ["cleanHandoffs": cleanHandoffs, "handoffs": handoffs,
         "earned": earned.map(\.rawValue).sorted(), "unlockEverything": unlockEverything]
    }
}
