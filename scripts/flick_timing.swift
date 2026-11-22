// Measures, to the sample, how far from the bar (as heard) a snapped flick lands. Compiled
// together with the TJCore sources so it can tap a band's gain node. Needs the two test
// tracks in ~/Music/serenity. Run with scripts/flick_timing.sh [extra lead in ms].
import AVFoundation
let mix = MixEngine()
mix.engine.mainMixerNode.outputVolume = 0
if let l = CommandLine.arguments.dropFirst().first.flatMap(Double.init) { mix.renderLead = l / 1000 }
try! mix.start()
func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
let M = NSHomeDirectory() + "/Music/serenity/"
var loaded = 0
mix.load(url: URL(fileURLWithPath: M + "HUGEL/Movin' to the Sun (2026)/HUGEL - Movin' to the Sun - 01 - Movin' to the Sun.mp3"), into: 0) { _ in loaded += 1 }
mix.load(url: URL(fileURLWithPath: M + "CamelPhat/Cola (2017)/CamelPhat - Cola - 01 - Cola.mp3"), into: 1) { _ in loaded += 1 }
while loaded < 2 { wait(0.1) }
let A = mix.decks[0], B = mix.decks[1]
let node = B.bandGains[.low]!
var onset: Int64? = nil
let lock = NSLock()
node.installTap(onBus: 0, bufferSize: 512, format: nil) { buf, when in
    lock.lock(); defer { lock.unlock() }
    guard onset == nil, let ch = buf.floatChannelData?[0] else { return }
    for i in 0..<Int(buf.frameLength) where abs(ch[i]) > 1e-4 { onset = when.sampleTime + Int64(i); return }
}
mix.playOutgoing(); wait(1.0)
mix.cueIncoming(every: 4); wait(3.0)
print(String(format: "time-stretch latency A %.1f ms", A.timePitch.latency * 1000))
var results: [Double] = []
for trial in 0..<10 {
    mix.setLane(.low, 0); wait(0.3 + Double((trial * 7) % 10) * 0.19)
    lock.lock(); onset = nil; lock.unlock()
    // The bar as heard, in A's 44.1 kHz render timeline (sample maths only, no host clock).
    guard let rt = A.player.lastRenderTime, let p = A.position(), let g = A.grid else { continue }
    let beat = g.beat(atSeconds: p.seconds), target = (floor(beat / 4) + 1) * 4
    let sr = rt.sampleRate
    let bar = rt.sampleTime + Int64(((target - beat) * g.secondsPerBeat / Double(A.timePitch.rate) + A.timePitch.latency) * sr)
    mix.flick(.low, to: 1)
    wait(2.6)
    lock.lock(); let o = onset; lock.unlock()
    if let o { let ms = Double(o - bar) / sr * 1000; results.append(ms); print(String(format: "trial %d: landed %+.1f ms from the bar", trial, ms)) }
}
if !results.isEmpty { print(String(format: "mean %+.1f ms, range %+.1f … %+.1f ms", results.reduce(0,+)/Double(results.count), results.min()!, results.max()!)) }
exit(0)
