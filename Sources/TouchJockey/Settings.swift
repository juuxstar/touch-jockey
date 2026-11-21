import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - Keys

/// UserDefaults keys for the settings window. Text size (`UIScale.key`), help icons
/// (`infoTipsKey`) and the library folder (`LibraryModel`) keep their own keys.
enum SettingsKey {
    /// Whether SYNC is on when the app starts. The SYNC button still changes it for the session.
    static let syncOnByDefault = "syncOnByDefault"
    /// Stop the display and the Mac from sleeping while a deck plays.
    static let keepAwake = "keepAwakeWhilePlaying"

    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}

// MARK: - Sections

enum SettingsSection: String, CaseIterable, Identifiable {
    case connect, display, library, playback, app
    var id: String { rawValue }

    var title: String {
        switch self {
        case .connect: return "Connect a phone"
        case .display: return "Display"
        case .library: return "Library"
        case .playback: return "Playback"
        case .app: return "App"
        }
    }

    var icon: String {
        switch self {
        case .connect: return "iphone.radiowaves.left.and.right"
        case .display: return "textformat.size"
        case .library: return "music.note.list"
        case .playback: return "play.circle"
        case .app: return "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .connect: return TJ.mint
        case .display: return TJ.sky
        case .library: return TJ.lav
        case .playback: return TJ.a
        case .app: return TJ.gold
        }
    }

    var tip: String {
        switch self {
        case .connect: return "**Connect a phone**: the code to scan and the steps to use a phone or tablet as a touch controller."
        case .display: return "**Display**: text size and help icons."
        case .library: return "**Library**: which music folder to use, and the beat analysis of your tracks."
        case .playback: return "**Playback**: how the decks behave when Touch Jockey starts."
        case .app: return "**App**: version, and restarting Touch Jockey."
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
                    .tip("**Done**: close Settings. Changes are already saved.\n\nShortcut: **Esc** or **Return**")
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
                .tip(sec.tip)
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
        case .display: display
        case .library: library
        case .playback: playback
        case .app: app
        }
    }

    private var sectionHelp: String {
        switch section {
        case .connect: return """
            **Surfaces**: phones and tablets you use as touch controllers. They open a web page from this Mac, so there's nothing to install.

            Any number can connect at once. **Touch ownership** stops two fingers on different devices fighting over the same lane.
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
                        .tip("**Copy** the address, to send it to a device or type it in yourself.")
                    }
                } else {
                    Text("No network address found. Connect this Mac to Wi-Fi.").font(.tj(13)).foregroundColor(TJ.mute)
                }
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Join the same Wi-Fi network as this Mac.")
                    step(2, "Scan the code with the camera, or type the address into the browser.")
                    step(3, "On iPhone: in Safari tap Share, then Add to Home Screen. Open it from the icon for full screen.")
                    step(4, "Turn the phone sideways for the handoff lanes.")
                }
                Label(m.surfaces == 1 ? "1 connected now" : "\(m.surfaces) connected now",
                      systemImage: "iphone.radiowaves.left.and.right")
                    .font(.tj(13, weight: .semibold)).monospacedDigit()
                    .foregroundColor(m.surfaces > 0 ? TJ.mint : TJ.mute)
                    .tip("**Connected**: how many phones and tablets have the touch surface open right now.")
            }
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
