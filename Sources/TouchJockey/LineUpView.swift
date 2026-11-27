import SwiftUI
import TJCore

/// Both whole tracks on one axis, the outgoing track's beats, for planning where the
/// incoming track comes in.
///
/// Anything stacked vertically plays at the same moment. The outgoing track fills its lane
/// from its start to its end; the incoming track is drawn from where it will start. Drag the
/// incoming track left or right to choose the outgoing bar it starts on (snapped to phrase
/// lines): that sets `MixEngine.plannedEntry`, and the engine starts it there by itself.
/// Until it's dragged, a dimmed suggestion shows four phrases before the outgoing track's end.
/// Drag a stopped outgoing track's lane to move where it starts.
struct LineUpView: View {
    let mix: MixEngine
    /// While dragging the incoming track: the beats between the pointer and its start.
    @State private var grab: Double?
    @State private var dragging: Int?

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
                Canvas { ctx, size in
                    _ = timeline.date
                    draw(ctx, size)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in drag(g, size: geo.size) }
                .onEnded { _ in grab = nil; dragging = nil })
        }
    }

    // MARK: Geometry

    private struct Axis {
        var lo: Double, hi: Double, width: CGFloat
        func x(_ beat: Double) -> CGFloat { CGFloat((beat - lo) / (hi - lo)) * width }
        func beat(_ x: CGFloat) -> Double { lo + Double(x / width) * (hi - lo) }
    }

    /// From the outgoing track's first sound to 16 bars after it ends, so the incoming track
    /// can be seen carrying on.
    private func axis(_ width: CGFloat) -> Axis? {
        guard let g = mix.decks[mix.outgoing].grid else { return nil }
        return Axis(lo: g.beat(atSeconds: 0), hi: g.beat(atSeconds: g.duration) + 64, width: width)
    }

    private func laneRect(_ deck: Int, _ size: CGSize) -> CGRect {
        let gap: CGFloat = 8, h = (size.height - gap) / 2
        return CGRect(x: 0, y: deck == 0 ? 0 : h + gap, width: size.width, height: h)
    }

    /// The incoming track's alignment: the outgoing beat it starts on, the outgoing beat its
    /// beat 0 lines up with, the beat it plays from, and whether that's real, planned or only suggested.
    private enum Kind { case playing, planned, suggested }
    private func alignment() -> (entry: Double, zero: Double, from: Double, kind: Kind)? {
        let out = mix.decks[mix.outgoing], inc = mix.decks[mix.incoming]
        guard out.grid != nil, inc.grid != nil else { return nil }
        if inc.isPlaying {
            let from = inc.startedFromBeat
            if let s = mix.incomingStartBeat, (out.currentBeat() ?? out.shownBeat) < s { return (s, s - from, from, .playing) }
            guard let ib = inc.currentBeat() else { return nil }
            let zero = out.shownBeat - ib
            return (mix.incomingStartBeat ?? zero + from, zero, from, .playing)
        }
        let from = max(0, inc.parkedBeat.rounded())
        if let p = mix.plannedEntry { return (p, p - from, from, .planned) }
        guard let s = mix.suggestedEntry else { return nil }
        return (s, s - from, from, .suggested)
    }

    // MARK: Dragging

    private func drag(_ g: DragGesture.Value, size: CGSize) {
        guard let ax = axis(size.width), let og = mix.decks[mix.outgoing].grid else { return }
        let outEnd = og.beat(atSeconds: og.duration)
        if dragging == nil {
            let inIncoming = laneRect(mix.incoming, size).contains(g.startLocation)
            dragging = inIncoming ? mix.incoming : mix.outgoing
            if inIncoming, let a = alignment(), a.kind != .playing { grab = ax.beat(g.startLocation.x) - a.entry }
        }
        if dragging == mix.incoming {
            // The incoming track: choose the outgoing phrase line it starts on.
            guard let grab, !mix.decks[mix.incoming].isPlaying, let earliest = mix.earliestEntry else { return }
            let latest = max(earliest, floor((outEnd - 1) / 32) * 32)
            let phrase = ((ax.beat(g.location.x) - grab) / 32).rounded() * 32
            mix.planIncoming(atBeat: min(max(phrase, earliest), latest))
        } else if !mix.decks[mix.outgoing].isPlaying {
            // A stopped outgoing track: move where it starts, to a phrase line.
            let phrase = (ax.beat(g.location.x) / 32).rounded() * 32
            mix.seek(deck: mix.outgoing, toBeat: min(max(0, phrase), max(0, floor((outEnd - 1) / 32) * 32)))
        }
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let out = mix.decks[mix.outgoing], inc = mix.decks[mix.incoming]
        let outRect = laneRect(mix.outgoing, size), incRect = laneRect(mix.incoming, size)
        for (d, r) in [(mix.outgoing, outRect), (mix.incoming, incRect)] {
            ctx.fill(Path(roundedRect: r, cornerRadius: 6), with: .color(.black.opacity(0.35)))
            if mix.decks[d].grid == nil {
                ctx.draw(Text("Deck \(mix.decks[d].name): load a track to line it up").font(.tj(12)).foregroundColor(TJ.mute),
                         at: CGPoint(x: r.midX, y: r.midY))
            }
        }
        guard let ax = axis(size.width), let og = out.grid else { return }
        let outEnd = og.beat(atSeconds: og.duration)

        // Phrase lines of the outgoing track, labelled as far apart as there's room for.
        let phrasePx = ax.x(32) - ax.x(0)
        let every = max(1, Int((60 / max(phrasePx, 1)).rounded(.up)))
        var k = 0
        while Double(k * 32) <= outEnd {
            let x = ax.x(Double(k * 32))
            ctx.fill(Path(CGRect(x: x - 0.5, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(k % every == 0 ? 0.3 : 0.12)))
            if k % every == 0, x > 28 {   // clear of the deck letter
                ctx.draw(Text("BAR \(k * 8 + 1)").font(.tj(9, weight: .bold)).foregroundColor(.white.opacity(0.5)),
                         at: CGPoint(x: x + 3, y: outRect.minY + 2), anchor: .topLeading)
            }
            k += 1
        }

        // The outgoing track, whole.
        waveform(ctx, deck: out, color: TJ.deck(mix.outgoing), rect: outRect, ax: ax, opacity: 1) { $0 }
        lettered(ctx, out, TJ.deck(mix.outgoing), outRect)

        // The incoming track, from where it starts.
        if let a = alignment() {
            let from = a.kind == .playing ? -Double.infinity : a.from
            waveform(ctx, deck: inc, color: TJ.deck(mix.incoming), rect: incRect, ax: ax,
                     opacity: a.kind == .suggested ? 0.45 : 1) { ob in
                let ib = ob - a.zero
                return ib >= from ? ib : nil
            }
            lettered(ctx, inc, TJ.deck(mix.incoming), incRect)

            // Where it starts: a gold line down both lanes, and what it means.
            let x = ax.x(a.entry)
            let line = Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height))
            if a.kind == .suggested {
                var dashed = Path()
                dashed.move(to: CGPoint(x: x, y: 0)); dashed.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(dashed, with: .color(TJ.gold.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            } else {
                ctx.fill(line, with: .color(TJ.gold))
            }
            let bar = Int(floor(a.entry / 4)) + 1
            let text: String
            switch a.kind {
            case .suggested: text = "DRAG \(inc.name) TO CHOOSE WHERE IT STARTS"
            case .planned: text = "\(inc.name) STARTS ON \(out.name)'S BAR \(bar)"
            case .playing: text = "\(inc.name) CAME IN ON \(out.name)'S BAR \(bar)"
            }
            let label = ctx.resolve(Text(text).font(.tj(9.5, weight: .heavy)).foregroundColor(TJ.gold))
            let w = label.measure(in: size).width
            let right = x + 6 + w < size.width
            ctx.draw(label, at: CGPoint(x: right ? x + 6 : x - 6, y: incRect.maxY - 4),
                     anchor: right ? .bottomLeading : .bottomTrailing)
        }

        // Where the outgoing track is now.
        let px = ax.x(out.shownBeat)
        ctx.fill(Path(CGRect(x: px - 1, y: 0, width: 2, height: size.height)), with: .color(.white))
    }

    /// One deck's waveform across the axis. `beatFor` maps an outgoing beat to this deck's
    /// beat, or nil where it doesn't play.
    private func waveform(_ ctx: GraphicsContext, deck: Deck, color: Color, rect: CGRect, ax: Axis,
                          opacity: Double, beatFor: (Double) -> Double?) {
        guard let g = deck.grid, let wf = deck.waveform else { return }
        let mid = rect.midY, half = rect.height / 2 - 4, step: CGFloat = 2
        var full = Path(), low = Path()
        var x: CGFloat = 0
        while x < rect.width {
            if let b0 = beatFor(ax.beat(x)), let b1 = beatFor(ax.beat(x + step)) {
                let s0 = g.seconds(atBeat: b0), s1 = g.seconds(atBeat: b1)
                if s1 > 0, s0 < g.duration {
                    let lv = wf.bands(from: max(0, s0), to: min(g.duration, s1))
                    let hf = CGFloat(lv.full) * half, hl = CGFloat(lv.low) * half
                    full.addRect(CGRect(x: x, y: mid - hf, width: step - 0.5, height: hf * 2))
                    low.addRect(CGRect(x: x, y: mid - hl, width: step - 0.5, height: hl * 2))
                }
            }
            x += step
        }
        ctx.fill(full, with: .color(color.opacity(0.35 * opacity)))
        ctx.fill(low, with: .color(color.opacity(0.9 * opacity)))
    }

    /// The deck's letter in the lane's corner, as on the timeline.
    private func lettered(_ ctx: GraphicsContext, _ deck: Deck, _ color: Color, _ rect: CGRect) {
        ctx.fill(Path(roundedRect: CGRect(x: rect.minX + 5, y: rect.minY + 4, width: 18, height: 18), cornerRadius: 4),
                 with: .color(color))
        ctx.draw(Text(deck.name).font(.tj(11, weight: .heavy)).foregroundColor(.black),
                 at: CGPoint(x: rect.minX + 14, y: rect.minY + 13))
    }
}
