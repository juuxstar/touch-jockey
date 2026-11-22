// Muted engine test for the blend levels of the skill ladder: the handoff lanes, the
// mixer (EQ, channel faders, crossfader), switching between them, the mixer's role swap,
// and Flick timing (snap to the bar, or free).
//
// Reads back the band mixer node volumes and the deck output volumes. Needs two tracks
// in ~/Music/serenity. Run with scripts/mixer_test.sh (builds first).
import Foundation
import TJCore

let mix = MixEngine()
mix.engine.mainMixerNode.outputVolume = 0
try! mix.start()
func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

let M = NSHomeDirectory() + "/Music/serenity/"
var loaded = 0
mix.load(url: URL(fileURLWithPath: M + "HUGEL/Movin' to the Sun (2026)/HUGEL - Movin' to the Sun - 01 - Movin' to the Sun.mp3"), into: 0) { r in
    if case .failure(let e) = r { print("load A failed: \(e)"); exit(2) }; loaded += 1 }
mix.load(url: URL(fileURLWithPath: M + "CamelPhat/Cola (2017)/CamelPhat - Cola - 01 - Cola.mp3"), into: 1) { r in
    if case .failure(let e) = r { print("load B failed: \(e)"); exit(2) }; loaded += 1 }
while loaded < 2 { wait(0.1) }

let A = mix.decks[0], B = mix.decks[1]
var failures = 0

func check(_ label: String, _ got: Float, _ want: Double, tol: Double = 0.001) {
    let ok = abs(Double(got) - want) < tol
    if !ok { failures += 1 }
    print("  \(ok ? "ok  " : "FAIL") \(label.padding(toLength: 34, withPad: " ", startingAt: 0)) \(String(format: "%.4f", got))  (want \(String(format: "%.4f", want)))")
}
func check(_ label: String, _ cond: Bool) {
    if !cond { failures += 1 }
    print("  \(cond ? "ok  " : "FAIL") \(label)")
}
func gains(_ title: String) {
    print("\n\(title)")
    let row = { (d: Deck) in Band.allCases.map { String(format: "%@ %.4f", $0.rawValue, d.bandGain($0)) }.joined(separator: "  ") + String(format: "  | out %.4f", d.outputGain) }
    print("  A: \(row(A))\n  B: \(row(B))")
}
/// Every gain the listener hears: per deck, each band × that deck's output.
func heard() -> [Float] { [A, B].flatMap { d in Band.allCases.map { d.bandGain($0) * d.outputGain } } }
func maxJump(_ a: [Float], _ b: [Float]) -> Float { zip(a, b).map { abs($0 - $1) }.max() ?? 0 }
func neutral() -> Bool {
    mix.eq.allSatisfy { $0.values.allSatisfy { $0 == 0.5 } } && mix.volumes == [1, 1] && mix.crossfader == 0.5
}
/// Polls until a lane leaves `from`; returns seconds taken (nil if it never moved).
func timeToMove(_ band: Band, from: Double, limit: Double = 3) -> Double? {
    let t0 = Date()
    while Date().timeIntervalSince(t0) < limit {
        if abs((mix.lanes[band] ?? 0) - from) > 1e-9 { return Date().timeIntervalSince(t0) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.002))
    }
    return nil
}

let s = sqrt(0.5)               // equal-power midpoint, cos(π/4)
let plus6 = pow(10, 6.0 / 20)   // +6 dB
let minus15 = pow(10, -15.0 / 20)

gains("1. Defaults: blend = handoff, timing = snap; lanes on A, mixer neutral")
check("ladder is beginner", mix.ladder.blend == .handoff && mix.ladder.timing == .snap && mix.ladder.tempo == .sync)
check("A low", A.bandGain(.low), 1); check("B low", B.bandGain(.low), 0)
check("A out", A.outputGain, 1); check("B out", B.outputGain, 1)

mix.setEQ(deck: 0, band: .high, 0); mix.setVolume(deck: 0, 0.2); mix.setCrossfader(1)
gains("2. Handoff: the mixer is held neutral and ignores eq / volume / xfade")
check("mixer still neutral", neutral())
check("A high (not killed)", A.bandGain(.high), 1); check("A out (not faded)", A.outputGain, 1)

mix.setLane(.high, 0.5); mix.setLane(.mid, 0.25)
gains("3. Handoff: lanes drive the bands (HIGH half-way, MID a quarter)")
check("A high", A.bandGain(.high), s); check("B high", B.bandGain(.high), s)
check("A mid", A.bandGain(.mid), cos(.pi / 8)); check("B mid", B.bandGain(.mid), sin(.pi / 8))

var before = heard()
mix.setLevel(.mixer)
gains("4. Switch to mixer: EQ takes over what the lanes were doing")
check("blend = mixer", mix.mixerMode)
check("largest jump in any gain", maxJump(before, heard()), 0, tol: 0.001)
check("B low EQ = kill (lane was on A)", mix.eq[1][.low] == 0)
check("A low EQ = unity", mix.eq[0][.low] == 0.5)
check("faders full, crossfader centred", mix.volumes == [1, 1] && mix.crossfader == 0.5)

before = heard()
mix.setLane(.high, 1); mix.flick(.low, to: 1); mix.backToStable(); wait(0.1)
gains("5. Mixer: lane / flick / stable are ignored, and the lanes are bypassed")
check("lanes unchanged", mix.lanes[.high] == 0.5 && mix.lanes[.low] == 0 && mix.lanes[.mid] == 0.25)
check("no gain changed", maxJump(before, heard()) == 0)
mix.setEQ(deck: 1, band: .high, 1)
check("B high at +6 dB (no lane factor)", B.bandGain(.high), plus6)
mix.setEQ(deck: 1, band: .low, 0.25)
check("B low at −15 dB (lane on A)", B.bandGain(.low), minus15)
mix.setEQ(deck: 0, band: .low, 0)
check("A low killed", A.bandGain(.low), 0)

mix.setVolume(deck: 0, 0.5)
gains("6. Mixer: A's fader half-way (squared taper → 0.25), then the crossfader")
check("A out", A.outputGain, 0.25); check("B out", B.outputGain, 1)
mix.setCrossfader(0.75)
check("xfade ¾ → A out", A.outputGain, 0.25 * s); check("xfade ¾ → B out", B.outputGain, 1)
mix.setCrossfader(0.25)
check("xfade ¼ → A out", A.outputGain, 0.25); check("xfade ¼ → B out", B.outputGain, s)
mix.setCrossfader(0); check("xfade 0: B out", B.outputGain, 0)
mix.setCrossfader(1); check("xfade 1: A out", A.outputGain, 0)
mix.setCrossfader(-3); check("xfade clamps to 0", mix.crossfader == 0)
mix.setEQ(deck: 0, band: .low, 7); check("EQ clamps to 1", mix.eq[0][.low] == 1)

print("\n7. Switch back to handoff while both decks play: the lanes take the mixer's balance")
for d in 0..<2 { for b in Band.allCases { mix.setEQ(deck: d, band: b, 0.5) }; mix.setVolume(deck: d, 1) }
mix.setCrossfader(0.5)
mix.play(deck: 0); wait(1); mix.cueIncoming(every: 4); wait(2.5)
check("A and B playing, outgoing = A", A.isPlaying && B.isPlaying && mix.outgoing == 0)
let pS = MixEngine.eqPosition(forGain: s)
mix.setEQ(deck: 0, band: .high, pS); mix.setEQ(deck: 1, band: .high, pS)   // HIGH: equal power, half each
mix.setEQ(deck: 1, band: .mid, MixEngine.eqPosition(forGain: 0.5))           // MID: B at −6 dB under A
mix.setEQ(deck: 1, band: .low, 0)                                           // LOW: B killed
let highBefore = [A.bandGain(.high) * A.outputGain, B.bandGain(.high) * B.outputGain]
gains("   mixer before")
mix.setLevel(.handoff)
gains("   handoff after")
check("blend = handoff", !mix.mixerMode)
check("HIGH unchanged (lane ½)", maxJump(highBefore, [A.bandGain(.high), B.bandGain(.high)]), 0, tol: 0.001)
check("MID keeps B:A = 0.5", B.bandGain(.mid) / A.bandGain(.mid), 0.5)
check("LOW stays on A", A.bandGain(.low) == 1 && B.bandGain(.low) == 0)
check("mixer back to neutral", neutral())
check("still outgoing = A, both playing", mix.outgoing == 0 && A.isPlaying && B.isPlaying)

print("\n8. Handoff: moving every lane to B finishes the handoff on the next bar")
for b in Band.allCases { mix.setLane(b, 1) }
wait(2.5)
check("roles swapped: outgoing = B", mix.outgoing == 1)
check("A stopped", !A.isPlaying)
check("lanes stayed on B", Band.allCases.allSatisfy { mix.lanes[$0] == 1 })

print("\n9. Flick timing: snap lands on the next bar, free lands now")
mix.flick(.low, to: 0)
// The swap lands where the bar is *heard*, so compare with the heard beat. (The lane state moves
// just after the gains; scripts/flick_timing.sh measures the gains to the sample.)
if let t = timeToMove(.low, from: 1), let beat = mix.decks[mix.outgoing].heardBeat() {
    let inBar = beat.truncatingRemainder(dividingBy: 4)
    print(String(format: "  snap: landed after %.3f s at heard beat %.3f (%.3f into the bar)", t, beat, inBar))
    check("snap lands on a bar line (±0.1 beat)", inBar < 0.1 || inBar > 3.9)
} else { check("snap flick landed", false) }
wait(0.1)
mix.setLevel(.free)
check("timing = free", mix.ladder.timing == .free)
let beatAtFlick = mix.outgoingBeat() ?? 0
mix.flick(.low, to: 1)
if let t = timeToMove(.low, from: 0) {
    print(String(format: "  free: started after %.3f s (beat %.3f, %.3f into the bar)", t, beatAtFlick, beatAtFlick.truncatingRemainder(dividingBy: 4)))
    check("free starts within 15 ms", t < 0.015)
} else { check("free flick moved", false) }
wait(0.06)
check("free reaches B within the ramp", mix.lanes[.low] == 1)
mix.setLevel(.snap)

print("\n10. Mixer: the roles swap when the outgoing deck stops or pauses")
mix.setLevel(.mixer)
mix.cueIncoming(every: 4); wait(2.5)
check("B outgoing, A playing too", mix.outgoing == 1 && A.isPlaying && B.isPlaying)
mix.pause(deck: 1)
check("pause B → A is the master", mix.outgoing == 0 && A.isPlaying && !B.isPlaying)
check("master clock usable for SYNC", mix.hostTime(ofNextBoundary: 1) != nil)
mix.play(deck: 1)
check("B resumes synced to A (start scheduled on A's beat)", mix.incomingStartBeat != nil && mix.outgoing == 0)
check("B's tempo follows A", abs((B.playingBPM ?? 0) - (A.playingBPM ?? 0)) < 0.5)
wait(2)
mix.stop(deck: 0)
check("stop A → B is the master", mix.outgoing == 1 && B.isPlaying)

mix.setCrossfader(0.2)
mix.stopAll()
check("Stop all keeps the mixer", mix.crossfader == 0.2)
check("ladder dictionary", mix.ladder.dictionary == ["blend": "mixer", "timing": "snap", "tempo": "sync"])
check("ladder round-trips", SkillLadder(dictionary: mix.ladder.dictionary) == mix.ladder)
var l = SkillLadder(); l.step(.blend, by: 5); l.step(.timing, by: -1)
check("step stays on the ladder", l.blend == .mixer && l.timing == .snap)

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
