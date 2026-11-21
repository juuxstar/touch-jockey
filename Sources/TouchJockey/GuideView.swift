import SwiftUI

// MARK: - Chapters

/// One chapter of the built-in DJ guide, loaded from `Guide/NN-name.md` in the app bundle.
struct GuideChapter: Identifiable, Hashable {
    let id: String          // file name without extension, for example "04-first-transition"
    let title: String       // the chapter's "# " heading
    let body: String        // everything after the heading

    /// The chapter's "## Practice" section, if it has one (the exercise shown while practising).
    var practice: String? {
        guard let r = body.range(of: "## Practice") else { return nil }
        let rest = body[r.upperBound...]
        let end = rest.range(of: "\n## ")?.lowerBound ?? rest.endIndex
        let text = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func loadAll() -> [GuideChapter] {
        let folder: URL = {
            if let r = Bundle.main.resourceURL?.appendingPathComponent("Guide"),
               FileManager.default.fileExists(atPath: r.path) { return r }
            return URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Guide")
        }()
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let text = try? String(contentsOf: url) else { return nil }
                var lines = text.components(separatedBy: "\n")
                let title = lines.first.map { $0.hasPrefix("# ") ? String($0.dropFirst(2)) : $0 } ?? url.lastPathComponent
                lines.removeFirst()
                return GuideChapter(id: url.deletingPathExtension().lastPathComponent, title: title,
                                    body: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
            }
    }
}

/// Keys for the guide's saved state.
enum GuideKey {
    static let done = "guideChaptersDone"       // [String] of chapter ids marked done
    static let current = "guideCurrentChapter"  // id of the chapter last open
    static let seen = "guideSeenOnce"           // opened automatically on first launch
}

// MARK: - Window

/// The built-in tutorial: learn DJ techniques with Touch Jockey's starter controls, then level up.
/// Opened from Help → Touch Jockey Guide (⌘?), the book button in the status line, and once
/// automatically on first launch.
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppModel
    @State private var chapters = GuideChapter.loadAll()
    @State private var current: String = UserDefaults.standard.string(forKey: GuideKey.current) ?? ""
    @State private var done: Set<String> = Set(UserDefaults.standard.stringArray(forKey: GuideKey.done) ?? [])

    private var index: Int { chapters.firstIndex { $0.id == current } ?? 0 }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
            content
        }
        .frame(width: 900 * UIScale.current, height: 620 * UIScale.current)
        .modalStyle(TJ.gold)
        .onAppear { if current.isEmpty, let first = chapters.first { current = first.id } }
        .onChange(of: current) { UserDefaults.standard.set($0, forKey: GuideKey.current) }
        .background(Button("") { dismiss() }.keyboardShortcut(.cancelAction).opacity(0))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "book.fill").foregroundColor(TJ.gold)
                Text("DJ Guide").font(.tj(15, weight: .bold))
            }
            .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { i, ch in
                        Button { current = ch.id } label: {
                            HStack(spacing: 8) {
                                Image(systemName: done.contains(ch.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(done.contains(ch.id) ? TJ.mint : TJ.mute)
                                Text(i == 0 ? ch.title : "\(i). \(ch.title)")
                                    .font(.tj(12.5, weight: ch.id == current ? .semibold : .regular))
                                    .foregroundColor(ch.id == current ? .white : Color.white.opacity(0.75))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(ch.id == current ? TJ.gold.opacity(0.14) : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ch.id == current ? TJ.gold : .clear, lineWidth: 2))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    }
                }
            }
            Spacer(minLength: 0)
            Text("\(done.count) of \(chapters.count) done").font(.tj(11)).foregroundColor(TJ.mute)
        }
        .padding(16)
        .frame(width: 250 * UIScale.current)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if chapters.isEmpty {
                Text("The guide's chapters are missing from the app bundle.").foregroundColor(TJ.mute).padding(24)
                Spacer()
            } else {
                let ch = chapters[index]
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(ch.title).font(.tj(24, weight: .bold))
                        GuideMarkdown(source: ch.body)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(ch.id)   // start each chapter at the top
                footer(ch)
            }
        }
    }

    private func footer(_ ch: GuideChapter) -> some View {
        HStack(spacing: 10) {
            Button { if index > 0 { current = chapters[index - 1].id } } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .tjButton(TJ.mute).disabled(index == 0)
            Spacer()
            Button {
                if done.contains(ch.id) { done.remove(ch.id) } else { done.insert(ch.id) }
                UserDefaults.standard.set(Array(done), forKey: GuideKey.done)
            } label: {
                Label(done.contains(ch.id) ? "Done" : "Mark as done",
                      systemImage: done.contains(ch.id) ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .tjButton(TJ.mint, filled: done.contains(ch.id))
            if ch.practice != nil {
                Button {
                    app.practiceChapter = ch
                    dismiss()
                } label: { Label("Go practice", systemImage: "figure.dance") }
                .tjButton(TJ.sky)
                .tip("**Go practice**: close the guide and try this chapter's exercise. A practice bar keeps the steps at hand, and brings you back here when you're ready.")
            }
            if index < chapters.count - 1 {
                Button { current = chapters[index + 1].id } label: { Label("Next", systemImage: "chevron.right") }
                    .tjButton(TJ.gold, filled: true)
            } else {
                Button("Close") { dismiss() }.tjButton(TJ.gold, filled: true)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
        .background(Color.white.opacity(0.03))
    }
}

// MARK: - Markdown

/// Renders the guide's simple markdown: "## " headings, paragraphs, "- " bullets,
/// "1. " numbered steps and "> " tip boxes, with **bold** and *italic* inline.
struct GuideMarkdown: View {
    let source: String

    private enum Block: Hashable {
        case heading(String), paragraph(String), bullets([String]), steps([String]), tip(String)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var para: [String] = [], bullets: [String] = [], steps: [String] = [], tip: [String] = []
        func flush() {
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] }
            if !bullets.isEmpty { out.append(.bullets(bullets)); bullets = [] }
            if !steps.isEmpty { out.append(.steps(steps)); steps = [] }
            if !tip.isEmpty { out.append(.tip(tip.joined(separator: " "))); tip = [] }
        }
        for raw in source.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("## ") { flush(); out.append(.heading(String(line.dropFirst(3)))); continue }
            if line.hasPrefix("- ") {
                if bullets.isEmpty { flush() }
                bullets.append(String(line.dropFirst(2))); continue
            }
            if let dot = line.firstIndex(of: "."), let _ = Int(line[..<dot]), line[line.index(after: dot)...].hasPrefix(" ") {
                if steps.isEmpty { flush() }
                steps.append(String(line[line.index(dot, offsetBy: 2)...])); continue
            }
            if line.hasPrefix("> ") {
                if tip.isEmpty { flush() }
                tip.append(String(line.dropFirst(2))); continue
            }
            if !bullets.isEmpty || !steps.isEmpty || !tip.isEmpty { flush() }
            para.append(line)
        }
        flush()
        return out
    }

    private func inline(_ s: String) -> Text {
        Text((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let t):
                    Text(t.uppercased()).font(.tj(12, weight: .heavy)).tracking(1.2).foregroundColor(TJ.gold)
                        .padding(.top, 8)
                case .paragraph(let t):
                    inline(t).font(.tj(14)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(TJ.gold).frame(width: 5, height: 5).offset(y: -2)
                                inline(item).font(.tj(14)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                case .steps(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)").font(.tj(11, weight: .heavy)).foregroundColor(.black)
                                    .frame(width: 20, height: 20).background(TJ.gold).clipShape(RoundedRectangle(cornerRadius: 5))
                                inline(item).font(.tj(14)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                case .tip(let t):
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill").foregroundColor(TJ.gold)
                        inline(t).font(.tj(13.5)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(TJ.gold.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TJ.gold.opacity(0.7), lineWidth: 1.5))
                }
            }
        }
    }
}
