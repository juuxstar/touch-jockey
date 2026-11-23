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
    @State private var dragDeck: Int?
    @State private var dragFromBeat: Double = 0

    var body: some View {
        // Reading the frame's date inside the Canvas makes SwiftUI redraw it every frame;
        // without that it treats the drawing as unchanged and the waveform stands still.
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    _ = timeline.date
                    draw(ctx, size)
                }
                .contentShape(Rectangle())
                .pointingHandCursor()
                // Drag a stopped deck's waveform to jog it back and forth (snaps to the beat on release).
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { g in jog(g, size: geo.size) }
                    .onEnded { _ in
                        if let i = dragDeck { mix.seek(deck: i, toBeat: mix.decks[i].parkedBeat.rounded()) }
                        dragDeck = nil
                    })
                // Clicking cues the incoming track at the next phrase (when it isn't playing yet).
                .onTapGesture {
                    let inc = mix.decks[mix.incoming]
                    if inc.grid != nil, !inc.isPlaying, mix.decks[mix.outgoing].isPlaying { mix.cueIncoming(every: 32) }
                }
            }
        }
    }

    /// Dragging left moves the music left, so the deck moves later in the track (like sliding paper).
    private func jog(_ g: DragGesture.Value, size: CGSize) {
        if dragDeck == nil {
            let deck = g.startLocation.y < size.height / 2 ? 0 : 1     // A on top, B below
            guard mix.decks[deck].grid != nil, !mix.decks[deck].isPlaying else { return }
            dragDeck = deck
            dragFromBeat = mix.decks[deck].parkedBeat
        }
        guard let i = dragDeck else { return }
        let ppb = size.width / beatsVisible
        mix.seek(deck: i, toBeat: dragFromBeat - Double(g.translation.width / ppb))
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let out = mix.decks[mix.outgoing], inc = mix.decks[mix.incoming]
        let playX = size.width * 0.33
        let ppb = size.width / beatsVisible                 // pixels per beat
        let laneGap: CGFloat = 8
        let laneH = (size.height - laneGap) / 2

        let outNow = out.shownBeat
        // The outgoing beat that lines up with the incoming track's beat 0 (so incoming beat = outNow - offset).
        // A playing deck's real position wins; a scheduled start counts from the beat it starts at,
        // which isn't bar 1 when it resumes mid-track (PLAY, Play all).
        let startBeat: Double = {
            if inc.isPlaying, let ib = inc.currentBeat() { return outNow - ib }
            if let s = mix.incomingStartBeat { return s - (inc.isPlaying ? inc.startedFromBeat : 0) }
            return (floor(outNow / 32) + 1) * 32          // preview: next phrase
        }()
        // Where the incoming track comes in: its scheduled start, or the preview phrase.
        let entryBeat = mix.incomingStartBeat ?? startBeat
        // A stopped incoming deck that has been jogged shows where it sits, at the playhead.
        let incParked = inc.isParkedAway && mix.incomingStartBeat == nil
        let incNow = incParked ? inc.parkedBeat : outNow - startBeat
        let incPreview = !inc.isPlaying

        // Beat, bar and phrase lines across both lanes.
        let first = Int(floor(outNow - Double(playX / ppb))), last = Int(ceil(outNow + Double((size.width - playX) / ppb)))
        for b in first...last {
            let x = playX + CGFloat(Double(b) - outNow) * ppb
            let phrase = b % 32 == 0, bar = b % 4 == 0
            let w: CGFloat = phrase ? 2 : 1
            let alpha = phrase ? 0.45 : bar ? 0.24 : 0.08
            ctx.fill(Path(CGRect(x: x - w / 2, y: 0, width: w, height: size.height)), with: .color(.white.opacity(alpha)))
            if phrase {
                ctx.draw(Text("BAR \(b / 4 + 1)").font(.tj(9.5, weight: .bold)).foregroundColor(.white.opacity(0.55)),
                         at: CGPoint(x: x + 4, y: 2), anchor: .topLeading)
            }
        }

        // Fixed positions: deck A always on top, deck B always below.
        func laneRect(_ deck: Int) -> CGRect {
            CGRect(x: 0, y: deck == 0 ? 0 : laneH + laneGap, width: size.width, height: laneH)
        }
        let incTop = laneRect(mix.incoming).minY
        lane(ctx, deck: out, color: TJ.deck(mix.outgoing), now: outNow,
             rect: laneRect(mix.outgoing), ppb: ppb, playX: playX, dim: false)
        lane(ctx, deck: inc, color: TJ.deck(mix.incoming), now: incNow,
             rect: laneRect(mix.incoming), ppb: ppb, playX: playX, dim: incPreview)

        // Where the incoming track starts.
        if inc.grid != nil, !incParked {
            let x = playX + CGFloat(entryBeat - outNow) * ppb
            if x > 0, x < size.width {
                var line = Path()
                line.move(to: CGPoint(x: x, y: incTop))
                line.addLine(to: CGPoint(x: x, y: incTop + laneH))
                if incPreview {
                    // Not scheduled: a dashed preview of the next phrase, which moves on as the music plays.
                    ctx.stroke(line, with: .color(TJ.gold.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    if mix.decks[mix.outgoing].isPlaying {
                        ctx.draw(Text("\(inc.name) NOT CUED · CLICK HERE OR PRESS NEXT PHRASE TO START IT AT THIS PHRASE")
                                    .font(.tj(9.5, weight: .heavy)).foregroundColor(TJ.gold.opacity(0.75)),
                                 at: CGPoint(x: x + 5, y: incTop + 3), anchor: .topLeading)
                    }
                } else if mix.incomingStartBeat != nil {
                    ctx.stroke(line, with: .color(TJ.gold), lineWidth: 2)
                    ctx.draw(Text("\(inc.name) STARTS HERE").font(.tj(9.5, weight: .heavy)).foregroundColor(TJ.gold),
                             at: CGPoint(x: x + 5, y: incTop + 3), anchor: .topLeading)
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
            ctx.draw(Text("Deck \(deck.name): load a track").font(.tj(12)).foregroundColor(TJ.mute),
                     at: CGPoint(x: rect.midX, y: rect.midY))
            return
        }
        let mid = rect.midY, half = rect.height / 2 - 4
        let step: CGFloat = 2
        let secondsPerPixel = g.secondsPerBeat / Double(ppb)
        let spectrum = mix.ladder.waveform == .spectrum && !wf.mid.isEmpty
        var full = Path(), low = Path(), painter = SpectrumPainter()
        var x = rect.minX
        while x < rect.maxX {
            let beat = now + Double(x - playX) / Double(ppb)
            let s = g.seconds(atBeat: beat)
            if s >= 0, s < g.duration {
                let lv = wf.bands(from: s, to: s + secondsPerPixel * Double(step))
                let hf = CGFloat(lv.full) * half, hl = CGFloat(lv.low) * half
                let column = CGRect(x: x, y: mid - hf, width: step - 0.5, height: hf * 2)
                if spectrum {
                    painter.add(column, low: lv.low, mid: lv.mid, high: lv.high)
                } else {
                    full.addRect(column)
                    low.addRect(CGRect(x: x, y: mid - hl, width: step - 0.5, height: hl * 2))
                }
            }
            x += step
        }
        let o = dim ? 0.3 : 1.0
        if spectrum {
            painter.fill(ctx, opacity: o)
        } else {
            ctx.fill(full, with: .color(color.opacity(0.35 * o)))
            ctx.fill(low, with: .color(color.opacity(0.9 * o)))
        }
        // This deck's own bar at the playhead, so the two decks' positions can be compared at a glance.
        if now >= 0 {
            ctx.draw(Text("BAR \(Int(floor(now / 4)) + 1)").font(.tj(10, weight: .heavy)).foregroundColor(color.opacity(o)),
                     at: CGPoint(x: playX + 6, y: rect.minY + 4), anchor: .topLeading)
        }
        ctx.fill(Path(roundedRect: CGRect(x: rect.minX + 5, y: rect.minY + 4, width: 18, height: 18), cornerRadius: 4),
                 with: .color(color))
        ctx.draw(Text(deck.name).font(.tj(11, weight: .heavy)).foregroundColor(.black),
                 at: CGPoint(x: rect.minX + 14, y: rect.minY + 13))
    }
}
