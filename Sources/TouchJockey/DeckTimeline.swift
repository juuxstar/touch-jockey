import SwiftUI
import TJCore

/// Both decks on one scrolling, beat-aligned timeline, redrawn every frame.
///
/// The playhead sits a third of the way in. Lines mark beats, bars and phrases
/// (8 bars) of the outgoing track. The incoming track is drawn where it will
/// play: at its scheduled start once cued, otherwise at the next phrase as a preview.
struct DeckTimeline: View {
    let mix: MixEngine
    var beatsVisible: Double = 48

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in draw(ctx, size) }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let out = mix.decks[mix.outgoing], inc = mix.decks[mix.incoming]
        let playX = size.width * 0.33
        let ppb = size.width / beatsVisible                 // pixels per beat
        let laneGap: CGFloat = 8
        let laneH = (size.height - laneGap) / 2

        let outNow = out.currentBeat() ?? 0
        // Incoming beat at this moment, on the outgoing deck's timeline.
        let startBeat: Double = {
            if let s = mix.incomingStartBeat { return s }
            if inc.isPlaying, let ib = inc.currentBeat() { return outNow - ib }
            return (floor(outNow / 32) + 1) * 32          // preview: next phrase
        }()
        let incNow = outNow - startBeat
        let incPreview = !inc.isPlaying

        // Beat, bar and phrase lines across both lanes.
        let first = Int(floor(outNow - Double(playX / ppb))), last = Int(ceil(outNow + Double((size.width - playX) / ppb)))
        for b in first...last {
            let x = playX + CGFloat(Double(b) - outNow) * ppb
            let phrase = b % 32 == 0, bar = b % 4 == 0
            let w: CGFloat = phrase ? 2 : 1
            let alpha = phrase ? 0.32 : bar ? 0.14 : 0.05
            ctx.fill(Path(CGRect(x: x - w / 2, y: 0, width: w, height: size.height)), with: .color(.white.opacity(alpha)))
            if phrase {
                ctx.draw(Text("BAR \(b / 4 + 1)").font(.system(size: 9.5, weight: .bold)).foregroundColor(.white.opacity(0.55)),
                         at: CGPoint(x: x + 4, y: 2), anchor: .topLeading)
            }
        }

        lane(ctx, deck: out, color: TJ.deck(mix.outgoing), now: outNow,
             rect: CGRect(x: 0, y: 0, width: size.width, height: laneH), ppb: ppb, playX: playX, dim: false)
        lane(ctx, deck: inc, color: TJ.deck(mix.incoming), now: incNow,
             rect: CGRect(x: 0, y: laneH + laneGap, width: size.width, height: laneH), ppb: ppb, playX: playX, dim: incPreview)

        // Where the incoming track starts.
        if inc.grid != nil {
            let x = playX + CGFloat(startBeat - outNow) * ppb
            if x > 0, x < size.width {
                ctx.fill(Path(CGRect(x: x - 1, y: laneH + laneGap, width: 2, height: laneH)), with: .color(TJ.gold))
                let label = incPreview ? "\(inc.name) STARTS HERE (NEXT PHRASE)" : mix.incomingStartBeat != nil ? "\(inc.name) STARTS HERE" : ""
                if !label.isEmpty {
                    ctx.draw(Text(label).font(.system(size: 9.5, weight: .heavy)).foregroundColor(TJ.gold),
                             at: CGPoint(x: x + 5, y: laneH + laneGap + 3), anchor: .topLeading)
                }
            }
        }

        // Playhead.
        ctx.fill(Path(CGRect(x: playX - 1, y: 0, width: 2, height: size.height)), with: .color(.white))
    }

    private func lane(_ ctx: GraphicsContext, deck: Deck, color: Color, now: Double,
                      rect: CGRect, ppb: CGFloat, playX: CGFloat, dim: Bool) {
        ctx.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(.black.opacity(0.35)))
        guard let g = deck.grid, let wf = deck.waveform else {
            ctx.draw(Text("Deck \(deck.name): load a track").font(.system(size: 12)).foregroundColor(TJ.mute),
                     at: CGPoint(x: rect.midX, y: rect.midY))
            return
        }
        let mid = rect.midY, half = rect.height / 2 - 4
        let step: CGFloat = 2
        let secondsPerPixel = g.secondsPerBeat / Double(ppb)
        var full = Path(), low = Path()
        var x = rect.minX
        while x < rect.maxX {
            let beat = now + Double(x - playX) / Double(ppb)
            let s = g.seconds(atBeat: beat)
            if s >= 0, s < g.duration {
                let lv = wf.level(from: s, to: s + secondsPerPixel * Double(step))
                let hf = CGFloat(lv.full) * half, hl = CGFloat(lv.low) * half
                full.addRect(CGRect(x: x, y: mid - hf, width: step - 0.5, height: hf * 2))
                low.addRect(CGRect(x: x, y: mid - hl, width: step - 0.5, height: hl * 2))
            }
            x += step
        }
        let o = dim ? 0.45 : 1.0
        ctx.fill(full, with: .color(color.opacity(0.35 * o)))
        ctx.fill(low, with: .color(color.opacity(0.9 * o)))
        ctx.draw(Text(deck.name).font(.system(size: 11, weight: .heavy)).foregroundColor(.black),
                 at: CGPoint(x: rect.minX + 14, y: rect.minY + 13))
        ctx.fill(Path(roundedRect: CGRect(x: rect.minX + 5, y: rect.minY + 4, width: 18, height: 18), cornerRadius: 4),
                 with: .color(color))
        ctx.draw(Text(deck.name).font(.system(size: 11, weight: .heavy)).foregroundColor(.black),
                 at: CGPoint(x: rect.minX + 14, y: rect.minY + 13))
    }
}
