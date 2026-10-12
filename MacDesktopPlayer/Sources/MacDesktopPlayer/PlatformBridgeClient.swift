import Foundation
import AppKit
import AVFoundation
import ImageIO

/// Platform source exposed by the local Mineradio-compatible bridge.
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
        case .invalidResponse: return "平台 Bridge 返回了无法识别的数据"
        case .server(let message): return message
        case .notConfigured: return "未连接本机平台 Bridge（默认地址：http://127.0.0.1:3000）"
        }
    }
}

/// Thin client only. Authentication and platform-specific credentials remain in
/// the local Bridge; the Mac app never parses or uploads third-party cookies.
actor PlatformBridgeClient {
    static let shared = PlatformBridgeClient()

    private let session: URLSession
    private var baseURL: URL
    private let artworkMemoryCache = NSCache<NSString, NSImage>()
    private let artworkCacheLimitBytes = 32 * 1024 * 1024
    private let artworkDiskLimitBytes = 128 * 1024 * 1024
    private var audioPreparationTasks: [String: Task<(URL, URL?), Error>] = [:]

    init(baseURL: URL = URL(string: "http://127.0.0.1:3000")!) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: configuration)
        artworkMemoryCache.countLimit = 120
        artworkMemoryCache.totalCostLimit = artworkCacheLimitBytes
    }

    func setBaseURL(_ url: URL) throws {
        guard url.scheme == "http" || url.scheme == "https" else { throw PlatformBridgeError.notConfigured }
        baseURL = url
    }

    func search(_ provider: PlatformProvider, keywords: String, limit: Int = 20) async throws -> [PlatformTrack] {
        let path: String
        switch provider {
        case .netease: path = "/api/search"
        case .qq: path = "/api/qq/search"
        case .kugou: path = "/api/kugou/search"
        }
        let payload: [String: Any] = try await request(path: path, query: [
            URLQueryItem(name: "keywords", value: keywords),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 50))))
        ])
        guard let rows = payload["songs"] as? [[String: Any]] else {
            throw PlatformBridgeError.invalidResponse
        }
        return rows.compactMap { Self.decodeTrack($0, provider: provider) }
    }

    func userPlaylists(for provider: PlatformProvider, limit: Int = 0) async throws -> [PlatformPlaylist] {
        guard provider == .netease else {
            throw PlatformBridgeError.server("Mac 端当前先接入网易云用户歌单")
        }
        var query: [URLQueryItem] = []
        if limit > 0 { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        let response = try await request(path: "/api/user/playlists", query: query)
        guard let rows = response["playlists"] as? [[String: Any]] else {
            throw PlatformBridgeError.invalidResponse
        }
        return rows.compactMap(Self.decodePlaylist)
    }

    func playlistTracks(_ playlist: PlatformPlaylist, provider: PlatformProvider,
                        limit: Int? = nil, offset: Int = 0) async throws -> [PlatformTrack] {
        guard provider == .netease else {
            throw PlatformBridgeError.server("Mac 端当前先接入网易云用户歌单")
        }
        var query = [URLQueryItem(name: "id", value: playlist.id)]
        if let limit, limit > 0 {
            query.append(URLQueryItem(name: "limit", value: String(min(limit, 100))))
            query.append(URLQueryItem(name: "offset", value: String(max(0, offset))))
        }
        let response = try await request(path: "/api/playlist/tracks", query: query)
        guard let rows = response["tracks"] as? [[String: Any]] else {
            throw PlatformBridgeError.invalidResponse
        }
        return rows.compactMap { Self.decodeTrack($0, provider: provider) }
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
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("api/audio"),
            resolvingAgainstBaseURL: false
        ) else { throw PlatformBridgeError.notConfigured }
        components.queryItems = [URLQueryItem(name: "url", value: remoteURL.absoluteString)]
        guard let proxyURL = components.url else { throw PlatformBridgeError.notConfigured }
        var request = URLRequest(url: proxyURL)
        request.timeoutInterval = 30
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

    /// Fetches third-party artwork through the Bridge so HTTP artwork URLs and
    /// provider referer requirements do not prevent AppKit from decoding them.
    func coverData(for remoteURL: URL) async throws -> Data {
        let key = artworkCacheKey(for: remoteURL)
        let diskURL = artworkDiskURL(for: key)
        if let cached = try? Data(contentsOf: diskURL),
           !cached.isEmpty,
           CGImageSourceCreateWithData(cached as CFData, nil) != nil {
            return cached
        }
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("api/cover"),
            resolvingAgainstBaseURL: false
        ) else {
            throw PlatformBridgeError.notConfigured
        }
        components.queryItems = [URLQueryItem(name: "url", value: remoteURL.absoluteString)]
        guard let proxyURL = components.url else { throw PlatformBridgeError.notConfigured }
        let (data, response) = try await session.data(from: proxyURL)
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
        var query = [URLQueryItem(name: "quality", value: requestedQuality)]
        switch track.provider {
        case .netease:
            query.append(URLQueryItem(name: "id", value: track.id))
            query.append(URLQueryItem(name: "name", value: track.name))
            query.append(URLQueryItem(name: "artist", value: track.artist))
            let response: [String: Any] = try await request(path: "/api/song/url", query: query)
            return try Self.decodePlayback(response, provider: .netease)
        case .qq:
            query.append(URLQueryItem(name: "mid", value: track.mediaID ?? track.id))
            if let mediaID = track.mediaID { query.append(URLQueryItem(name: "mediaMid", value: mediaID)) }
            let response: [String: Any] = try await request(path: "/api/qq/song/url", query: query)
            return try Self.decodePlayback(response, provider: .qq)
        case .kugou:
            query.append(URLQueryItem(name: "hash", value: track.hash ?? track.id))
            let response: [String: Any] = try await request(path: "/api/kugou/song/url", query: query)
            return try Self.decodePlayback(response, provider: .kugou)
        }
    }

    func loginStatus(for provider: PlatformProvider) async throws -> PlatformLoginStatus {
        let path: String
        switch provider {
        case .netease: path = "/api/login/status"
        case .qq: path = "/api/qq/login/status"
        case .kugou: path = "/api/kugou/login/status"
        }
        let response: [String: Any] = try await request(path: path, query: [])
        return PlatformLoginStatus(
            provider: provider,
            loggedIn: response["loggedIn"] as? Bool ?? false,
            nickname: response["nickname"] as? String,
            userID: (response["userId"] as? String) ?? (response["uid"] as? String),
            isVIP: response["isVip"] as? Bool,
            isSVIP: response["isSvip"] as? Bool,
            message: response["message"] as? String
        )
    }

    func saveLoginCookie(_ cookie: String, for provider: PlatformProvider) async throws -> PlatformLoginStatus {
        let path: String
        switch provider {
        case .netease: path = "/api/login/cookie"
        case .qq: path = "/api/qq/login/cookie"
        case .kugou: path = "/api/kugou/login/cookie"
        }
        let response = try await postJSON(path: path, body: ["cookie": cookie])
        return PlatformLoginStatus(
            provider: provider,
            loggedIn: response["loggedIn"] as? Bool ?? false,
            nickname: response["nickname"] as? String,
            userID: (response["userId"] as? String) ?? (response["uid"] as? String),
            isVIP: response["isVip"] as? Bool,
            isSVIP: response["isSvip"] as? Bool,
            message: response["message"] as? String
        )
    }

    private func request(path: String, query: [URLQueryItem]) async throws -> [String: Any] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw PlatformBridgeError.notConfigured
        }
        components.queryItems = query
        guard let url = components.url else { throw PlatformBridgeError.notConfigured }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw PlatformBridgeError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw PlatformBridgeError.server(message ?? "平台 Bridge 请求失败（HTTP \(http.statusCode)）")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlatformBridgeError.invalidResponse
        }
        return object
    }

    private func postJSON(path: String, body: [String: String]) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlatformBridgeError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw PlatformBridgeError.server(message ?? "平台登录凭据提交失败（HTTP \(http.statusCode)）")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlatformBridgeError.invalidResponse
        }
        return object
    }

    private static func decodeTrack(_ row: [String: Any], provider: PlatformProvider) -> PlatformTrack? {
        let id = string(row["id"]) ?? string(row["mid"]) ?? string(row["hash"])
        let name = string(row["name"]) ?? string(row["title"])
        guard let id, let name else { return nil }
        return PlatformTrack(
            id: id,
            provider: provider,
            name: name,
            artist: string(row["artist"]) ?? string(row["artists"]) ?? "",
            album: string(row["album"]),
            durationMilliseconds: number(row["duration"]) ?? number(row["dt"]),
            coverURL: URL(string: string(row["cover"]) ?? string(row["coverUrl"]) ?? ""),
            mediaID: string(row["mid"]) ?? string(row["songmid"]),
            hash: string(row["hash"]) ?? string(row["fileHash"])
        )
    }

    private static func decodePlaylist(_ row: [String: Any]) -> PlatformPlaylist? {
        guard let id = string(row["id"]), let name = string(row["name"]) else { return nil }
        return PlatformPlaylist(
            id: id,
            name: name,
            coverURL: URL(string: string(row["cover"]) ?? string(row["coverUrl"]) ?? ""),
            trackCount: number(row["trackCount"]) ?? number(row["track_count"])
        )
    }

    private static func decodePlayback(_ response: [String: Any], provider: PlatformProvider) throws -> PlatformPlayback {
        let url = URL(string: string(response["url"]) ?? "")
        let restrictionObject = response["restriction"] as? [String: Any]
        let restriction = restrictionObject.map {
            PlaybackRestriction(category: string($0["category"]), action: string($0["action"]), message: string($0["message"]))
        }
        return PlatformPlayback(
            provider: provider,
            url: url,
            playable: response["playable"] as? Bool,
            trial: response["trial"] as? Bool,
            quality: string(response["quality"]),
            message: string(response["message"]),
            restriction: restriction
        )
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
