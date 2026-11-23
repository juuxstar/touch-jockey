import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import TJCore

// MARK: - Keys

/// UserDefaults keys for the settings window. Text size (`UIScale.key`), help icons
/// (`infoTipsKey`) and the library folder (`LibraryModel`) keep their own keys.
enum SettingsKey {
    /// Whether SYNC is on when the app starts. The SYNC button still changes it for the session.
    static let syncOnByDefault = "syncOnByDefault"
    /// Stop the display and the Mac from sleeping while a deck plays.
    static let keepAwake = "keepAwakeWhilePlaying"
    /// The learning ladder, as `SkillLadder.dictionary` (`{"blend": "handoff", …}`).
    static let skillLadder = "skillLadder"
    /// Output devices, by Core Audio UID: the speakers (absent = the system default) and the
    /// headphones (absent = none).
    static let speakersDevice = "speakersDevice"
    static let headphonesDevice = "headphonesDevice"
    /// The headphone cue mix, 0 (cued decks only) … 1 (speaker mix only).
    static let cueMix = "cueMix"

    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}

// MARK: - Sections

enum SettingsSection: String, CaseIterable, Identifiable {
    case connect, skills, display, library, playback, audio, app
    var id: String { rawValue }

    var title: String {
        switch self {
        case .connect: return "Connect a phone"
        case .skills: return "Your skills"
        case .display: return "Display"
        case .library: return "Library"
        case .playback: return "Playback"
        case .audio: return "Audio"
        case .app: return "About"
        }
    }

    var icon: String {
        switch self {
        case .connect: return "iphone.radiowaves.left.and.right"
        case .skills: return "graduationcap"
        case .display: return "textformat.size"
        case .library: return "music.note.list"
        case .playback: return "play.circle"
        case .audio: return "headphones"
        case .app: return "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .connect: return TJ.mint
        case .skills: return TJ.gold
        case .display: return TJ.sky
        case .library: return TJ.lav
        case .playback: return TJ.a
        case .audio: return TJ.b
        case .app: return TJ.gold
        }
    }
}

// MARK: - Window

/// Settings and rarely needed options, in a sheet over the main window so the window keeps its space for DJing.
/// Opened with ⌘, (Touch Jockey → Settings…), the gear in the status line, or the connected-devices indicator.
struct SettingsView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var lib: LibraryModel
    @AppStorage(UIScale.key) private var uiScale: Double = 1
    @AppStorage(infoTipsKey) private var showInfoTips = true
    @AppStorage(SettingsKey.syncOnByDefault) private var syncOnByDefault = true
    @AppStorage(SettingsKey.keepAwake) private var keepAwake = true
    @State private var copied = false

    private var s: CGFloat { UIScale.current }
    private var section: SettingsSection { m.settingsSection }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                sidebar
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 6) {
                            Cap(text: section.title)
                            InfoTip(sectionHelp)
                            Spacer()
                        }
                        content
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            HStack {
                Spacer()
                Button("Done") { m.showSettings = false }
                    .keyboardShortcut(.defaultAction)
                    .tjButton(TJ.sky, filled: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .frame(width: 700 * s, height: 450 * s)
        // Esc closes too.
        .background(Button("") { m.showSettings = false }.keyboardShortcut(.cancelAction).opacity(0))
        .modalStyle(TJ.sky)
        .tooltipScope("tjSettingsTooltipSpace")
        .onAppear { TooltipCenter.shared.hideAll() }   // a tip from the main window would linger under the sheet
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsSection.allCases) { sec in
                let on = sec == section
                Button { m.settingsSection = sec } label: {
                    HStack(spacing: 8) {
                        Image(systemName: sec.icon).frame(width: 18 * s)
                        Text(sec.title).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.tj(12.5, weight: .semibold))
                    .foregroundColor(on ? sec.color : TJ.mute)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(on ? sec.color.opacity(0.14) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? sec.color : .clear, lineWidth: 2))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 190 * s)
    }

    // MARK: Sections

    @ViewBuilder private var content: some View {
        switch section {
        case .connect: connect
        case .skills: skills
        case .display: display
        case .library: library
        case .playback: playback
        case .audio: audio
        case .app: app
        }
    }

    private var sectionHelp: String {
        switch section {
        case .connect: return """
            **Surfaces**: phones and tablets you use as touch controllers. They open a web page from this Mac, so there's nothing to install.

            Any number can connect at once. **Touch ownership** stops two fingers on different devices fighting over the same lane.
            """
        case .skills: return """
            **Your skills**: Touch Jockey starts you on simpler controls, and swaps each one for the real thing once you've got the hang of it.

            Each **technique** has its own ladder. **Click a level** to move to it. You can step up or down at any time, even in the middle of a mix: the sound carries over.
            """
        case .display: return """
            **Text size** scales every label and button in Touch Jockey.

            **Help icons** are these little ⓘ symbols. Turn them off once you know your way around; the **tooltips** on buttons stay.
            """
        case .library: return """
            **Library folder**: Touch Jockey shows every track in this folder and its subfolders.

            **Analysis** finds each track's **BPM** (tempo) and **beat grid** (where every beat falls), then saves it so tracks load instantly.
            """
        case .playback: return """
            **Playback** settings change how the decks behave.

            **SYNC** locks the incoming track's tempo and beat to the outgoing one, so the two play in time.
            """
        case .audio: return """
            **Speakers** play the mix: what the crowd hears.

            **Headphones** are for **cueing**: hearing the next track before anyone else does. Choose a headphone output and each deck gets a **headphones button**. Press it to hear that deck in your headphones, even while it's silent in the speakers. The **cue mix** slider beside the mixer sets what the headphones play: only the decks you've cued, only the speaker mix, or both.

            The headphones need their **own output**: a separate device (USB or Bluetooth headphones, or a second sound card), or channels 3–4 of a DJ controller or an audio interface. They can't share the speakers' output.
            """
        case .app: return "**Touch Jockey**: a DJ app for beginners. The Mac plays the music; phones and tablets are the controllers."
        }
    }

    private var connect: some View {
        HStack(alignment: .top, spacing: 20) {
            Group {
                if let url = m.connectURL, let qr = qrImage(url) {
                    Image(nsImage: qr).interpolation(.none).resizable().frame(width: 190 * s, height: 190 * s)
                        .padding(8).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 10))
                        .tip("**QR code**: point the phone's camera at it to open the touch surface.")
                } else {
                    Image(systemName: "wifi.slash").font(.tj(40)).foregroundColor(TJ.mute)
                        .frame(width: 206 * s, height: 206 * s)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.15), lineWidth: 1.5))
                        .tip("**No network**: this Mac has no Wi-Fi or network address, so phones can't reach it.")
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                if let url = m.connectURL {
                    HStack(spacing: 8) {
                        Text(url).font(.tj(17, weight: .semibold)).textSelection(.enabled).lineLimit(1)
                        Button(copied ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                            copied = true
                        }
                        .tjButton(TJ.mint)
                    }
                } else {
                    Text("No network address found. Connect this Mac to Wi-Fi.").font(.tj(13)).foregroundColor(TJ.mute)
                }
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Join the same Wi-Fi network as this Mac.")
                    step(2, "Scan the code with the camera, or type the address into the browser.")
                    step(3, "On iPhone: in Safari tap Share, then Add to Home Screen. Open it from the icon for full screen.")
                    step(4, "Hold the phone upright or sideways: the controls fit either way.")
                }
                Label(m.surfaces == 1 ? "1 connected now" : "\(m.surfaces) connected now",
                      systemImage: "iphone.radiowaves.left.and.right")
                    .font(.tj(13, weight: .semibold)).monospacedDigit()
                    .foregroundColor(m.surfaces > 0 ? TJ.mint : TJ.mute)
                    .tip("**Connected**: how many phones and tablets have the touch surface open right now.")
                if m.ladder[.blend] == .mixer, m.devices.count >= 2 { deckPickers }
            }
        }
    }

    /// One row per connected surface: which deck's mixer controls it shows.
    private var deckPickers: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Mixer controls").font(.tj(13, weight: .semibold))
                InfoTip("""
                    **Mixer controls per device**: give each phone one deck, and its channel gets the whole screen. **A + B** shows both channels on that device.

                    The **crossfader** shows on every device. You can also choose on the phone itself, under the crossfader on the mixer screen.
                    """)
            }
            ForEach(m.devices) { d in
                HStack(spacing: 10) {
                    Image(systemName: d.name.hasPrefix("iPad") ? "ipad" : "iphone").foregroundColor(TJ.mute)
                    Text(d.name).font(.tj(12.5)).frame(width: 110 * s, alignment: .leading).lineLimit(1)
                    HStack(spacing: 4) {
                        ForEach(DeckAssignment.allCases, id: \.self) { a in
                            let color = a == .a ? TJ.a : a == .b ? TJ.b : TJ.gold
                            Button(a.label) { m.assign(d.id, a) }.tjButton(color, filled: d.deck == a)
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var skills: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Technique.allCases, id: \.self) { t in
                VStack(alignment: .leading, spacing: 6) {
                    Text(t.title).font(.tj(13, weight: .semibold))
                    ForEach(t.levels, id: \.self) { level in levelRow(level) }
                }
            }
        }
    }

    /// One rung of a ladder: click to move to it. The current level is highlighted.
    private func levelRow(_ level: SkillLevel) -> some View {
        let on = m.ladder[level.technique] == level
        let color = SettingsSection.skills.color
        return HStack(spacing: 8) {
            Button { m.setLevel(level) } label: {
                HStack(spacing: 10) {
                    Text("\(level.rung + 1)").font(.tj(11, weight: .heavy)).foregroundColor(on ? .black : color)
                        .frame(width: 20 * s, height: 20 * s)
                        .background(RoundedRectangle(cornerRadius: 4).fill(on ? color : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color, lineWidth: 1.5))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(level.title).font(.tj(12.5, weight: .semibold)).foregroundColor(on ? color : .white)
                        Text(level.line).font(.tj(11.5)).foregroundColor(TJ.mute).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? color.opacity(0.12) : Color.white.opacity(0.03)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? color : Color.white.opacity(0.1), lineWidth: on ? 2 : 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(OptionalTip(text: on ? nil : level.switchTip))
            InfoTip(level.help)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.tj(11, weight: .heavy)).foregroundColor(.black)
                .frame(width: 18 * s, height: 18 * s).background(TJ.mint).clipShape(RoundedRectangle(cornerRadius: 4))
            Text(text).font(.tj(12.5)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var display: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Text size") {
                Button { uiScale = UIScale.stepped(uiScale, by: -0.1) } label: { Image(systemName: "minus") }
                    .tjButton(TJ.sky).disabled(uiScale <= UIScale.range.lowerBound)
                    .tip("**Smaller text**, down to 80%.\n\nShortcut: **⌘−**")
                Text("\(Int((uiScale * 100).rounded()))%").font(.tj(13, weight: .semibold)).monospacedDigit()
                    .frame(width: 48 * s)
                    .tip("**Text size**: how big every label and button is, from 80% to 160%.")
                Button { uiScale = UIScale.stepped(uiScale, by: 0.1) } label: { Image(systemName: "plus") }
                    .tjButton(TJ.sky).disabled(uiScale >= UIScale.range.upperBound)
                    .tip("**Bigger text**, up to 160%.\n\nShortcut: **⌘+**")
                Button("Actual size") { uiScale = 1 }
                    .tjButton(TJ.sky).disabled(uiScale == 1)
                    .tip("**Actual size**: back to 100%.\n\nShortcut: **⌘0**")
            }
            row("Help icons") {
                Toggle("Show help icons", isOn: $showInfoTips).labelsHidden()
                    .toggleStyle(.switch).tint(TJ.sky)
                    .tip("**Show help icons**: the gold ⓘ symbols that explain each part of the window.\n\nAlso in **View → Show Help Icons**.")
            }
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Folder") {
                Label(lib.root.lastPathComponent, systemImage: "folder").font(.tj(13, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                    .tip("**Library folder**: \(lib.root.path)")
            }
            row("") {
                Button("Choose folder…") { lib.chooseFolder() }
                    .tjButton(TJ.lav)
                    .tip("**Choose folder**: pick which folder the library shows. Subfolders are included.")
                Button { lib.rescan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .tjButton(TJ.lav).disabled(lib.scanning)
                    .tip("**Rescan**: look for new, changed or removed files in the library folder.")
            }
            row("Tracks") {
                Text(libraryStatus).font(.tj(12.5)).foregroundColor(TJ.mute).monospacedDigit()
                    .tip("**Tracks**: how many audio files the library found, and how many still need their BPM.")
            }
            row("Analysis") {
                Button { lib.reanalyseAll() } label: { Label("Re-analyse all tracks", systemImage: "waveform") }
                    .tjButton(TJ.gold).disabled(lib.scanning)
                    .tip("""
                        **Re-analyse all tracks**: forget the saved **BPM** and **beat grid** of every track and work them out again.

                        Use it after an update that improves beat detection. It runs in the background and can take a while for a big library.
                        """)
            }
        }
    }

    private var libraryStatus: String {
        if lib.scanning { return "Scanning… \(lib.scanned) files" }
        if lib.analysing > 0 { return "\(lib.tracks.count) tracks · finding BPM, \(lib.analysing) left" }
        return "\(lib.tracks.count) tracks, all analysed"
    }

    private var playback: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("SYNC on by default") {
                Toggle("SYNC on by default", isOn: $syncOnByDefault).labelsHidden()
                    .toggleStyle(.switch).tint(TJ.a)
                    .tip("""
                        **SYNC on by default**: when Touch Jockey starts, the incoming deck follows the master's **tempo** and **beat**.

                        Turn it off to beat-match by ear. Takes effect at the next start; the **SYNC** button on the deck changes it right away.
                        """)
            }
            row("Keep Mac awake") {
                Toggle("Keep Mac awake while playing", isOn: $keepAwake).labelsHidden()
                    .toggleStyle(.switch).tint(TJ.a)
                    .tip("**Keep Mac awake while playing**: the screen won't dim or sleep while a deck is playing.\n\nOnce everything stops, your normal energy settings apply again.")
            }
        }
    }

    @State private var outputDevices: [AudioOutputs.Device] = []

    private var audio: some View {
        let spkUID = UserDefaults.standard.string(forKey: SettingsKey.speakersDevice)
        let hpUID = UserDefaults.standard.string(forKey: SettingsKey.headphonesDevice)
        let speakers = m.speakers
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Speakers").font(.tj(13, weight: .semibold))
                deviceRow("System default" + (spkUID == nil ? speakers.map { " (\($0.name))" } ?? "" : ""), icon: "hifispeaker",
                          selected: spkUID == nil) { m.setOutputs(speakers: nil, headphones: hpUID) }
                ForEach(outputDevices) { d in
                    deviceRow(d.name, icon: "hifispeaker", selected: spkUID == d.uid) { m.setOutputs(speakers: d.uid, headphones: hpUID == d.uid ? nil : hpUID) }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Headphones").font(.tj(13, weight: .semibold))
                deviceRow("None", icon: "xmark", selected: hpUID == nil) { m.setOutputs(speakers: spkUID, headphones: nil) }
                ForEach(outputDevices.filter { $0.uid != speakers?.uid || $0.channels >= 4 }) { d in
                    deviceRow(d.uid == speakers?.uid ? "\(d.name), channels 3–4" : d.name, icon: "headphones",
                              selected: hpUID == d.uid) { m.setOutputs(speakers: spkUID, headphones: d.uid) }
                }
                if hpUID != nil && m.headphones == nil {
                    Text(AudioOutputs.device(uid: hpUID!) == nil ? "Those headphones aren't connected." : "Those headphones couldn't be used with these speakers.")
                        .font(.tj(12, weight: .semibold)).foregroundColor(TJ.rose)
                }
            }
            Text("Changing an output pauses the decks.").font(.tj(12)).foregroundColor(TJ.mute)
        }
        .onAppear { outputDevices = AudioOutputs.devices() }
        .onChange(of: m.headphones) { _ in outputDevices = AudioOutputs.devices() }
        .onChange(of: m.speakers) { _ in outputDevices = AudioOutputs.devices() }
    }

    /// One choice in a device list: the whole row is the button, outlined when chosen.
    private func deviceRow(_ name: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : icon)
                    .foregroundColor(selected ? TJ.b : TJ.mute).frame(width: 18)
                Text(name).font(.tj(13, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: 34 * s)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? TJ.b.opacity(0.14) : Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? TJ.b : Color.white.opacity(0.12), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .frame(maxWidth: 420 * s)
    }

    private var app: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                if let img = NSImage(contentsOf: AppModel.surfaceFolder().appendingPathComponent("tj-icon.png")) {
                    Image(nsImage: img).resizable().frame(width: 72 * s, height: 72 * s)
                        .clipShape(RoundedRectangle(cornerRadius: 16 * s))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Touch Jockey").font(.tj(20, weight: .bold))
                    Text("Version \(Self.version)").font(.tj(12.5)).foregroundColor(TJ.mute).textSelection(.enabled)
                        .tip("**Version**: which build of Touch Jockey this is.")
                }
            }
            Button { AppRestart.relaunch() } label: { Label("Restart Touch Jockey", systemImage: "arrow.clockwise") }
                .tjButton(TJ.rose)
                .tip("**Restart**: quit and reopen Touch Jockey, for example after a new build. The music stops.\n\nShortcut: **⌥⌘R**")
        }
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development build"
    }

    /// A label on the left and its controls on the right, so rows line up.
    private func row<C: View>(_ label: String, @ViewBuilder _ controls: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.tj(13, weight: .semibold)).frame(width: 150 * s, alignment: .leading)
            controls()
            Spacer(minLength: 0)
        }
    }
}

// MARK: - QR code

/// A crisp QR code for a URL (draw it with `.interpolation(.none)`).
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

// MARK: - Skill ladder text

/// A `.tip` only when there's something a beginner wouldn't see coming.
private struct OptionalTip: ViewModifier {
    let text: String?
    func body(content: Content) -> some View {
        if let text { content.tip(text) } else { content }
    }
}

extension Technique {
    var title: String {
        switch self {
        case .blend: return "Blending"
        case .timing: return "Bass-swap timing"
        case .tempo: return "Tempo"
        }
    }
}

extension SkillLevel {
    var title: String {
        switch self {
        case .handoff: return "Handoff lanes"
        case .mixer: return "Mixer"
        case .snap: return "Snap to the bar"
        case .free: return "Free"
        case .sync: return "SYNC"
        }
    }

    /// One line under the title.
    var line: String {
        switch self {
        case .handoff: return "Three lanes move the lows, mids and highs from one track to the other."
        case .mixer: return "EQ, volume faders and a crossfader, like a club mixer."
        case .snap: return "A Flick waits for the next bar, so a bass swap always lands on the 1."
        case .free: return "A Flick lands the moment you flick: your timing decides."
        case .sync: return "Touch Jockey matches the incoming track's tempo and beat for you."
        }
    }

    /// The ⓘ help: what the level is, and when to move on.
    var help: String {
        switch self {
        case .handoff: return """
            **Handoff lanes**: on the phone (or in the Mac's Handoff panel), one lane each for **LOWS**, **MIDS** and **HIGHS**. Slide a lane from one deck to the other to hand that part of the music over.

            **Move up when you can** blend a whole track with the lanes without thinking about them: the new hats come in early, the bass swaps on a phrase, and the old track has gone by the end.
            """
        case .mixer: return """
            **Mixer**: the real thing, on the Mac and on the phone. Each deck has **HIGH**, **MID** and **LOW** EQ and a **volume** fader, with a **crossfader** between them.

            Do the same moves as with the lanes: bring the new track in with its LOW killed, then swap the bass on a phrase. To finish, **stop or pause** the old track.

            Step back to the lanes any time; the sound carries over.
            """
        case .snap: return """
            **Snap to the bar**: Flick a lane and it swaps exactly on the next **bar** (every 4 beats), so a bass swap can't land off the beat.

            **Move up when you can** feel the 1 coming: count 1-2-3-4 with the music, and your flicks would land on the 1 even without the snap.
            """
        case .free: return """
            **Free**: a Flick swaps the band **the moment you flick**, with a tiny fade so it doesn't click. Early or late, you'll hear it.

            Flicks are part of the **handoff lanes**. On the mixer you swap the bass with the LOW EQ by hand.

            If swaps keep landing off the beat, step back to **snap** for a while.
            """
        case .sync: return """
            **SYNC**: the incoming track follows the master's **tempo** and **beat**, so the two never drift apart and you can focus on the blend.

            Beat-matching by ear will be the next level.
            """
        }
    }

    /// Tooltip on a level the user isn't on, for a change they might not expect.
    var switchTip: String? {
        switch self {
        case .handoff: return "**Back to the handoff lanes**: the Mixer panel and the phone switch to the lanes right away. The sound carries over; the EQ and faders reset."
        case .mixer: return "**Move up to the mixer**: the Mixer panel and the phone switch to EQ and faders right away. The sound carries over."
        default: return nil
        }
    }
}
