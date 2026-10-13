import Foundation
import CommonCrypto

/// Native Kugou client migrated from the bundled Bridge/kugou-api.js implementation.
/// The upstream Bridge is GPL-3.0; this file preserves its request/signing behavior.
final class KugouProviderClient {
    private let session: URLSession
    private let credentials: PlatformCredentialStore

    private let searchURL = URL(string: "https://songsearch.kugou.com/song_search_v2")!
    private let gatewayURL = URL(string: "https://gateway.kugou.com/v5/url")!
    private let mobileURL = URL(string: "https://m.kugou.com/app/i/getSongInfo.php")!
    private let webURL = URL(string: "https://wwwapi.kugou.com/play/songinfo")!
    private let webRetryURL = URL(string: "https://wwwapiretry.kugou.com/play/songinfo")!
    private let searchAppID = "1014"
    private let gatewayAppID = "1005"
    private let clientVersion = "20489"
    private let h5Salt = "NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt"
    private let signSalt = "57ae12eb6890223e355ccfcb74edf70d"
    private let androidSalt = "OIlwieks28dk2k092lksi2UIkp"

    init(session: URLSession = .shared, credentials: PlatformCredentialStore = PlatformCredentialStore()) {
        self.session = session
        self.credentials = credentials
    }

    func search(keywords: String, limit: Int = 12, offset: Int = 0) async throws -> [PlatformTrack] {
        let cookie = try credentials.load(for: .kugou) ?? ""
        let auth = Auth(cookie: cookie)
        let pageSize = min(max(limit, 1), 20)
        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "keyword", value: keywords), .init(name: "page", value: String(offset / pageSize + 1)),
            .init(name: "pagesize", value: String(pageSize)), .init(name: "userid", value: auth.userID ?? "-1"),
            .init(name: "clientver", value: "2000"), .init(name: "platform", value: "WebFilter"),
            .init(name: "tag", value: "em"), .init(name: "filter", value: "2"), .init(name: "iscorrection", value: "1"),
            .init(name: "privilege_filter", value: "0"), .init(name: "filter_ver", value: "2"),
            .init(name: "appid", value: searchAppID), .init(name: "token", value: auth.token), .init(name: "mid", value: auth.mid)
        ]
        let json = try await requestJSON(components.url!, cookie: cookie)
        guard let data = json["data"] as? [String: Any], let list = data["lists"] as? [[String: Any]] else { return [] }
        return list.compactMap(Self.track(from:))
    }

    func userPlaylists(limit: Int = 0) async throws -> [PlatformPlaylist] {
        let cookie = try credentials.load(for: .kugou) ?? ""
        let auth = Auth(cookie: cookie)
        guard let userID = auth.userID, let token = auth.token else {
            throw PlatformBridgeError.server("请先登录酷狗音乐")
        }
        let body: [String: Any] = ["userid": Int(userID) ?? 0, "token": token, "total_ver": 979,
                                   "type": 2, "page": 1, "pagesize": min(max(limit, 50), 100)]
        let json = try await h5Request("/v7/get_all_list", cookie: cookie, auth: auth,
                                       router: "cloudlist.service.kugou.com", body: body, extra: ["plat": "1"])
        let data = json["data"] as? [String: Any] ?? [:]
        let info = data["info"] as? [String: Any] ?? data
        let rows = [data["info"], data["list"], info["collect"], info["love"], info["self"], info["list"]]
            .compactMap { $0 as? [[String: Any]] }.flatMap { $0 }
        var seen = Set<String>()
        return rows.compactMap { row in
            let id = Self.string(row["global_collection_id"] ?? row["specialid"] ?? row["listid"] ?? row["list_id"] ?? row["id"])
            guard let id, !id.isEmpty, seen.insert(id).inserted else { return nil }
            let name = Self.string(row["name"] ?? row["listname"] ?? row["specialname"] ?? row["title"]) ?? "酷狗歌单"
            let cover = Self.string(row["pic"] ?? row["img"] ?? row["imgurl"] ?? row["sizable_cover"] ?? row["create_user_pic"])
            return PlatformPlaylist(id: id, name: name.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression),
                                    coverURL: cover.flatMap(URL.init(string:)),
                                    trackCount: Self.integer(row["count"] ?? row["m_count"] ?? row["song_count"] ?? row["total"]))
        }
    }

    func playlistTracks(_ playlist: PlatformPlaylist, limit: Int = 50, offset: Int = 0) async throws -> [PlatformTrack] {
        let cookie = try credentials.load(for: .kugou) ?? ""
        let auth = Auth(cookie: cookie)
        guard let userID = auth.userID, let token = auth.token else {
            throw PlatformBridgeError.server("请先登录酷狗音乐")
        }
        let digits = playlist.id.range(of: #"\d+"#, options: .regularExpression).map { String(playlist.id[$0]) } ?? playlist.id
        let pageSize = max(1, min(50, limit))
        let page = offset / pageSize + 1
        let body: [String: Any] = ["listid": Int(digits) ?? digits, "userid": Int(userID) ?? 0, "area_code": 1,
                                   "show_relate_goods": 0, "pagesize": pageSize, "allplatform": 1,
                                   "show_cover": 1, "type": 0, "token": token, "page": page]
        let json = try await h5Request("/v4/get_list_all_file", cookie: cookie, auth: auth,
                                       router: "cloudlist.service.kugou.com", body: body, extra: ["plat": "1"])
        let data = json["data"] as? [String: Any] ?? [:]
        let info = data["info"] ?? data["songs"] ?? data["lists"] ?? data["file"]
        let rows = (info as? [[String: Any]]) ?? ((info as? [String: Any])?["file"] as? [[String: Any]]) ?? []
        return rows.compactMap(Self.playlistTrack(from:))
    }

    func playback(for track: PlatformTrack, quality: String = "standard") async throws -> PlatformPlayback {
        let cookie = try credentials.load(for: .kugou) ?? ""
        let auth = Auth(cookie: cookie)
        guard let hash = track.hash, !hash.isEmpty else { return PlatformPlayback(provider: .kugou, url: nil, playable: false, trial: nil, quality: nil, message: "缺少酷狗歌曲 hash", restriction: nil) }
        guard let userID = auth.userID, let token = auth.token else { return PlatformPlayback(provider: .kugou, url: nil, playable: false, trial: nil, quality: nil, message: "酷狗播放需要登录", restriction: PlaybackRestriction(category: "login_required", action: nil, message: "请重新登录酷狗")) }
        // The web/mobile endpoints are more reliable for current tracks; gateway remains the final fallback.
        for endpoint in [webURL, mobileURL, webRetryURL] {
            var p: [String: String] = ["hash": hash, "album_id": track.albumID ?? "0", "album_audio_id": track.albumAudioID ?? "0", "srcappid": "2919", "clientver": "20000", "uuid": auth.mid, "mid": auth.mid, "userid": userID, "token": token]
            if endpoint == mobileURL { p = ["cmd":"playInfo", "hash":hash, "key":Self.md5(hash + "kgcloud"), "album_id":track.albumID ?? "0", "pid":"1", "forceDown":"0", "userid":userID, "token":token] }
            p["signature"] = Self.md5(h5Salt + p.keys.sorted().map { "\($0)=\(p[$0]!)" }.joined() + h5Salt)
            var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!; c.queryItems = p.map { URLQueryItem(name: $0.key, value: $0.value) }
            var r = URLRequest(url: c.url!); r.setValue(endpoint == mobileURL ? "https://m.kugou.com/" : "https://www.kugou.com/", forHTTPHeaderField: "Referer"); r.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent"); if !cookie.isEmpty { r.setValue(cookie, forHTTPHeaderField: "Cookie") }
            if let (data, response) = try? await session.data(for: r), (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let url = Self.extractURL(json) { return PlatformPlayback(provider: .kugou, url: URL(string: url), playable: true, trial: Self.isTrial(json), quality: quality, message: nil, restriction: nil) }
        }
        let q = quality.lowercased() == "lossless" ? "flac" : (quality.lowercased() == "exhigh" ? "320" : "128")
        let mid = auth.mid
        let now = String(Int(Date().timeIntervalSince1970 * 1000))
        var params: [String: String] = [
            "srcappid": "2919", "clientver": "20000", "clienttime": now, "mid": mid,
            "uuid": now, "dfid": auth.dfid, "appid": searchAppID, "token": token,
            "userid": userID, "album_id": track.albumID ?? "0", "area_code": "1",
            "hash": hash.lowercased(), "ssa_flag": "is_fromtrack", "version": "11430",
            "quality": q, "album_audio_id": track.albumAudioID ?? "0", "behavior": "play",
            "pid": "2", "cmd": "26", "pidversion": "3001", "IsFreePart": "1",
            "cdnBackup": "1", "module": ""
        ]
        params["key"] = md5(hash.lowercased() + signSalt + searchAppID + mid + userID)
        params["signature"] = md5(h5Salt + params.keys.sorted().map { "\($0)=\(params[$0]!)" }.joined() + h5Salt)
        var components = URLComponents(url: gatewayURL, resolvingAgainstBaseURL: false)!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue("https://www.kugou.com/", forHTTPHeaderField: "Referer")
        request.setValue("Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi", forHTTPHeaderField: "User-Agent")
        request.setValue("trackercdn.kugou.com", forHTTPHeaderField: "x-router")
        if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw KugouProviderError.invalidResponse }
        let urlString = ((json["data"] as? [String: Any])?["url"] as? String) ?? (json["url"] as? String)
        return PlatformPlayback(provider: .kugou, url: urlString.flatMap(URL.init(string:)), playable: urlString != nil, trial: nil, quality: quality, message: nil, restriction: nil)
    }

    func loginStatus() throws -> PlatformLoginStatus {
        let auth = Auth(cookie: try credentials.load(for: .kugou) ?? "")
        return PlatformLoginStatus(provider: .kugou, loggedIn: auth.userID != nil, nickname: nil, userID: auth.userID, isVIP: nil, isSVIP: nil, message: nil)
    }

    func saveCookie(_ cookie: String) throws -> PlatformLoginStatus {
        let normalized = cookie.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.contains("=") }.joined(separator: "; ")
        let auth = Auth(cookie: normalized)
        guard auth.userID != nil || normalized.range(of: #"(?:^|;\s*)(kg_mid|KugooID|userid)=[^;\s]+"#, options: .regularExpression) != nil else { throw KugouProviderError.invalidCookie }
        try credentials.save(normalized, for: .kugou)
        return try loginStatus()
    }

    func deleteCookie() throws { try credentials.delete(for: .kugou) }

    private func requestJSON(_ url: URL, cookie: String) async throws -> [String: Any] {
        var request = URLRequest(url: url); request.setValue("https://www.kugou.com/", forHTTPHeaderField: "Referer"); request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent"); if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw KugouProviderError.invalidResponse }
        return object
    }

    private func h5Request(_ path: String, cookie: String, auth: Auth, router: String,
                          body: [String: Any], extra: [String: String]) async throws -> [String: Any] {
        var parameters: [String: String] = ["srcappid": "2919", "clientver": "20000",
            "clienttime": String(Int(Date().timeIntervalSince1970 * 1000)), "mid": auth.mid,
            "uuid": String(Int(Date().timeIntervalSince1970 * 1000)), "dfid": auth.dfid,
            "appid": "1014", "token": auth.token ?? "", "userid": auth.userID ?? "0"]
        parameters.merge(extra) { _, new in new }
        let orderedBodyKeys = path.contains("get_all_list")
            ? ["userid", "token", "total_ver", "type", "page", "pagesize"]
            : ["listid", "userid", "area_code", "show_relate_goods", "pagesize", "allplatform", "show_cover", "type", "token", "page"]
        let bodyFields = try orderedBodyKeys.compactMap { key -> String? in
            guard let value = body[key] else { return nil }
            let encoded = try JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed])
            let valueText = String(data: encoded, encoding: .utf8)!.dropFirst().dropLast()
            let keyEncoded = try JSONSerialization.data(withJSONObject: [key], options: [.fragmentsAllowed])
            let keyText = String(data: keyEncoded, encoding: .utf8)!.dropFirst().dropLast()
            return "\(keyText):\(valueText)"
        }
        let bodyString = "{" + bodyFields.joined(separator: ",") + "}"
        let bodyData = Data(bodyString.utf8)
        let signatureInput = parameters.keys.sorted().map { "\($0)=\(parameters[$0]!)" }.joined() + bodyString
        parameters["signature"] = Self.md5(h5Salt + signatureInput + h5Salt)
        var components = URLComponents(string: "https://gateway.kugou.com\(path)")!
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.kugou.com/", forHTTPHeaderField: "Referer")
        request.setValue("Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi", forHTTPHeaderField: "User-Agent")
        request.setValue(router, forHTTPHeaderField: "x-router")
        if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? Int ?? 1) == 1 else { throw KugouProviderError.invalidResponse }
        return json
    }

    private static func track(from item: [String: Any]) -> PlatformTrack? {
        let hash = item["FileHash"] as? String ?? ""; let name = (item["SongName"] as? String ?? item["FileName"] as? String ?? "").replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression); guard !name.isEmpty, !hash.isEmpty else { return nil }
        let artist = item["SingerName"] as? String ?? ""; let cover = item["Image"] as? String
        let albumID = item["AlbumID"].map { String(describing: $0) }
        let mixSongID = item["MixSongID"].map { String(describing: $0) } ?? item["mixsongid"].map { String(describing: $0) } ?? ""
        let albumAudioID = (mixSongID.range(of: #"^\d+$"#, options: .regularExpression) != nil ? mixSongID : nil)
            ?? item["EMixSongID"].map { String(describing: $0) }
            ?? item["AlbumAudioID"].map { String(describing: $0) }
        return PlatformTrack(id: hash, provider: .kugou, name: name, artist: artist, album: item["AlbumName"] as? String, durationMilliseconds: (item["Duration"] as? Int).map { $0 * 1000 }, coverURL: cover.flatMap(URL.init(string:)), mediaID: nil, hash: hash, albumID: albumID, albumAudioID: albumAudioID)
    }

    private static func playlistTrack(from item: [String: Any]) -> PlatformTrack? {
        let singers = item["singerinfo"] as? [[String: Any]] ?? item["Singers"] as? [[String: Any]] ?? []
        let singer = singers.compactMap { $0["name"] as? String ?? $0["SingerName"] as? String }.joined(separator: " / ")
        let hash = string(item["hash"] ?? item["FileHash"])
        guard let hash, !hash.isEmpty else { return nil }
        var normalized = item
        normalized["FileHash"] = hash
        normalized["SongName"] = item["name"] ?? item["SongName"] ?? item["filename"]
        normalized["SingerName"] = singer.isEmpty ? (item["SingerName"] as? String ?? "") : singer
        normalized["AlbumID"] = item["album_id"] ?? item["AlbumID"] ?? (item["albuminfo"] as? [String: Any])?["id"]
        normalized["AlbumAudioID"] = item["album_audio_id"] ?? item["mixsongid"] ?? item["MixSongID"]
        normalized["AlbumName"] = item["album_name"] ?? item["AlbumName"] ?? (item["albuminfo"] as? [String: Any])?["name"]
        normalized["Image"] = item["cover"] ?? item["img"] ?? item["Image"] ?? (item["trans_param"] as? [String: Any])?["union_cover"]
        normalized["Duration"] = item["duration"] ?? item["Duration"] ?? ((item["timelen"] as? Int).map { $0 / 1000 })
        return track(from: normalized)
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func extractURL(_ json: [String: Any]) -> String? { let d = json["data"] as? [String: Any]; return (json["url"] as? String) ?? (json["play_url"] as? String) ?? (d?["url"] as? String) ?? (d?["play_url"] as? String) }
    private static func isTrial(_ json: [String: Any]) -> Bool { let d = json["data"] as? [String: Any] ?? [:]; return [json["is_free_part"], json["isFreePart"], d["is_free_part"], d["isFreePart"]].contains { ($0 as? NSNumber)?.boolValue == true } }
    private static func md5(_ string: String) -> String { var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH)); let bytes = Array(string.utf8); CC_MD5(bytes, CC_LONG(bytes.count), &digest); return digest.map { String(format: "%02x", $0) }.joined() }
    private func md5(_ value: String) -> String { Self.md5(value) }
    private struct Auth { let userID: String?; let token: String?; let mid: String; let dfid: String; init(cookie: String) { var d = [String: String](); cookie.split(separator: ";").forEach { let p = $0.split(separator: "=", maxSplits: 1).map(String.init); if p.count == 2 { d[p[0].trimmingCharacters(in: .whitespaces)] = p[1].trimmingCharacters(in: .whitespaces) } }; userID = d["userid"] ?? d["UserId"] ?? d["KugooID"] ?? d["kugouID"]; token = d["token"] ?? d["Token"] ?? d["t"] ?? d["T"]; mid = d["kg_mid"] ?? d["KG_MID"] ?? d["KUGOU_API_MID"] ?? d["mid"] ?? KugouProviderClient.md5("mineradio-kugou:" + (userID ?? token ?? "guest")); dfid = d["kg_dfid"] ?? d["KG_DFID"] ?? d["dfid"] ?? d["DFID"] ?? "-" } }
}

enum KugouProviderError: Error { case invalidCookie, invalidResponse }
