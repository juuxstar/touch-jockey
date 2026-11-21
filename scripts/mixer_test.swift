// Muted engine test for the mixer layer: EQ, channel faders, crossfader and handoff lanes.
//
// Reads back the band mixer node volumes (lane × EQ) and the deck output volumes
// (fader × crossfader), and checks that a handoff still finishes on the lanes alone.
// Needs two tracks in ~/Music/serenity. Run with scripts/mixer_test.sh (builds first).
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

func check(_ label: String, _ got: Float, _ want: Double) {
    let ok = abs(Double(got) - want) < 0.001
    if !ok { failures += 1 }
    print("  \(ok ? "ok  " : "FAIL") \(label.padding(toLength: 22, withPad: " ", startingAt: 0)) \(String(format: "%.4f", got))  (want \(String(format: "%.4f", want)))")
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

let s = sqrt(0.5)               // equal-power midpoint, cos(π/4)
let plus6 = pow(10, 6.0 / 20)   // +6 dB
let minus15 = pow(10, -15.0 / 20)

gains("1. Defaults: lanes on A, EQ at unity, faders full, crossfader centred")
check("A low", A.bandGain(.low), 1); check("B low", B.bandGain(.low), 0)
check("A out", A.outputGain, 1); check("B out", B.outputGain, 1)

mix.setLane(.high, 0.5)
gains("2. HIGH lane half-way (equal power)")
check("A high", A.bandGain(.high), s); check("B high", B.bandGain(.high), s)

mix.setEQ(deck: 0, band: .high, 0)
gains("3. Kill A's HIGH EQ: lane × 0 = silent, B untouched")
check("A high", A.bandGain(.high), 0); check("B high", B.bandGain(.high), s)

mix.setEQ(deck: 1, band: .high, 1)
gains("4. Boost B's HIGH EQ to the top (+6 dB): lane × 1.995")
check("B high", B.bandGain(.high), s * plus6)

mix.setEQ(deck: 1, band: .mid, 0.25)
gains("5. B's MID EQ at a quarter (−15 dB), MID lane still on A")
check("B mid (lane 0)", B.bandGain(.mid), 0)
mix.setLane(.mid, 1)
gains("   ... MID lane moved to B")
check("B mid (lane 1)", B.bandGain(.mid), minus15); check("A mid (lane 1)", A.bandGain(.mid), 0)

mix.setVolume(deck: 0, 0.5)
gains("6. A's channel fader half-way (squared taper → 0.25)")
check("A out", A.outputGain, 0.25); check("B out", B.outputGain, 1)

mix.setCrossfader(0.75)
gains("7. Crossfader three-quarters to B: A × cos(π/4), B full")
check("A out", A.outputGain, 0.25 * s); check("B out", B.outputGain, 1)
mix.setCrossfader(0.25)
gains("   ... a quarter (towards A): A full × fader, B × sin(π/4)")
check("A out", A.outputGain, 0.25); check("B out", B.outputGain, s)
mix.setCrossfader(0)
check("xfade 0: B out", B.outputGain, 0)
mix.setCrossfader(1)
check("xfade 1: A out", A.outputGain, 0)
mix.setCrossfader(-3); check("xfade clamps to 0", mix.crossfader == 0)
mix.setEQ(deck: 0, band: .low, 7); check("EQ clamps to 1", mix.eq[0][.low] == 1)

// Reset the mixer, then show the handoff finishes on the lanes alone.
for d in 0..<2 { for b in Band.allCases { mix.setEQ(deck: d, band: b, 0.5) }; mix.setVolume(deck: d, 1) }
mix.setCrossfader(0.5)
mix.backToStable()
print("\n8. Handoff A → B with the crossfader hard on A and B's fader down")
mix.play(deck: 0); wait(1); mix.cueIncoming(every: 4); wait(2.5)
check("A and B playing", A.isPlaying && B.isPlaying)
mix.setCrossfader(0); mix.setVolume(deck: 1, 0)
check("B silent by faders (out 0)", B.outputGain == 0)
for b in Band.allCases { mix.setLane(b, 1) }
wait(2.5)
check("roles swapped: outgoing = B", mix.outgoing == 1)
check("A stopped", !A.isPlaying)
check("lanes stayed on B", Band.allCases.allSatisfy { mix.lanes[$0] == 1 })
check("mixer untouched by the swap", mix.crossfader == 0 && mix.volumes[1] == 0)

print("\n9. Mixer alone never finishes a handoff: B → A with the crossfader on A, lanes on B")
mix.setCrossfader(0); mix.setVolume(deck: 1, 1); mix.setVolume(deck: 0, 1)
mix.cueIncoming(every: 4); wait(5)
check("still outgoing = B", mix.outgoing == 1)

mix.stopAll()
check("Stop all keeps the mixer", mix.crossfader == 0)

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
