import Foundation
import CommonCrypto
import Security

/// Native NetEase client used by the iOS account and library surfaces.
public actor NetEasePlatformClient: PlatformMusicProviderClient {
    public let platform: MusicPlatform = .netease
    private let session: URLSession
    private let webRoot = URL(string: "https://music.163.com")!
    private let interfaceRoot = URL(string: "https://interface.music.163.com")!

    public init(session: URLSession = .shared) { self.session = session }

    public func verify(platform: AccountPlatform, cookies: [HTTPCookie]) async -> Bool {
        guard platform == .netease else { return false }
        let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        guard !cookieValues(header)["music_u", default: ""].isEmpty else { return false }
        do { let response = try await request("/api/w/nuser/account/get", payload: [:], cookieHeader: header, mode: .weapi)
            return integer(response["code"]) == 200 && accountUserID(response) != nil
        } catch { return false }
    }

    public func userPlaylists(cookieHeader: String) async throws -> [ProviderPlaylist] {
        guard !cookieValues(cookieHeader)["music_u", default: ""].isEmpty else { throw PlatformMusicError.missingCredential }
        let account = try await request("/api/w/nuser/account/get", payload: [:], cookieHeader: cookieHeader, mode: .weapi)
        guard let uid = accountUserID(account) else { throw PlatformMusicError.unavailable("网易云账号验证失败，请重新登录。") }
        let response = try await request("/api/user/playlist", payload: ["uid": uid, "limit": 100, "offset": 0, "includeVideo": true], cookieHeader: cookieHeader, mode: .weapi)
        let rows = ((response["playlist"] as? [[String: Any]]) ?? (response["data"] as? [String: Any])?["playlist"] as? [[String: Any]]) ?? []
        return rows.compactMap { row in
            guard let id = string(row["id"]), let name = string(row["name"]) else { return nil }
            return ProviderPlaylist(id: id, platform: .netease, name: name, coverURL: URL(string: string(row["coverImgUrl"]) ?? ""), trackCount: integer(row["trackCount"]))
        }
    }

    public func playlistTracks(_ playlist: ProviderPlaylist, cookieHeader: String, limit: Int, offset: Int) async throws -> [ProviderTrack] {
        let detail = try await request("/api/v6/playlist/detail", payload: ["id": playlist.id, "n": 100000, "s": 8], cookieHeader: cookieHeader, mode: .eapi)
        guard let list = (detail["playlist"] as? [String: Any])?["trackIds"] as? [[String: Any]] else { throw PlatformMusicError.unavailable("网易云歌单数据格式无法识别。") }
        let start = min(max(offset, 0), list.count), end = min(list.count, start + max(0, min(limit, 100)))
        guard start < end else { return [] }
        let ids = list[start..<end].compactMap { string($0["id"]) }
        let c = "[" + ids.map { "{\"id\":\($0)}" }.joined(separator: ",") + "]"
        let response = try await request("/api/v3/song/detail", payload: ["c": c], cookieHeader: cookieHeader, mode: .weapi)
        return ((response["songs"] as? [[String: Any]]) ?? []).compactMap(track(from:))
    }

    public func searchTracks(keyword: String, cookieHeader: String, limit: Int) async throws -> [ProviderTrack] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response = try await request("/api/cloudsearch/pc", payload: [
            "s": trimmed, "type": 1, "limit": max(1, min(limit, 50)), "offset": 0, "total": true
        ], cookieHeader: cookieHeader, mode: .eapi)
        return ((response["result"] as? [String: Any])?["songs"] as? [[String: Any]] ?? []).compactMap(track(from:))
    }

    private func track(from song: [String: Any]) -> ProviderTrack? {
        guard let id = string(song["id"]), let name = string(song["name"]) else { return nil }
        let artists = (song["ar"] as? [[String: Any]] ?? song["artists"] as? [[String: Any]])?.compactMap { string($0["name"]) } ?? []
        let album = (song["al"] as? [String: Any]) ?? (song["album"] as? [String: Any])
        let duration = integer(song["dt"] ?? song["duration"]).map { Double($0) / 1000 }
        return ProviderTrack(id: id, platform: .netease, name: name, artist: artists.joined(separator: ", "), album: string(album?["name"]), artworkURL: string(album?["picUrl"]).flatMap(URL.init(string:)), duration: duration, mediaID: id, albumID: string(album?["id"]))
    }

    public func playbackURL(for track: ProviderTrack, cookieHeader: String) async throws -> URL {
        let response = try await request("/api/song/enhance/player/url/v1", payload: ["ids": "[\"\(track.id)\"]", "level": "exhigh", "encodeType": "flac"], cookieHeader: cookieHeader, mode: .eapi)
        let row = (response["data"] as? [[String: Any]])?.first
        guard integer(row?["code"]) == 200, let url = URL(string: string(row?["url"]) ?? ""), url.scheme?.hasPrefix("http") == true else { throw PlatformMusicError.unavailable("网易云未返回可播放音源，可能受版权或会员限制。") }
        return url
    }

    public func lyrics(trackID: String, cookieHeader: String) async throws -> String? {
        let response = try await request("/api/song/lyric", payload: [
            "id": trackID, "lv": -1, "tv": -1, "rv": -1, "kv": -1, "_nmclfl": 1
        ], cookieHeader: cookieHeader, mode: .weapi)
        let lyric = ((response["lrc"] as? [String: Any])?["lyric"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return lyric?.isEmpty == false ? lyric : nil
    }

    private enum Mode { case weapi, eapi }
    private func request(_ path: String, payload: [String: Any], cookieHeader: String, mode: Mode) async throws -> [String: Any] {
        var body = payload; body["csrf_token"] = cookieValues(cookieHeader)["__csrf"] ?? ""; body["e_r"] = false
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let encrypted: (String, String?) = try { switch mode { case .weapi: let x = try weapi(data); return (x.0, x.1); case .eapi: return (try eapi(path, data), nil) } }()
        var components = URLComponents(url: mode == .weapi ? webRoot : interfaceRoot, resolvingAgainstBaseURL: false)!; components.path = (mode == .weapi ? "/weapi/" : "/eapi/") + String(path.dropFirst(5))
        var req = URLRequest(url: components.url!); req.httpMethod = "POST"; req.timeoutInterval = 15; req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); req.setValue("https://music.163.com", forHTTPHeaderField: "Referer"); req.setValue(cookieHeader, forHTTPHeaderField: "Cookie"); req.httpBody = ("params=" + form(encrypted.0) + (encrypted.1.map { "&encSecKey=" + form($0) } ?? "")).data(using: .utf8)
        let (dataOut, response) = try await session.data(for: req); guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let object = try? JSONSerialization.jsonObject(with: dataOut) as? [String: Any], integer(object["code"]) ?? 200 == 200 else { throw PlatformMusicError.unavailable("网易云接口请求失败，请稍后重试。") }; return object
    }

    private func cookieValues(_ value: String) -> [String: String] { Dictionary(value.split(separator: ";").compactMap { p -> (String, String)? in let a = p.split(separator: "=", maxSplits: 1); guard a.count == 2 else { return nil }; return (a[0].trimmingCharacters(in: .whitespaces).lowercased(), a[1].trimmingCharacters(in: .whitespaces)) }, uniquingKeysWith: { _, b in b }) }
    private func accountUserID(_ r: [String: Any]) -> String? { let d = r["data"] as? [String: Any] ?? r; let p = d["profile"] as? [String: Any] ?? r["profile"] as? [String: Any] ?? [:]; let a = d["account"] as? [String: Any] ?? r["account"] as? [String: Any] ?? [:]; return string(p["userId"] ?? p["id"] ?? a["id"]) }
    private func string(_ v: Any?) -> String? { if let s = v as? String, !s.isEmpty { return s }; if let n = v as? NSNumber { return n.stringValue }; return nil }
    private func integer(_ v: Any?) -> Int? { if let n = v as? NSNumber { return n.intValue }; if let s = v as? String { return Int(s) }; return nil }
    private func form(_ v: String) -> String { var c = CharacterSet.alphanumerics; c.insert(charactersIn: "-._* "); return (v.addingPercentEncoding(withAllowedCharacters: c) ?? v).replacingOccurrences(of: " ", with: "+") }
}

private func weapi(_ data: Data) throws -> (String, String) {
    let iv = Array("0102030405060708".utf8), preset = Array("0CoJUm6Qyw8W8jud".utf8), key = String((0..<16).map { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
    let first = try aes(data, key: preset, iv: iv, ecb: false), second = try aes(Data(first.base64EncodedString().utf8), key: Array(key.utf8), iv: iv, ecb: false)
    let der = Data(base64Encoded: "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDgtQn2JZ34ZC28NWYpAUd98iZ37BUrX/aKzmFbt7clFSs6sXqHauqKWqdtLkF2KexO40H1YTX8z2lSgBBOAxLsvaklV8k4cBFK9snQXE9/DDaFt6Rr7iVZMldczhC0JNgTz+SHXT6CBHuX3e9SdB1Ua44oncaTWz7OBGLbCiK45wIDAQAB")!
    let attrs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic, kSecAttrKeySizeInBits: 1024]; guard let rsa = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, nil), let encrypted = SecKeyCreateEncryptedData(rsa, .rsaEncryptionRaw, Data(key.utf8.reversed()) as CFData, nil) else { throw PlatformMusicError.unavailable("网易云请求加密失败，请稍后重试。") }
    return (second.base64EncodedString(), (encrypted as Data).map { String(format: "%02x", $0) }.joined())
}

@objc(NetEaseLyricsBridge)
public final class NetEaseLyricsBridge: NSObject {
    @objc(sharedBridge)
    public static let shared = NetEaseLyricsBridge()

    @objc(fetchLyricsForTrackID:completion:)
    public func fetchLyrics(trackID: String, completion: @escaping (String?, String?) -> Void) {
        Task {
            do {
                let lyric = try await PlatformMusicService.shared.neteaseLyrics(trackID: trackID)
                DispatchQueue.main.async { completion(lyric, nil) }
            } catch {
                DispatchQueue.main.async { completion(nil, error.localizedDescription) }
            }
        }
    }
}

private func eapi(_ path: String, _ data: Data) throws -> String {
    let text = String(decoding: data, as: UTF8.self), digest = md5("nobody\(path)use\(text)md5forencrypt"), payload = "\(path)-36cd479b6b5-\(text)-36cd479b6b5-\(digest)"
    return try aes(Data(payload.utf8), key: Array("e82ckenh8dichen8".utf8), iv: nil, ecb: true).map { String(format: "%02X", $0) }.joined()
}

private func aes(_ data: Data, key: [UInt8], iv: [UInt8]?, ecb: Bool) throws -> Data {
    var output = Data(count: data.count + kCCBlockSizeAES128), length = 0
    let outputCapacity = output.count
    let options = CCOptions(kCCOptionPKCS7Padding) | (ecb ? CCOptions(kCCOptionECBMode) : 0)
    let status = output.withUnsafeMutableBytes { out in data.withUnsafeBytes { input in CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), options, key, key.count, iv, input.baseAddress, data.count, out.baseAddress, outputCapacity, &length) } }
    guard status == kCCSuccess else { throw PlatformMusicError.unavailable("网易云请求加密失败，请稍后重试。") }; output.removeSubrange(length..<output.count); return output
}

private func md5(_ value: String) -> String { value.data(using: .utf8)!.withUnsafeBytes { p in var d = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH)); CC_MD5(p.baseAddress, CC_LONG(p.count), &d); return d.map { String(format: "%02x", $0) }.joined() } }
