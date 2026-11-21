import SwiftUI
import TJCore

/// A two-channel DJ mixer: a channel strip per deck (HIGH, MID, LOW EQ and a volume
/// fader), a crossfader along the bottom, and in the middle a compact readout of the
/// phone's handoff lanes, which multiply with the mixer (see MixEngine).
struct MixerPanel: View {
    @EnvironmentObject var m: AppModel

    private static let bands: [Band] = [.high, .mid, .low]

    var body: some View {
        Panel(color: TJ.lav, fillHeight: true) {
            HStack(spacing: 6) {
                Cap(text: "Mixer")
                InfoTip("""
                    **Mixer**: one **channel strip** per deck, deck **A** on the left and **B** on the right, like the mixer in a DJ booth.

                    **EQ** (equaliser): each strip splits its track into three bands. **HIGH** is hi-hats and cymbals, **MID** is vocals, leads and chords, **LOW** is the kick and bassline.

                    **Centre** leaves a band as it is. **Down** turns it down; at the **bottom** it's **killed** (silent). **Up** boosts it a little (+6 dB), so use that sparingly.

                    **Classic house blend**: bring the incoming track in with its **LOW killed**, let the hats and percussion ride together, then **swap the basslines** on a phrase: kill the old LOW as you open the new one.

                    **Double-click** any control to reset it.
                    """)
                Spacer()
                Button("Back to \(m.decks[m.outgoing].name)") { m.mix.backToStable() }.tjButton(TJ.deck(m.outgoing))
                    .tip("**Back to \(m.decks[m.outgoing].name)**: move every handoff lane back to the outgoing deck, undoing the handoff so far.\n\nSame as a **two-finger tap** on the phone. The mixer's EQ and faders stay where they are.")
                Button("Stop all") { m.stopAll() }.tjButton(TJ.rose)
                    .tip("**Stop all**: stop both decks, send them back to bar 1, and reset the handoff lanes.\n\nThe mixer's EQ and faders stay where they are.")
            }
            HStack(alignment: .top, spacing: 14) {
                channelStrip(0)
                handoffReadout.frame(maxWidth: .infinity)
                channelStrip(1)
            }
            crossfaderRow
        }
    }

    // MARK: Channel strip

    /// EQ sliders and the volume fader. Deck B is mirrored so both faders sit next to the centre.
    private func channelStrip(_ i: Int) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if i == 1 { volumeColumn(i) }
            ForEach(Self.bands, id: \.self) { eqColumn(i, $0) }
            if i == 0 { volumeColumn(i) }
        }
    }

    private func eqColumn(_ i: Int, _ band: Band) -> some View {
        let v = m.eq[i][band] ?? 0.5
        return column(label: band == .high ? "HIGH" : band.rawValue.uppercased(), color: TJ.band(band), readout: eqReadout(v)) {
            MixerSlider(value: v, color: TJ.band(band), fill: .fromCentre, detent: 0.5, resetTo: 0.5) { m.setEQ(i, band, $0) }
        }
        .sliderTip(eqTip(band, deck: m.decks[i].name))
    }

    private func volumeColumn(_ i: Int) -> some View {
        let v = m.volumes[i]
        return column(label: "VOL", color: TJ.deck(i), readout: faderReadout(v)) {
            MixerSlider(value: v, color: TJ.deck(i), fill: .fromStart, resetTo: 1, wide: true) { m.setVolume(i, $0) }
        }
        .sliderTip("""
            **Deck \(m.decks[i].name) volume** (channel fader): how loud this track is, before the crossfader.

            **Top** = full, the normal place for it. Lower it to bring a track in gradually: in progressive house and melodic techno, a slow fader ride over **16 or 32 bars** makes a long, smooth blend.

            **Double-click** for full.
            """)
    }

    private func column<S: View>(label: String, color: Color, readout: String, @ViewBuilder slider: () -> S) -> some View {
        VStack(spacing: 3) {
            slider()
            Text(label).font(.tj(10, weight: .heavy)).tracking(0.6).foregroundColor(color)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(readout).font(.tj(10)).monospacedDigit().foregroundColor(TJ.mute)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: 34)
    }

    private func eqTip(_ band: Band, deck: String) -> String {
        let what: String
        switch band {
        case .high:
            what = """
                **Deck \(deck) HIGH EQ** (treble, above 2.5 kHz): hi-hats, shakers, cymbals and air.

                Bring the incoming track's hats in early so the two grooves lock together; turn the old track's highs down as it leaves.
                """
        case .mid:
            what = """
                **Deck \(deck) MID EQ** (200 Hz to 2.5 kHz): vocals, synth leads, chords, pads and claps.

                If two melodies or vocals clash, dip one track's mids. In melodic techno the lead lives here, so give one lead the stage at a time.
                """
        case .low:
            what = """
                **Deck \(deck) LOW EQ** (bass, below 200 Hz): the kick drum and bassline.

                Never run two basslines at full: it sounds muddy and overloads the speakers. Keep the incoming LOW **killed**, then swap the bass on a phrase.
                """
        }
        return what + "\n\n**Centre** = unchanged, **bottom** = kill (silent), **top** = +6 dB.\n\n**Double-click** to reset to the centre."
    }

    private func eqReadout(_ v: Double) -> String {
        let g = MixEngine.eqGain(v)
        if g == 0 { return "KILL" }
        let db = 20 * log10(g)
        return abs(db) < 0.5 ? "0 dB" : String(format: "%+.0f", db).replacingOccurrences(of: "-", with: "−")
    }

    private func faderReadout(_ v: Double) -> String {
        let g = MixEngine.faderGain(v)
        if g == 0 { return "−∞" }
        let db = 20 * log10(g)
        return abs(db) < 0.5 ? "0 dB" : String(format: "%.0f", db).replacingOccurrences(of: "-", with: "−")
    }

    // MARK: Handoff readout

    /// The phone's lanes, read-only, with Flick buttons.
    private var handoffReadout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Cap(text: "Handoff")
                Text("\(m.decks[m.outgoing].name) → \(m.decks[1 - m.outgoing].name) · phone")
                    .font(.tj(11, weight: .semibold)).foregroundColor(TJ.mute).lineLimit(1)
                InfoTip("""
                    **Handoff lanes**: the phone's way of mixing. Each lane moves one band (**HIGH**, **MID**, **LOW**) from deck **A** (left) to deck **B** (right). The little bars here show where the phone has them.

                    **They work together with the mixer**: a band is as loud as its lane lets it be **times** its EQ, and a deck is as loud as its fader **times** the crossfader. So a band killed on the EQ stays silent whatever the lane does, and a lane on deck A silences that band on B even with B's EQ up.

                    **Finishing**: when every lane reaches the incoming deck, the handoff ends on the next bar and the decks swap roles. Only the lanes do this, not the faders.

                    **No phone?** Use **Flick** to swap a band on the next bar.
                    """)
            }
            ForEach(Self.bands, id: \.self) { band in
                let v = m.lanes[band] ?? 0
                HStack(spacing: 6) {
                    Text(band.rawValue.uppercased()).font(.tj(10, weight: .heavy)).tracking(1)
                        .foregroundColor(.black).frame(width: 44 * UIScale.current, height: 18 * UIScale.current).background(TJ.band(band))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("A").font(.tj(10, weight: .heavy)).foregroundColor(TJ.a)
                    LaneMeter(value: v, color: TJ.band(band))
                        .tip("**\(band.rawValue.uppercased()) lane**: \(laneReadout(v)).\n\nMoved by the phone, or by **Flick**. Left is deck **A**, right is deck **B**.")
                    Text("B").font(.tj(10, weight: .heavy)).foregroundColor(TJ.b)
                    Button("Flick") { m.flick(band) }.tjButton(TJ.band(band))
                        .tip("**Flick \(band.rawValue.uppercased())**: swap this band to the other deck exactly on the **next bar**, like flicking the lane on the phone.\n\nUse it on **LOW** for a clean bass swap on the downbeat.")
                }
            }
        }
    }

    /// "all A", "all B", or how much of the band is on B.
    private func laneReadout(_ v: Double) -> String {
        v <= 0.005 ? "all on A" : v >= 0.995 ? "all on B" : String(format: "%.0f%% on B", v * 100)
    }

    // MARK: Crossfader

    private var crossfaderRow: some View {
        HStack(spacing: 8) {
            Text("A").font(.tj(12, weight: .heavy)).foregroundColor(TJ.a)
            MixerSlider(value: m.crossfader, color: TJ.gold, axis: .horizontal, fill: .none, detent: 0.5, resetTo: 0.5) { m.setCrossfader($0) }
                .sliderTip("""
                    **Crossfader**: blends between deck **A** (left) and deck **B** (right).

                    **Centre**: both decks at full volume. Towards one side, the other deck fades out; at the end only that side plays.

                    Many house and techno DJs leave it in the **centre** and blend with the volume faders and EQ. It's handy for a quick cut on the beat.

                    **Double-click** to centre it.
                    """)
            Text("B").font(.tj(12, weight: .heavy)).foregroundColor(TJ.b)
            InfoTip("""
                **Volume fader or crossfader?**

                Each **volume fader** sets one deck's level on its own. The **crossfader** sits after them and blends between the two decks with one hand.

                They multiply: a deck you hear is its fader **times** its side of the crossfader. If a deck is silent, check both.

                **Tip**: leave the crossfader in the centre and mix with the volume faders and EQ. That's how most long house and techno blends are done.
                """)
        }
    }
}

// MARK: - Controls

/// A mixer slider in the app's style: a slot in a dark well, a coloured fill and a white cap.
///
/// Drags are relative, so grabbing it never makes the value jump. It snaps to the
/// detent when passing close to it, and a double-click resets it.
struct MixerSlider: View {
    enum Fill { case fromStart, fromCentre, none }

    let value: Double
    let color: Color
    var axis: Axis = .vertical
    var fill: Fill = .fromStart
    var detent: Double? = nil
    var resetTo: Double
    /// Wider cap, for channel faders.
    var wide = false
    let set: (Double) -> Void

    @State private var dragStart: Double?
    @State private var hover = false

    private let cap: CGFloat = 12
    private var vertical: Bool { axis == .vertical }

    var body: some View {
        GeometryReader { g in
            let length = vertical ? g.size.height : g.size.width
            let across = vertical ? g.size.width : g.size.height
            let travel = max(1, length - cap - 8)
            // Distance along the slot from its start (top or left) for a value.
            let at = { (v: Double) -> CGFloat in 4 + cap / 2 + (vertical ? 1 - v : v) * travel }
            let p = at(value)
            let base: CGFloat? = fill == .fromStart ? at(0) : fill == .fromCentre ? at(0.5) : nil

            ZStack {
                bar(from: 4, to: length - 4, thickness: 4, length: length, across: across)
                    .foregroundColor(Color.white.opacity(0.12))
                if let base {
                    bar(from: min(base, p), to: max(base, p), thickness: 4, length: length, across: across)
                        .foregroundColor(color)
                }
                if let d = detent {
                    bar(from: at(d) - 0.75, to: at(d) + 0.75, thickness: across * 0.6, length: length, across: across)
                        .foregroundColor(TJ.mute.opacity(0.8))
                }
                capView(across: across)
                    .position(vertical ? CGPoint(x: across / 2, y: p) : CGPoint(x: p, y: across / 2))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { d in
                    let start = dragStart ?? value
                    if dragStart == nil { dragStart = value }
                    let delta = Double(vertical ? -d.translation.height : d.translation.width) / Double(travel)
                    var v = min(1, max(0, start + delta))
                    if let det = detent, abs(v - det) < 0.03 { v = det }
                    if v != value { set(v) }
                }
                .onEnded { _ in dragStart = nil })
            .onTapGesture(count: 2) { set(resetTo) }
        }
        .frame(width: vertical ? 34 : nil, height: vertical ? 96 : 24)
        .frame(maxWidth: vertical ? nil : .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(hover ? 0.07 : 0.035)))
        .onHover { hover = $0 }
    }

    /// A centred bar along the slot between two positions.
    private func bar(from a: CGFloat, to b: CGFloat, thickness: CGFloat, length: CGFloat, across: CGFloat) -> some View {
        let size = max(0, b - a)
        return RoundedRectangle(cornerRadius: min(2, thickness / 2))
            .frame(width: vertical ? thickness : size, height: vertical ? size : thickness)
            .position(vertical ? CGPoint(x: across / 2, y: a + size / 2) : CGPoint(x: a + size / 2, y: across / 2))
    }

    /// White cap with a coloured line through it, like a fader knob.
    private func capView(across: CGFloat) -> some View {
        let w = vertical ? (wide ? 28 : 24) : cap
        let h = vertical ? cap : across - 6
        return RoundedRectangle(cornerRadius: 3).fill(Color.white)
            .overlay(Rectangle().fill(color).frame(width: vertical ? w : 2, height: vertical ? 2 : h))
            .frame(width: w, height: h)
            .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
    }
}

/// A read-only lane position: a thin track from A to B with a marker.
struct LaneMeter: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08))
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1.5, height: h - 6).position(x: w / 2, y: h / 2)
                RoundedRectangle(cornerRadius: 2).fill(color)
                    .frame(width: 6, height: h - 4)
                    .position(x: 3 + CGFloat(value) * (w - 6), y: h / 2)
            }
        }
        .frame(height: 16)
        .frame(minWidth: 60, maxWidth: .infinity)
    }
}
