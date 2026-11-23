// Muted engine test for speakers + headphones: the cue sends, the cue mix, and the router that
// puts the speaker mix on channels 1–2 and the headphone mix on the headphones' channels.
//
// Uses the first output device that isn't the speakers as the headphones (an aggregate device is
// made for the test and removed after). The main mixer is muted, so nothing is heard; levels are
// read from a tap on the router's output. Run with scripts/outputs_test.sh (builds first).
import AVFoundation
import TJCore

setbuf(stdout, nil)
print("init")
let mix = MixEngine()
print("engine made")
mix.engine.mainMixerNode.outputVolume = 0
try! mix.start()
func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
var failures = 0
func check(_ label: String, _ cond: Bool) { print(cond ? "  ok   \(label)" : "  FAIL \(label)"); if !cond { failures += 1 } }

let M = NSHomeDirectory() + "/Music/serenity/"
var loaded = 0
mix.load(url: URL(fileURLWithPath: M + "HUGEL/Movin' to the Sun (2026)/HUGEL - Movin' to the Sun - 01 - Movin' to the Sun.mp3"), into: 0) { _ in loaded += 1 }
mix.load(url: URL(fileURLWithPath: M + "CamelPhat/Cola (2017)/CamelPhat - Cola - 01 - Cola.mp3"), into: 1) { _ in loaded += 1 }
while loaded < 2 { wait(0.1) }

let devs = AudioOutputs.devices()
print("outputs:", devs.map { "\($0.name) (\($0.channels))" }.joined(separator: ", "))
let spkID = AudioOutputs.defaultOutput()
guard let hp = devs.first(where: { $0.id != spkID && !$0.name.contains("Multi-Output") && $0.channels >= 2 }) else {
    print("no second output device: skipped"); exit(0)
}
print("headphones for the test:", hp.name)

/// Peak level per router output channel over `seconds`.
func levels(_ seconds: Double) -> [Float] {
    var peaks: [Float] = []
    let node = mix.routerNode
    node.installTap(onBus: 0, bufferSize: 2048, format: nil) { buf, _ in
        let n = Int(buf.format.channelCount)
        if peaks.count < n { peaks = [Float](repeating: 0, count: n) }
        for c in 0..<n { let d = buf.floatChannelData![c]; for i in 0..<Int(buf.frameLength) { peaks[c] = max(peaks[c], abs(d[i])) } }
    }
    wait(seconds)
    node.removeTap(onBus: 0)
    return peaks
}

print("\n1. Headphones join the speakers")
check("setOutputs succeeds", mix.setOutputs(speakers: nil, headphones: hp.uid))
mix.engine.mainMixerNode.outputVolume = 0
check("headphones active", mix.hasHeadphones)
let ch = Int(mix.hardwareFormat.channelCount)
let h = (mix.speakers?.channels ?? 2)
print("   output channels: \(ch), headphones from channel \(h + 1)")
check("four or more channels", ch >= 4)
wait(1.5)   // the device switch settles: the engine re-announces the hardware and gets wired again
check("still four channels all the way to the device", mix.engine.mainMixerNode.outputFormat(forBus: 0).channelCount >= 4
      && mix.engine.outputNode.inputFormat(forBus: 0).channelCount >= 4)

print("\n2. Speaker mix on 1–2 only; nothing cued → headphones carry only the speaker mix")
mix.seek(deck: 0, toBeat: 64)
mix.play(deck: 0)
mix.setCueMix(0)   // cue only
wait(0.5)
var p = levels(1.0)
print("   peaks:", p.map { String(format: "%.3f", $0) })
check("speakers playing", p.count >= 2 && p[0] > 0.01 && p[1] > 0.01)
check("headphones silent (cue only, nothing cued)", p.count > h + 1 && p[h] < 0.001 && p[h + 1] < 0.001)

print("\n3. Cue deck A → headphones")
mix.setCue(deck: 0, true)
wait(0.3)
p = levels(1.0)
print("   peaks:", p.map { String(format: "%.3f", $0) })
check("headphones carry deck A", p[h] > 0.01 && p[h + 1] > 0.01)

print("\n4. Cue B (stopped) only, cue mix at speaker side → headphones hear the speaker mix")
mix.setCue(deck: 0, false); mix.setCue(deck: 1, true); mix.setCueMix(1)
wait(0.3)
p = levels(1.0)
check("headphones carry the speaker mix", p[h] > 0.01)
mix.setCueMix(0)
wait(0.3)
p = levels(1.0)
check("cue side: B is stopped, so silence", p[h] < 0.001)

print("\n5. A cued deck is heard in the headphones even when silent in the speakers")
mix.setLane(.low, 1); mix.setLane(.mid, 1); mix.setLane(.high, 1)   // all lanes to B: A silent in the speakers
mix.setCue(deck: 1, false); mix.setCue(deck: 0, true)
wait(0.4)
p = levels(1.0)
print("   peaks:", p.map { String(format: "%.3f", $0) })
check("speakers: A gone", p[0] < 0.01)
check("headphones: A there", p[h] > 0.01)

print("\n6. Back to the speakers only")
mix.stopAll()
check("setOutputs back to default", mix.setOutputs(speakers: nil, headphones: nil))
check("no headphones", !mix.hasHeadphones)
check("two channels again", mix.hardwareFormat.channelCount <= 2)

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
