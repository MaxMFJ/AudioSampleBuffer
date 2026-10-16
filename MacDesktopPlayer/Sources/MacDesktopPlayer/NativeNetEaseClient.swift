import Foundation

/// Native macOS client for the NetEase operations used by the player.
/// The request shapes follow the same provider endpoints used by the existing
/// local bridge, while networking and account state stay inside the Mac app.
actor NativeNetEaseClient {
    static let shared = NativeNetEaseClient()

    private let session: URLSession
    private let interfaceRoot = URL(string: "https://interface.music.163.com")!
    private let webRoot = URL(string: "https://music.163.com")!

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
    }

    func search(keywords: String, limit: Int, offset: Int = 0) async throws -> [[String: Any]] {
        let payload: [String: Any] = [
            "s": keywords,
            "type": 1,
            "limit": max(1, min(limit, 50)),
            "offset": max(0, offset),
            "total": true
        ]
        let response = try await request("/api/cloudsearch/pc", payload: payload,
            cookie: try PlatformCredentialStore.shared.load(for: .netease), mode: .eapi)
        return ((response["result"] as? [String: Any])?["songs"] as? [[String: Any]]) ?? []
    }

    /// Reuses the same saved account credentials and encrypted transport as playback.
    func lyrics(trackID: String) async throws -> String? {
        let response = try await request("/api/song/lyric", payload: [
            "id": trackID, "lv": -1, "tv": -1, "rv": -1, "kv": -1, "_nmclfl": 1
        ], cookie: try PlatformCredentialStore.shared.load(for: .netease), mode: .weapi)
        return (response["lrc"] as? [String: Any])?["lyric"] as? String
    }

    /// Require matching title/artist; duration helps choose the correct recording.
    func matchedLyricTrackID(title: String, artist: String?, duration: Double?) async throws -> String? {
        let titleKey = Self.lyricMatchKey(title)
        guard !titleKey.isEmpty else { return nil }
        let artistKey = Self.lyricMatchKey(artist ?? "")
        let knownArtist = !artistKey.isEmpty && artistKey != Self.lyricMatchKey("未知艺术家")
        let songs = try await search(keywords: [title, knownArtist ? artist : nil].compactMap { $0 }.joined(separator: " "), limit: 20)
        try Task.checkCancellation()
        var best: (id: String, delta: Double)?
        for song in songs {
            guard Self.lyricMatchKey(Self.string(song["name"]) ?? "") == titleKey,
                  let id = Self.string(song["id"]) else { continue }
            let artists = (song["ar"] ?? song["artists"]) as? [[String: Any]] ?? []
            let names = artists.compactMap { Self.string($0["name"]) }.map(Self.lyricMatchKey)
            guard !knownArtist || names.contains(artistKey) || names.joined() == artistKey else { continue }
            let milliseconds = Self.integer(song["dt"] ?? song["duration"])
            let delta: Double
            if let duration, duration > 0, let milliseconds {
                delta = abs(Double(milliseconds) / 1000 - duration)
                guard delta <= 5 else { continue }
            } else {
                // Without an artist or duration there is too little evidence to auto-match.
                guard knownArtist else { continue }
                delta = 0
            }
            if best == nil || delta < best!.delta { best = (id, delta) }
        }
        return best?.id
    }

    private static func lyricMatchKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    func loginStatus() async throws -> PlatformLoginStatus {
        let cookie = try PlatformCredentialStore.shared.load(for: .netease)
        guard let cookie, !cookie.isEmpty else {
            return PlatformLoginStatus(provider: .netease, loggedIn: false, nickname: nil,
                                       userID: nil, isVIP: false, isSVIP: false, message: nil)
        }
        var response: [String: Any]
        do {
            response = try await request("/api/w/nuser/account/get", payload: [:], cookie: cookie, mode: .weapi)
        } catch {
            // The standard account endpoint is the fallback used by
            // NeteaseCloudMusicApi when login_status cannot return a profile.
            response = try await request("/api/nuser/account/get", payload: [:], cookie: cookie, mode: .weapi)
        }
        if Self.accountUserID(in: response) == nil {
            if let fallback = try? await request("/api/nuser/account/get", payload: [:], cookie: cookie, mode: .weapi) {
                response = fallback
            }
        }
        let data = response["data"] as? [String: Any] ?? response
        let profile = data["profile"] as? [String: Any] ?? response["profile"] as? [String: Any] ?? [:]
        let account = data["account"] as? [String: Any] ?? response["account"] as? [String: Any] ?? [:]
        let userID = Self.accountUserID(in: response)
        // NetEase may answer HTTP/JSON success while returning no authenticated
        // profile. Treat that as an invalid login instead of showing a false
        // "logged in" state that later fails on user_playlist.
        let loggedIn = Self.integer(response["code"]) == 200 && userID != nil
        let vipType = Self.integer(profile["vipType"] ?? account["vipType"]) ?? 0
        let svip = Self.integer(profile["svipLevel"] ?? profile["svipType"]) ?? 0
        return PlatformLoginStatus(
            provider: .netease,
            loggedIn: loggedIn,
            nickname: Self.string(profile["nickname"] ?? profile["userName"]),
            userID: userID,
            isVIP: vipType > 0 || svip > 0,
            isSVIP: svip > 0,
            message: loggedIn ? nil : "网易云账号验证失败：当前登录凭据未通过账号资料校验，请在内嵌页面重新登录后刷新"
        )
    }

    func saveLoginCookie(_ cookie: String) async throws -> PlatformLoginStatus {
        let normalized = Self.normalizedCookie(cookie)
        guard Self.cookieValues(normalized)["music_u"]?.isEmpty == false else {
            throw PlatformBridgeError.server("网易云登录凭据无效或缺少 MUSIC_U")
        }
        try PlatformCredentialStore.shared.save(normalized, for: .netease)
        do {
            let status = try await loginStatus()
            return status
        } catch {
            return PlatformLoginStatus(provider: .netease, loggedIn: false,
                                       nickname: "网易云用户", userID: nil,
                                       isVIP: false, isSVIP: false,
                                       message: "网易云登录凭据已保存，但账号验证失败：\(error.localizedDescription)")
        }
    }

    func userPlaylists(limit: Int = 0, offset: Int = 0) async throws -> [[String: Any]] {
        let status = try await loginStatus()
        guard status.loggedIn else {
            throw PlatformBridgeError.server("请先登录网易云音乐")
        }
        guard let userID = status.userID else {
            throw PlatformBridgeError.server(status.message ?? "网易云已登录，但暂时无法获取账号 ID")
        }
        let pageLimit = limit > 0 ? min(limit, 100) : 100
        let response = try await request("/api/user/playlist", payload: [
            "uid": userID,
            "limit": pageLimit,
            "offset": max(0, offset),
            "includeVideo": true
        ], cookie: try PlatformCredentialStore.shared.load(for: .netease), mode: .weapi)
        let data = response["data"] as? [String: Any] ?? response
        if let playlists = data["playlist"] as? [[String: Any]] { return playlists }
        if let playlists = response["playlist"] as? [[String: Any]] { return playlists }
        throw PlatformBridgeError.server("网易云歌单接口返回了无法识别的数据结构（字段：\(response.keys.sorted().joined(separator: ", "))）")
    }

    func playlistTracks(id: String, limit: Int, offset: Int) async throws -> [[String: Any]] {
        let cookie = try PlatformCredentialStore.shared.load(for: .netease)
        let detail = try await request("/api/v6/playlist/detail", payload: [
            "id": id, "n": 100_000, "s": 8
        ], cookie: cookie, mode: .eapi)
        guard let playlist = detail["playlist"] as? [String: Any],
              let trackIDs = playlist["trackIds"] as? [[String: Any]] else {
            throw PlatformBridgeError.invalidResponse
        }
        let start = min(max(0, offset), trackIDs.count)
        let count = max(1, min(limit, 100))
        let ids = trackIDs[start..<min(trackIDs.count, start + count)].compactMap { Self.string($0["id"]) }
        guard !ids.isEmpty else { return [] }
        let idJSON = "[" + ids.map { "{\"id\":\($0)}" }.joined(separator: ",") + "]"
        let songs = try await request("/api/v3/song/detail", payload: ["c": idJSON], cookie: cookie, mode: .weapi)
        return songs["songs"] as? [[String: Any]] ?? []
    }

    func playback(trackID: String, quality: String) async throws -> PlatformPlayback {
        let response = try await request("/api/song/enhance/player/url/v1", payload: [
            "ids": "[\"\(trackID)\"]",
            "level": quality,
            "encodeType": "flac"
        ], cookie: try PlatformCredentialStore.shared.load(for: .netease), mode: .eapi)
        let row = (response["data"] as? [[String: Any]])?.first ?? [:]
        let url = URL(string: Self.string(row["url"]) ?? "")
        let code = Self.integer(row["code"]) ?? 0
        let playable = url != nil && code == 200
        let trial = row["freeTrialInfo"] != nil
        let message = playable ? nil : "网易云未返回可播放音源（可能受版权或会员限制）"
        return PlatformPlayback(provider: .netease, url: url, playable: playable,
                                trial: trial, quality: quality, message: message,
                                restriction: playable ? nil : PlaybackRestriction(
                                    category: trial ? "trial" : "unavailable",
                                    action: "choose_another_track", message: message
                                ))
    }

    private enum RequestMode: Equatable { case eapi, weapi }

    private func request(_ uri: String, payload: [String: Any], cookie: String?, mode: RequestMode) async throws -> [String: Any] {
        let cookies = Self.cookieValues(cookie ?? "")
        let csrf = cookies["__csrf"] ?? ""
        var body = payload
        body["csrf_token"] = csrf
        body["e_r"] = false

        let jsonData = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .fragmentsAllowed])
        let params: String
        let secret: String?
        switch mode {
        case .weapi:
            let encrypted = try neteaseWEAPIParameters(jsonData: jsonData)
            params = encrypted.params
            secret = encrypted.encSecKey
        case .eapi:
            var eapiBody = body
            eapiBody["header"] = Self.requestHeader(cookies: cookies, csrf: csrf)
            let encrypted = try neteaseEAPIParameters(
                url: uri,
                jsonData: JSONSerialization.data(withJSONObject: eapiBody, options: [.sortedKeys, .fragmentsAllowed])
            )
            params = encrypted.params
            secret = nil
        }

        var components = URLComponents(url: mode == .weapi ? webRoot : interfaceRoot, resolvingAgainstBaseURL: false)!
        let suffix = String(uri.dropFirst(5))
        components.path = (mode == .weapi ? "/weapi/" : "/eapi/") + suffix
        guard let url = components.url else { throw PlatformBridgeError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124 Safari/537.36", forHTTPHeaderField: "User-Agent")
        if let cookie, !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        var fields = ["params=" + Self.formEscape(params)]
        if let secret { fields.append("encSecKey=" + Self.formEscape(secret)) }
        request.httpBody = fields.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PlatformBridgeError.server("网易云接口请求失败")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
            throw PlatformBridgeError.server("网易云接口返回非 JSON 数据（HTTP \(http.statusCode)，\(contentType)，\(data.count) 字节）")
        }
        let code = Self.integer(object["code"]) ?? 200
        guard code == 200 else {
            let message = Self.string(object["message"] ?? object["msg"]) ?? "网易云接口返回错误（\(code)）"
            throw PlatformBridgeError.server(message)
        }
        return object
    }

    private static func requestHeader(cookies: [String: String], csrf: String) -> [String: Any] {
        [
            "osver": "14.0.0",
            "deviceId": "",
            "os": "iPhone OS",
            "appver": "9.0.90",
            "versioncode": "140",
            "mobilename": "",
            "buildver": String(Int(Date().timeIntervalSince1970)),
            "resolution": "1920x1080",
            "__csrf": csrf,
            "channel": "distribution",
            "requestId": "\(Int(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 0...9999))",
            "MUSIC_U": cookies["music_u"] ?? "",
            "MUSIC_A": cookies["music_a"] ?? ""
        ]
    }

    private static func normalizedCookie(_ value: String) -> String {
        value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "; ")
    }

    private static func cookieValues(_ header: String) -> [String: String] {
        Dictionary(header.split(separator: ";").compactMap { pair -> (String, String)? in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0].trimmingCharacters(in: .whitespaces).lowercased(), parts[1].trimmingCharacters(in: .whitespaces))
        }, uniquingKeysWith: { _, latest in latest })
    }

    private static func formEscape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._* ")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)?.replacingOccurrences(of: " ", with: "+") ?? value
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

    private static func accountUserID(in response: [String: Any]) -> String? {
        let data = response["data"] as? [String: Any] ?? [:]
        let profile = (data["profile"] as? [String: Any])
            ?? (response["profile"] as? [String: Any])
            ?? [:]
        let account = (data["account"] as? [String: Any])
            ?? (response["account"] as? [String: Any])
            ?? [:]
        return string(profile["userId"] ?? profile["id"] ?? account["id"])
    }
}
