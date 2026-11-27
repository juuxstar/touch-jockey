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

extension SkillProgress.Unlock {
    var title: String {
        switch self {
        case .freeTiming: return "Free bass-swap timing"
        case .cue: return "CUE buttons"
        }
    }

    /// What changed, in a line, when it's unlocked.
    var unlockedLine: String {
        switch self {
        case .freeTiming: return "Your Flicks can land when you make them, not on the next bar."
        case .cue: return "Each deck has a CUE button now, to set your own starting points."
        }
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
            // The library, with the last handoff's scorecard beside it once there is one.
            HStack(alignment: .top, spacing: 10) {
                // The library gives up width (its text columns narrow) so the scorecard always fits.
                LibraryView().frame(minWidth: 0, maxWidth: .infinity)
                if m.scoring { scoringCard.frame(width: 340).layoutPriority(1) }
                else if let r = m.lastReport { scorecard(r).frame(width: 340).layoutPriority(1) }
            }
            .frame(minHeight: 170, maxHeight: .infinity)
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

    @AppStorage(SettingsKey.timelineBars) private var timelineBars = 12
    @AppStorage(SettingsKey.timelineLineUp) private var lineUp = false

    /// A row of small segment buttons, as on the timeline's corner.
    private func segment(_ title: String, on: Bool, minWidth: CGFloat = 26, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.tj(10.5, weight: .heavy)).monospacedDigit()
                .foregroundColor(on ? .black : TJ.sky)
                .frame(minWidth: minWidth).padding(.vertical, 3).padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(on ? TJ.sky : Color.black.opacity(0.55)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func segmentGroup<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 2, content: content)
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.45)))
    }

    /// Timeline or line-up view.
    var timelineMode: some View {
        segmentGroup {
            segment("TIMELINE", on: !lineUp) { lineUp = false }
                .tip("**Timeline**: both tracks scrolling past the white line, beat for beat, as they play.")
            segment("LINE UP", on: lineUp) { lineUp = true }
                .tip("**Line up**: both whole tracks, one above the other. **Drag the waiting track** under the playing one to choose where it comes in; it then starts there by itself.")
        }
    }

    /// The timeline's zoom: how many bars it shows.
    var timelineZoom: some View {
        segmentGroup {
            ForEach([12, 32, 64, 128], id: \.self) { n in
                segment("\(n)", on: timelineBars == n) { timelineBars = n }
            }
            Text("BARS").font(.tj(9.5, weight: .heavy)).tracking(1).foregroundColor(TJ.sky).padding(.leading, 3)
        }
        .tip("**Zoom**: how many bars the timeline shows. Zoom out to **64** or **128** to see a whole blend: the new track's intro and bass against the playing track's outro.")
    }

    static let timelineHelp = """
                            **Timeline**: both tracks lined up beat for beat.

                            **The white line** is now; the music scrolls past it.

                            **Lines**: faint for **beats**, brighter for **bars** (4 beats), labelled for **phrases** (8 bars). Dance tracks change on phrases, so that's where to start a transition.

                            **The gold line** marks where the incoming track starts. **Dashed** means it isn't cued yet: it shows where **Next phrase** would start it (on the next phrase line), or **Play all** with both decks stopped (at the white line). **Click the timeline** (or press **Next phrase**) to start it there.

                            **A stopped track** is drawn as it will play, starting at the gold line; what comes before its start spot isn't drawn, because it won't play. **Drag its waveform** to choose which part starts on the line.

                            **Colour**: bright for the **bass**, the lighter outline for everything else.

                            **Zoom**: **12 bars** to see the beats; **32**, **64** or **128** to see a whole blend, one track's outro over the other's intro. With both decks stopped, the tracks line up as **Play all** will start them, so you can see where the new track's intro and bass fall before you press it.

                            **Jog**: drag a **stopped** deck's waveform left or right to move through it. When you let go it snaps to the nearest **beat** at 12 bars, the nearest **bar** at 32, and the nearest **phrase** at 64 or 128. Press **CUE** there to make it the cue point, or **PLAY** to start from there. A playing deck can't be dragged, so it never slips out of sync.

                            **Line up**: switch to it to drag the waiting track under the playing one and plan where it comes in. A planned start shows here as a solid gold line.
                            """

    static let lineUpHelp = """
        **Line up**: both whole tracks, one above the other, on the playing track's bars. Anything stacked vertically plays at the same moment.

        **Drag the waiting track** left or right to choose the bar it starts on; it snaps to phrase lines. The gold line and its label say where. When the playing track gets there, the waiting track **starts by itself**, synced, from its start spot. Until you drag it, a dimmed suggestion shows four phrases before the end.

        **Further left** than the playing track allows (it can't start in the part that has already played), it keeps sliding and starts **later in its own track**: the part that would have played already is skipped. Drag it back to undo that.

        Line its **intro** up under the playing track's **outro**, so its bass comes in as the other's goes.

        **Which part of it starts**: click the waiting deck's overview to choose. The line-up redraws from there.

        **Both decks stopped**: drag the playing track's lane to move where it starts, then press **Play all**. It starts that track, and the other comes in where you put it.

        **Next phrase** or **Next bar** still start it straight away, and drop the plan. So does **Clear**.
        """

    var mainColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                deckCard(0)
                deckCard(1)
            }
            Panel(color: TJ.sky) {
                Group {
                    if lineUp { LineUpView(mix: m.mix) }
                    else { DeckTimeline(mix: m.mix, beatsVisible: Double(timelineBars * 4)) }
                }
                .frame(height: 116)   // two compact lanes; the rest of the window goes to the mixer and library
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 6) {
                        if lineUp, m.plannedEntry != nil {
                            segment("CLEAR", on: false) { m.mix.planIncoming(atBeat: nil) }
                                .tip("**Clear**: drop the plan. The waiting track then waits for **Next phrase** or **Next bar** again.")
                        }
                        timelineMode
                        if !lineUp { timelineZoom }
                        InfoTip(lineUp ? Self.lineUpHelp : Self.timelineHelp)
                    }
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

    /// While a handoff is under way: where its scorecard will go, with the checks it is
    /// being scored on pulsing in turn.
    var scoringCard: some View {
        Panel(color: TJ.sky, fillHeight: true) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(TJ.sky)
                Text("Scoring this handoff").font(.tj(11, weight: .heavy)).tracking(1).textCase(.uppercase)
                    .foregroundColor(TJ.sky).lineLimit(1)
                Spacer(minLength: 0)
            }
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { t in
                let phase = t.date.timeIntervalSinceReferenceDate
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(HandoffCoach.checkTitles.enumerated()), id: \.offset) { k, title in
                        // A pulse that runs down the list, one check after another.
                        let wave = 0.5 + 0.5 * cos((phase * 1.6 - Double(k) * 0.55) * .pi)
                        HStack(spacing: 8) {
                            Circle().fill(TJ.sky.opacity(0.25 + 0.75 * wave)).frame(width: 9, height: 9)
                                .scaleEffect(0.8 + 0.3 * wave)
                            Text(title).font(.tj(12.5, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.45 + 0.4 * wave))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Text("Your scorecard appears when every lane reaches the new track and the old one stops.")
                .font(.tj(11.5)).foregroundColor(TJ.mute).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// After a handoff at the handoff level: each check passed or missed, progress towards the
    /// next unlock, and anything this handoff unlocked.
    func scorecard(_ r: HandoffReport) -> some View {
        let color = r.clean ? TJ.mint : TJ.gold
        let passed = r.checks.filter(\.passed).count
        let next = SkillProgress.Unlock.allCases.first { !m.progress.isUnlocked($0) }
        return Panel(color: color, fillHeight: true) {
            HStack(spacing: 8) {
                Image(systemName: r.clean ? "checkmark.seal.fill" : "list.bullet.clipboard").foregroundColor(color)
                Text(r.clean ? "Scorecard · all \(r.checks.count) checks passed" : "Scorecard · \(passed) of \(r.checks.count) checks passed")
                    .font(.tj(11, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundColor(color)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button { m.lastReport = nil; m.newUnlocks = [] } label: { Image(systemName: "xmark") }
                    .tjButton(TJ.mute)
                    .tip("**Close** the scorecard. The next handoff brings a new one.")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(m.newUnlocks, id: \.self) { u in
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Unlocked: \(u.title)", systemImage: "lock.open.fill")
                                .font(.tj(13, weight: .bold)).foregroundColor(TJ.gold)
                            Text(u.unlockedLine).font(.tj(12)).foregroundColor(TJ.mute)
                                .fixedSize(horizontal: false, vertical: true)
                            if u == .freeTiming, m.ladder.timing != .free {
                                Button("Switch to Free") { m.setLevel(.free) }
                                    .tjButton(TJ.gold, filled: true)
                                    .tip("**Free timing**: from now on a Flick lands the moment you make it. Step back to **Snap** any time in **Settings → Your skills**.")
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(TJ.gold.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(TJ.gold, lineWidth: 1.5))
                    }
                    ForEach(Array(r.checks.enumerated()), id: \.offset) { k, c in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: c.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(c.passed ? TJ.mint : TJ.rose)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).font(.tj(12.5, weight: .semibold))
                                    .foregroundColor(c.passed ? .white : TJ.rose)
                                Text(k == 1 ? c.detail + Self.offsetText(r.bassSwapOffsetMs) : c.detail)
                                    .font(.tj(11.5)).foregroundColor(TJ.mute)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let advice = c.advice {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Image(systemName: "lightbulb.fill").font(.tj(10.5)).foregroundColor(TJ.gold)
                                        Text("Next time: " + advice).font(.tj(11.5)).foregroundColor(Color.white.opacity(0.85))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.top, 2)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 5) {
                if let next {
                    Text("\(m.progress.cleanHandoffs) of \(next.cleanHandoffsNeeded) clean handoffs to unlock \(next.title)")
                        .font(.tj(12)).foregroundColor(TJ.mute).monospacedDigit()
                    ProgressView(value: Double(min(m.progress.cleanHandoffs, next.cleanHandoffsNeeded)),
                                 total: Double(next.cleanHandoffsNeeded))
                        .tint(TJ.mint)
                } else {
                    Text("\(m.progress.cleanHandoffs) clean handoffs. Everything is unlocked.")
                        .font(.tj(12)).foregroundColor(TJ.mute).monospacedDigit()
                }
            }
        }
    }

    /// " 18 ms early." for a free bass swap; nothing at snap, where it lands on the bar.
    static func offsetText(_ ms: Double?) -> String {
        guard let ms else { return "" }
        let n = Int(abs(ms).rounded())
        return n < 5 ? " Right on the 1." : " \(n) ms \(ms < 0 ? "early" : "late")."
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
            if ch.wantsPracticeTracks {
                Button { m.setUpPractice() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    .tjButton(TJ.sky)
                    .tip("**Reset**: stop, and set the two decks up again: the deck you mix out of near its end, the other at bar 1."
                         + (m.ladder.blend != .mixer ? " The handoff lanes go back to the outgoing deck."
                            : ch.practiceMixerStart == .crossfader
                            ? " The mixer starts over too: every EQ in the centre, both faders up, and the crossfader on the outgoing deck's side."
                            : " The mixer starts over too: every EQ in the centre, the outgoing deck's fader up and the incoming deck's down.")
                         + "\n\nPress **Play all** for another run.")
                Button { m.setUpPractice(newPair: true) } label: { Label("New pair", systemImage: "shuffle") }
                    .tjButton(TJ.sky)
                    .tip("**New pair**: load two different tracks from your library, with similar tempos and keys that blend, and set them up for practice.")
            }
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
                    Cap(text: isOut ? "Outgoing · Master" : "Incoming")
                    InfoTip(isOut
                        ? "**Outgoing deck**: the track the crowd hears now.\n\nIt's the **master**: it sets the tempo, and the other deck syncs to it. You blend away from it with the **handoff lanes**.\n\nA deck playing on its own is always the outgoing deck: pause this one while the other plays and they swap."
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
                Spacer(minLength: 150)   // room for the role label in the corner
            }
            DeckPosition(mix: m.mix, deck: i, color: TJ.deck(i))
            HStack {
                if !isOut {
                    Button { m.cueMatch() } label: { Label("Cue a match", systemImage: "wand.and.stars") }
                        .disabled(!m.canCueMatch).tjButton(TJ.deck(i))
                        .tip("**Cue a match**: load a track from your library that blends with the outgoing one: a tempo within 6%, and a key that sits next to it on the Camelot wheel when there is one.\n\nIt goes on this deck at bar 1, ready for **Next phrase**. Press again for a different one; each press replaces the track on this deck.")
                }
                if d.loading {
                    Text("Analysing…").font(.tj(12, weight: .semibold)).foregroundColor(TJ.gold)
                }
                Spacer()
                if !isOut {
                    Button("Next bar") { m.cueIncoming(every: 4) }
                        .disabled(d.bpm == nil || !m.decks[m.outgoing].playing).tjButton(TJ.deck(i))
                        .tip("**Next bar**: start this track on the master's next **bar**, at most 4 beats away.\n\nQuick, but it lands on a phrase line only if you press it in the last bar of a phrase. To start in phrase every time, use **Next phrase**.\n\nIt plays from where it's parked, synced and **silent** until you move the lanes.")
                    Button("Next phrase") { m.cueIncoming(every: 32) }
                        .disabled(d.bpm == nil || !m.decks[m.outgoing].playing).tjButton(TJ.deck(i))
                        .tip("**Next phrase**: start this track when the master reaches its next **phrase** line, up to 8 bars away.\n\nPhrases are where dance tracks change, so the track always comes in in phrase. To start sooner, use **Next bar**.\n\nIt plays from where it's parked, synced and **silent** until you move the lanes.")
                    InfoTip("**Next bar** and **Next phrase** both start this track from where it's parked, synced to the master and **silent** until you move the lanes. They differ in **when** it starts:\n\n- **Next bar**: on the master's next bar, at most 4 beats away. Quick, but in phrase only if you press it in the last bar of a phrase.\n- **Next phrase**: on the master's next phrase line, up to 8 bars away. Always in phrase, which is what the scorecard checks.\n\nUse **Next phrase** for your handoffs.")
                }
                if m.headphones != nil {
                    Button { m.toggleCue(i) } label: { Image(systemName: "headphones").frame(width: 18) }
                        .tjButton(TJ.deck(i), filled: m.cue[i])
                        .tip(m.cue[i] ? "**In your headphones**: this deck plays in your headphones. Click to take it out.\n\nThe crowd hears it only through the mixer."
                                      : "**Headphones**: hear this deck in your headphones, even while it's silent in the speakers.\n\nUse it to check the next track before you bring it in.")
                }
                // CDJ-style transport: CUE, PLAY/PAUSE, then SYNC on the incoming deck. The master is named in the role label.
                // CUE is earned with clean handoffs (see SkillProgress); until then Go practice places the tracks.
                if m.progress.isUnlocked(.cue) {
                CueButton(color: TJ.deck(i), enabled: d.bpm != nil,
                          onDown: { m.cueDown(i) }, onUp: { m.cueUp(i) })
                    .tip(d.playing ? "**CUE**: jump back to the **cue point** and pause."
                          : d.atCue ? "**CUE**: hold to **preview** from the cue point; let go to return.\n\nPress **PLAY** while holding to keep it playing."
                          : "**CUE**: set the **cue point** here, snapped to the nearest beat.\n\nCUE always comes back to this spot.")
                }
                Button { m.togglePlay(i) } label: {
                    Image(systemName: d.playing ? "pause.fill" : "play.fill").frame(width: 16)
                }
                .disabled(d.bpm == nil).tjButton(TJ.deck(i), filled: true)
                .tip(d.playing ? "**PAUSE**. Press again to carry on from here."
                      : isOut || !m.decks[m.outgoing].playing || !m.syncOn ? "**PLAY** from \(d.paused ? "where you paused" : "the cue point"), at the track's own tempo."
                      : "**PLAY**, synced to the master, starting on its next beat.\n\nIt's **silent** until you move the lanes.")
                if !isOut {
                    Button("SYNC") { m.toggleSync() }.tjButton(TJ.deck(i), filled: m.syncOn)
                        .tip(m.syncOn ? "**SYNC on**: this deck follows the master's **tempo** and **beat**. A track loaded here takes the master's tempo straight away, so its BPM already shows the synced tempo; the library shows its own.\n\nClick to turn it off and play at its own tempo."
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
