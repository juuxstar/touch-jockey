import AVFoundation
import Foundation

/// One audio file in the library.
public struct LibraryTrack: Codable, Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    public var title: String
    public var artist: String
    public var album: String
    public var duration: Double
    /// Filled in by background analysis, or when the track is loaded into a deck.
    public var bpm: Double?
    /// 0...1; below about 0.25 the BPM is a guess.
    public var bpmConfidence: Double?
    public var modified: Date

    public var url: URL { URL(fileURLWithPath: path) }
}

/// Scans a music folder, reads tags, and keeps a cache so later launches are instant.
///
/// The cache (tags plus analysed BPM, keyed by path and modification date) lives in
/// `~/Library/Application Support/TouchJockey/library-v2.json`.
public final class LibraryStore {
    public static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "aif", "aiff", "caf", "alac"]

    public private(set) var tracks: [LibraryTrack] = []
    private var byPath: [String: LibraryTrack] = [:]
    private let cacheURL: URL

    public init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TouchJockey", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Bump the version when the cached fields or how they are derived change.
        cacheURL = dir.appendingPathComponent("library-v2.json")
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode([LibraryTrack].self, from: data) {
            tracks = cached
            byPath = Dictionary(cached.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    /// Walks `root` and returns the up-to-date track list. Tags are read only for new or changed files.
    /// Runs synchronously; call it off the main thread.
    public func scan(root: URL, progress: ((Int) -> Void)? = nil) -> [LibraryTrack] {
        var found: [LibraryTrack] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        for case let url as URL in walker {
            // Never look inside Apple Music's or iTunes' own library folders: macOS guards them
            // with a media-library permission prompt, and they aren't DJ files anyway.
            if Self.isProtectedMediaFolder(url) { walker.skipDescendants(); continue }
            guard Self.audioExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let modified = values.contentModificationDate ?? .distantPast
            if let known = byPath[url.path], known.modified == modified {
                found.append(known)
            } else {
                var t = Self.readTags(url, modified: modified)
                if let known = byPath[url.path], known.modified == modified { t.bpm = known.bpm; t.bpmConfidence = known.bpmConfidence }
                found.append(t)
            }
            if found.count % 25 == 0 { progress?(found.count) }
        }
        found.sort { ($0.artist.lowercased(), $0.album.lowercased(), $0.path) < ($1.artist.lowercased(), $1.album.lowercased(), $1.path) }
        tracks = found
        byPath = Dictionary(found.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        save()
        return found
    }

    /// Apple Music / iTunes library folders (and photo/music library packages) that the scan skips.
    static func isProtectedMediaFolder(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        if ["musiclibrary", "photoslibrary", "tvlibrary", "itlp"].contains(ext) { return true }
        let musicHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music").standardizedFileURL.path
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        return parent == musicHome && ["Music", "iTunes", "Apple Music", "TV", "Podcasts", "Audio Music Apps", "GarageBand"].contains(name)
    }

    /// Records an analysed BPM for a track.
    public func setBPM(_ bpm: Double, confidence: Double, for path: String) {
        guard var t = byPath[path] else { return }
        t.bpm = bpm
        t.bpmConfidence = confidence
        byPath[path] = t
        if let i = tracks.firstIndex(where: { $0.path == path }) { tracks[i] = t }
    }

    public func track(at path: String) -> LibraryTrack? { byPath[path] }

    public func save() {
        if let data = try? JSONEncoder().encode(tracks) { try? data.write(to: cacheURL, options: .atomic) }
    }

    /// Title, artist and album from a file name like "Artist - Album - 01 - Title" (how Lidarr names files),
    /// falling back to the folder names.
    public static func guessFromFileName(_ url: URL) -> (title: String, artist: String, album: String) {
        let name = url.deletingPathExtension().lastPathComponent
        let folderArtist = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        let folderAlbum = url.deletingLastPathComponent().lastPathComponent
        let parts = name.components(separatedBy: " - ")
        if parts.count >= 4, Int(parts[2]) != nil {
            return (parts[3...].joined(separator: " - "), parts[0], parts[1])
        }
        if parts.count >= 2 { return (parts[1...].joined(separator: " - "), parts[0], folderAlbum) }
        return (name, folderArtist, folderAlbum)
    }

    static func readTags(_ url: URL, modified: Date) -> LibraryTrack {
        let asset = AVURLAsset(url: url)
        let items = asset.commonMetadata
        func value(_ key: AVMetadataKey) -> String? {
            AVMetadataItem.metadataItems(from: items, withKey: key, keySpace: .common).first?.stringValue
        }
        let guess = guessFromFileName(url)
        return LibraryTrack(
            path: url.path,
            title: value(.commonKeyTitle) ?? guess.title,
            artist: value(.commonKeyArtist) ?? guess.artist,
            album: value(.commonKeyAlbumName) ?? guess.album,
            duration: CMTimeGetSeconds(asset.duration).isFinite ? CMTimeGetSeconds(asset.duration) : 0,
            bpm: nil,
            bpmConfidence: nil,
            modified: modified)
    }
}
