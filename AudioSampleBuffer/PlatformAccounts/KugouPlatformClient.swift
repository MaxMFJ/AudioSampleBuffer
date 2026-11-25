import Foundation

/// Kugou account surface for the shared account layer.  The current iOS
/// client deliberately does not guess at web endpoints or manufacture audio
/// URLs when the authenticated API is unavailable.
public final class KugouPlatformClient: PlatformMusicProviderClient, @unchecked Sendable {
    public let platform: MusicPlatform = .kugou

    public init() {}

    public func verify(platform: AccountPlatform, cookies: [HTTPCookie]) async -> Bool {
        guard platform == .kugou else { return false }
        // kg_mid identifies a browser session, but does not prove that the
        // session is authenticated.  Verification requires Kugou's signed
        // account API, which is not exposed by this iOS client.
        return false
    }

    public func userPlaylists(cookieHeader: String) async throws -> [ProviderPlaylist] {
        throw PlatformMusicError.unsupported("酷狗歌单需要 Kugou 的签名账户接口；当前 iOS 客户端暂不支持。")
    }

    public func playlistTracks(_ playlist: ProviderPlaylist, cookieHeader: String, limit: Int, offset: Int) async throws -> [ProviderTrack] {
        throw PlatformMusicError.unsupported("酷狗歌单曲目需要 Kugou 的签名账户接口；当前 iOS 客户端暂不支持。")
    }

    public func searchTracks(keyword: String, cookieHeader: String, limit: Int) async throws -> [ProviderTrack] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var components = URLComponents(string: "https://songsearch.kugou.com/song_search_v2")!
        components.queryItems = [
            URLQueryItem(name: "keyword", value: trimmed),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pagesize", value: String(max(1, min(limit, 30)))),
            URLQueryItem(name: "userid", value: "-1"),
            URLQueryItem(name: "clientver", value: "2000"),
            URLQueryItem(name: "platform", value: "WebFilter"),
            URLQueryItem(name: "filter", value: "2"),
            URLQueryItem(name: "iscorrection", value: "1"),
            URLQueryItem(name: "privilege_filter", value: "0"),
            URLQueryItem(name: "appid", value: "1014")
        ]
        guard let url = components.url else { throw PlatformMusicError.unavailable("酷狗搜索地址无效。") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("https://www.kugou.com/", forHTTPHeaderField: "Referer")
        if !cookieHeader.isEmpty { request.setValue(cookieHeader, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = json["data"] as? [String: Any],
              let list = body["lists"] as? [[String: Any]] else {
            throw PlatformMusicError.unavailable("酷狗搜索暂时不可用。")
        }
        return list.compactMap(Self.track(from:))
    }

    private static func track(from item: [String: Any]) -> ProviderTrack? {
        let hash = (item["FileHash"] as? String) ?? ""
        let rawName = (item["SongName"] as? String) ?? (item["FileName"] as? String) ?? ""
        let name = rawName.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        guard !name.isEmpty, !hash.isEmpty else { return nil }
        let artist = ((item["SingerName"] as? String) ?? "").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let album = (item["AlbumName"] as? String)?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let albumID = item["AlbumID"].map { String(describing: $0) }
        let mix = item["MixSongID"].map { String(describing: $0) } ?? item["mixsongid"].map { String(describing: $0) }
        let duration = (item["Duration"] as? NSNumber)?.doubleValue
        return ProviderTrack(id: hash, platform: .kugou, name: name, artist: artist, album: album, artworkURL: (item["Image"] as? String).flatMap(URL.init(string:)), duration: duration, hash: hash, albumID: albumID, albumAudioID: mix)
    }

    public func playbackURL(for track: ProviderTrack, cookieHeader: String) async throws -> URL {
        throw PlatformMusicError.unsupported("酷狗播放地址受签名、会员和版权策略控制；当前 iOS 客户端不提供未授权直链。")
    }
}
