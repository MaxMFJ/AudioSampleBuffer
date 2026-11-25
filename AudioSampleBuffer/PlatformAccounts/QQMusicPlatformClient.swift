import Foundation

public struct QQMusicMV: Sendable, Equatable {
    public let id: String
    public let title: String
    public let artist: String
    public let duration: TimeInterval?
    public let artworkURL: URL?
}

public final class QQMusicPlatformClient: PlatformMusicProviderClient, @unchecked Sendable {
    public let platform: MusicPlatform = .qqMusic
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func verify(platform: AccountPlatform, cookies: [HTTPCookie]) async -> Bool {
        guard platform == .qqMusic else { return false }
        let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        do { _ = try await userPlaylists(cookieHeader: header); return true } catch { return false }
    }

    public func userPlaylists(cookieHeader: String) async throws -> [ProviderPlaylist] {
        let values = cookieValues(cookieHeader)
        guard let uin = values["uin"] ?? values["qqmusic_uin"], !uin.isEmpty else { throw PlatformMusicError.missingCredential }
        let url = try makeURL("https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss", ["hostUin":"0", "hostuin":uin, "sin":"0", "size":"200", "g_tk":"5381", "loginUin":uin, "format":"json", "inCharset":"utf8", "outCharset":"utf-8", "notice":"0", "platform":"yqq.json", "needNewCode":"0"])
        let json = try await get(url, cookieHeader: cookieHeader)
        guard let data = json["data"] as? [String: Any] else { throw PlatformMusicError.unavailable("QQ 音乐未返回有效歌单数据。") }
        return (data["disslist"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = string(row["dissid"] ?? row["tid"] ?? row["dirid"] ?? row["id"]), !id.isEmpty else { return nil }
            return ProviderPlaylist(id: id, platform: .qqMusic, name: string(row["diss_name"] ?? row["name"]) ?? "QQ 歌单", coverURL: string(row["diss_cover"] ?? row["logo"] ?? row["picurl"]).flatMap(URL.init), trackCount: integer(row["song_cnt"] ?? row["songnum"]))
        }
    }

    public func playlistTracks(_ playlist: ProviderPlaylist, cookieHeader: String, limit: Int, offset: Int) async throws -> [ProviderTrack] {
        let values = cookieValues(cookieHeader); guard let uin = values["uin"] ?? values["qqmusic_uin"], !uin.isEmpty else { throw PlatformMusicError.missingCredential }
        let url = try makeURL("https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg", ["type":"1", "utf8":"1", "disstid":playlist.id, "song_begin":String(max(0, offset)), "song_num":String(max(1, min(100, limit))), "loginUin":uin, "format":"json", "inCharset":"utf8", "outCharset":"utf-8", "notice":"0", "platform":"yqq.json", "needNewCode":"0"])
        let json = try await get(url, cookieHeader: cookieHeader)
        let detail = (json["cdlist"] as? [[String: Any]])?.first ?? [:]
        return (detail["songlist"] as? [[String: Any]] ?? []).compactMap(track)
    }

    public func searchTracks(keyword: String, cookieHeader: String, limit: Int) async throws -> [ProviderTrack] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let url = try makeURL("https://c.y.qq.com/soso/fcgi-bin/client_search_cp", [
            "p": "1", "n": String(max(1, min(limit, 30))), "w": trimmed, "format": "json",
            "inCharset": "utf8", "outCharset": "utf-8", "platform": "yqq.json", "needNewCode": "0"
        ])
        let json = try await get(url, cookieHeader: cookieHeader)
        let songs = ((json["data"] as? [String: Any])?["song"] as? [String: Any])?["list"] as? [[String: Any]] ?? []
        return songs.compactMap(track)
    }

    public func playbackURL(for track: ProviderTrack, cookieHeader: String) async throws -> URL {
        let values = cookieValues(cookieHeader)
        let uin = values["uin"] ?? values["qqmusic_uin"] ?? values["wxuin"] ?? values["p_uin"] ?? "0"
        let playbackKey = values["qm_keyst"] ?? values["qqmusic_key"] ?? values["music_key"] ?? values["wxskey"] ?? ""
        guard uin != "0", !playbackKey.isEmpty else {
            throw PlatformMusicError.unavailable("QQ 歌单账号态有效，但缺少播放授权票据（qm_keyst / qqmusic_key / music_key / wxskey）。请重新打开 QQ 登录页，等待 QQ 音乐播放器页完成授权同步后再播放。")
        }

        // Use QQ Music's account-gated VKey endpoint. A URL is accepted only
        // when QQ returns a non-empty purl for this logged-in account.
        let fileTypes = [("M500", ".mp3"), ("C400", ".m4a")]
        let mediaIDs = [track.mediaID, track.id].compactMap { $0 }.filter { !$0.isEmpty }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let filenames = mediaIDs.flatMap { mediaID in fileTypes.map { $0.0 + mediaID + $0.1 } }
        guard !filenames.isEmpty else { throw PlatformMusicError.unavailable("QQ 音乐曲目缺少媒体标识，无法请求授权音源。") }

        let payload: [String: Any] = [
            "comm": ["uin": uin, "format": "json", "ct": 19, "cv": 0, "authst": playbackKey],
            "req_0": [
                "module": "vkey.GetVkeyServer",
                "method": "CgiGetVkey",
                "param": [
                    "guid": String(Int.random(in: 1_000_000_000...9_999_999_999)),
                    "songmid": Array(repeating: track.id, count: filenames.count),
                    "songtype": Array(repeating: 0, count: filenames.count),
                    "uin": uin,
                    "loginflag": 1,
                    "platform": "20",
                    "filename": filenames
                ]
            ],
            "loginUin": uin
        ]
        // Use QQ's current module endpoint; the legacy musics.fcg path can
        // return HTTP 200 with req_0.code=2000 but no req_0.data.
        var request = URLRequest(url: URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("QQMusic 14090508(android 12)", forHTTPHeaderField: "User-Agent")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PlatformMusicError.unavailable("QQ 播放授权请求失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)）。请重新登录后重试。")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlatformMusicError.unavailable("QQ 播放授权接口返回了无法识别的数据。")
        }
        let req = root["req_0"] as? [String: Any]
        guard let result = req?["data"] as? [String: Any] else {
            let code = string(req?["code"] ?? root["code"] ?? root["ret"])
            let message = string(req?["msg"] ?? root["msg"] ?? root["message"])
            if code == "2000" {
                throw PlatformMusicError.unavailable("QQ 音乐播放接口返回业务码 2000，未生成授权数据。请求已切换到当前 musicu 接口；若仍出现，通常是 QQ 拒绝了该请求或接口参数已变化。请确认播放授权票据已同步，再换一首普通音质歌曲验证。")
            }
            if code == "104003" {
                throw PlatformMusicError.unavailable("QQ 音乐拒绝返回播放授权（104003）。这通常表示网页登录态存在，但播放票据未同步，或该曲目受会员、版权及地区限制。请重新登录并等待授权同步。")
            }
            throw PlatformMusicError.unavailable("QQ 播放授权结果缺少 req_0.data\(code.map { "（\($0)）" } ?? "")\(message.map { "：\($0)" } ?? "")。")
        }
        let infos = result["midurlinfo"] as? [[String: Any]] ?? []
        let hosts = (result["sip"] as? [String])?.filter { !$0.isEmpty } ?? []
        for info in infos {
            guard let purl = string(info["purl"]), !purl.isEmpty else { continue }
            if let directURL = URL(string: purl), let scheme = directURL.scheme, ["https", "http"].contains(scheme.lowercased()) {
                return directURL
            }
            for host in hosts {
                if let url = URL(string: host + purl) { return url }
            }
        }
        let code = string(req?["code"] ?? result["code"] ?? root["code"] ?? root["ret"])
        let message = string(result["msg"] ?? result["message"] ?? result["errmsg"] ?? req?["msg"])
        if code == "104003" {
            throw PlatformMusicError.unavailable("QQ 音乐拒绝返回播放授权（104003）。账号网页态可能有效，但 QQ 未提供这首歌的播放票据；请确认登录页已完成授权同步，或检查歌曲版权、会员和地区限制。")
        }
        throw PlatformMusicError.unavailable(message?.isEmpty == false
            ? "QQ 音乐未返回此曲的播放授权：\(message!)"
            : "QQ 音乐没有为此账号返回可播放音源，可能受会员、版权或地区限制。")
    }

    /// Searches QQ Music's MV catalog for a title and artist. The result is metadata only;
    /// playback URLs are resolved separately because QQ returns short-lived stream URLs.
    public func searchMVs(for track: ProviderTrack, cookieHeader: String) async throws -> [QQMusicMV] {
        let query = [track.name, track.artist].filter { !$0.isEmpty }.joined(separator: " ")
        guard !query.isEmpty else { throw PlatformMusicError.unavailable("歌曲缺少标题，无法搜索 QQ MV。") }
        NSLog("[QQMV] 开始搜索歌曲 MV：%@ - %@", track.artist, track.name)
        func search(_ searchText: String) async throws -> [QQMusicMV] {
            let url = try makeURL("https://c.y.qq.com/soso/fcgi-bin/client_search_cp", [
                "ct": "24", "p": "1", "n": "10", "w": searchText, "format": "json", "t": "12",
                "aggr": "0", "catZhida": "1", "lossless": "0", "sem": "1",
                "remoteplace": "txt.yqq.mv", "loginUin": "0", "hostUin": "0",
                "inCharset": "utf8", "outCharset": "utf-8", "platform": "yqq.json", "needNewCode": "0"
            ])
            let json = try await get(url, cookieHeader: cookieHeader)
            let data = json["data"] as? [String: Any]
            let mv = data?["mv"] as? [String: Any]
            let rows = mv?["list"] as? [[String: Any]] ?? []
            return rows.compactMap { row -> QQMusicMV? in
                guard let id = string(row["vid"] ?? row["v_id"]), !id.isEmpty else { return nil }
                let singers = (row["singer"] as? [[String: Any]] ?? row["singers"] as? [[String: Any]] ?? [])
                    .compactMap { string($0["name"]) }.joined(separator: " / ")
                return QQMusicMV(id: id,
                                 title: string(row["name"] ?? row["title"]) ?? "QQ MV",
                                 artist: singers.isEmpty ? (string(row["singername"]) ?? "") : singers,
                                 duration: integer(row["duration"]).map(TimeInterval.init),
                                 artworkURL: string(row["picurl"] ?? row["cover"]).flatMap(URL.init))
            }
        }
        var results = try await search(query)
        if results.isEmpty, query != track.name { results = try await search(track.name) }
        guard !results.isEmpty else {
            NSLog("[QQMV] 搜索无结果：歌曲=%@，组合关键词与标题关键词均未找到 MV", track.name)
            throw PlatformMusicError.unavailable("QQ 音乐没有为《\(track.name)》返回 MV 搜索结果。")
        }
        NSLog("[QQMV] 搜索完成：歌曲=%@，候选数=%ld", track.name, results.count)
        for (index, mv) in results.enumerated() {
            NSLog("[QQMV] 候选 %ld：%@，VID=%@，时长=%@ 秒", index + 1, mv.title, mv.id, mv.duration.map { String(format: "%.1f", $0) } ?? "未知")
        }
        return results
    }

    /// Resolves a selected MV VID to a temporary playable URL; never persist or log it.
    public func mvPlaybackURL(for mv: QQMusicMV, cookieHeader: String) async throws -> URL {
        let payload: [String: Any] = ["getMvUrl": [
            "module": "gosrf.Stream.MvUrlProxy", "method": "GetMvUrls",
            "param": ["vids": [mv.id], "request_typet": 10001]
        ]]
        var request = URLRequest(url: URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["getMvUrl"] as? [String: Any],
              let body = result["data"] as? [String: Any],
              let item = body[mv.id] as? [String: Any] else {
            throw PlatformMusicError.unavailable("QQ 音乐未返回《\(mv.title)》的 MV 播放地址。")
        }
        let formats = item["mp4"] as? [[String: Any]] ?? []
        for format in formats {
            let urls = format["freeflow_url"] as? [String] ?? []
            if let raw = urls.first(where: { !$0.isEmpty }),
               let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                NSLog("[QQMV] 视频流地址已解析：VID=%@，host=%@，格式=%@；已隐藏含鉴权参数的完整地址", mv.id, url.host ?? "未知", url.pathExtension.isEmpty ? "未知" : url.pathExtension)
                return url
            }
        }
        NSLog("[QQMV] 已找到 MV 但没有可播放视频流：标题=%@，VID=%@", mv.title, mv.id)
        throw PlatformMusicError.unavailable("QQ 音乐找到了《\(mv.title)》，但当前账号没有可播放的视频流。")
    }

    private func get(_ url: URL, cookieHeader: String) async throws -> [String: Any] { var r = URLRequest(url: url); r.setValue(cookieHeader, forHTTPHeaderField: "Cookie"); r.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer"); let (d, response) = try await session.data(for: r); guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true, let o = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw PlatformMusicError.unavailable("QQ 音乐服务暂时不可用。") }; return o }
    private func makeURL(_ raw: String, _ query: [String: String]) throws -> URL { var c = URLComponents(string: raw)!; c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }; guard let u = c.url else { throw PlatformMusicError.unavailable("QQ 音乐请求地址无效。") }; return u }
    private func cookieValues(_ header: String) -> [String: String] { Dictionary(header.split(separator: ";").compactMap { p -> (String, String)? in let x = p.split(separator: "=", maxSplits: 1); guard x.count == 2 else { return nil }; let name = String(x[0]).trimmingCharacters(in: .whitespaces).lowercased(); let rawValue = String(x[1]).trimmingCharacters(in: .whitespaces); return (name, rawValue.removingPercentEncoding ?? rawValue) }, uniquingKeysWith: { _, new in new }) }
    private func string(_ value: Any?) -> String? { if let s = value as? String, !s.isEmpty { return s }; if let n = value as? NSNumber { return n.stringValue }; return nil }
    private func integer(_ value: Any?) -> Int? { if let n = value as? NSNumber { return n.intValue }; if let s = value as? String { return Int(s) }; return nil }
    private func track(_ item: [String: Any]) -> ProviderTrack? { let song = item["track_info"] as? [String: Any] ?? item["songInfo"] as? [String: Any] ?? item; guard let id = string(song["mid"] ?? song["songmid"]) else { return nil }; let singers = (song["singer"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: " / "); let album = song["album"] as? [String: Any]; let albumMID = string(album?["mid"] ?? album?["pmid"] ?? song["albummid"]); let artworkURL = albumMID.flatMap { URL(string: "https://y.gtimg.cn/music/photo_new/T002R300x300M000\($0).jpg") }; let mediaID = string((song["file"] as? [String: Any])?["media_mid"] ?? song["strMediaMid"] ?? song["media_mid"]); return ProviderTrack(id: id, platform: .qqMusic, name: string(song["name"] ?? song["songname"]) ?? "", artist: singers.isEmpty ? (string(song["singername"]) ?? "") : singers, album: string(album?["name"]), artworkURL: artworkURL, duration: integer(song["interval"]).map(TimeInterval.init), mediaID: mediaID, hash: nil, albumID: nil, albumAudioID: nil) }
}
