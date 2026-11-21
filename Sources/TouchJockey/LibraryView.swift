import SwiftUI
import TJCore

/// Library sidebar: search, recent picks, and every track under the music folder,
/// with BPM and how well each fits the track that's playing.
struct LibraryView: View {
    @EnvironmentObject var lib: LibraryModel
    @EnvironmentObject var m: AppModel
    @FocusState private var searchFocused: Bool
    @State private var selection: String?

    var body: some View {
        Panel(color: TJ.lav) {
            HStack {
                Cap(text: "Library")
                InfoTip("""
                    **Library**: every track in your music folder.

                    **Load** a track by double-clicking it (it goes to the next deck), or select it and press **A** or **B**.

                    **The dot** shows how well its tempo fits the track playing now: **green** within 3%, **gold** within 6%, **red** further off. Close tempos blend most easily.

                    **BPM?** A question mark means the beat was weak, so the tempo is a guess.

                    **Recent** lists the tracks you loaded lately. **⌘F** jumps to search.
                    """)
                Spacer()
                Button { lib.chooseFolder() } label: {
                    Label(lib.root.lastPathComponent, systemImage: "folder")
                }
                .tjButton(TJ.lav).tip("**Library folder**: choose which folder the library shows.\n\nNow: \(lib.root.path)")
                Button { lib.rescan() } label: { Image(systemName: "arrow.clockwise") }
                    .tjButton(TJ.lav).tip("**Rescan**: look for new, changed or removed files in the library folder.").disabled(lib.scanning)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(TJ.mute)
                TextField("Search title, artist or album", text: $lib.query)
                    .textFieldStyle(.plain).focused($searchFocused)
                if !lib.query.isEmpty {
                    Button { lib.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundColor(TJ.mute).tip("**Clear** the search.")
                }
            }
            .padding(.horizontal, 8).frame(height: 30)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(searchFocused ? TJ.sky : Color.white.opacity(0.15), lineWidth: 1.5))

            Picker("", selection: $lib.showRecent) {
                Text("Recent (\(lib.recents.count))").tag(true)
                Text("All (\(lib.tracks.count))").tag(false)
            }
            .pickerStyle(.segmented).labelsHidden()

            list

            Text(footer).font(.tj(11)).foregroundColor(TJ.mute).lineLimit(1)
        }
        // ⌘F jumps to the search field.
        .background(Button("") { searchFocused = true }.keyboardShortcut("f").opacity(0))
    }

    private var footer: String {
        if lib.scanning { return "Scanning… \(lib.scanned) files" }
        if lib.analysing > 0 { return "\(lib.tracks.count) tracks · finding BPM, \(lib.analysing) left" }
        return "\(lib.tracks.count) tracks · double-click loads into deck \(m.decks[1 - m.outgoing].name)"
    }

    private var list: some View {
        let rows = lib.visible
        return ScrollView {
            LazyVStack(spacing: 2) {
                if rows.isEmpty {
                    Text(lib.showRecent ? "Tracks you load show up here." : lib.scanning ? "Scanning…" : "No tracks match.")
                        .font(.tj(12)).foregroundColor(TJ.mute).padding(.top, 20)
                }
                ForEach(rows) { t in row(t) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ t: LibraryTrack) -> some View {
        let selected = selection == t.path
        let onDeck = m.loadedPaths.firstIndex(of: t.path)
        return HStack(spacing: 8) {
            Circle().fill(fitColor(t.bpm)).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.title).font(.tj(12.5, weight: .semibold)).lineLimit(1)
                Text(t.artist).font(.tj(11)).foregroundColor(TJ.mute).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let i = onDeck {
                Text(i == 0 ? "A" : "B").font(.tj(10, weight: .heavy)).foregroundColor(.black)
                    .frame(width: 16, height: 16).background(TJ.deck(i)).clipShape(RoundedRectangle(cornerRadius: 4))
            }
            let unsure = (t.bpmConfidence ?? 1) < 0.25
            Text(t.bpm.map { String(format: unsure ? "%.0f?" : "%.1f", $0) } ?? "…").font(.tj(11.5)).monospacedDigit()
                .foregroundColor(t.bpm == nil || unsure ? TJ.mute : .primary).frame(width: 40, alignment: .trailing)
                .tip(unsure ? "**Unsure BPM**: the beat was weak, so this tempo is a guess.\n\nSync may drift with this track." : "")
            Text(duration(t.duration)).font(.tj(11)).monospacedDigit().foregroundColor(TJ.mute)
                .frame(width: 36, alignment: .trailing)
            if selected {
                deckButton(t, 0)
                deckButton(t, 1)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(selected ? Color.white.opacity(0.08) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? TJ.mint : .clear, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { m.load(t.url, into: m.incomingForLoading) }
        .onTapGesture { selection = t.path }
        .tip("**\(t.title)**\n\n\(t.path)\n\n**Double-click** to load it into the next deck.")
    }

    private func deckButton(_ t: LibraryTrack, _ deck: Int) -> some View {
        Button { m.load(t.url, into: deck) } label: {
            Text(deck == 0 ? "A" : "B").font(.tj(11, weight: .heavy)).foregroundColor(.black)
                .frame(width: 22, height: 20).background(TJ.deck(deck)).clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain).tip("**Load into deck \(deck == 0 ? "A" : "B")**.\n\nIf that deck is playing, it stops.")
    }

    private func fitColor(_ bpm: Double?) -> Color {
        guard let bpm, let ref = m.decks[m.outgoing].bpm, ref > 0 else { return Color.white.opacity(0.15) }
        // Compare against the nearest of the track's tempo, half and double.
        let ratio = [bpm, bpm * 2, bpm / 2].map { abs($0 - ref) / ref }.min() ?? 1
        return ratio <= 0.03 ? TJ.mint : ratio <= 0.06 ? TJ.gold : Color(red: 1.0, green: 0.37, blue: 0.56)
    }

    private func duration(_ s: Double) -> String {
        guard s > 0 else { return "" }
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}
