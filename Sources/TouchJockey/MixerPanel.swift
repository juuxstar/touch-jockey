import SwiftUI
import TJCore

/// The blend panel. What it shows depends on the user's **blend** level (`SkillLadder`):
///
/// - **Handoff** (beginner): the phone's three handoff lanes, each with a slider for mouse
///   use and a Flick button, plus Back to and Stop all. While a phone is connected the lanes
///   are moved there, so here they only show positions: no dragging, no Flick buttons.
/// - **Mixer**: a two-channel DJ mixer, a channel strip per deck (HIGH, MID, LOW EQ and a
///   volume fader) and a crossfader along the bottom.
struct MixerPanel: View {
    @EnvironmentObject var m: AppModel

    private static let bands: [Band] = [.high, .mid, .low]
    private var mixerMode: Bool { m.ladder.blend == .mixer }

    var body: some View {
        Panel(color: TJ.lav, fillHeight: true) {
            HStack(spacing: 6) {
                Cap(text: mixerMode ? "Mixer" : "Handoff")
                if mixerMode {
                    InfoTip("""
                        **Mixer**: one **channel strip** per deck, deck **A** on the left and **B** on the right, like the mixer in a DJ booth.

                        **EQ** (equaliser): each strip splits its track into three bands. **HIGH** is hi-hats and cymbals, **MID** is vocals, leads and chords, **LOW** is the kick and bassline.

                        **Centre** leaves a band as it is. **Down** turns it down; at the **bottom** it's **killed** (silent). **Up** boosts it a little (+6 dB), so use that sparingly.

                        **Classic house blend**: bring the incoming track in with its **LOW killed**, let the hats and percussion ride together, then **swap the basslines** on a phrase: kill the old LOW as you open the new one.

                        **Finishing**: stop or pause the old track and the one still playing becomes the **master**.

                        **Double-click** any control to reset it. Want the handoff lanes back? **Settings → Your skills**.
                        """)
                    Text("\(m.decks[m.outgoing].name) master · \(m.decks[1 - m.outgoing].name) incoming")
                        .font(.tj(11, weight: .semibold)).foregroundColor(TJ.mute).lineLimit(1)
                } else {
                    InfoTip("""
                        **Handoff lanes**: the beginner's way to blend. Each lane moves one band (**HIGH**, **MID**, **LOW**) from deck **A** (left) to deck **B** (right). Drag them on the phone, or here with the mouse.

                        **Finishing**: when every lane reaches the incoming deck, the handoff ends on the next bar and the decks swap roles.

                        **Flick** swaps a band in one go. Use it on **LOW** for a clean bass swap.

                        **Ready for more?** When you can blend a whole track without thinking about the lanes, move up to the full **mixer** in **Settings → Your skills**.
                        """)
                    Text("\(m.decks[m.outgoing].name) → \(m.decks[1 - m.outgoing].name)")
                        .font(.tj(11, weight: .semibold)).foregroundColor(TJ.mute).lineLimit(1)
                }
                Spacer()
                if m.headphones != nil { cueMixControl }
                if !mixerMode {
                    Button("Back to \(m.decks[m.outgoing].name)") { m.mix.backToStable() }.tjButton(TJ.deck(m.outgoing))
                        .tip("**Back to \(m.decks[m.outgoing].name)**: move every handoff lane back to the outgoing deck, undoing the handoff so far.\n\nSame as a **two-finger tap** on the phone.")
                }
                Button { m.playAll() } label: { Label("Play all", systemImage: "play.fill") }
                    .tjButton(TJ.mint).disabled(!m.canPlayAll)
                    .tip("**Play all**: start both decks together, each from where it's parked, with their beats lined up. Shortcut: **Space**.\n\nIf one deck is already playing, the other joins on its next beat.")
                Button("Stop all") { m.stopAll() }.tjButton(TJ.rose)
                    .tip(mixerMode
                         ? "**Stop all**: stop both decks and send them back to bar 1.\n\nThe mixer's EQ and faders stay where they are."
                         : "**Stop all**: stop both decks, send them back to bar 1, and reset the handoff lanes.")
            }
            if mixerMode {
                HStack(alignment: .top, spacing: 14) {
                    channelStrip(0)
                    Spacer(minLength: 0)
                    channelStrip(1)
                }
                crossfaderRow
            } else {
                handoffLanes
            }
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
        return column(label: band == .high ? "HIGH" : band.rawValue.uppercased(), color: TJ.band(band)) {
            MixerSlider(value: v, color: TJ.band(band), fill: .fromCentre, detent: 0.5, resetTo: 0.5,
                        readout: eqReadout(v), killed: MixEngine.eqGain(v) == 0) { m.setEQ(i, band, $0) }
        }
        .sliderTip(eqTip(band, deck: m.decks[i].name))
    }

    private func volumeColumn(_ i: Int) -> some View {
        let v = m.volumes[i]
        return column(label: "VOL", color: TJ.deck(i)) {
            MixerSlider(value: v, color: TJ.deck(i), fill: .fromStart, resetTo: 1, readout: faderReadout(v)) { m.setVolume(i, $0) }
        }
        .sliderTip("""
            **Deck \(m.decks[i].name) volume** (channel fader): how loud this track is, before the crossfader.

            **Top** = full, the normal place for it. Lower it to bring a track in gradually: in progressive house and melodic techno, a slow fader ride over **16 or 32 bars** makes a long, smooth blend.

            **Double-click** for full.
            """)
    }

    private func column<S: View>(label: String, color: Color, @ViewBuilder slider: () -> S) -> some View {
        VStack(spacing: 4) {
            slider()
            Text(label).font(.tj(10, weight: .heavy)).tracking(0.6).foregroundColor(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: MixerSlider.columnWidth)
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
        return abs(db) < 0.5 ? "0 dB" : String(format: "%+.0f dB", db).replacingOccurrences(of: "-", with: "−")
    }

    private func faderReadout(_ v: Double) -> String {
        let g = MixEngine.faderGain(v)
        if g == 0 { return "−∞" }
        let db = 20 * log10(g)
        return abs(db) < 0.5 ? "0 dB" : String(format: "%.0f dB", db).replacingOccurrences(of: "-", with: "−")
    }

    // MARK: Handoff lanes

    /// The phone's lanes, with a slider each for mouse use and a Flick button.
    /// With a phone connected the lanes are moved there, so here they only show where each band is.
    private var phoneDrives: Bool { !m.devices.isEmpty }

    private var handoffLanes: some View {
        VStack(alignment: .leading, spacing: 6) {
            if phoneDrives {
                HStack(spacing: 6) {
                    Image(systemName: "iphone").foregroundColor(TJ.mute)
                    Text("Moved from the phone").font(.tj(11, weight: .semibold)).foregroundColor(TJ.mute)
                }
            }
            ForEach(Self.bands, id: \.self) { band in
                let v = m.lanes[band] ?? 0
                HStack(spacing: 8) {
                    Text(band == .high ? "HIGHS" : band == .mid ? "MIDS" : "LOWS").font(.tj(10, weight: .heavy)).tracking(1)
                        .foregroundColor(.black).frame(width: 52 * UIScale.current, height: 20 * UIScale.current).background(TJ.band(band))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("A").font(.tj(11, weight: .heavy)).foregroundColor(TJ.a)
                    MixerSlider(value: v, color: TJ.band(band), axis: .horizontal, fill: .none, detent: 0.5,
                                resetTo: m.mix.laneEnd(forDeck: m.outgoing), readout: laneReadout(v),
                                tint: MixerSlider.blend(v)) { m.setLane(band, $0) }
                        .allowsHitTesting(!phoneDrives)
                        .sliderTip("**\(band.rawValue.uppercased()) lane**: left is deck **A**, right is deck **B**. Drag to hand this band over.\n\n**Double-click** to send it back to the outgoing deck.")
                    Text("B").font(.tj(11, weight: .heavy)).foregroundColor(TJ.b)
                    if !phoneDrives {
                        Button("Flick") { m.flick(band) }.tjButton(TJ.band(band))
                            .tip(m.ladder.timing == .free
                                 ? "**Flick \(band.rawValue.uppercased())**: swap this band to the other deck **right now**.\n\nYour timing decides where it lands, so press it on the downbeat."
                                 : "**Flick \(band.rawValue.uppercased())**: swap this band to the other deck exactly on the **next bar**, like flicking the lane on the phone.\n\nUse it on **LOW** for a clean bass swap on the downbeat.")
                    }
                }
            }
        }
    }

    /// What the headphones play: only the cued decks (left), only the speaker mix (right), or both.
    private var cueMixControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "headphones").foregroundColor(TJ.mute)
            Text("CUE").font(.tj(10, weight: .heavy)).tracking(1).foregroundColor(TJ.mute)
            MixerSlider(value: m.cueMix, color: TJ.mute, axis: .horizontal, fill: .none, detent: 0.5, resetTo: 0.5,
                        readout: m.cueMix <= 0.005 ? "cue only" : m.cueMix >= 0.995 ? "mix only" : nil) { m.setCueMix($0) }
                .frame(width: 150 * UIScale.current)
                .sliderTip("**Cue mix**: what your headphones play.\n\n**Left**: only the decks you've sent to the headphones. **Right**: only what the speakers play. **Centre**: both at full.\n\n**Double-click** to centre it.")
            Text("MIX").font(.tj(10, weight: .heavy)).tracking(1).foregroundColor(TJ.mute)
        }
        .padding(.trailing, 6)
    }

    /// "all A", "all B", or how much of the band is on B.
    private func laneReadout(_ v: Double) -> String {
        v <= 0.005 ? "all A" : v >= 0.995 ? "all B" : String(format: "%.0f%% B", v * 100)
    }

    // MARK: Crossfader

    private var crossfaderRow: some View {
        HStack(spacing: 8) {
            Text("A").font(.tj(12, weight: .heavy)).foregroundColor(TJ.a)
            MixerSlider(value: m.crossfader, color: TJ.gold, axis: .horizontal, fill: .none, detent: 0.5, resetTo: 0.5,
                        tint: MixerSlider.blend(m.crossfader)) { m.setCrossfader($0) }
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

/// A mixer control drawn as a digital level, in the style of the phone's handoff lanes
/// rather than a physical fader: a rounded container with a bright border, a filled
/// level, a crisp indicator line at the exact value and the value as text inside.
///
/// - `.fromStart`: a solid tinted fill rising from the bottom (channel faders).
/// - `.fromCentre`: a fill from the centre line, up for boost and down for cut (EQ).
///   `killed` empties the container and shows KILL.
/// - `.none` with a `tint`: the whole container tinted, for the crossfader and lanes.
///
/// Drags are relative, so grabbing it never makes the value jump. It snaps to the
/// detent when passing close to it, and a double-click resets it. The whole container
/// is the hit area.
struct MixerSlider: View {
    enum Fill { case fromStart, fromCentre, none }

    let value: Double
    let color: Color
    var axis: Axis = .vertical
    var fill: Fill = .fromStart
    var detent: Double? = nil
    var resetTo: Double
    /// The value as text, drawn inside the container.
    var readout: String? = nil
    /// An EQ band at its kill: empty container, KILL readout.
    var killed = false
    /// Background tint of the whole container (the crossfader and lanes blend A/B).
    var tint: Color? = nil
    let set: (Double) -> Void

    @State private var dragStart: Double?
    @State private var hover = false

    /// Width of a vertical slider (and its column), scaled with the text so readouts fit.
    static var columnWidth: CGFloat { 44 * UIScale.current }
    static let verticalHeight: CGFloat = 112
    /// Lane background, as on the phone.
    static let well = Color(red: 0.063, green: 0.075, blue: 0.094)
    /// The A/B tint for a position from 0 (all A, blue) to 1 (all B, orange).
    static func blend(_ x: Double) -> Color {
        let c = NSColor(TJ.a).usingColorSpace(.sRGB)!.blended(withFraction: CGFloat(min(1, max(0, x))), of: NSColor(TJ.b).usingColorSpace(.sRGB)!)!
        return Color(nsColor: c).opacity(0.24)
    }

    /// Inset of the value travel from each end, so the indicator stays inside the border.
    private let inset: CGFloat = 7
    private var vertical: Bool { axis == .vertical }

    var body: some View {
        GeometryReader { g in
            let length = vertical ? g.size.height : g.size.width
            let travel = max(1, length - 2 * inset)
            // Distance along the container from its start (top or left) for a value.
            let at = { (v: Double) -> CGFloat in inset + (vertical ? 1 - v : v) * travel }
            let p = at(value)

            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Self.well)
                if let tint { RoundedRectangle(cornerRadius: 10).fill(tint) }
                if !killed, let base = fill == .fromStart ? (vertical ? length : 0) : fill == .fromCentre ? at(0.5) : nil {
                    span(min(base, p), max(base, p), in: g.size).fill(color.opacity(0.32))
                }
                if let d = detent {
                    span(at(d) - 0.5, at(d) + 0.5, in: g.size, inset: 5).fill(Color.white.opacity(0.22))
                }
                if !killed {
                    span(p - 1.25, p + 1.25, in: g.size, inset: 4).fill(Color.white)
                        .shadow(color: color.opacity(0.9), radius: 2)
                }
                if let readout {
                    Text(killed ? "KILL" : readout)
                        .font(.tj(10, weight: killed ? .heavy : .semibold)).monospacedDigit()
                        .tracking(killed ? 0.8 : 0)
                        .foregroundColor(killed ? color : Color.white.opacity(0.92))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.horizontal, 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: vertical ? (killed ? .center : readoutAlignment(p: p, length: length)) : .trailing)
                        .padding(vertical ? .vertical : .horizontal, vertical ? 6 : 10)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(killed ? color.opacity(0.55) : color, style: StrokeStyle(lineWidth: 2.5, dash: killed ? [4, 3] : [])))
            .brightness(hover ? 0.04 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .slideCursor(axis)   // arrows: "slide me"
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
        .frame(width: vertical ? Self.columnWidth : nil, height: vertical ? Self.verticalHeight : 26 * max(1, UIScale.current))
        .frame(maxWidth: vertical ? nil : .infinity)
        .onHover { hover = $0 }
    }

    /// Keeps the vertical readout out of the indicator's way: at the top when the level is
    /// low, at the bottom when it's high.
    private func readoutAlignment(p: CGFloat, length: CGFloat) -> Alignment {
        p > length * 0.4 ? .top : .bottom
    }

    /// A band across the container between two positions along its axis.
    private func span(_ a: CGFloat, _ b: CGFloat, in size: CGSize, inset across: CGFloat = 0) -> Path {
        let lo = max(0, a), hi = min(vertical ? size.height : size.width, b)
        let r = vertical
            ? CGRect(x: across, y: lo, width: size.width - 2 * across, height: max(0, hi - lo))
            : CGRect(x: lo, y: across, width: max(0, hi - lo), height: size.height - 2 * across)
        return Path(r)   // the container clips it to its rounded corners
    }
}
