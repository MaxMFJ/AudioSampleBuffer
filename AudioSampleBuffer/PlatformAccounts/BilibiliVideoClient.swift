import CryptoKit
import AVFoundation
import Foundation

/// Experimental client for discovering public Bilibili videos and resolving a
/// progressive video URL for the iOS demo player. The endpoints are unofficial.
public final class BilibiliVideoClient: @unchecked Sendable {
    public struct Video: Sendable, Equatable {
        public let id: String
        public let title: String
        public let author: String
        public let duration: String
        public let coverURL: URL?
    }

    private let session: URLSession
    private let userAgent = BiliPlaybackSupport.userAgent

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            self.session = URLSession(configuration: configuration)
        }
    }

    public func verify(cookies: [HTTPCookie]) async -> Bool {
        let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        guard !header.isEmpty,
              let json = try? await get("https://api.bilibili.com/x/web-interface/nav", query: [:], cookieHeader: header),
              let data = json["data"] as? [String: Any],
              (data["isLogin"] as? NSNumber)?.boolValue == true else { return false }
        return true
    }

    public func search(song: String, artist: String, cookieHeader: String) async throws -> [Video] {
        // A long list of featured artists dilutes the title query. Preserve K/DA
        // as one name rather than treating its slash as an artist separator.
        let primaryArtist = artist.components(separatedBy: CharacterSet(charactersIn: ",，、&"))
            .first?.components(separatedBy: " / ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? artist
        let keys = try await wbiKeys(cookieHeader: cookieHeader)
        for suffix in ["官方 MV", "MV"] {
            let keyword = [primaryArtist, song, suffix].filter { !$0.isEmpty }.joined(separator: " ")
            NSLog("[BiliMV] 开始搜索：%@", keyword)
            let params = ["search_type": "video", "keyword": keyword, "page": "1", "order": "totalrank", "wts": String(Int(Date().timeIntervalSince1970))]
            let signed = sign(params, mixinKey: keys)
            let json = try await get("https://api.bilibili.com/x/web-interface/wbi/search/type", query: signed, cookieHeader: cookieHeader)
            let data = json["data"] as? [String: Any]
            let rows = data?["result"] as? [[String: Any]] ?? []
            let videos = rows.compactMap { row -> Video? in
                guard let id = row["bvid"] as? String, !id.isEmpty else { return nil }
                return Video(id: id,
                             title: Self.cleanHTML(row["title"] as? String ?? "Bilibili 视频"),
                             author: row["author"] as? String ?? "",
                             duration: row["duration"] as? String ?? "",
                             coverURL: (row[" pic"] as? String ?? row["pic"] as? String).flatMap(URL.init))
            }
            let ranked = BilibiliMVResolverBridge.rankedMatches(videos, song: song, artist: artist)
            NSLog("[BiliMV] 搜索完成：原始候选=%ld，标题匹配=%ld", videos.count, ranked.count)
            if !ranked.isEmpty { return Array(ranked.prefix(8)) }
        }
        throw PlatformMusicError.unavailable("B 站没有返回标题匹配的视频。")
    }

    public func playbackURL(for video: Video, cookieHeader: String) async throws -> URL {
        try await playbackInfo(for: video, cookieHeader: cookieHeader).url
    }

    public struct PlaybackInfo {
        public let url: URL
        public let urls: [URL]
        public let cid: String
        public let duration: Double
    }

    public func playbackInfo(for video: Video, cookieHeader: String) async throws -> PlaybackInfo {
        let detail = try await get("https://api.bilibili.com/x/web-interface/view", query: ["bvid": video.id], cookieHeader: cookieHeader)
        guard let data = detail["data"] as? [String: Any],
              let cid = data["cid"].map({ String(describing: $0) }) else {
            throw PlatformMusicError.unavailable("B 站未返回视频分 P 信息。")
        }
        // Request MP4 (fnval=0) for AVPlayer compatibility. DASH is split into
        // separate audio/video tracks and cannot be loaded as one AVPlayer URL.
        let play = try await get("https://api.bilibili.com/x/player/playurl", query: [
            "bvid": video.id, "cid": cid, "qn": "32", "fnval": "0", "fourk": "0", "otype": "json", "platform": "html5"
        ], cookieHeader: cookieHeader)
        guard let body = play["data"] as? [String: Any] else {
            let code = (play["code"] as? NSNumber)?.intValue ?? -1
            throw PlatformMusicError.unavailable("B 站没有返回 AVPlayer 可用的 MP4 地址（接口码 \(code)）。视频可能需要登录、较高清晰度权限，或当前地区不可播放。")
        }
        guard let durls = body["durl"] as? [[String: Any]], !durls.isEmpty else {
            let code = (play["code"] as? NSNumber)?.intValue ?? -1
            throw PlatformMusicError.unavailable("B 站没有返回 AVPlayer 可用的 MP4 地址（接口码 \(code)）。视频可能需要登录、较高清晰度权限，或当前地区不可播放。")
        }
        guard durls.count == 1 else {
            throw PlatformMusicError.unavailable("B 站返回了分段视频，当前播放器不支持。")
        }
        var candidates: [URL] = []
        var seen = Set<URL>()
        for item in durls {
            let rawURLs = ([item["url"] as? String].compactMap { $0 }) + (item["backup_url"] as? [String] ?? [])
            for rawURL in rawURLs {
                guard let url = URL(string: rawURL), url.scheme == "https", seen.insert(url).inserted else { continue }
                candidates.append(url)
            }
        }
        let urls = try await probeCandidates(candidates)
        guard let url = urls.first else {
            throw PlatformMusicError.unavailable("B 站返回的播放地址均不是可用的 MP4。")
        }
        BiliPlaybackSupport.register(urls: urls)
        NSLog("[BiliMV] 已解析播放地址：BV=%@，host=%@；候选数=%ld", video.id, url.host ?? "未知", urls.count)
        let duration = (data["duration"] as? NSNumber)?.doubleValue ?? 0
        guard duration.isFinite, duration > 0 else { throw PlatformMusicError.unavailable("视频时长无效。") }
        return PlaybackInfo(url: url, urls: urls, cid: cid, duration: duration)
    }

    private func probeCandidates(_ candidates: [URL]) async throws -> [URL] {
        var passed: [URL] = []
        for url in candidates {
            if Task.isCancelled { throw CancellationError() }
            do {
                let result = try await probe(url)
                NSLog("[BiliMV] 格式探测：host=%@，status=%ld，mime=%@，format=%@", url.host ?? "unknown", result.status, result.mime, result.format)
                if result.format == "mp4" { passed.append(url) }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let nsError = error as NSError
                let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
                NSLog("[BiliMV] 格式探测失败：host=%@，domain=%@，code=%ld，underlyingDomain=%@，underlyingCode=%ld", url.host ?? "unknown", BiliPlaybackSupport.safeText(nsError.domain), nsError.code, BiliPlaybackSupport.safeText(underlying?.domain ?? "none"), underlying?.code ?? 0)
            }
        }
        return passed
    }

    private struct ProbeResult { let status: Int; let mime: String; let format: String }

    private func probe(_ url: URL) async throws -> ProbeResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForResource = 12
        let probeSession = URLSession(configuration: configuration)
        defer { probeSession.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.httpShouldHandleCookies = false
        request.setValue(nil, forHTTPHeaderField: "Cookie")
        request.setValue("bytes=0-4095", forHTTPHeaderField: "Range")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        let (bytes, response) = try await probeSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let mime = BiliPlaybackSupport.safeText(http.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";", maxSplits: 1).first.map(String.init) ?? "unknown")
        guard http.statusCode == 200 || http.statusCode == 206 else {
            NSLog("[BiliMV] 格式探测响应：host=%@，status=%ld，mime=%@", url.host ?? "unknown", http.statusCode, mime)
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 206 {
            guard let contentRange = http.value(forHTTPHeaderField: "Content-Range"), contentRange.hasPrefix("bytes 0-") else {
                throw URLError(.cannotParseResponse)
            }
        }
        var sample = Data()
        sample.reserveCapacity(4096)
        for try await byte in bytes {
            sample.append(byte)
            if sample.count >= 4096 { break }
        }
        let format: String
        if sample.count >= 16 && sample[4..<8].elementsEqual(Data("ftyp".utf8)) {
            let boxSize = sample.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            if boxSize >= 16, boxSize <= sample.count, boxSize % 4 == 0 {
                let offsets = [8] + Array(stride(from: 16, to: boxSize, by: 4))
                let brands = offsets.compactMap { String(data: sample.subdata(in: $0..<($0 + 4)), encoding: .ascii) }
                // A video-only DASH/CMAF segment is not a progressive MP4 resource.
                format = brands.contains(where: { ["dash", "msdh", "msix", "cmfc", "cmfv"].contains($0) }) ? "dash/cmaf" : "mp4"
            } else {
                format = "invalid-ftyp"
            }
        } else if sample.starts(with: Data("FLV".utf8)) {
            format = "flv"
        } else if sample.prefix(64).contains(0x3C) {
            format = "html"
        } else {
            format = "unknown"
        }
        return ProbeResult(status: http.statusCode, mime: mime, format: format)
    }

    public func playerAsset(for url: URL) -> AVAsset {
        let headers = ["Referer": "https://www.bilibili.com/", "User-Agent": userAgent]
        return AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    }

    private func wbiKeys(cookieHeader: String) async throws -> String {
        let json = try await get("https://api.bilibili.com/x/web-interface/nav", query: [:], cookieHeader: cookieHeader)
        guard let data = json["data"] as? [String: Any],
              let image = data["wbi_img"] as? [String: Any],
              let imgURL = image["img_url"] as? String,
              let subURL = image["sub_url"] as? String else {
            throw PlatformMusicError.unavailable("无法读取 B 站搜索签名参数。")
        }
        let source = Self.key(from: imgURL) + Self.key(from: subURL)
        let permutation = [46, 47, 18,  2, 53,  8, 23, 32, 15, 50, 10, 31, 58,  3, 45, 35, 27, 43,  5, 49, 33,  9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48,  7, 16, 24, 55, 40, 61, 26, 17,  0,  1, 60, 51, 30,  4, 22, 25, 54, 21, 56, 59,  6, 63, 57, 62, 11, 36, 20, 34, 44, 52]
        let characters = Array(source)
        return String(permutation.compactMap { $0 < characters.count ? characters[$0] : nil }.prefix(32))
    }

    private func sign(_ params: [String: String], mixinKey: String) -> [String: String] {
        let forbidden = CharacterSet(charactersIn: "!'()*")
        var values = params.mapValues { value in String(value.unicodeScalars.filter { !forbidden.contains($0) }) }
        let query = values.keys.sorted().map { "\($0)=\(values[$0]!.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? values[$0]!)" }.joined(separator: "&")
        let digest = Insecure.MD5.hash(data: Data((query + mixinKey).utf8)).map { String(format: "%02x", $0) }.joined()
        values["w_rid"] = digest
        return values
    }

    private func get(_ rawURL: String, query: [String: String], cookieHeader: String? = nil) async throws -> [String: Any] {
        var components = URLComponents(string: rawURL)!
        if !query.isEmpty { components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) } }
        guard let url = components.url else { throw PlatformMusicError.unavailable("B 站请求地址无效。") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = false
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        if let cookieHeader, !cookieHeader.isEmpty { request.setValue(cookieHeader, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlatformMusicError.unavailable("B 站接口请求失败。")
        }
        if let code = (json["code"] as? NSNumber)?.intValue, code != 0 {
            let message = json["message"] as? String ?? "未知错误"
            NSLog("[BiliMV] 接口拒绝：path=%@，code=%ld，message=%@", components.path, code, message)
            throw PlatformMusicError.unavailable("B 站接口返回 \(code)：\(message)")
        }
        return json
    }

    private static func key(from url: String) -> String {
        String(URL(string: url)?.deletingPathExtension().lastPathComponent ?? "")
    }

    private static func cleanHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}

/// Objective-C bridge used by the main audio player to resolve one likely
/// Bilibili MV for the source-grounded video timeline.
@objc(BilibiliMVResolverBridge)
public final class BilibiliMVResolverBridge: NSObject {
    @objc(sharedResolver)
    public static let shared = BilibiliMVResolverBridge()

    @objc(resolveVideoForSong:artist:completion:)
    public func resolveVideo(song: String, artist: String,
                             completion: @escaping (URL?, String?, String?) -> Void) {
        Task {
            do {
                let track = ProviderTrack(id: "bilibili-auto-\(song)", platform: .netease,
                                          name: song, artist: artist)
                let videos = try await PlatformMusicService.shared.searchBilibiliVideos(for: track)
                guard let video = Self.bestMatch(videos, song: song, artist: artist) else {
                    throw PlatformMusicError.unavailable("没有找到可用于自动播放的 B 站视频。")
                }
                let url = try await PlatformMusicService.shared.bilibiliPlaybackURL(for: video)
                NSLog("[BiliMV] 自动候选已准备：BV=%@，标题=%@", video.id, video.title)
                DispatchQueue.main.async { completion(url, video.title, nil) }
            } catch {
                let message = error.localizedDescription
                NSLog("[BiliMV] 自动候选解析失败：%@", message)
                DispatchQueue.main.async { completion(nil, nil, message) }
            }
        }
    }

    static func bestMatch(_ videos: [BilibiliVideoClient.Video], song: String, artist: String) -> BilibiliVideoClient.Video? {
        let ranked = rankedMatches(videos, song: song, artist: artist)
        guard let chosen = ranked.first else { return nil }
        NSLog("[BiliMV] 自动选择：BV=%@，标题=%@，发布者=%@；依据标题及发布者匹配，未验证官方身份", chosen.id, chosen.title, chosen.author)
        return chosen
    }

    @objc(searchVideosForSong:artist:completion:)
    public func searchVideos(song: String, artist: String, completion: @escaping ([[String: String]]?, String?) -> Void) {
        Task {
            do {
                let track = ProviderTrack(id: "bilibili-manual-\(song)", platform: .netease, name: song, artist: artist)
                let videos = try await PlatformMusicService.shared.searchBilibiliVideos(for: track)
                let rankedIDs = Set(Self.rankedMatches(videos, song: song, artist: artist).map(\.id))
                let ordered = Self.rankedMatches(videos, song: song, artist: artist) + videos.filter { !rankedIDs.contains($0.id) }
                let rows = ordered.prefix(12).map { ["id": $0.id, "title": $0.title, "author": $0.author, "duration": $0.duration] }
                DispatchQueue.main.async { completion(rows, nil) }
            } catch {
                let message = error.localizedDescription
                NSLog("[BiliMV] 视频列表读取失败：%@", message)
                DispatchQueue.main.async { completion(nil, message) }
            }
        }
    }

    static func rankedMatches(_ videos: [BilibiliVideoClient.Video], song: String, artist: String) -> [BilibiliVideoClient.Video] {
        func compact(_ value: String) -> String {
            value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
        }
        let songKey = compact(song)
        guard !songKey.isEmpty else { return [] }
        let normalizedArtist = artist.replacingOccurrences(of: "K/DA", with: "KDA", options: .caseInsensitive)
        let artistKeys = normalizedArtist.split(whereSeparator: { "/、,，&".contains($0) })
            .map { compact(String($0)) }.filter { $0.count >= 2 }
        func score(_ video: BilibiliVideoClient.Video) -> Int {
            let title = compact(video.title)
            let author = compact(video.author)
            var result = 0
            if artistKeys.contains(where: { title.contains($0) }) { result += 15 }
            if artistKeys.contains(where: { author.contains($0) }) { result += 20 }
            if title.contains("mv") || title.contains("musicvideo") { result += 15 }
            if ["官方", "official"].contains(where: title.contains) { result += 25 }
            if ["完整版", "fullversion"].contains(where: title.contains) { result += 5 }
            // Scene edits and alternate performances are poor full-song anchors.
            for marker in ["饭制", "混剪", "翻跳", "翻唱", "舞蹈练习", "练习室", "直拍", "现场", "剪辑", "片段", "竖屏", "dancepractice", "预告", "解说", "解析", "教程"] {
                if title.contains(marker) { result -= 60 }
            }
            if video.title.range(of: #"\b(reaction|cover|remix|fancam|live|teaser)\b"#,
                                 options: [.regularExpression, .caseInsensitive]) != nil { result -= 60 }
            return result
        }
        return videos.enumerated().filter { compact($0.element.title).contains(songKey) }
            .sorted { left, right in
                let lhs = score(left.element), rhs = score(right.element)
                return lhs == rhs ? left.offset < right.offset : lhs > rhs
            }.map(\.element)
    }
}
