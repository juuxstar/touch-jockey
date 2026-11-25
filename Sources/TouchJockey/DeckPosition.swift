import SwiftUI
import TJCore

/// Where a deck is in its track: elapsed and remaining time, the bar and beat, how far
/// through the 8-bar phrase, and an overview of the whole track with a playhead.
/// Redrawn about 20 times a second from the engine, so it follows playback, jogs and cues.
///
/// While the deck is stopped, clicking or dragging the overview moves it there (snapped to a phrase line).
struct DeckPosition: View {
    let mix: MixEngine
    let deck: Int
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
            let _ = timeline.date
            content
        }
    }

    private struct Now {
        var seconds: Double, duration: Double, beat: Double, beatsTotal: Double
    }

    private var now: Now? {
        let d = mix.decks[deck]
        guard let g = d.grid else { return nil }
        let beat = d.shownBeat
        let s = min(max(g.seconds(atBeat: beat), 0), g.duration)
        return Now(seconds: s, duration: g.duration, beat: beat, beatsTotal: g.beat(atSeconds: g.duration))
    }

    @ViewBuilder private var content: some View {
        if let n = now {
            VStack(alignment: .leading, spacing: 6) {
                readouts(n)
                overview(n)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("–:––").font(.tj(20, weight: .semibold)).monospacedDigit().foregroundColor(TJ.mute.opacity(0.5))
                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35)).frame(height: 30)
            }
        }
    }

    // MARK: Readouts

    private func readouts(_ n: Now) -> some View {
        // Before the first downbeat the beat is negative: show bar 0 rather than a negative bar.
        let b = max(n.beat, 0)
        let bar = Int(floor(b / 4)) + 1
        let beatInBar = Int(floor(b)) % 4
        let barInPhrase = (bar - 1) % 8
        let barsLeft = max(0, Int(ceil((n.beatsTotal - b) / 4)))
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.clock(n.seconds)).font(.tj(20, weight: .semibold)).monospacedDigit()
                Text("−" + Self.clock(n.duration - n.seconds)).font(.tj(12.5, weight: .medium)).monospacedDigit()
                    .foregroundColor(TJ.mute)
            }
            .tip("**Time**: how far into the track, and how much is left.")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("BAR").font(.tj(10.5, weight: .heavy)).tracking(1).foregroundColor(color)
                Text("\(n.beat < 0 ? 0 : bar)").font(.tj(20, weight: .semibold)).monospacedDigit()
                beatDots(beatInBar)
                phraseBar(barInPhrase)
                Text("\(barsLeft) left").font(.tj(12.5, weight: .medium)).monospacedDigit().foregroundColor(TJ.mute)
            }
            .tip("**Bar and beat**: the four dots are the beats of this bar.\n\nThe **eight segments** are the bars of the current **phrase**. Dance tracks change every phrase, so start and swap things when it fills up.\n\n**Left**: bars until the track ends.")
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    private func beatDots(_ beat: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { k in
                Circle().fill(k == beat ? color : Color.white.opacity(0.14)).frame(width: 8, height: 8)
            }
        }
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
    }

    private func phraseBar(_ barInPhrase: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<8, id: \.self) { k in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(k <= barInPhrase ? color.opacity(k == barInPhrase ? 1 : 0.55) : Color.white.opacity(0.12))
                    .frame(width: 9, height: 6)
            }
        }
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3 }
        .padding(.leading, 4)
    }

    static func clock(_ s: Double) -> String {
        let t = max(0, Int(s.rounded(.down)))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    // MARK: Overview

    private func overview(_ n: Now) -> some View {
        let d = mix.decks[deck]
        let stopped = !d.isPlaying
        return GeometryReader { geo in
            Canvas { ctx, size in drawOverview(ctx, size, n) }
                .contentShape(Rectangle())
                .cursor(.pointingHand, enabled: stopped)
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    guard !mix.decks[deck].isPlaying, let grid = mix.decks[deck].grid else { return }
                    let f = min(max(g.location.x / max(geo.size.width, 1), 0), 1)
                    let beat = grid.beat(atSeconds: Double(f) * grid.duration)
                    // Snap to a phrase line, so two decks parked here start in phrase (Play all).
                    var phrase = (beat / 32).rounded() * 32
                    if phrase > grid.beat(atSeconds: grid.duration) - 1 { phrase -= 32 }
                    mix.seek(deck: deck, toBeat: max(0, phrase))
                })
        }
        .frame(height: 30)
        .tip(stopped ? "**Track overview**: the whole track, with the white line where the deck is.\n\nWhile the deck is stopped, **click or drag** here to move to another **phrase** (the faint lines). Drag the waveform above to fine-tune by the beat."
                     : "**Track overview**: the whole track, with the white line where the deck is. Faint lines mark every 8-bar **phrase**.")
    }

    private func drawOverview(_ ctx: GraphicsContext, _ size: CGSize, _ n: Now) {
        let d = mix.decks[deck]
        ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6), with: .color(.black.opacity(0.35)))
        guard let g = d.grid, let wf = d.waveform, n.duration > 0 else { return }
        let mid = size.height / 2, half = size.height / 2 - 3
        let step: CGFloat = 2
        let playX = CGFloat(n.seconds / n.duration) * size.width
        let spectrum = mix.ladder.waveform == .spectrum && !wf.mid.isEmpty
        var fullDone = Path(), lowDone = Path(), fullAhead = Path(), lowAhead = Path()
        var paintDone = SpectrumPainter(), paintAhead = SpectrumPainter()
        var x: CGFloat = 0
        while x < size.width {
            let s0 = Double(x / size.width) * n.duration, s1 = Double((x + step) / size.width) * n.duration
            let lv = wf.bands(from: s0, to: s1)
            let hf = CGFloat(lv.full) * half, hl = CGFloat(lv.low) * half
            let rf = CGRect(x: x, y: mid - hf, width: step - 0.5, height: hf * 2)
            let rl = CGRect(x: x, y: mid - hl, width: step - 0.5, height: hl * 2)
            if spectrum {
                if x < playX { paintDone.add(rf, low: lv.low, mid: lv.mid, high: lv.high) }
                else { paintAhead.add(rf, low: lv.low, mid: lv.mid, high: lv.high) }
            } else if x < playX { fullDone.addRect(rf); lowDone.addRect(rl) } else { fullAhead.addRect(rf); lowAhead.addRect(rl) }
            x += step
        }
        // Played part dimmed, the rest bright.
        if spectrum {
            paintDone.fill(ctx, opacity: 0.3)
            paintAhead.fill(ctx, opacity: 1)
        } else {
            ctx.fill(fullDone, with: .color(color.opacity(0.15)))
            ctx.fill(lowDone, with: .color(color.opacity(0.35)))
            ctx.fill(fullAhead, with: .color(color.opacity(0.35)))
            ctx.fill(lowAhead, with: .color(color.opacity(0.9)))
        }

        // A faint line at every phrase (32 beats).
        var b = 0.0
        while true {
            let s = g.seconds(atBeat: b)
            if s > n.duration { break }
            if s >= 0 {
                let px = CGFloat(s / n.duration) * size.width
                ctx.fill(Path(CGRect(x: px - 0.5, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.12)))
            }
            b += 32
        }

        // Cue point: a small gold flag at the top.
        let cueS = g.seconds(atBeat: d.cueBeat)
        if cueS >= 0, cueS <= n.duration {
            let cx = CGFloat(cueS / n.duration) * size.width
            var flag = Path()
            flag.move(to: CGPoint(x: cx - 4, y: 0)); flag.addLine(to: CGPoint(x: cx + 4, y: 0)); flag.addLine(to: CGPoint(x: cx, y: 6))
            flag.closeSubpath()
            ctx.fill(flag, with: .color(TJ.gold))
        }

        // Playhead.
        ctx.fill(Path(CGRect(x: playX - 1, y: 0, width: 2, height: size.height)), with: .color(.white))
    }
}
