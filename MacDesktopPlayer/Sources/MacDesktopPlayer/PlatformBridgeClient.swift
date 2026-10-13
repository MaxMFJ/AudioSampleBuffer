import Foundation
import AppKit
import AVFoundation
import ImageIO

/// Music provider supported by the Mac player.
enum PlatformProvider: String, CaseIterable, Codable {
    case netease
    case qq
    case kugou

    var title: String {
        switch self {
        case .netease: return "网易云音乐"
        case .qq: return "QQ 音乐"
        case .kugou: return "酷狗音乐"
        }
    }
}

struct PlatformTrack: Identifiable, Codable {
    let id: String
    let provider: PlatformProvider
    let name: String
    let artist: String
    let album: String?
    let durationMilliseconds: Int?
    let coverURL: URL?
    let mediaID: String?
    let hash: String?
    let albumID: String?
    let albumAudioID: String?

    var displayArtist: String { artist.isEmpty ? "未知艺术家" : artist }
}

struct PlatformPlaylist: Identifiable, Codable {
    let id: String
    let name: String
    let coverURL: URL?
    let trackCount: Int?
}

struct PlatformPlayback: Codable {
    let provider: PlatformProvider
    let url: URL?
    let playable: Bool?
    let trial: Bool?
    let quality: String?
    let message: String?
    let restriction: PlaybackRestriction?
}

struct PlaybackRestriction: Codable {
    let category: String?
    let action: String?
    let message: String?
}

struct PlatformLoginStatus: Codable {
    let provider: PlatformProvider
    let loggedIn: Bool
    let nickname: String?
    let userID: String?
    let isVIP: Bool?
    let isSVIP: Bool?
    let message: String?
}

enum PlatformBridgeError: LocalizedError {
    case invalidResponse
    case server(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "音乐平台返回了无法识别的数据"
        case .server(let message): return message
        case .notConfigured: return "平台请求配置无效"
        }
    }
}

/// Native provider client for the Mac app.
actor PlatformBridgeClient {
    static let shared = PlatformBridgeClient()

    private let session: URLSession
    private let kugou = KugouProviderClient()
    private let artworkMemoryCache = NSCache<NSString, NSImage>()
    private let artworkCacheLimitBytes = 32 * 1024 * 1024
    private let artworkDiskLimitBytes = 128 * 1024 * 1024
    private var audioPreparationTasks: [String: Task<(URL, URL?), Error>] = [:]

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: configuration)
        artworkMemoryCache.countLimit = 120
        artworkMemoryCache.totalCostLimit = artworkCacheLimitBytes
    }

    func search(_ provider: PlatformProvider, keywords: String, limit: Int = 20) async throws -> [PlatformTrack] {
        if provider == .netease {
            let rows = try await NativeNetEaseClient.shared.search(keywords: keywords, limit: limit)
            return rows.compactMap { Self.decodeNetEaseTrack($0) }
        }
        if provider == .qq {
            return try await QQProviderClient.shared.search(keywords: keywords, limit: limit)
        }
        return try await kugou.search(keywords: keywords, limit: limit)
    }

    func userPlaylists(for provider: PlatformProvider, limit: Int = 0) async throws -> [PlatformPlaylist] {
        switch provider {
        case .netease:
            let rows = try await NativeNetEaseClient.shared.userPlaylists(limit: limit)
            return rows.compactMap(Self.decodeNetEasePlaylist)
        case .qq:
            return try await QQProviderClient.shared.userPlaylists()
        case .kugou:
            return try await kugou.userPlaylists(limit: limit)
        }
    }

    func playlistTracks(_ playlist: PlatformPlaylist, provider: PlatformProvider,
                        limit: Int? = nil, offset: Int = 0) async throws -> [PlatformTrack] {
        switch provider {
        case .netease:
            let rows = try await NativeNetEaseClient.shared.playlistTracks(
                id: playlist.id,
                limit: limit ?? 100,
                offset: offset
            )
            return rows.compactMap { Self.decodeNetEaseTrack($0) }
        case .qq:
            return try await QQProviderClient.shared.playlistTracks(id: playlist.id, limit: limit ?? 40, offset: offset)
        case .kugou:
            return try await kugou.playlistTracks(playlist, limit: limit ?? 40, offset: offset)
        }
    }

    /// Reuses a complete local copy before asking the provider to resolve a
    /// short-lived URL. Adjacent-track prefetches and taps share one task.
    func hasCachedAudioFile(for track: PlatformTrack) -> Bool {
        let quality = track.provider == .netease ? "exhigh" : "standard"
        let key = audioCacheKey(provider: track.provider, trackID: track.id, quality: quality)
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacDesktopPlayer/PlatformAudio", isDirectory: true)
        return validAudioCache(in: directory, key: key) != nil
    }

    func preparedAudioFile(for track: PlatformTrack) async throws -> (fileURL: URL, remoteURL: URL?, cacheHit: Bool) {
        let quality = track.provider == .netease ? "exhigh" : "standard"
        let cacheKey = audioCacheKey(provider: track.provider, trackID: track.id, quality: quality)
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacDesktopPlayer/PlatformAudio", isDirectory: true)

        if let cached = validAudioCache(in: cacheDirectory, key: cacheKey) {
            NSLog("[PlatformPlayback] provider=%@ track=%@ cache=hit", track.provider.rawValue, track.id)
            return (cached, nil, true)
        }
        if let task = audioPreparationTasks[cacheKey] {
            let (fileURL, remoteURL) = try await task.value
            return (fileURL, remoteURL, false)
        }

        let task = Task { () throws -> (URL, URL?) in
            let resolveStart = Date()
            let playback = try await self.playbackURL(for: track, quality: quality)
            let resolveMilliseconds = Int(Date().timeIntervalSince(resolveStart) * 1_000)
            guard let remoteURL = playback.url else {
                throw PlatformBridgeError.server(playback.restriction?.message ?? playback.message ?? "这首歌当前没有可播放地址")
            }

            let downloadStart = Date()
            let downloaded = try await self.downloadAudioFile(for: remoteURL, in: cacheDirectory, key: cacheKey)
            let downloadMilliseconds = Int(Date().timeIntervalSince(downloadStart) * 1_000)
            let fileSize = (try? downloaded.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            NSLog("[PlatformPlayback] provider=%@ track=%@ cache=miss resolve=%dms download=%dms bytes=%d",
                  track.provider.rawValue, track.id, resolveMilliseconds, downloadMilliseconds, fileSize)
            return (downloaded, remoteURL)
        }
        audioPreparationTasks[cacheKey] = task
        defer { audioPreparationTasks[cacheKey] = nil }
        let (fileURL, remoteURL) = try await task.value
        return (fileURL, remoteURL, false)
    }

    private func downloadAudioFile(for remoteURL: URL, in cacheDirectory: URL, key: String) async throws -> URL {
        if let cached = validAudioCache(in: cacheDirectory, key: key) { return cached }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 30
        request.setValue(Self.referer(for: remoteURL), forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124 Safari/537.36", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PlatformBridgeError.server("平台音频地址不可用")
        }
        let ext = remoteURL.pathExtension.isEmpty ? "audio" : remoteURL.pathExtension
        let destination = cacheDirectory.appendingPathComponent("\(key).\(ext)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        guard validAudioCache(in: cacheDirectory, key: key) != nil else {
            try? FileManager.default.removeItem(at: destination)
            throw PlatformBridgeError.server("平台返回的音频文件无效")
        }
        trimAudioCache(in: cacheDirectory, keeping: destination)
        return destination
    }

    private func validAudioCache(in directory: URL, key: String) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]),
              let candidate = files.first(where: { $0.lastPathComponent.hasPrefix(key + ".") }),
              let size = try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 4_096,
              let audio = try? AVAudioFile(forReading: candidate), audio.length > 0 else { return nil }
        return candidate
    }

    private func audioCacheKey(provider: PlatformProvider, trackID: String, quality: String) -> String {
        let bytes = Array("\(provider.rawValue)|\(trackID)|\(quality)".utf8)
        var hash: UInt64 = 1469598103934665603
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }

    private func trimAudioCache(in directory: URL, keeping currentFile: URL) {
        let limit = 512 * 1024 * 1024
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }
        var entries = files.compactMap { file -> (URL, Int, Date)? in
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize, let date = values.contentModificationDate else { return nil }
            return (file, size, date)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        while total > limit, let oldest = entries.first {
            entries.removeFirst()
            guard oldest.0 != currentFile else { continue }
            try? FileManager.default.removeItem(at: oldest.0)
            total -= oldest.1
        }
    }

    /// Fetches third-party artwork directly from the provider.
    func coverData(for remoteURL: URL) async throws -> Data {
        let key = artworkCacheKey(for: remoteURL)
        let diskURL = artworkDiskURL(for: key)
        if let cached = try? Data(contentsOf: diskURL),
           !cached.isEmpty,
           CGImageSourceCreateWithData(cached as CFData, nil) != nil {
            return cached
        }
        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 15
        request.setValue(Self.referer(for: remoteURL), forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124 Safari/537.36", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PlatformBridgeError.server("平台封面不可用")
        }
        guard !data.isEmpty else { throw PlatformBridgeError.server("平台封面为空") }
        // Persist the same bounded, sRGB-normalized pixels used by the live
        // renderer. Keeping provider bytes on disk made the first load and a
        // later disk-cache decode take different color-management paths.
        guard let image = downsampledArtwork(data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let normalizedData = NSBitmapImageRep(cgImage: cgImage)
                .representation(using: .png, properties: [:]) else {
            throw PlatformBridgeError.server("平台封面无法规范化")
        }
        try? FileManager.default.createDirectory(at: diskURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? normalizedData.write(to: diskURL, options: .atomic)
        trimArtworkDiskCache()
        return normalizedData
    }

    /// Returns a bounded thumbnail rather than retaining provider-sized cover art.
    func coverImage(for remoteURL: URL) async throws -> NSImage {
        let key = artworkCacheKey(for: remoteURL) as NSString
        if let cached = artworkMemoryCache.object(forKey: key) { return cached }
        let data = try await coverData(for: remoteURL)
        let image = downsampledArtwork(data) ?? NSImage(data: data)
        guard let image else { throw PlatformBridgeError.server("平台封面无法解码") }
        let cost = max(1, Int(image.size.width * image.size.height * 4))
        artworkMemoryCache.setObject(image, forKey: key, cost: cost)
        return image
    }

    private func artworkCacheKey(for remoteURL: URL) -> String {
        let bytes = Array(remoteURL.absoluteString.utf8)
        var hash: UInt64 = 1469598103934665603
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }

    private func artworkDiskURL(for key: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacDesktopPlayer/PlatformArtwork-v2", isDirectory: true)
            .appendingPathComponent("\(key).img")
    }

    private func downsampledArtwork(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: thumbnail.width,
                                      height: thumbnail.height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: thumbnail.width * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        guard let normalized = context.makeImage() else { return nil }
        return NSImage(cgImage: normalized, size: NSSize(width: normalized.width, height: normalized.height))
    }

    private func trimArtworkDiskCache() {
        let directory = artworkDiskURL(for: "").deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize, let date = values.contentModificationDate else { return nil }
            return (url, size, date)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        while total > artworkDiskLimitBytes, let oldest = entries.first {
            try? FileManager.default.removeItem(at: oldest.0)
            total -= oldest.1
            entries.removeFirst()
        }
    }

    func playbackURL(for track: PlatformTrack, quality: String? = nil) async throws -> PlatformPlayback {
        let requestedQuality = quality ?? (track.provider == .netease ? "exhigh" : "standard")
        if track.provider == .netease {
            return try await NativeNetEaseClient.shared.playback(trackID: track.id, quality: requestedQuality)
        }
        if track.provider == .qq {
            return try await QQProviderClient.shared.playback(for: track, quality: requestedQuality)
        }
        return try await kugou.playback(for: track, quality: requestedQuality)
    }

    func loginStatus(for provider: PlatformProvider) async throws -> PlatformLoginStatus {
        if provider == .netease {
            return try await NativeNetEaseClient.shared.loginStatus()
        }
        if provider == .qq {
            return try await QQProviderClient.shared.loginStatus()
        }
        return try kugou.loginStatus()
    }

    func saveLoginCookie(_ cookie: String, for provider: PlatformProvider) async throws -> PlatformLoginStatus {
        if provider == .netease {
            return try await NativeNetEaseClient.shared.saveLoginCookie(cookie)
        }
        if provider == .qq {
            return try await QQProviderClient.shared.saveLoginCookie(cookie)
        }
        return try kugou.saveCookie(cookie)
    }

    private static func decodeNetEaseTrack(_ row: [String: Any]) -> PlatformTrack? {
        let album = (row["al"] as? [String: Any]) ?? (row["album"] as? [String: Any]) ?? [:]
        let artists = (row["ar"] as? [[String: Any]]) ?? (row["artists"] as? [[String: Any]]) ?? []
        let artist = artists.compactMap { string($0["name"]) }.joined(separator: ", ")
        let cover = string(album["picUrl"] ?? album["coverImgUrl"])
        guard let id = string(row["id"]), let name = string(row["name"]) else { return nil }
        return PlatformTrack(
            id: id,
            provider: .netease,
            name: name,
            artist: artist,
            album: string(album["name"]),
            durationMilliseconds: number(row["dt"] ?? row["duration"]),
            coverURL: URL(string: cover ?? ""),
            mediaID: nil,
            hash: nil,
            albumID: nil,
            albumAudioID: nil
        )
    }

    private static func decodeNetEasePlaylist(_ row: [String: Any]) -> PlatformPlaylist? {
        guard let id = string(row["id"]), let name = string(row["name"]) else { return nil }
        return PlatformPlaylist(
            id: id,
            name: name,
            coverURL: URL(string: string(row["coverImgUrl"] ?? row["cover"]) ?? ""),
            trackCount: number(row["trackCount"] ?? row["trackNumber"])
        )
    }

    private static func referer(for url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        if host.contains("163.com") || host.contains("126.net") { return "https://music.163.com/" }
        if host.contains("qq.com") || host.contains("gtimg.cn") { return "https://y.qq.com/" }
        if host.contains("kugou.com") { return "https://www.kugou.com/" }
        return "https://music.163.com/"
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func number(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}
