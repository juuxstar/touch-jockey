import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import TJCore

@main
struct TouchJockeyApp: App {
    @StateObject private var model = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("Touch Jockey") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 760)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Palette (matches the web surface)

enum TJ {
    static let bg = Color(red: 0.043, green: 0.047, blue: 0.059)
    static let panel = Color(red: 0.082, green: 0.090, blue: 0.110)
    static let mute = Color(red: 0.545, green: 0.565, blue: 0.612)
    static let a = Color(red: 0.361, green: 0.722, blue: 1.0)
    static let b = Color(red: 1.0, green: 0.604, blue: 0.239)
    static let gold = Color(red: 1.0, green: 0.769, blue: 0.302)
    static let mint = Color(red: 0.357, green: 0.890, blue: 0.690)
    static let lav = Color(red: 0.769, green: 0.608, blue: 1.0)
    static let sky = Color(red: 0.561, green: 0.816, blue: 1.0)
    static func band(_ b: Band) -> Color {
        switch b {
        case .high: return Color(red: 0.561, green: 0.816, blue: 1.0)
        case .mid: return lav
        case .low: return Color(red: 1.0, green: 0.373, blue: 0.561)
        }
    }
    static func deck(_ i: Int) -> Color { i == 0 ? a : b }
}

struct Panel<Content: View>: View {
    var color: Color
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TJ.panel)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct Cap: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundColor(TJ.gold)
    }
}

// MARK: - Window

struct ContentView: View {
    @EnvironmentObject var m: AppModel

    @State private var showSplash = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                deckCard(0)
                deckCard(1)
            }
            Panel(color: TJ.sky) {
                DeckTimeline(mix: m.mix).frame(minHeight: 180, maxHeight: .infinity)
            }
            HStack(alignment: .top, spacing: 10) {
                lanesPanel
                connectPanel.frame(width: 300)
            }
            Text(m.status).font(.system(size: 11)).foregroundColor(TJ.mute).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .padding(.top, 4)
        .background(TJ.bg)
        .overlay {
            if showSplash { SplashView().transition(.opacity) }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
            }
        }
    }

    func deckCard(_ i: Int) -> some View {
        let d = m.decks[i]
        let isOut = m.outgoing == i
        return Panel(color: TJ.deck(i)) {
            HStack(spacing: 10) {
                Text(d.name).font(.system(size: 15, weight: .heavy)).foregroundColor(.black)
                    .frame(width: 30, height: 30).background(TJ.deck(i)).clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.title.isEmpty ? "No track" : d.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text((d.artist.isEmpty ? "" : d.artist + " · ") + meta(d)).font(.system(size: 12)).foregroundColor(TJ.mute).monospacedDigit()
                }
                Spacer()
                Cap(text: isOut ? "Outgoing" : "Incoming")
            }
            HStack {
                Button(d.loading ? "Analysing…" : "Load track…") { m.chooseTrack(for: i) }.disabled(d.loading)
                Spacer()
                if isOut {
                    if let beat = m.beat {
                        Text("Bar \(Int(floor(beat / 4)) + 1) · beat \(Int(floor(beat)) % 4 + 1)")
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundColor(TJ.gold)
                    }
                    Button("Play from bar 1") { m.playOutgoing() }.disabled(d.bpm == nil)
                } else {
                    Button("Bring in next bar") { m.cueIncoming(every: 4) }.disabled(d.bpm == nil || !m.decks[m.outgoing].playing)
                    Button("Next phrase") { m.cueIncoming(every: 32) }.disabled(d.bpm == nil || !m.decks[m.outgoing].playing)
                }
            }
        }
    }

    func meta(_ d: AppModel.DeckInfo) -> String {
        guard let bpm = d.bpm else { return "Load a track to analyse it" }
        return String(format: "%.2f BPM · %@", bpm, d.playing ? "playing" : "ready")
    }

    var lanesPanel: some View {
        Panel(color: TJ.lav) {
            HStack {
                Cap(text: "Handoff \(m.decks[m.outgoing].name) → \(m.decks[1 - m.outgoing].name)")
                Spacer()
                Button("Back to \(m.decks[m.outgoing].name)") { m.mix.backToStable() }
                Button("Stop all") { m.stopAll() }
            }
            ForEach([Band.high, .mid, .low], id: \.self) { band in
                HStack(spacing: 10) {
                    Text(band.rawValue.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(1.2)
                        .foregroundColor(.black).frame(width: 58, height: 22).background(TJ.band(band))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Slider(value: Binding(get: { m.lanes[band] ?? 0 }, set: { m.setLane(band, $0) }), in: 0...1)
                        .tint(TJ.band(band))
                    Text(String(format: "%3.0f%%", (m.lanes[band] ?? 0) * 100)).font(.system(size: 12)).monospacedDigit()
                        .foregroundColor(TJ.mute).frame(width: 40, alignment: .trailing)
                    Button("Flick") { m.flick(band) }
                }
            }
            Text("Lanes run from the outgoing track (left) to the incoming one (right). A flick lands on the next bar. When every lane reaches the right, the handoff finishes on the next bar and the decks swap roles.")
                .font(.system(size: 11.5)).foregroundColor(TJ.mute).fixedSize(horizontal: false, vertical: true)
        }
    }

    var connectPanel: some View {
        Panel(color: TJ.mint) {
            Cap(text: "Touch surfaces")
            if let url = m.connectURL {
                HStack(alignment: .top, spacing: 12) {
                    if let qr = qrImage(url) {
                        Image(nsImage: qr).interpolation(.none).resizable().frame(width: 110, height: 110)
                            .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scan with a phone on the same Wi-Fi, or open:").font(.system(size: 12)).foregroundColor(TJ.mute)
                        Text(url).font(.system(size: 13, weight: .semibold)).textSelection(.enabled)
                        Text("\(m.surfaces) connected").font(.system(size: 12, weight: .semibold))
                            .foregroundColor(m.surfaces > 0 ? TJ.mint : TJ.mute)
                    }
                }
            } else {
                Text("No network address found. Connect to Wi-Fi.").font(.system(size: 12)).foregroundColor(TJ.mute)
            }
        }
    }

    func qrImage(_ s: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(s.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

// MARK: - Launch splash

/// Shown for a moment at launch while the engine and control server start.
struct SplashView: View {
    @State private var appear = false
    var body: some View {
        ZStack {
            TJ.bg
            VStack(spacing: 18) {
                if let img = NSImage(contentsOf: AppModel.surfaceFolder().appendingPathComponent("tj-icon.png")) {
                    Image(nsImage: img).resizable().frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .scaleEffect(appear ? 1 : 0.9)
                }
                Text("Touch Jockey").font(.system(size: 30, weight: .bold))
                Text("Starting the audio engine and touch surfaces…").font(.system(size: 13)).foregroundColor(TJ.mute)
            }
            .opacity(appear ? 1 : 0)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appear = true } }
    }
}
