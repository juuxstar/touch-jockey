// Handoff coach test: scores synthetic handoffs (clean, sloppy, ran out, a free bass swap's
// offset) and checks SkillProgress unlocks and storage. No audio; runs instantly.
// Run with scripts/coach_test.sh (builds first).
import Foundation
import TJCore
var failures = 0
func check(_ l: String, _ c: Bool) { if !c { failures += 1 }; print("  \(c ? "ok  " : "FAIL") \(l)") }
func run(_ timing: SkillLevel, entry: Double, _ lanes: (Double) -> [Band: Double], until end: Double, ranOut: Bool = false) -> HandoffReport {
    var c = HandoffCoach(); c.begin(entryBeat: entry, timing: timing)
    var b = entry
    while b < end { c.sample(beat: b, progress: lanes(b), secondsPerBeat: 0.5); b += 0.0625 }
    return (ranOut ? c.ranOut(atBeat: end) : c.finish(atBeat: end))!
}
func ramp(_ b: Double, _ from: Double, _ to: Double) -> Double { min(1, max(0, (b - from) / (to - from))) }

print("clean handoff (snap)")
var r = run(.snap, entry: 320, { b in [.high: ramp(b, 336, 352), .mid: ramp(b, 344, 360), .low: b >= 384 ? 1 : 0] }, until: 388)
for c in r.checks { print("     \(c.passed ? "+" : "-") \(c.title): \(c.detail)") }
check("clean", r.clean)
check("blend about 13 bars (\(r.blendBars))", abs(r.blendBars - 13) < 0.3)
check("no bass overlap", r.bassOverlapBars == 0)

print("sloppy handoff")
r = run(.snap, entry: 324, { b in [.high: ramp(b, 340, 342), .mid: ramp(b, 340, 342), .low: ramp(b, 350, 370)] }, until: 372)
for c in r.checks { print("     \(c.passed ? "+" : "-") \(c.title): \(c.detail)") }
check("entry off phrase", !r.checks[0].passed)
check("bass swap off phrase", !r.checks[1].passed)
check("overlap about 3 bars (\(r.bassOverlapBars))", abs(r.bassOverlapBars - 3) < 0.1)
check("blend short", !r.checks[3].passed)

print("ran out")
r = run(.snap, entry: 320, { b in [.high: ramp(b, 336, 352), .mid: 0, .low: 0] }, until: 400, ranOut: true)
check("not finished, no bass swap", !r.checks[4].passed && !r.checks[1].passed && !r.clean)

print("free timing offset")
r = run(.free, entry: 320, { b in [.high: ramp(b, 330, 350), .mid: ramp(b, 330, 350), .low: b >= 384.05 ? 1 : 0] }, until: 388)
check("bass swap 25 ms late (\(r.bassSwapOffsetMs ?? -1))", abs((r.bassSwapOffsetMs ?? 0) - 25) < 16)

print("progress")
var p = SkillProgress()
let clean = run(.snap, entry: 320, { b in [.high: ramp(b, 336, 352), .mid: ramp(b, 344, 360), .low: b >= 384 ? 1 : 0] }, until: 388)
var got: [SkillProgress.Unlock] = []
for _ in 0..<4 { got += p.record(clean) }
check("locked after 4", !p.allows(.free) && got.isEmpty)
_ = p.record(r)   // a handoff that may not be clean: counted, but not towards unlocks unless clean
got = p.record(clean)
check("free unlocked after 5 clean (\(p.cleanHandoffs))", p.allows(.free) && (got == [.freeTiming] || p.cleanHandoffs == 6))
for _ in 0..<5 { got += p.record(clean) }
check("cue unlocked by 10", p.isUnlocked(.cue))
let q = SkillProgress(dictionary: p.dictionary)
check("round-trips through storage", q == p)
var fresh = SkillProgress(); fresh.unlockEverything = true
check("unlock everything", fresh.allows(.free) && fresh.isUnlocked(.cue))
print(failures == 0 ? "\nall ok" : "\n\(failures) FAILED"); exit(failures == 0 ? 0 : 1)
