import AppKit
import SwiftUI
import TJCore

@main
struct TouchJockeyApp: App {
    @StateObject private var model = AppModel()
    @AppStorage(UIScale.key) private var uiScale: Double = 1
    @AppStorage(infoTipsKey) private var showInfoTips = true

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("Touch Jockey") {
            ContentView()
                .id(uiScale)          // rebuild every view so all text picks up the new size
                .environmentObject(model)
                .environmentObject(model.library)
                .frame(minWidth: 1240, minHeight: 760)
                .preferredColorScheme(.dark)
                // Outside .id(uiScale), so changing the text size from Settings doesn't close and reopen it.
                .sheet(isPresented: $model.showSettings) {
                    SettingsView()
                        .id(uiScale)
                        .environmentObject(model)
                        .environmentObject(model.library)
                        .preferredColorScheme(.dark)
                }
                .sheet(isPresented: $model.showGuide) {
                    GuideView().id(uiScale).environmentObject(model).preferredColorScheme(.dark)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.openSettings() }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .help) {
                Button("Touch Jockey Guide") { model.showGuide = true }
                    .keyboardShortcut("?")
            }
            CommandGroup(after: .appInfo) {
                Button("Restart Touch Jockey") { AppRestart.relaunch() }
                    .keyboardShortcut("r", modifiers: [.command, .option])
            }
            CommandGroup(after: .toolbar) {
                Button("Bigger Text") { uiScale = UIScale.stepped(uiScale, by: 0.1) }
                    .keyboardShortcut("+")
                Button("Smaller Text") { uiScale = UIScale.stepped(uiScale, by: -0.1) }
                    .keyboardShortcut("-")
                Button("Actual Size") { uiScale = 1 }
                    .keyboardShortcut("0")
                Divider()
                Toggle("Show Help Icons", isOn: $showInfoTips)
            }
        }
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Restart

/// Quits and reopens the app, picking up a freshly built bundle.
enum AppRestart {
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this process to exit, then open the bundle again.
        task.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; open \"$0\"", path]
        try? task.run()
        // macOS refuses to quit while a sheet is open (the Settings sheet, where the Restart
        // button lives), so close every sheet first, then quit; force it if quitting still stalls.
        for window in NSApp.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApplication.shared.terminate(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exit(0) }
        }
    }
}

// MARK: - Text size

/// App-wide text scale, changed with ⌘+ / ⌘− / ⌘0 and remembered between launches.
enum UIScale {
    static let key = "uiScale"
    static let range: ClosedRange<Double> = 0.8...1.6
    static var current: CGFloat { CGFloat(UserDefaults.standard.object(forKey: key) as? Double ?? 1) }

    /// One step bigger or smaller, rounded to a whole 10% and kept in range.
    static func stepped(_ value: Double, by delta: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, ((value + delta) * 10).rounded() / 10))
    }
}

extension Font {
    /// The app's font at a base size, scaled by the text-size setting.
    static func tj(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * UIScale.current, weight: weight)
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
    static let rose = Color(red: 1.0, green: 0.373, blue: 0.561)
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
    /// Stretch to the height the parent offers (used to match neighbouring panels).
    var fillHeight = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
            .background(TJ.panel)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Buttons

/// The app's button: a bright outline in one colour, or filled for the main action.
/// Slightly brighter on hover, tinted when pressed, dimmed when disabled.
struct TJButtonStyle: ButtonStyle {
    var color: Color
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        TJButtonBody(configuration: configuration, color: color, filled: filled)
    }

    fileprivate struct TJButtonBody: View {
        let configuration: Configuration
        let color: Color
        let filled: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .font(.tj(12, weight: .semibold))
                .foregroundColor(filled ? .black : color)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(
                        filled ? color.opacity(pressed ? 0.75 : hover ? 0.92 : 1)
                               : color.opacity(pressed ? 0.28 : hover ? 0.14 : 0.04)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color, lineWidth: 2))
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Rectangle())
                .onHover { hover = $0 && enabled }
                .cursor(.pointingHand, enabled: enabled)
                .animation(.easeOut(duration: 0.08), value: pressed)
        }
    }
}

extension View {
    func tjButton(_ color: Color = TJ.sky, filled: Bool = false) -> some View {
        buttonStyle(TJButtonStyle(color: color, filled: filled))
    }

    /// Pop-ups and sheets: dark background with a bright border so they stand out from the window behind.
    func modalStyle(_ color: Color) -> some View {
        background(TJ.bg)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color, lineWidth: 2.5))
    }
}

struct Cap: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.tj(11, weight: .bold)).tracking(1.2).foregroundColor(TJ.gold)
    }
}

// MARK: - Window

struct ContentView: View {
    @EnvironmentObject var m: AppModel

    /// Only on the first appearance; text-size changes rebuild this view without showing it again.
    private static var splashDone = false
    @State private var showSplash = !ContentView.splashDone

    var body: some View {
        // Decks, timeline and mixer on top; the library table fills the rest; status line last.
        VStack(alignment: .leading, spacing: 10) {
            mainColumn
            LibraryView().frame(minHeight: 170, maxHeight: .infinity)
            if let ch = m.practiceChapter { practiceBar(ch) }
            statusLine
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .padding(.top, 4)
        .background(TJ.bg)
        .overlay {
            if showSplash { SplashView().transition(.opacity) }
        }
        .onAppear {
            WindowPlacement.fullScreenOnLaptop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                ContentView.splashDone = true
                withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
            }
        }
        .coordinateSpace(name: tooltipSpace)
        .overlay(TooltipLayer())
    }

    var mainColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                deckCard(0)
                deckCard(1)
            }
            Panel(color: TJ.sky) {
                DeckTimeline(mix: m.mix).frame(height: 116)   // two compact lanes; the rest of the window goes to the mixer and library
                    .overlay(alignment: .topTrailing) {
                        InfoTip("""
                            **Timeline**: both tracks lined up beat for beat.

                            **The white line** is now; the music scrolls past it.

                            **Lines**: faint for **beats**, brighter for **bars** (4 beats), labelled for **phrases** (8 bars). Dance tracks change on phrases, so that's where to start a transition.

                            **The gold line** marks where the incoming track starts. **Dashed** means it isn't cued yet: it only shows the next phrase. **Click the timeline** (or press **Next phrase**) to start it there.

                            **Colour**: bright for the **bass**, the lighter outline for everything else.

                            **Jog**: drag a **stopped** deck's waveform left or right to move through it; it snaps to the nearest beat when you let go. Press **CUE** there to make it the cue point, or **PLAY** to start from there. A playing deck can't be dragged, so it never slips out of sync.
                            """)
                            .padding(6)
                    }
            }
            // Mixer panel (phone connection lives in Settings now).
            HStack(alignment: .top, spacing: 10) {
                MixerPanel()
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Shown after "Go practice" in the guide: what you're practising, the exercise, and the way back.
    func practiceBar(_ ch: GuideChapter) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.dance").foregroundColor(TJ.sky)
            Text("Practising").font(.tj(11, weight: .heavy)).tracking(1).foregroundColor(TJ.sky)
            Text(ch.title).font(.tj(13, weight: .semibold)).lineLimit(1)
            if let steps = ch.practice {
                InfoTip("**Practice: \(ch.title)**\n\n" + steps)
            }
            Spacer()
            Button { m.showGuide = true } label: { Label("Back to the guide", systemImage: "book") }
                .tjButton(TJ.gold, filled: true)
            Button { m.practiceChapter = nil } label: { Image(systemName: "xmark") }
                .tjButton(TJ.mute)
                .tip("**Stop practising**: hide this bar. The guide remembers where you were.")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(TJ.sky.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TJ.sky, lineWidth: 2))
    }

    var statusLine: some View {
            HStack(spacing: 8) {
                Text(m.status).font(.tj(11)).foregroundColor(TJ.mute).lineLimit(1)
                Spacer()
                connectedIndicator
                Button { m.showGuide = true } label: { Label("Guide", systemImage: "book") }
                    .tjButton(TJ.gold)
                    .tip("**DJ Guide**: learn DJing step by step, one technique at a time.\n\nShortcut: **⌘?**")
                Button { m.openSettings() } label: { Image(systemName: "gearshape") }
                    .tjButton(TJ.mute)
                    .tip("**Settings**: connect a phone, text size, library folder, playback options and more.\n\nShortcut: **⌘,**")
            }
    }

    func deckCard(_ i: Int) -> some View {
        let d = m.decks[i]
        let isOut = m.outgoing == i
        return deckCardBody(i, d, isOut)
            // Role label tucked into the card's top-right corner.
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    Cap(text: isOut ? "Outgoing" : "Incoming")
                    InfoTip(isOut
                        ? "**Outgoing deck**: the track the crowd hears now.\n\nIt's the **master**, so it sets the tempo. You blend away from it with the **handoff lanes**."
                        : "**Incoming deck**: the next track.\n\n1. **Load** it from the library.\n2. **Start** it: it plays silently, synced to the master.\n3. **Move the lanes** to bring it in.\n\nWhen every lane reaches it, it becomes the outgoing deck.")
                }
                .padding(.top, 7).padding(.trailing, 10)
            }
    }

    private func deckCardBody(_ i: Int, _ d: AppModel.DeckInfo, _ isOut: Bool) -> some View {
        Panel(color: TJ.deck(i)) {
            HStack(spacing: 10) {
                Text(d.name).font(.tj(15, weight: .heavy)).foregroundColor(.black)
                    .frame(width: 30, height: 30).background(TJ.deck(i)).clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.title.isEmpty ? "No track" : d.title).font(.tj(14, weight: .semibold)).lineLimit(1)
                    Text((d.artist.isEmpty ? "" : d.artist + " · ") + meta(d)).font(.tj(12)).foregroundColor(TJ.mute).monospacedDigit()
                }
                Spacer(minLength: 90)   // room for the role label in the corner
            }
            HStack {
                if d.loading {
                    Text("Analysing…").font(.tj(12, weight: .semibold)).foregroundColor(TJ.gold)
                }
                Spacer()
                if isOut, let beat = m.beat {
                    Text("Bar \(Int(floor(beat / 4)) + 1) · beat \(Int(floor(beat)) % 4 + 1)")
                        .font(.tj(12, weight: .semibold)).monospacedDigit().foregroundColor(TJ.gold)
                }
                if !isOut {
                    Button("Bring in next bar") { m.cueIncoming(every: 4) }
                        .disabled(d.bpm == nil || !m.decks[m.outgoing].playing).tjButton(TJ.deck(i))
                        .tip("**Bring in next bar**: start this track from bar 1, synced, at the start of the master\'s next bar.\n\nIt stays **silent** until you move the lanes.")
                    Button("Next phrase") { m.cueIncoming(every: 32) }
                        .disabled(d.bpm == nil || !m.decks[m.outgoing].playing).tjButton(TJ.deck(i))
                        .tip("**Next phrase**: start this track from bar 1, synced, when the master reaches its next **phrase** (8 bars).\n\nPhrases are where dance tracks change, so this is the natural moment to bring a track in.")
                }
                // CDJ-style transport: CUE, PLAY/PAUSE, then SYNC (incoming) or MASTER (outgoing).
                CueButton(color: TJ.deck(i), enabled: d.bpm != nil,
                          onDown: { m.cueDown(i) }, onUp: { m.cueUp(i) })
                    .tip(d.playing ? "**CUE**: jump back to the **cue point** and pause."
                          : d.atCue ? "**CUE**: hold to **preview** from the cue point; let go to return.\n\nPress **PLAY** while holding to keep it playing."
                          : "**CUE**: set the **cue point** here, snapped to the nearest beat.\n\nCUE always comes back to this spot.")
                Button { m.togglePlay(i) } label: {
                    Image(systemName: d.playing ? "pause.fill" : "play.fill").frame(width: 16)
                }
                .disabled(d.bpm == nil).tjButton(TJ.deck(i), filled: true)
                .tip(d.playing ? "**PAUSE**. Press again to carry on from here."
                      : isOut || !m.decks[m.outgoing].playing || !m.syncOn ? "**PLAY** from \(d.paused ? "where you paused" : "the cue point"), at the track's own tempo."
                      : "**PLAY**, synced to the master, starting on its next beat.\n\nIt's **silent** until you move the lanes.")
                if isOut {
                    Text("MASTER").font(.tj(11, weight: .heavy)).tracking(1).foregroundColor(TJ.deck(i))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(TJ.deck(i).opacity(0.5), lineWidth: 1.5))
                        .tip("**Master**: this deck sets the tempo.\n\nThe other deck syncs to it.")
                } else {
                    Button("SYNC") { m.toggleSync() }.tjButton(TJ.deck(i), filled: m.syncOn)
                        .tip(m.syncOn ? "**SYNC on**: this deck follows the master's **tempo** and **beat**.\n\nClick to turn it off and play at its own tempo."
                              : "**SYNC off**: this deck plays at its own tempo.\n\nClick to lock it to the master's tempo and beat.")
                }
            }
        }
    }

    func meta(_ d: AppModel.DeckInfo) -> String {
        guard let bpm = d.bpm else { return "Double-click a track in the library" }
        return String(format: "%.2f BPM%@%@ · %@", bpm, d.bpmUnsure ? " (unsure)" : "", d.key.map { " · key \($0)" } ?? "", d.playing ? "playing" : d.paused ? "paused" : "ready")
    }

    /// How many phones and tablets are connected. Click for the code to scan and the steps.
    var connectedIndicator: some View {
        Button { m.openSettings(.connect) } label: {
            Label(m.surfaces == 1 ? "1 connected" : "\(m.surfaces) connected",
                  systemImage: "iphone.radiowaves.left.and.right")
                .font(.tj(11.5, weight: .semibold)).monospacedDigit()
                .foregroundColor(m.surfaces > 0 ? TJ.mint : TJ.mute)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tip("**Surfaces**: phones and tablets you use as touch controllers. This counts the ones connected now.\n\n**Click** for the code to scan and step-by-step instructions.")
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
                Text("Touch Jockey").font(.tj(30, weight: .bold))
                Text("Starting the audio engine and touch surfaces…").font(.tj(13)).foregroundColor(TJ.mute)
            }
            .opacity(appear ? 1 : 0)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appear = true } }
    }
}

// MARK: - CUE button

/// CUE needs press and release separately (hold to preview), so it uses a gesture instead of Button.
struct CueButton: View {
    let color: Color
    let enabled: Bool
    let onDown: () -> Void
    let onUp: () -> Void
    @State private var held = false
    @State private var hover = false

    var body: some View {
        Text("CUE")
            .font(.tj(12, weight: .heavy)).tracking(0.5)
            .foregroundColor(color)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(held ? 0.3 : hover ? 0.14 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color, lineWidth: 2))
            .opacity(enabled ? 1 : 0.35)
            .contentShape(Rectangle())
            .onHover { hover = $0 && enabled }
            .cursor(.pointingHand, enabled: enabled)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard enabled, !held else { return }
                    held = true
                    onDown()
                }
                .onEnded { _ in
                    guard held else { return }
                    held = false
                    onUp()
                })
    }
}
