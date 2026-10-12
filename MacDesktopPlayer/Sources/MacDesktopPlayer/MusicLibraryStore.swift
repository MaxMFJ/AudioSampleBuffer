import AppKit
import AVFoundation
import CryptoKit
import Foundation

struct LocalTrack: Codable, Identifiable {
    var id: String
    var path: String
    var title: String
    var artist: String?
    var isFavorite = false
    var lastPlayed: Date?

    private enum CodingKeys: String, CodingKey { case id, path, title, artist, isFavorite, lastPlayed }
    init(id: String, path: String, title: String, artist: String?, isFavorite: Bool = false, lastPlayed: Date? = nil) {
        self.id = id; self.path = path; self.title = title; self.artist = artist
        self.isFavorite = isFavorite; self.lastPlayed = lastPlayed
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        path = try values.decode(String.self, forKey: .path)
        title = try values.decode(String.self, forKey: .title)
        artist = try values.decodeIfPresent(String.self, forKey: .artist)
        isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        lastPlayed = try values.decodeIfPresent(Date.self, forKey: .lastPlayed)
    }
}

struct QQMusicSearchResult {
    let rid: String
    let name: String
    let artist: String
}

struct UserPlaylist: Codable, Identifiable {
    var id: String
    var name: String
    var trackIDs: [String]
}

@MainActor
final class MusicLibraryStore {
    private(set) var tracks: [LocalTrack] = []
    private(set) var playlists: [UserPlaylist] = []
    private let fileURL: URL
    private let audioDirectory: URL
    var recentTracks: [LocalTrack] { tracks.filter { $0.lastPlayed != nil }.sorted { $0.lastPlayed! > $1.lastPlayed! } }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacDesktopPlayer", isDirectory: true)
        fileURL = support.appendingPathComponent("library.json")
        audioDirectory = support.appendingPathComponent("Music", isDirectory: true)
        if let data = try? Data(contentsOf: fileURL),
           let library = try? JSONDecoder().decode(SavedLibrary.self, from: data) {
            tracks = library.tracks
            playlists = library.playlists
        }
    }

    func add(_ urls: [URL], to playlistID: String?) {
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        for source in urls {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            do {
                guard !tracks.contains(where: { $0.title == source.deletingPathExtension().lastPathComponent }) else { continue }
                let id = UUID().uuidString
                let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension
                let destination = audioDirectory.appendingPathComponent("\(id).\(ext)")
                try FileManager.default.copyItem(at: source, to: destination)
                let title = source.deletingPathExtension().lastPathComponent
                let track = LocalTrack(id: id, path: destination.path, title: title, artist: nil)
                tracks.append(track)
                if let playlistID, let index = playlists.firstIndex(where: { $0.id == playlistID }) {
                    playlists[index].trackIDs.append(track.id)
                }
            } catch {
                NSLog("Unable to import audio at %@: %@", source.path, error.localizedDescription)
            }
        }
        save()
    }

    func addDownloadedFile(at source: URL, fileExtension: String, title: String, artist: String, to playlistID: String?) throws {
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let destination = audioDirectory.appendingPathComponent("\(id).\(fileExtension)")
        try FileManager.default.moveItem(at: source, to: destination)
        let track = LocalTrack(id: id, path: destination.path, title: title, artist: artist)
        tracks.append(track)
        if let playlistID, let index = playlists.firstIndex(where: { $0.id == playlistID }) {
            playlists[index].trackIDs.append(track.id)
        }
        save()
    }

    func markPlayed(_ id: String) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].lastPlayed = Date()
        save()
    }

    func toggleFavorite(_ id: String) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].isFavorite.toggle()
        save()
    }

    func createPlaylist(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let id = UUID().uuidString
        playlists.append(UserPlaylist(id: id, name: trimmed, trackIDs: []))
        save()
        return id
    }

    func deletePlaylist(_ id: String) {
        playlists.removeAll { $0.id == id }
        save()
    }

    func removeFromLibrary(_ trackID: String) {
        tracks.removeAll { $0.id == trackID }
        for index in playlists.indices { playlists[index].trackIDs.removeAll { $0 == trackID } }
        save()
    }

    func removeTrack(_ trackID: String, from playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].trackIDs.removeAll { $0 == trackID }
        save()
    }

    func tracks(in playlistID: String?) -> [LocalTrack] {
        guard let playlistID, let playlist = playlists.first(where: { $0.id == playlistID }) else { return tracks }
        return playlist.trackIDs.compactMap { id in tracks.first(where: { $0.id == id }) }
    }

    func playlistName(_ id: String) -> String? { playlists.first(where: { $0.id == id })?.name }
    func track(id: String) -> LocalTrack? { tracks.first(where: { $0.id == id }) }

    func artwork(for track: LocalTrack) async -> NSImage? {
        let fileURL = URL(fileURLWithPath: track.path)
        if let image = sidecarArtwork(for: fileURL) { return image }
        if let cached = await AppleArtworkLookupService.shared.cachedArtwork(forFilePath: track.path),
           let image = NSImage(data: cached) { return image }

        let asset = AVURLAsset(url: fileURL)
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        if let item = AVMetadataItem.metadataItems(
            from: metadata, filteredByIdentifier: .commonIdentifierArtwork
        ).first, let data = try? await item.load(.dataValue), let image = NSImage(data: data) {
            return image
        }

        var values: [String: String] = [:]
        for item in metadata {
            guard let key = item.commonKey?.rawValue,
                  let value = try? await item.load(.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            if values[key] == nil { values[key] = value }
        }
        let title = values[AVMetadataKey.commonKeyTitle.rawValue] ?? track.title
        let artist = track.artist ?? values[AVMetadataKey.commonKeyArtist.rawValue]
        let album = values[AVMetadataKey.commonKeyAlbumName.rawValue]
        guard let data = await AppleArtworkLookupService.shared.lookup(
            title: title, artist: artist, album: album, filePath: track.path
        ) else { return nil }
        return NSImage(data: data)
    }

    private func sidecarArtwork(for audioURL: URL) -> NSImage? {
        let basename = audioURL.deletingPathExtension().lastPathComponent
        let directory = audioURL.deletingLastPathComponent()
        for stem in ["\(basename)_cover", basename] {
            for ext in ["jpg", "jpeg", "png", "webp"] {
                let coverURL = directory.appendingPathComponent(stem).appendingPathExtension(ext)
                if let image = NSImage(contentsOf: coverURL) { return image }
            }
        }
        return nil
    }

    private func save() {
        let library = SavedLibrary(tracks: tracks, playlists: playlists)
        guard let data = try? JSONEncoder().encode(library) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        NotificationCenter.default.post(name: .desktopMusicLibraryChanged, object: self)
    }
}

private struct SavedLibrary: Codable {
    var tracks: [LocalTrack]
    var playlists: [UserPlaylist]
}

actor AppleArtworkLookupService {
    static let shared = AppleArtworkLookupService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }()
    private let negativeCacheTTL: TimeInterval = 6 * 60 * 60
    private var memoryCache: [String: Data] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private var negativeCache: [String: Date] = [:]

    func cachedArtwork(forFilePath filePath: String) -> Data? {
        let key = "file:\(filePath)"
        if let data = memoryCache[key] { return data }
        guard let data = try? Data(contentsOf: cacheURL(for: key)), NSImage(data: data) != nil else { return nil }
        remember(data, for: key)
        return data
    }

    func lookup(title: String?, artist: String?, album: String?, filePath: String?) async -> Data? {
        let resolvedTitle = trimmed(title)
        let resolvedArtist = trimmed(artist)
        let resolvedAlbum = trimmed(album)
        guard let resolvedTitle, isUsableTitle(resolvedTitle) else { return nil }

        let searchKey = searchCacheKey(title: resolvedTitle, artist: resolvedArtist, album: resolvedAlbum)
        if let cached = cachedData(for: searchKey) {
            persist(cached, searchKey: searchKey, filePath: filePath)
            return cached
        }
        if let failedAt = negativeCache[searchKey], Date().timeIntervalSince(failedAt) < negativeCacheTTL {
            return nil
        }

        let task: Task<Data?, Never>
        if let active = inFlight[searchKey] {
            task = active
        } else {
            task = Task { await self.searchAndDownload(title: resolvedTitle, artist: resolvedArtist, album: resolvedAlbum) }
            inFlight[searchKey] = task
        }
        let imageData = await task.value
        inFlight.removeValue(forKey: searchKey)
        if let imageData {
            negativeCache.removeValue(forKey: searchKey)
            persist(imageData, searchKey: searchKey, filePath: filePath)
        } else {
            negativeCache[searchKey] = Date()
        }
        return imageData
    }

    private func searchAndDownload(title: String, artist: String?, album: String?) async -> Data? {
        let term = [artist, title, album].compactMap { trimmed($0) }.joined(separator: " ")
        for country in storefronts(title: title, artist: artist) {
            let songs = await performSearch(term: term, country: country, entity: "song")
            if let match = bestSongMatch(songs, title: title, artist: artist, album: album),
               let image = await downloadArtwork(result: match) { return image }

            let albums = await performSearch(term: term, country: country, entity: "album")
            if let match = bestAlbumMatch(albums, title: title, artist: artist, album: album),
               let image = await downloadArtwork(result: match) { return image }
        }
        return nil
    }

    private func performSearch(term: String, country: String, entity: String) async -> [[String: Any]] {
        guard var components = URLComponents(string: "https://itunes.apple.com/search") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "lang", value: "zh_cn")
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("MacDesktopPlayer/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = payload["results"] as? [[String: Any]] else { return [] }
            return rows
        } catch {
            NSLog("[Artwork] iTunes search failed: %@", error.localizedDescription)
            return []
        }
    }

    private func bestSongMatch(_ rows: [[String: Any]], title: String, artist: String?, album: String?) -> [String: Any]? {
        let best = rows.max { songScore($0, title: title, artist: artist, album: album) < songScore($1, title: title, artist: artist, album: album) }
        guard let best, songScore(best, title: title, artist: artist, album: album) >= 55 else { return nil }
        return best
    }

    private func bestAlbumMatch(_ rows: [[String: Any]], title: String, artist: String?, album: String?) -> [String: Any]? {
        let targetAlbum = album?.isEmpty == false ? album! : title
        let best = rows.max { albumScore($0, targetAlbum: targetAlbum, artist: artist) < albumScore($1, targetAlbum: targetAlbum, artist: artist) }
        guard let best, albumScore(best, targetAlbum: targetAlbum, artist: artist) >= 50 else { return nil }
        return best
    }

    private func songScore(_ row: [String: Any], title: String, artist: String?, album: String?) -> Double {
        var score = similarity(normalized(row["trackName"] as? String), normalized(title)) * 70
        if let artist, !artist.isEmpty { score += similarity(normalized(row["artistName"] as? String), normalized(artist)) * 25 }
        if let album, !album.isEmpty { score += similarity(normalized(row["collectionName"] as? String), normalized(album)) * 10 }
        return score
    }

    private func albumScore(_ row: [String: Any], targetAlbum: String, artist: String?) -> Double {
        var score = similarity(normalized(row["collectionName"] as? String), normalized(targetAlbum)) * 70
        if let artist, !artist.isEmpty { score += similarity(normalized(row["artistName"] as? String), normalized(artist)) * 30 }
        return score
    }

    private func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        guard lhs.contains(rhs) || rhs.contains(lhs) else { return 0 }
        return Double(min(lhs.count, rhs.count)) / Double(max(lhs.count, rhs.count))
    }

    private func downloadArtwork(result: [String: Any]) async -> Data? {
        guard let imageURL = highResolutionURL(result) else { return nil }
        if let data = await download(urlString: imageURL), NSImage(data: data) != nil { return data }
        if imageURL.contains("1200x1200bb") {
            let fallback = imageURL.replacingOccurrences(of: "1200x1200bb", with: "600x600bb")
            if let data = await download(urlString: fallback), NSImage(data: data) != nil { return data }
        }
        return nil
    }

    private func download(urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            NSLog("[Artwork] cover download failed: %@", error.localizedDescription)
            return nil
        }
    }

    private func highResolutionURL(_ result: [String: Any]) -> String? {
        guard let source = (result["artworkUrl100"] as? String) ?? (result["artworkUrl60"] as? String), !source.isEmpty,
              let regex = try? NSRegularExpression(pattern: "\\d+x\\d+[a-z]*", options: [.caseInsensitive]) else { return nil }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.stringByReplacingMatches(in: source, range: range, withTemplate: "1200x1200bb")
    }

    private func storefronts(title: String, artist: String?) -> [String] {
        let probe = title + (artist ?? "")
        if probe.unicodeScalars.contains(where: { (0xAC00...0xD7AF).contains(Int($0.value)) }) { return ["kr", "us", "cn"] }
        if probe.unicodeScalars.contains(where: { (0x3040...0x30FF).contains(Int($0.value)) }) { return ["jp", "us", "cn"] }
        if probe.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains(Int($0.value)) }) { return ["cn", "hk", "tw", "us"] }
        return ["us", "cn", "jp"]
    }

    private func isUsableTitle(_ value: String) -> Bool {
        let value = normalized(value)
        return value.count >= 2 && !["unknown", "untitled", "track", "未知", "未知歌曲", "无标题"].contains(value)
    }

    private func normalized(_ value: String?) -> String {
        guard let value = trimmed(value) else { return "" }
        var folded = value.lowercased().folding(options: [.widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        if let regex = try? NSRegularExpression(pattern: "\\s*[\\(\\[]?(feat\\.?|ft\\.)\\s+.*$", options: [.caseInsensitive]) {
            let range = NSRange(folded.startIndex..<folded.endIndex, in: folded)
            folded = regex.stringByReplacingMatches(in: folded, range: range, withTemplate: "")
        }
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0.value > 0x7F })
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private func searchCacheKey(title: String, artist: String?, album: String?) -> String {
        "search:\(normalized(artist))|\(normalized(title))|\(normalized(album))"
    }

    private func cachedData(for key: String) -> Data? {
        if let data = memoryCache[key] { return data }
        guard let data = try? Data(contentsOf: cacheURL(for: key)), NSImage(data: data) != nil else { return nil }
        remember(data, for: key)
        return data
    }

    private func remember(_ data: Data, for key: String) {
        memoryCache[key] = data
        if memoryCache.count > 8, let first = memoryCache.keys.first { memoryCache.removeValue(forKey: first) }
    }

    private func persist(_ data: Data, searchKey: String, filePath: String?) {
        remember(data, for: searchKey)
        try? data.write(to: cacheURL(for: searchKey), options: .atomic)
        if let filePath {
            let fileKey = "file:\(filePath)"
            remember(data, for: fileKey)
            try? data.write(to: cacheURL(for: fileKey), options: .atomic)
            writeSidecar(data, filePath: filePath)
        }
    }

    private func writeSidecar(_ data: Data, filePath: String) {
        let fileURL = URL(fileURLWithPath: filePath)
        let directory = fileURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: directory.path) else { return }
        let destination = directory.appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent + "_cover.jpg")
        try? data.write(to: destination, options: .atomic)
    }

    private func cacheURL(for key: String) -> URL {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacDesktopPlayer/AppleMusicArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(digest).appendingPathExtension("art")
    }
}

/// Match platform tracks to the same Apple/iTunes artwork source used for
/// local songs, and retain the platform-provided image as a reliable fallback.

