import SwiftUI
import TJCore

/// The library as a full-width table along the bottom of the window: search, recent picks,
/// and every track under the music folder, with sortable columns.
struct LibraryView: View {
    @EnvironmentObject var lib: LibraryModel
    @EnvironmentObject var m: AppModel
    @FocusState private var searchFocused: Bool
    @State private var selection: String?
    @State private var hovered: String?
    @State private var sortKey: SortKey? = nil
    @State private var ascending = true
    /// Width available to the table, measured once per layout; header and rows share fixed widths from it.
    @State private var tableWidth: CGFloat = 900

    enum SortKey: String, CaseIterable { case title, artist, album, bpm, key, fit, length }

    // Column widths (the text columns share what's left).
    private let dotW: CGFloat = 16, bpmW: CGFloat = 62, keyW: CGFloat = 52, fitW: CGFloat = 58, lenW: CGFloat = 66, deckW: CGFloat = 44, loadW: CGFloat = 64
    private let gap: CGFloat = 10

    /// Title, artist and album split what's left after the fixed columns: 40% / 32% / 28%.
    private var textWidths: (title: CGFloat, artist: CGFloat, album: CGFloat) {
        let fixed = dotW + bpmW + keyW + fitW + lenW + deckW + loadW + gap * 10 + 16
        let flex = max(240, tableWidth - fixed)
        return (flex * 0.40, flex * 0.32, flex * 0.28)
    }

    var body: some View {
        Panel(color: TJ.lav, fillHeight: true) {
            // One tight stack, so the header and column titles don't get the panel's 10 pt gaps.
            VStack(alignment: .leading, spacing: 4) {
                header
                columnHeaders
                    .background(GeometryReader { g in
                        Color.clear.onAppear { tableWidth = g.size.width }
                            .onChange(of: g.size.width) { tableWidth = $0 }
                    })
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                list
            }
        }
        // ⌘F jumps to the search field.
        .background(Button("") { searchFocused = true }.keyboardShortcut("f").opacity(0))
    }

    // MARK: Header: title, search, Recent/All, status

    private var header: some View {
        HStack(spacing: 12) {
            Cap(text: "Library")
            InfoTip("""
                **Library**: every track in your music folder.

                **Load** a track by double-clicking it (it goes to the next deck), or hover it and press **A** or **B**.

                **Sort** by clicking a column title; click again to reverse.

                **Fit** shows how close each track's tempo is to the track playing now: **green** within 3%, **gold** within 6%, **red** further off. Close tempos blend most easily.

                **BPM?** A question mark means the beat was weak, so the tempo is a guess.

                **Key** is shown in Camelot notation (for example **8A**). Keys that sit next to each other on the Camelot wheel blend smoothly: **green** means the same key or a neighbour of the playing track, **gold** two steps away, **red** a likely clash.

                **Recent** lists the tracks you loaded lately. **⌘F** jumps to search.

                **Folder**: change it, or rescan it, in **Settings** (**⌘,**).
                """)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(TJ.mute)
                TextField("Search title, artist or album", text: $lib.query)
                    .textFieldStyle(.plain).focused($searchFocused)
                if !lib.query.isEmpty {
                    Button { lib.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundColor(TJ.mute)
                }
            }
            .padding(.horizontal, 8).frame(width: 300, height: 24)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(searchFocused ? TJ.sky : Color.white.opacity(0.15), lineWidth: 1.5))
            // Recent / All as the app's own buttons: the selected one is filled.
            HStack(spacing: 6) {
                Button("Recent (\(lib.recents.count))") { lib.showRecent = true }
                    .tjButton(TJ.lav, filled: lib.showRecent)
                Button("All (\(lib.tracks.count))") { lib.showRecent = false }
                    .tjButton(TJ.lav, filled: !lib.showRecent)
            }
            Spacer()
            Text(status).font(.tj(11)).foregroundColor(TJ.mute).lineLimit(1)
        }
    }

    private var status: String {
        if lib.scanning { return "Scanning… \(lib.scanned) files" }
        if lib.analysing > 0 { return "\(lib.tracks.count) tracks · finding BPM, \(lib.analysing) left" }
        return "\(lib.visible.count) shown · double-click loads into deck \(m.decks[m.incomingForLoading].name)"
    }

    // MARK: Columns

    private var columnHeaders: some View {
        let w = textWidths
        return HStack(spacing: gap) {
            Color.clear.frame(width: dotW, height: 1)
            sortHeader("Title", .title).frame(width: w.title, alignment: .leading)
            sortHeader("Artist", .artist).frame(width: w.artist, alignment: .leading)
            sortHeader("Album", .album).frame(width: w.album, alignment: .leading)
            Group {
                sortHeader("BPM", .bpm).frame(width: bpmW, alignment: .trailing)
                sortHeader("Key", .key).frame(width: keyW, alignment: .trailing)
            sortHeader("Fit", .fit).frame(width: fitW, alignment: .trailing)
            sortHeader("Length", .length).frame(width: lenW, alignment: .trailing)
            Text("DECK").font(.tj(10.5, weight: .bold)).tracking(1).lineLimit(1).fixedSize().foregroundColor(TJ.mute).frame(width: deckW)
            }
            Color.clear.frame(width: loadW, height: 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
    }

    private func sortHeader(_ title: String, _ key: SortKey) -> some View {
        Button {
            if sortKey == key { ascending.toggle() } else { sortKey = key; ascending = key != .fit ? true : true }
        } label: {
            HStack(spacing: 3) {
                Text(title.uppercased()).font(.tj(10.5, weight: .bold)).tracking(1).lineLimit(1).fixedSize()
                if sortKey == key { Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.tj(8.5, weight: .bold)) }
            }
            .foregroundColor(sortKey == key ? TJ.gold : TJ.mute)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: Rows

    private var rows: [LibraryTrack] {
        let base = lib.visible
        guard let key = sortKey else { return base }
        func cmp(_ a: LibraryTrack, _ b: LibraryTrack) -> Bool {
            switch key {
            case .title: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case .artist: return a.artist.localizedCaseInsensitiveCompare(b.artist) == .orderedAscending
            case .album: return a.album.localizedCaseInsensitiveCompare(b.album) == .orderedAscending
            case .bpm: return (a.bpm ?? .infinity) < (b.bpm ?? .infinity)
            case .key: return MusicalKey.sortIndex(a.key) < MusicalKey.sortIndex(b.key)
            case .fit: return (fitRatio(a.bpm) ?? .infinity) < (fitRatio(b.bpm) ?? .infinity)
            case .length: return a.duration < b.duration
            }
        }
        return base.sorted { ascending ? cmp($0, $1) : cmp($1, $0) }
    }

    private var list: some View {
        let rows = self.rows
        return ScrollView {
            LazyVStack(spacing: 1) {
                if rows.isEmpty {
                    Text(lib.showRecent ? "Tracks you load show up here." : lib.scanning ? "Scanning…" : "No tracks match.")
                        .font(.tj(12)).foregroundColor(TJ.mute).padding(.top, 16)
                }
                ForEach(rows) { t in row(t) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ t: LibraryTrack) -> some View {
        let selected = selection == t.path
        let isHovered = hovered == t.path
        return HStack(spacing: gap) {
            textCells(t)
            numberCells(t)
            deckCells(t, showLoad: selected || isHovered)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(selected ? Color.white.opacity(0.08) : isHovered ? Color.white.opacity(0.04) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? TJ.mint : .clear, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? t.path : (hovered == t.path ? nil : hovered) }
        .pointingHandCursor()
        .onTapGesture(count: 2) { m.load(t.url, into: m.incomingForLoading) }
        .onTapGesture { selection = t.path }
    }

    /// Fit dot, title, artist, album.
    @ViewBuilder private func textCells(_ t: LibraryTrack) -> some View {
        let w = textWidths
        Circle().fill(fitColor(fitRatio(t.bpm))).frame(width: 8, height: 8).frame(width: dotW)
        Text(t.title).font(.tj(12.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
            .frame(width: w.title, alignment: .leading)
        Text(t.artist.isEmpty ? "–" : t.artist).font(.tj(12)).foregroundColor(Color.white.opacity(0.8)).lineLimit(1)
            .frame(width: w.artist, alignment: .leading)
        Text(t.album).font(.tj(12)).foregroundColor(TJ.mute).lineLimit(1)
            .frame(width: w.album, alignment: .leading)
    }

    /// BPM, key, fit, length.
    @ViewBuilder private func numberCells(_ t: LibraryTrack) -> some View {
        let unsure = (t.bpmConfidence ?? 1) < 0.25
        let ratio = fitRatio(t.bpm)
        Text(t.bpm.map { String(format: unsure ? "%.0f?" : "%.1f", $0) } ?? "…")
            .font(.tj(12)).monospacedDigit()
            .foregroundColor(t.bpm == nil || unsure ? TJ.mute : .primary)
            .frame(width: bpmW, alignment: .trailing)
            .tip(unsure ? "**Unsure BPM**: the beat was weak, so this tempo is a guess.\n\nSync may drift with this track." : "")
        Text(t.key ?? "")
            .font(.tj(12, weight: .semibold)).monospacedDigit()
            .foregroundColor(keyColor(t.key))
            .frame(width: keyW, alignment: .trailing)
        Text(ratio.map { $0 < 0.0005 ? "same" : String(format: "%.1f%%", $0 * 100) } ?? "")
            .font(.tj(12)).monospacedDigit().foregroundColor(fitColor(ratio))
            .frame(width: fitW, alignment: .trailing)
        Text(duration(t.duration)).font(.tj(12)).monospacedDigit().foregroundColor(TJ.mute)
            .frame(width: lenW, alignment: .trailing)
    }

    /// Which deck the track is on, and the load buttons.
    @ViewBuilder private func deckCells(_ t: LibraryTrack, showLoad: Bool) -> some View {
        Group {
            if let i = m.loadedPaths.firstIndex(of: t.path) {
                Text(i == 0 ? "A" : "B").font(.tj(10, weight: .heavy)).foregroundColor(.black)
                    .frame(width: 18, height: 18).background(TJ.deck(i)).clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(width: deckW)
        HStack(spacing: 6) {
            if showLoad {
                deckButton(t, 0)
                deckButton(t, 1)
            }
        }
        .frame(width: loadW)
    }

    private func deckButton(_ t: LibraryTrack, _ deck: Int) -> some View {
        Button { m.load(t.url, into: deck) } label: {
            Text(deck == 0 ? "A" : "B").font(.tj(11, weight: .heavy)).foregroundColor(.black)
                .frame(width: 24, height: 20).background(TJ.deck(deck)).clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain).pointingHandCursor().tip("**Load into deck \(deck == 0 ? "A" : "B")**.\n\nIf that deck is playing, it stops.")
    }

    // MARK: Fit

    /// How far a track's tempo is from the playing track's, as a fraction (nearest of its tempo, half and double).
    private func fitRatio(_ bpm: Double?) -> Double? {
        guard let bpm, let ref = m.decks[m.outgoing].bpm, ref > 0 else { return nil }
        return [bpm, bpm * 2, bpm / 2].map { abs($0 - ref) / ref }.min()
    }

    /// Key colour against the playing track: green = same key or a Camelot neighbour (blends cleanly),
    /// gold = two steps away (use with care), red = clashes.
    private func keyColor(_ key: String?) -> Color {
        guard let key else { return TJ.mute }
        guard let playing = m.decks[m.outgoing].key else { return .primary }
        switch MusicalKey.compatibility(key, playing) {
        case 0: return TJ.mint
        case 1: return TJ.gold
        default: return Color(red: 1.0, green: 0.37, blue: 0.56)
        }
    }

    private func fitColor(_ ratio: Double?) -> Color {
        guard let ratio else { return Color.white.opacity(0.15) }
        return ratio <= 0.03 ? TJ.mint : ratio <= 0.06 ? TJ.gold : Color(red: 1.0, green: 0.37, blue: 0.56)
    }

    private func duration(_ s: Double) -> String {
        guard s > 0 else { return "" }
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}
