import Foundation
import AVFoundation

public final class PlatformMusicService: PlatformAccountVerifying, @unchecked Sendable {
    public static let shared = PlatformMusicService()

    private let clients: [MusicPlatform: any PlatformMusicProviderClient]
    private let credentials = KeychainPlatformCredentialStore()
    private let bilibiliVideoClient = BilibiliVideoClient()
    private var playbackQueue: [ProviderTrack] = []
    private var playbackIndex = 0
    private var playbackQueueHasMore = false
    private var playbackPlaylistID: String?

    public init(clients: [any PlatformMusicProviderClient]) {
        self.clients = Dictionary(uniqueKeysWithValues: clients.map { ($0.platform, $0) })
        NotificationCenter.default.addObserver(forName: .platformMusicSkipNext, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.advancePlayback(by: 1) }
        }
        NotificationCenter.default.addObserver(forName: .platformMusicSkipPrevious, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.advancePlayback(by: -1) }
        }
        NotificationCenter.default.addObserver(forName: .platformMusicReplayCurrent, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.advancePlayback(by: 0) }
        }
        NotificationCenter.default.addObserver(forName: .platformMusicClearQueue, object: nil, queue: .main) { [weak self] _ in
            self?.clearPlaybackQueue()
        }
    }

    private convenience init() {
        self.init(clients: [
            NetEasePlatformClient(),
            QQMusicPlatformClient(),
            KugouPlatformClient()
        ])
    }

    public func verify(platform: AccountPlatform, cookies: [HTTPCookie]) async -> Bool {
        if platform == .bilibili { return await bilibiliVideoClient.verify(cookies: cookies) }
        guard let client = clients[platform] else { return false }
        return await client.verify(platform: platform, cookies: cookies)
    }

    public func playlists(for platform: MusicPlatform) async throws -> [ProviderPlaylist] {
        let cookieHeader = try await requiredCredential(for: platform)
        guard let client = clients[platform] else { throw PlatformMusicError.unsupported("该音乐平台暂未接入。") }
        return try await client.userPlaylists(cookieHeader: cookieHeader)
    }

    public func tracks(in playlist: ProviderPlaylist, limit: Int = 100, offset: Int = 0) async throws -> [ProviderTrack] {
        let cookieHeader = try await requiredCredential(for: playlist.platform)
        guard let client = clients[playlist.platform] else { throw PlatformMusicError.unsupported("该音乐平台暂未接入。") }
        return try await client.playlistTracks(playlist, cookieHeader: cookieHeader, limit: limit, offset: offset)
    }

    public func searchTracks(on platform: MusicPlatform, keyword: String, limit: Int = 30) async throws -> [ProviderTrack] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let cookieHeader = (try? await requiredCredential(for: platform)) ?? ""
        if platform != .kugou, cookieHeader.isEmpty { throw PlatformMusicError.missingCredential }
        guard let client = clients[platform] else { throw PlatformMusicError.unsupported("该音乐平台暂未接入。") }
        return try await client.searchTracks(keyword: trimmed, cookieHeader: cookieHeader, limit: limit)
    }

    public func searchQQMusicMVs(for track: ProviderTrack) async throws -> [QQMusicMV] {
        guard track.platform == .qqMusic,
              let client = clients[.qqMusic] as? QQMusicPlatformClient else {
            throw PlatformMusicError.unsupported("QQ MV 测试仅支持 QQ 音乐曲目。")
        }
        let cookieHeader = try await requiredCredential(for: .qqMusic)
        return try await client.searchMVs(for: track, cookieHeader: cookieHeader)
    }

    public func qqMusicMVPlaybackURL(for mv: QQMusicMV) async throws -> URL {
        guard let client = clients[.qqMusic] as? QQMusicPlatformClient else {
            throw PlatformMusicError.unsupported("QQ MV 服务当前不可用。")
        }
        let cookieHeader = try await requiredCredential(for: .qqMusic)
        return try await client.mvPlaybackURL(for: mv, cookieHeader: cookieHeader)
    }

    public func searchBilibiliVideos(for track: ProviderTrack) async throws -> [BilibiliVideoClient.Video] {
        let cookieHeader = try requiredBilibiliCookieHeader()
        return try await bilibiliVideoClient.search(song: track.name, artist: track.artist, cookieHeader: cookieHeader)
    }

    public func bilibiliPlaybackURL(for video: BilibiliVideoClient.Video) async throws -> URL {
        let cookieHeader = try requiredBilibiliCookieHeader()
        return try await bilibiliVideoClient.playbackURL(for: video, cookieHeader: cookieHeader)
    }

    public func bilibiliPlaybackInfo(for video: BilibiliVideoClient.Video) async throws -> BilibiliVideoClient.PlaybackInfo {
        let cookieHeader = try requiredBilibiliCookieHeader()
        return try await bilibiliVideoClient.playbackInfo(for: video, cookieHeader: cookieHeader)
    }

    public func bilibiliPlayerAsset(for url: URL) -> AVAsset {
        bilibiliVideoClient.playerAsset(for: url)
    }

    public func neteaseLyrics(trackID: String) async throws -> String {
        let cookieHeader = try await requiredCredential(for: .netease)
        guard let client = clients[.netease] as? NetEasePlatformClient else {
            throw PlatformMusicError.unsupported("网易云歌词服务当前不可用。")
        }
        guard let lyric = try await client.lyrics(trackID: trackID, cookieHeader: cookieHeader) else {
            throw PlatformMusicError.unavailable("网易云没有返回这首歌的歌词。")
        }
        return lyric
    }

    public func playFile(for track: ProviderTrack) async throws -> URL {
        let cookieHeader = try await requiredCredential(for: track.platform)
        guard let client = clients[track.platform] else { throw PlatformMusicError.unsupported("该音乐平台暂未接入。") }
        let remoteURL = try await client.playbackURL(for: track, cookieHeader: cookieHeader)
        let playbackURL = try securePlaybackURL(remoteURL)

        var request = URLRequest(url: playbackURL)
        request.timeoutInterval = 30
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PlatformMusicError.unavailable("音乐文件暂时无法获取，请检查登录状态或平台版权限制。")
        }
        let prefix: Data
        do {
            let handle = try FileHandle(forReadingFrom: temporaryURL)
            defer { try? handle.close() }
            prefix = try handle.read(upToCount: 16) ?? Data()
        } catch {
            throw PlatformMusicError.unavailable("平台没有返回可读取的音频文件。")
        }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let bytes = [UInt8](prefix)
        let signatureLooksLikeAudio = String(bytes: bytes.prefix(3), encoding: .ascii) == "ID3"
            || String(bytes: bytes.prefix(4), encoding: .ascii) == "fLaC"
            || String(bytes: bytes.prefix(4), encoding: .ascii) == "OggS"
            || (bytes.count >= 12 && String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp")
            || (bytes.count >= 12 && String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF" && String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE")
            || (bytes.count >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0)
        guard !prefix.isEmpty, !contentType.contains("text/html"), !contentType.contains("json"), signatureLooksLikeAudio else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw PlatformMusicError.unavailable("平台返回的内容不是可播放音频，可能是登录、版权或地区限制响应。")
        }
        let ext = response.suggestedFilename.map { URL(fileURLWithPath: $0).pathExtension }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "m4a"
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlatformMusic", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("\(track.platform.rawValue)-\(safeFileComponent(track.id)).\(ext)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    public func artworkFile(for track: ProviderTrack) async -> URL? {
        guard let source = track.artworkURL,
              let secureURL = try? securePlaybackURL(source) else { return nil }
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlatformMusic/Artwork", isDirectory: true)
        let destination = folder.appendingPathComponent("\(track.platform.rawValue)-\(safeFileComponent(track.id)).image")
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        var request = URLRequest(url: secureURL)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased().hasPrefix("image/"),
              !data.isEmpty, data.count <= 8 * 1024 * 1024 else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    public func setPlaybackQueue(_ tracks: [ProviderTrack], selectedIndex: Int, hasMore: Bool = false, playlistID: String? = nil) {
        playbackQueue = tracks
        playbackIndex = max(0, min(selectedIndex, max(0, tracks.count - 1)))
        playbackQueueHasMore = hasMore
        playbackPlaylistID = playlistID
        NotificationCenter.default.post(name: .platformMusicQueueDidChange, object: nil, userInfo: ["active": !tracks.isEmpty])
    }

    public func clearPlaybackQueue() {
        playbackQueue.removeAll()
        playbackIndex = 0
        playbackQueueHasMore = false
        playbackPlaylistID = nil
        NotificationCenter.default.post(name: .platformMusicQueueDidChange, object: nil, userInfo: ["active": false])
    }

    private func advancePlayback(by delta: Int) async {
        guard !playbackQueue.isEmpty else { return }
        if delta > 0, playbackIndex == playbackQueue.count - 1, playbackQueueHasMore {
            NotificationCenter.default.post(name: .platformMusicRequestMoreForQueue, object: nil, userInfo: ["requestedIndex": playbackIndex + 1])
            return
        }
        playbackIndex = (playbackIndex + delta + playbackQueue.count) % playbackQueue.count
        let track = playbackQueue[playbackIndex]
        do {
            let url = try await playFile(for: track)
            let artwork = await artworkFile(for: track)
            await MainActor.run {
                NotificationCenter.default.post(name: .platformMusicDidResolvePlayback, object: nil, userInfo: [
                    "filePath": url.path,
                    "title": track.name,
                    "artist": track.artist,
                    "album": track.album ?? "",
                    "duration": track.duration ?? 0,
                    "artworkFilePath": artwork?.path ?? "",
                    "artworkURL": track.artworkURL?.absoluteString ?? "",
                    "platform": track.platform.rawValue,
                    "trackID": track.id,
                    "mediaID": track.mediaID ?? "",
                    "hash": track.hash ?? "",
                    "albumID": track.albumID ?? "",
                    "albumAudioID": track.albumAudioID ?? "",
                    "playlistID": playbackPlaylistID ?? "",
                    "queueIndex": playbackIndex
                ])
            }
        } catch {
            NotificationCenter.default.post(name: .platformMusicQueueDidChange, object: nil, userInfo: ["active": true, "error": error.localizedDescription])
        }
    }

    private func requiredCredential(for platform: MusicPlatform) async throws -> String {
        guard let credential = try credentials.credential(for: platform),
              let header = credential.cookieHeader, !header.isEmpty else {
            throw PlatformMusicError.missingCredential
        }
        return header
    }

    private func requiredBilibiliCookieHeader() throws -> String {
        guard let credential = try credentials.credential(for: .bilibili),
              let header = credential.cookieHeader, !header.isEmpty else {
            throw PlatformMusicError.unavailable("请先点上方「B站登录」并完成网页登录，再搜索或播放视频。")
        }
        return header
    }

    private func safeFileComponent(_ value: String) -> String {
        let safe = value.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return String(safe.prefix(80))
    }

    private func securePlaybackURL(_ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              components.host != nil else {
            throw PlatformMusicError.unavailable("平台返回了无效的播放地址。")
        }
        if scheme == "https" { return url }
        guard scheme == "http" else {
            throw PlatformMusicError.unavailable("平台返回了不支持的播放地址协议。")
        }
        // Music providers sometimes return legacy HTTP CDN links. Try the same
        // signed resource over TLS; never weaken ATS or fall back to plaintext.
        components.scheme = "https"
        guard let upgradedURL = components.url else {
            throw PlatformMusicError.unavailable("无法将平台音源地址升级为安全连接。")
        }
        return upgradedURL
    }
}

/// Supplies the main transparent music table with platform playlists and tracks.
/// Rows cross the Objective-C boundary as dictionaries; track playback retains
/// the typed ProviderTrack queue inside this service.
@objc(PlatformMusicLibraryBridge)
public final class PlatformMusicLibraryBridge: NSObject {
    private let service = PlatformMusicService.shared
    private var selectedPlatform: MusicPlatform?
    private var playlists: [ProviderPlaylist] = []
    private var tracks: [ProviderTrack] = []
    private var selectedPlaylist: ProviderPlaylist?
    private var trackOffset = 0
    private var hasMoreTracks = false
    private var isLoading = false
    private var advanceAfterPage = false
    private var pendingTrackIndex: Int?
    private var selectedTrackIndex = 0
    private var isQueueActive = false
    private var requestGeneration = 0
    private var queueTracks: [ProviderTrack] = []
    private var queuePlaylist: ProviderPlaylist?
    private var queueHasMore = false
    private var queueSelectedIndex = 0
    private var queuePageLoading = false
    private var pendingQueueIndex: Int?

    public override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(loadSource(_:)), name: .platformMusicLoadSource, object: nil)
        center.addObserver(self, selector: #selector(loadPlaylist(_:)), name: .platformMusicLoadPlaylist, object: nil)
        center.addObserver(self, selector: #selector(loadMore), name: .platformMusicLoadMore, object: nil)
        center.addObserver(self, selector: #selector(searchSongs(_:)), name: .platformMusicSearch, object: nil)
        center.addObserver(self, selector: #selector(playTrack(_:)), name: .platformMusicPlayTrackAtIndex, object: nil)
        center.addObserver(self, selector: #selector(loadMoreForQueue(_:)), name: .platformMusicRequestMoreForQueue, object: nil)
        center.addObserver(self, selector: #selector(queuePlaybackDidResolve(_:)), name: .platformMusicDidResolvePlayback, object: nil)
    }

    @objc private func loadSource(_ notification: Notification) {
        guard let raw = notification.userInfo?["platform"] as? String,
              let platform = MusicPlatform(rawValue: raw) else { return }
        selectedPlatform = platform
        requestGeneration += 1
        let generation = requestGeneration
        selectedPlaylist = nil
        selectedTrackIndex = 0
        playlists.removeAll()
        tracks.removeAll()
        isLoading = true
        publish(mode: "playlists", rows: [], hasMore: false, message: "正在读取\(platform.displayName)歌单…")
        Task { @MainActor in
            do {
                let result = try await service.playlists(for: platform)
                guard generation == requestGeneration else { return }
                playlists = result
                isLoading = false
                publish(mode: "playlists", rows: playlists.map(playlistRow), hasMore: false,
                        message: playlists.isEmpty ? "该账号没有返回歌单。" : "选择歌单查看曲目。")
            } catch {
                guard generation == requestGeneration else { return }
                isLoading = false
                publish(mode: "playlists", rows: [], hasMore: false, message: error.localizedDescription)
            }
        }
    }

    @objc private func loadPlaylist(_ notification: Notification) {
        guard let raw = notification.userInfo?["platform"] as? String,
              let platform = MusicPlatform(rawValue: raw),
              let playlistID = notification.userInfo?["playlistID"] as? String else { return }
        let name = notification.userInfo?["title"] as? String ?? "歌单"
        selectedPlatform = platform
        selectedPlaylist = playlists.first(where: { $0.id == playlistID })
            ?? ProviderPlaylist(id: playlistID, platform: platform, name: name)
        requestGeneration += 1
        let generation = requestGeneration
        selectedTrackIndex = 0
        tracks.removeAll()
        trackOffset = 0
        hasMoreTracks = false
        isLoading = true
        publish(mode: "tracks", rows: [], hasMore: false, message: "正在读取《\(name)》…")
        Task { @MainActor in
            await fetchNextTrackPage(generation: generation)
        }
    }

    @objc private func searchSongs(_ notification: Notification) {
        guard let raw = notification.userInfo?["platform"] as? String,
              let platform = MusicPlatform(rawValue: raw) else { return }
        let keyword = (notification.userInfo?["keyword"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        selectedPlatform = platform
        requestGeneration += 1
        let generation = requestGeneration
        if keyword.isEmpty {
            selectedPlaylist = nil
            tracks.removeAll()
            hasMoreTracks = false
            isLoading = true
            publish(mode: "playlists", rows: [], hasMore: false, message: "正在读取\(platform.displayName)歌单…")
            Task { @MainActor in
                do {
                    let result = try await service.playlists(for: platform)
                    guard generation == requestGeneration else { return }
                    playlists = result
                    isLoading = false
                    publish(mode: "playlists", rows: playlists.map(playlistRow), hasMore: false,
                            message: playlists.isEmpty ? "该账号没有返回歌单。" : "选择歌单查看曲目。")
                } catch {
                    guard generation == requestGeneration else { return }
                    isLoading = false
                    publish(mode: "playlists", rows: [], hasMore: false, message: error.localizedDescription)
                }
            }
            return
        }
        selectedPlaylist = nil
        tracks.removeAll()
        hasMoreTracks = false
        isLoading = true
        publish(mode: "tracks", rows: [], hasMore: false, message: "正在搜索「\(keyword)」…")
        Task { @MainActor in
            do {
                let result = try await service.searchTracks(on: platform, keyword: keyword, limit: 30)
                guard generation == requestGeneration else { return }
                tracks = result
                isLoading = false
                publish(mode: "tracks", rows: tracks.map(trackRow), hasMore: false,
                        message: result.isEmpty ? "没有找到与「\(keyword)」匹配的歌曲。" : "搜索「\(keyword)」· \(result.count) 首，点按即可播放。")
            } catch {
                guard generation == requestGeneration else { return }
                isLoading = false
                publish(mode: "tracks", rows: [], hasMore: false, message: error.localizedDescription)
            }
        }
    }

    @objc private func loadMore() {
        guard selectedPlaylist != nil, hasMoreTracks, !isLoading else { return }
        isLoading = true
        let generation = requestGeneration
        Task { @MainActor in
            await fetchNextTrackPage(generation: generation)
        }
    }

    @objc private func loadMoreForQueue(_ notification: Notification) {
        Task { @MainActor in self.handleLoadMoreForQueue(notification) }
    }

    @MainActor private func handleLoadMoreForQueue(_ notification: Notification) {
        guard isQueueActive, let playlist = queuePlaylist, queueHasMore, !queuePageLoading else {
            return
        }
        pendingQueueIndex = (notification.userInfo?["requestedIndex"] as? NSNumber)?.intValue
        queuePageLoading = true
        if isLoading, selectedPlaylist?.id == playlist.id { return }
        Task { @MainActor in await fetchNextQueuePage(playlist: playlist) }
    }

    @objc private func queuePlaybackDidResolve(_ notification: Notification) {
        guard let id = notification.userInfo?["trackID"] as? String else { return }
        if let index = queueTracks.firstIndex(where: { $0.id == id }) { queueSelectedIndex = index }
        if let index = tracks.firstIndex(where: { $0.id == id }) { selectedTrackIndex = index }
    }

    private func fetchNextTrackPage(generation: Int) async {
        guard let playlist = selectedPlaylist else { return }
        do {
            let page = try await service.tracks(in: playlist, limit: 20, offset: trackOffset)
            guard generation == requestGeneration, selectedPlaylist?.id == playlist.id else { return }
            tracks.append(contentsOf: page)
            trackOffset += page.count
            hasMoreTracks = page.count == 20
            if isQueueActive, queuePlaylist?.id == playlist.id {
                queueTracks = tracks
                queueHasMore = hasMoreTracks
                queueSelectedIndex = min(queueSelectedIndex, max(0, queueTracks.count - 1))
                service.setPlaybackQueue(queueTracks, selectedIndex: queueSelectedIndex, hasMore: queueHasMore, playlistID: playlist.id)
            }
            publish(mode: "tracks", rows: tracks.map(trackRow), hasMore: hasMoreTracks,
                    message: "《\(playlist.name)》· 已显示 \(tracks.count) 首\(hasMoreTracks ? "，上滑加载更多。" : "")")
            isLoading = false
            if queuePageLoading, queuePlaylist?.id == playlist.id {
                queuePageLoading = false
                if let target = pendingQueueIndex, queueTracks.indices.contains(target) {
                    pendingQueueIndex = nil
                    await playQueueTrack(at: target)
                }
            }
        } catch {
            guard generation == requestGeneration else { return }
            isLoading = false
            hasMoreTracks = false
            if isQueueActive, queuePlaylist?.id == playlist.id {
                queueHasMore = false
                service.setPlaybackQueue(queueTracks, selectedIndex: queueSelectedIndex, hasMore: false, playlistID: playlist.id)
            }
            publish(mode: "tracks", rows: tracks.map(trackRow), hasMore: hasMoreTracks, message: error.localizedDescription)
            if queuePageLoading, queuePlaylist?.id == playlist.id {
                queuePageLoading = false
                pendingQueueIndex = nil
            }
        }
    }

    @objc private func playTrack(_ notification: Notification) {
        let index = (notification.userInfo?["index"] as? NSNumber)?.intValue ?? -1
        Task { @MainActor in await playTrack(at: index) }
    }

    private func playTrack(at index: Int) async {
        guard tracks.indices.contains(index) else { return }
        selectedTrackIndex = index
        isQueueActive = true
        queueTracks = tracks
        queuePlaylist = selectedPlaylist
        queueHasMore = hasMoreTracks
        queueSelectedIndex = index
        service.setPlaybackQueue(queueTracks, selectedIndex: index, hasMore: hasMoreTracks, playlistID: selectedPlaylist?.id)
        let track = tracks[index]
        do {
            let fileURL = try await service.playFile(for: track)
            let artworkURL = await service.artworkFile(for: track)
            postOnMain(.platformMusicDidResolvePlayback, userInfo: [
                "filePath": fileURL.path,
                "title": track.name,
                "artist": track.artist,
                "album": track.album ?? "",
                "duration": track.duration ?? 0,
                "artworkFilePath": artworkURL?.path ?? "",
                "artworkURL": track.artworkURL?.absoluteString ?? "",
                "platform": track.platform.rawValue,
                "trackID": track.id,
                "mediaID": track.mediaID ?? "",
                "hash": track.hash ?? "",
                "albumID": track.albumID ?? "",
                "albumAudioID": track.albumAudioID ?? "",
                "playlistID": selectedPlaylist?.id ?? "",
                "queueIndex": index
            ])
            publish(mode: "tracks", rows: tracks.map(trackRow), hasMore: hasMoreTracks, message: "正在播放：\(track.name) · \(track.artist)")
        } catch {
            publish(mode: "tracks", rows: tracks.map(trackRow), hasMore: hasMoreTracks, message: error.localizedDescription)
        }
    }

    @MainActor private func fetchNextQueuePage(playlist: ProviderPlaylist) async {
        do {
            let page = try await service.tracks(in: playlist, limit: 20, offset: queueTracks.count)
            guard queuePlaylist?.id == playlist.id else { queuePageLoading = false; return }
            queueTracks.append(contentsOf: page)
            queueHasMore = page.count == 20
            service.setPlaybackQueue(queueTracks, selectedIndex: queueSelectedIndex, hasMore: queueHasMore, playlistID: playlist.id)
            if selectedPlaylist?.id == playlist.id {
                tracks = queueTracks
                trackOffset = tracks.count
                hasMoreTracks = queueHasMore
                publish(mode: "tracks", rows: tracks.map(trackRow), hasMore: hasMoreTracks,
                        message: "《\(playlist.name)》· 已显示 \(tracks.count) 首\(hasMoreTracks ? "，上滑加载更多。" : "")")
            }
            queuePageLoading = false
            if let target = pendingQueueIndex, queueTracks.indices.contains(target) {
                pendingQueueIndex = nil
                await playQueueTrack(at: target)
            } else if !queueHasMore, !queueTracks.isEmpty {
                pendingQueueIndex = nil
                await playQueueTrack(at: 0)
            }
        } catch {
            queuePageLoading = false
            queueHasMore = false
            pendingQueueIndex = nil
            service.setPlaybackQueue(queueTracks, selectedIndex: queueSelectedIndex, hasMore: false, playlistID: playlist.id)
            if selectedPlaylist?.id == playlist.id {
                publish(mode: "tracks", rows: tracks.map(trackRow), hasMore: false, message: error.localizedDescription)
            }
        }
    }

    @MainActor private func playQueueTrack(at index: Int) async {
        guard queueTracks.indices.contains(index) else { return }
        queueSelectedIndex = index
        let track = queueTracks[index]
        do {
            let fileURL = try await service.playFile(for: track)
            let artworkURL = await service.artworkFile(for: track)
            postOnMain(.platformMusicDidResolvePlayback, userInfo: [
                "filePath": fileURL.path, "title": track.name, "artist": track.artist, "album": track.album ?? "",
                "duration": track.duration ?? 0, "artworkFilePath": artworkURL?.path ?? "",
                "artworkURL": track.artworkURL?.absoluteString ?? "", "platform": track.platform.rawValue,
                "trackID": track.id, "mediaID": track.mediaID ?? "", "hash": track.hash ?? "",
                "albumID": track.albumID ?? "", "albumAudioID": track.albumAudioID ?? "",
                "playlistID": queuePlaylist?.id ?? "", "queueIndex": index
            ])
        } catch {
            postOnMain(.platformMusicQueueDidChange, userInfo: ["active": true, "error": error.localizedDescription])
        }
    }

    private func playlistRow(_ playlist: ProviderPlaylist) -> [String: Any] {
        ["rowType": "playlist", "title": playlist.name,
         "subtitle": playlist.trackCount.map { "\($0) 首" } ?? "\(playlist.platform.displayName) 歌单",
         "platform": playlist.platform.rawValue, "playlistID": playlist.id,
         "trackCount": playlist.trackCount ?? 0, "artworkURL": playlist.coverURL?.absoluteString ?? ""]
    }

    private func trackRow(_ track: ProviderTrack) -> [String: Any] {
        ["rowType": "track", "title": track.name, "subtitle": [track.artist, track.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
         "platform": track.platform.rawValue, "trackID": track.id, "mediaID": track.mediaID ?? "",
         "hash": track.hash ?? "", "albumID": track.albumID ?? "", "albumAudioID": track.albumAudioID ?? "",
         "artist": track.artist, "album": track.album ?? "", "duration": track.duration ?? 0,
         "artworkURL": track.artworkURL?.absoluteString ?? ""]
    }

    private func publish(mode: String, rows: [[String: Any]], hasMore: Bool, message: String) {
        postOnMain(.platformMusicLibraryDidUpdate, userInfo: [
            "mode": mode, "rows": rows, "hasMore": hasMore, "message": message,
            "platform": selectedPlatform?.rawValue ?? "",
            "playlistID": selectedPlaylist?.id ?? ""
        ])
    }

    private func postOnMain(_ name: Notification.Name, userInfo: [String: Any]) {
        let post = {
            NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
        }
        if Thread.isMainThread { post() }
        else { DispatchQueue.main.async(execute: post) }
    }
}

private extension MusicPlatform {
    var displayName: String {
        switch self { case .netease: return "网易云音乐"; case .qqMusic: return "QQ 音乐"; case .kugou: return "酷狗音乐"; case .bilibili: return "哔哩哔哩" }
    }
}
