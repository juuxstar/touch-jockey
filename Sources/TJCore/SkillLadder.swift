import Foundation

/// The learning ladder: how much of real DJing the user does by hand, one technique at a time.
///
/// Touch Jockey starts a beginner on simplified controls. Each **technique** (how to
/// blend, when a bass swap lands, how tempo is matched) has a ladder of **levels**,
/// from the simplest to the real thing. When the user has mastered a technique they
/// step it up, and the simplified control is swapped for the real one; they can step
/// back down at any time. The techniques are independent, so someone can mix on the
/// full mixer while bass swaps still snap to the bar.
///
/// To add a level, add a `SkillLevel` case in ladder order (lowest first) and name its
/// technique; to add a technique, add a `Technique` case too. The app then needs the
/// level's text in Settings, and the engine whatever behaviour the level changes.
public enum Technique: String, CaseIterable, Codable {
    /// How two tracks are blended.
    case blend
    /// When a Flick (a bass swap) lands.
    case timing
    /// How the incoming track's tempo is matched to the master's.
    case tempo
    /// How much the waveform shows: its loudness, or which frequencies are playing too.
    case waveform

    /// This technique's levels, lowest (most help) first.
    public var levels: [SkillLevel] { SkillLevel.allCases.filter { $0.technique == self } }
    /// Where a beginner starts.
    public var beginner: SkillLevel { levels[0] }
}

/// One rung of a technique's ladder. Cases are in ladder order within each technique.
public enum SkillLevel: String, CaseIterable, Codable {
    /// Blend: the phone's three handoff lanes move the bands from one deck to the other.
    case handoff
    /// Blend: a conventional mixer, per-deck EQ, channel faders and a crossfader.
    case mixer
    /// Timing: a Flick lands on the outgoing deck's next bar.
    case snap
    /// Timing: a Flick lands the moment you flick (with a short ramp so it doesn't click).
    case free
    /// Tempo: SYNC matches tempo and beat. Beat-matching by ear comes later.
    case sync
    /// Waveform: one colour per deck; height is loudness, the bright core the bass.
    case single
    /// Waveform: coloured by frequency, as in club DJ software (bass red, mids green, highs blue).
    case spectrum

    public var technique: Technique {
        switch self {
        case .handoff, .mixer: return .blend
        case .snap, .free: return .timing
        case .sync: return .tempo
        case .single, .spectrum: return .waveform
        }
    }

    /// Position on its technique's ladder, 0 = beginner.
    public var rung: Int { technique.levels.firstIndex(of: self) ?? 0 }
}

/// The user's level on every technique.
public struct SkillLadder: Equatable {
    private var levels: [Technique: SkillLevel]

    /// Everything at beginner level.
    public init() {
        levels = Dictionary(uniqueKeysWithValues: Technique.allCases.map { ($0, $0.beginner) })
    }

    /// From the stored or broadcast form, `{"blend": "mixer", …}`. Unknown or missing
    /// entries fall back to the beginner level, so old saved settings keep working.
    public init(dictionary: [String: String]) {
        self.init()
        for (k, v) in dictionary {
            if let t = Technique(rawValue: k), let l = SkillLevel(rawValue: v), l.technique == t { levels[t] = l }
        }
    }

    /// `{"blend": "handoff", "timing": "snap", "tempo": "sync", "waveform": "single"}`, for UserDefaults and the state broadcast.
    public var dictionary: [String: String] {
        Dictionary(uniqueKeysWithValues: levels.map { ($0.key.rawValue, $0.value.rawValue) })
    }

    public subscript(_ t: Technique) -> SkillLevel {
        get { levels[t] ?? t.beginner }
        set { if newValue.technique == t { levels[t] = newValue } }
    }

    /// Puts that level's technique on that level.
    public mutating func set(_ level: SkillLevel) { levels[level.technique] = level }

    /// One rung up or down (`by: 1` / `by: -1`), staying on the ladder.
    public mutating func step(_ t: Technique, by delta: Int) {
        let ls = t.levels
        let i = min(ls.count - 1, max(0, self[t].rung + delta))
        levels[t] = ls[i]
    }

    // Shorthands for the engine.
    public var blend: SkillLevel { self[.blend] }
    public var timing: SkillLevel { self[.timing] }
    public var tempo: SkillLevel { self[.tempo] }
    public var waveform: SkillLevel { self[.waveform] }
}
