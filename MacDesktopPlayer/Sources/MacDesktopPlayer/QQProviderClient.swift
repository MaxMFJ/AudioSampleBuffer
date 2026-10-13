import Foundation
import CryptoKit

// Native translation of the QQ request portions of the local Bridge server.
// The surrounding Bridge is GPL-3; this file is an independent implementation
// of its documented QQ Music HTTP behavior, with no Bridge or Node dependency.

internal actor QQProviderClient {
    static let shared = QQProviderClient()
    private let session = URLSession(configuration: .ephemeral)
    private let musicURL = URL(string: "https://u.y.qq.com/cgi-bin/musics.fcg")!

    private func request(_ url: URL, body: Any? = nil, cookie: String? = nil) async throws -> [String: Any] {
        var r = URLRequest(url: url); r.timeoutInterval = 12
        r.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        r.setValue("QQMusic 14090508(android 12)", forHTTPHeaderField: "User-Agent")
        if let cookie, !cookie.isEmpty { r.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if let body { r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await session.data(for: r)
        guard (response as? HTTPURLResponse)?.statusCode ?? 0 < 400,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PlatformBridgeError.invalidResponse }
        return object
    }

    internal func search(keywords: String, limit: Int = 20, offset: Int = 0) async throws -> [PlatformTrack] {
        let n = max(1, min(30, limit)); let payload: [String: Any] = ["comm": ["ct":"11","cv":"14090508","v":"14090508","tmeAppID":"qqmusic","phonetype":"EBG-AN10","os_ver":"12","OpenUDID":"0","QIMEI36":"0","udid":"0","chid":"0","aid":"0","oaid":"0","taid":"0","tid":"0","wid":"0","uid":"0","sid":"0","modeSwitch":"6","teenMode":"0","ui_mode":"2","nettype":"1020"], "req": ["module":"music.search.SearchCgiService","method":"DoSearchForQQMusicMobile","param":["search_type":0,"searchid":UUID().uuidString,"query":keywords,"page_num":offset / n + 1,"num_per_page":n,"sin":offset,"cat":2,"grp":1,"highlight":0,"nqc_flag":0,"multi_zhida":0,"sem":0]]]
        let body = try JSONSerialization.data(withJSONObject: payload)
        var components = URLComponents(url: musicURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "sign", value: Self.searchSign(body))]
        var signedRequest = URLRequest(url: components.url!)
        signedRequest.httpMethod = "POST"
        signedRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        signedRequest.setValue("QQMusic 14090508(android 12)", forHTTPHeaderField: "User-Agent")
        signedRequest.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        signedRequest.httpBody = body
        let (responseData, response) = try await session.data(for: signedRequest)
        guard (response as? HTTPURLResponse)?.statusCode ?? 0 < 400,
              let data = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else { throw PlatformBridgeError.invalidResponse }
        let req = data["req"] as? [String: Any]
        let reqData = req?["data"] as? [String: Any]
        let bodyObject = (reqData?["body"] as? [String: Any]) ?? reqData ?? [:]
        let items = bodyObject["item_song"] as? [[String: Any]] ?? (bodyObject["song"] as? [String: Any])?["list"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            let song = (item["track_info"] as? [String: Any]) ?? (item["songInfo"] as? [String: Any]) ?? item; guard let mid = song["mid"] as? String, !mid.isEmpty else { return nil }
            let singers = (song["singer"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: " / ")
            let album = song["album"] as? [String: Any]; let albumMid = album?["mid"] as? String
            let mediaMid = (song["file"] as? [String: Any])?["media_mid"] as? String
            return PlatformTrack(id: mid, provider: .qq, name: song["name"] as? String ?? "", artist: singers, album: album?["name"] as? String, durationMilliseconds: (song["interval"] as? Int).map { $0 * 1000 }, coverURL: albumMid.flatMap { URL(string: "https://y.qq.com/music/photo_new/T002R300x300M000\($0).jpg") }, mediaID: mediaMid, hash: nil, albumID: nil, albumAudioID: nil)
        }
    }

    internal func userPlaylists() async throws -> [PlatformPlaylist] {
        let cookie = try PlatformCredentialStore.shared.load(for: .qq) ?? ""
        let uin = cookieValue(cookie, "uin") ?? cookieValue(cookie, "qqmusic_uin") ?? ""
        guard !uin.isEmpty else { throw PlatformBridgeError.server("请先登录 QQ 音乐") }
        async let created = getJSON("https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss", query: [
            "hostUin": "0", "hostuin": uin, "sin": "0", "size": "200", "g_tk": "5381",
            "loginUin": uin, "format": "json", "inCharset": "utf8", "outCharset": "utf-8",
            "notice": "0", "platform": "yqq.json", "needNewCode": "0"
        ], cookie: cookie)
        async let collected = getJSON("https://c.y.qq.com/fav/fcgi-bin/fcg_get_profile_order_asset.fcg", query: [
            "ct": "20", "cid": "205360956", "userid": uin, "reqtype": "3", "sin": "0", "ein": "199"
        ], cookie: cookie)
        let (createdResult, collectedResult) = await (try? created, try? collected)
        let createdData = createdResult?["data"] as? [String: Any] ?? [:]
        let collectedData = collectedResult?["data"] as? [String: Any] ?? [:]
        let rows = (createdData["disslist"] as? [[String: Any]] ?? [])
            + (collectedData["cdlist"] as? [[String: Any]] ?? [])
        var seen = Set<String>()
        return rows.compactMap { row in
            let id = Self.string(row["dissid"] ?? row["tid"] ?? row["dirid"] ?? row["id"])
            guard let id, !id.isEmpty, seen.insert(id).inserted else { return nil }
            let name = row["diss_name"] as? String ?? row["name"] as? String ?? "QQ 歌单"
            let cover = row["diss_cover"] as? String ?? row["logo"] as? String ?? row["picurl"] as? String
            return PlatformPlaylist(id: id, name: name, coverURL: cover.flatMap(URL.init(string:)),
                                    trackCount: Self.integer(row["song_cnt"] ?? row["songnum"] ?? row["total_song_num"]))
        }
    }

    internal func playlistTracks(id: String, limit: Int, offset: Int) async throws -> [PlatformTrack] {
        let cookie = try PlatformCredentialStore.shared.load(for: .qq) ?? ""
        let uin = cookieValue(cookie, "uin") ?? cookieValue(cookie, "qqmusic_uin") ?? ""
        guard !uin.isEmpty else { throw PlatformBridgeError.server("请先登录 QQ 音乐") }
        let result = try await getJSON("https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg", query: [
            "type": "1", "utf8": "1", "disstid": id, "song_begin": String(max(0, offset)),
            "song_num": String(max(1, min(100, limit))), "loginUin": uin, "format": "json",
            "inCharset": "utf8", "outCharset": "utf-8", "notice": "0", "platform": "yqq.json", "needNewCode": "0"
        ], cookie: cookie)
        let detail = ((result["cdlist"] as? [[String: Any]])?.first) ?? [:]
        return (detail["songlist"] as? [[String: Any]] ?? []).compactMap { item in
            let song = (item["track_info"] as? [String: Any]) ?? (item["songInfo"] as? [String: Any]) ?? item
            guard let mid = Self.string(song["mid"] ?? song["songmid"]), !mid.isEmpty else { return nil }
            let singers = (song["singer"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: " / ")
            let album = song["album"] as? [String: Any] ?? [:]
            let albumMid = Self.string(album["mid"] ?? song["albummid"])
            let mediaMid = Self.string((song["file"] as? [String: Any])?["media_mid"] ?? song["strMediaMid"] ?? song["media_mid"])
            return PlatformTrack(id: mid, provider: .qq, name: song["name"] as? String ?? song["songname"] as? String ?? "",
                                 artist: singers.isEmpty ? (song["singername"] as? String ?? "") : singers,
                                 album: album["name"] as? String, durationMilliseconds: Self.integer(song["interval"]).map { $0 * 1000 },
                                 coverURL: albumMid.flatMap { URL(string: "https://y.qq.com/music/photo_new/T002R300x300M000\($0).jpg") },
                                 mediaID: mediaMid, hash: nil, albumID: nil, albumAudioID: nil)
        }
    }

    private func getJSON(_ rawURL: String, query: [String: String], cookie: String) async throws -> [String: Any] {
        var components = URLComponents(string: rawURL)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return try await request(components.url!, cookie: cookie)
    }

    internal func playback(for track: PlatformTrack, quality: String = "") async throws -> PlatformPlayback {
        let cookie = try PlatformCredentialStore.shared.load(for: .qq) ?? ""; let uin = cookieValue(cookie, "uin") ?? "0"; let key = cookieValue(cookie, "qm_keyst") ?? cookieValue(cookie, "qqmusic_key") ?? ""
        let mediaIDs = [track.mediaID, track.id].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }; return value
        }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let candidates: [(String, String, String)]
        switch quality.lowercased() {
        case "jymaster", "master", "studio": candidates = [("AI00", ".wav", "jymaster"), ("RS01", ".flac", "hires"), ("F000", ".flac", "lossless"), ("M800", ".mp3", "exhigh"), ("M500", ".mp3", "standard"), ("C400", ".m4a", "aac")]
        case "hires", "hi-res": candidates = [("RS01", ".flac", "hires"), ("F000", ".flac", "lossless"), ("M800", ".mp3", "exhigh"), ("M500", ".mp3", "standard"), ("C400", ".m4a", "aac")]
        case "lossless", "flac": candidates = [("F000", ".flac", "lossless"), ("M800", ".mp3", "exhigh"), ("M500", ".mp3", "standard"), ("C400", ".m4a", "aac")]
        case "320", "exhigh": candidates = [("M800", ".mp3", "exhigh"), ("M500", ".mp3", "standard"), ("C400", ".m4a", "aac")]
        default: candidates = [("M500", ".mp3", "standard"), ("C400", ".m4a", "aac")]
        }
        let filenames = mediaIDs.flatMap { id in candidates.map { $0.0 + id + $0.1 } }
        let payload: [String: Any] = ["comm":["uin":uin,"format":"json","ct":key.isEmpty ? 24 : 19,"cv":0,"authst":key],"req_0":["module":"vkey.GetVkeyServer","method":"CgiGetVkey","param":["guid":String(Int.random(in: 10_000_000...99_999_999)),"songmid":Array(repeating: track.id, count: filenames.count),"songtype":Array(repeating: 0, count: filenames.count),"uin":uin,"loginflag":1,"platform":"20","filename":filenames]]]
        let data = try await request(musicURL, body: payload, cookie: cookie)
        let result = (data["req_0"] as? [String: Any])?["data"] as? [String: Any]
        let infos = result?["midurlinfo"] as? [[String: Any]] ?? []
        let sips = (result?["sip"] as? [String])?.filter { !$0.isEmpty } ?? ["https://ws.stream.qqmusic.qq.com/"]
        let playableInfos = infos.filter { ($0["purl"] as? String)?.isEmpty == false }
        for info in playableInfos {
            guard let purl = info["purl"] as? String else { continue }
            for sip in sips {
                guard let url = URL(string: sip + purl), try await Self.looksLikeAudio(url, session: session) else { continue }
                let filename = info["filename"] as? String
                let resolvedQuality = candidates.first(where: { filename?.hasPrefix($0.0) == true })?.2 ?? quality
                return PlatformPlayback(provider: .qq, url: url, playable: true, trial: false, quality: resolvedQuality, message: nil, restriction: nil)
            }
        }
        let raw = playableInfos.first.flatMap { ($0["filename"] as? String) } ?? ""
        let msg = String(describing: result?["msg"] ?? result?["message"] ?? result?["errmsg"] ?? "")
        let lower = msg.lowercased()
        let category = lower.contains("vip") || lower.contains("会员") || lower.contains("付费") ? "paid_required" : (lower.contains("copyright") || lower.contains("版权") ? "copyright_unavailable" : "unavailable")
        return PlatformPlayback(provider: .qq, url: nil, playable: false, trial: false, quality: raw.isEmpty ? quality : raw, message: msg.isEmpty ? "QQ 音乐没有返回可播放音源（可能受版权或会员限制）" : msg, restriction: PlaybackRestriction(category: category, action: category == "paid_required" ? "upgrade" : "switch_source", message: nil))
    }

    internal func loginStatus() async throws -> PlatformLoginStatus {
        let cookie = try PlatformCredentialStore.shared.load(for: .qq) ?? ""; let uin = cookieValue(cookie, "uin") ?? cookieValue(cookie, "qqmusic_uin") ?? cookieValue(cookie, "wxuin") ?? cookieValue(cookie, "p_uin"); let key = cookieValue(cookie, "qm_keyst") ?? cookieValue(cookie, "qqmusic_key") ?? cookieValue(cookie, "music_key") ?? cookieValue(cookie, "wxskey")
        return PlatformLoginStatus(provider: .qq, loggedIn: uin != nil && key != nil, nickname: nil, userID: uin, isVIP: nil, isSVIP: nil, message: nil)
    }

    internal func saveLoginCookie(_ cookie: String) throws -> PlatformLoginStatus {
        var parts: [String: String] = [:]
        cookie.split(separator: ";").forEach { piece in
            let p = piece.split(separator: "=", maxSplits: 1); guard p.count == 2 else { return }
            let key = String(p[0]).trimmingCharacters(in: .whitespacesAndNewlines); let value = String(p[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && !value.isEmpty { parts[key] = value }
        }
        if parts["uin"] == nil { parts["uin"] = parts["qqmusic_uin"] ?? parts["wxuin"] ?? parts["p_uin"] }
        let normalized = parts.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
        let uin = cookieValue(normalized, "uin")
        let key = cookieValue(normalized, "qm_keyst") ?? cookieValue(normalized, "qqmusic_key") ?? cookieValue(normalized, "music_key") ?? cookieValue(normalized, "wxskey")
        guard uin != nil, key != nil else { throw PlatformBridgeError.server("QQ cookie 缺少 uin 或播放票据") }
        try PlatformCredentialStore.shared.save(normalized, for: .qq)
        return PlatformLoginStatus(provider: .qq, loggedIn: true, nickname: nil, userID: uin, isVIP: nil, isSVIP: nil, message: nil)
    }

    private func cookieValue(_ cookie: String, _ name: String) -> String? {
        for part in cookie.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2, pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name.lowercased() else { continue }
            let value = String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value.removingPercentEncoding ?? value }
        }
        return nil
    }

    private static func looksLikeAudio(_ url: URL, session: URLSession) async throws -> Bool {
        var request = URLRequest(url: url); request.httpMethod = "GET"; request.setValue("bytes=0-8191", forHTTPHeaderField: "Range"); request.timeoutInterval = 2
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...206).contains(http.statusCode), data.count >= 512 else { return false }
        let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if type.contains("text/html") || type.contains("json") || type.contains("xml") { return false }
        let bytes = [UInt8](data.prefix(12))
        return String(bytes: bytes.prefix(3), encoding: .ascii) == "ID3" || String(bytes: bytes.prefix(4), encoding: .ascii) == "fLaC" || String(bytes: bytes.prefix(4), encoding: .ascii) == "OggS" || (bytes.count >= 12 && String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF" && String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE") || (bytes.count >= 8 && String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp") || (bytes.count >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0)
    }

    private static func searchSign(_ body: Data) -> String {
        let hash = Array(Insecure.SHA1.hash(data: body).map { String(format: "%02x", $0) }.joined().utf8)
        let part1 = [23,14,6,36,16,40,7,19].map { String(decoding: [hash[$0]], as: UTF8.self) }.joined()
        let part2 = [16,1,32,12,19,27,8,5].map { String(decoding: [hash[$0]], as: UTF8.self) }.joined()
        let scramble: [UInt8] = [89,39,179,150,218,82,58,252,177,52,186,123,120,64,242,133,143,161,121,179]
        let bytes = scramble.enumerated().map { index, value in value ^ UInt8(String(decoding: hash[index * 2...index * 2 + 1], as: UTF8.self), radix: 16)! }
        let middle = Data(bytes).base64EncodedString().replacingOccurrences(of: "[\\\\/+=]", with: "", options: .regularExpression)
        return "zzc\(part1)\(middle)\(part2)".lowercased()
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
}
