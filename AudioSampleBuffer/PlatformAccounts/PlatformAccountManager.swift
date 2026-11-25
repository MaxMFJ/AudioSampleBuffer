import Foundation
import WebKit

public protocol PlatformAccountVerifying: Sendable {
    func verify(platform: AccountPlatform, cookies: [HTTPCookie]) async -> Bool
}

public actor MusicAuthManager {
    public static let shared = MusicAuthManager(verifier: PlatformMusicService.shared)
    public let credentialStore: any PlatformCredentialStore
    public private(set) var states: [AccountPlatform: AccountLoginState] = [:]
    private let verifier: any PlatformAccountVerifying

    public init(credentialStore: any PlatformCredentialStore = KeychainPlatformCredentialStore(), verifier: any PlatformAccountVerifying) {
        self.credentialStore = credentialStore; self.verifier = verifier
    }

    public func state(for platform: AccountPlatform) -> AccountLoginState {
        states[platform] ?? AccountLoginState(platform: platform, detectedLogin: false, verifiedLogin: false)
    }

    @discardableResult
    public func restoreAndVerify(platform: AccountPlatform) async -> AccountLoginState {
        let saved: PlatformCredential?
        do { saved = try credentialStore.credential(for: platform) } catch { saved = nil }
        guard let credential = saved, let header = credential.cookieHeader, !header.isEmpty else {
            let empty = AccountLoginState(platform: platform, detectedLogin: false, verifiedLogin: false)
            states[platform] = empty
            return empty
        }
        let domain: String
        switch platform {
        case .netease: domain = ".163.com"
        case .qqMusic: domain = ".qq.com"
        case .kugou: domain = ".kugou.com"
        case .bilibili: domain = ".bilibili.com"
        }
        let cookies = header.split(separator: ";").compactMap { part -> HTTPCookie? in
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return nil }
            return HTTPCookie(properties: [.domain: domain, .path: "/", .name: pair[0].trimmingCharacters(in: .whitespaces), .value: pair[1].trimmingCharacters(in: .whitespaces), .secure: "TRUE"])
        }
        await updateDetectedLogin(platform: platform, cookies: cookies)
        return state(for: platform)
    }

    public func updateDetectedLogin(platform: AccountPlatform, cookies: [HTTPCookie]) async {
        let policy = ProviderCookiePolicy.policy(for: platform)
        let acceptedCookies = cookies.filter { policy.accepts($0) }
        let detected = policy.indicatesLogin(acceptedCookies)
        let cookieNames = Set(acceptedCookies.map { $0.name.lowercased() })
        let playbackAuthorized = platform != .qqMusic || (
            ["uin", "qqmusic_uin", "wxuin", "p_uin"].contains(where: cookieNames.contains)
                && ["qm_keyst", "qqmusic_key", "music_key", "wxskey"].contains(where: cookieNames.contains)
        )
        let verified: Bool
        if detected { verified = await verifier.verify(platform: platform, cookies: acceptedCookies) }
        else { verified = false }
        if verified {
            let header = acceptedCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            do {
                try credentialStore.save(PlatformCredential(cookieHeader: header), for: platform)
            } catch {
                states[platform] = AccountLoginState(platform: platform, detectedLogin: true, verifiedLogin: false, playbackAuthorized: playbackAuthorized)
                return
            }
        }
        states[platform] = AccountLoginState(platform: platform, detectedLogin: detected, verifiedLogin: verified, playbackAuthorized: playbackAuthorized)
    }

    public func logout(platform: AccountPlatform, dataStore: WKWebsiteDataStore) async throws {
        try credentialStore.removeCredential(for: platform)
        let policy = ProviderCookiePolicy.policy(for: platform)
        let records = await dataStore.httpCookieStore.allCookies()
        for cookie in records where policy.accepts(cookie) { await dataStore.httpCookieStore.deleteCookie(cookie) }
        states[platform] = AccountLoginState(platform: platform, detectedLogin: false, verifiedLogin: false, playbackAuthorized: false)
    }
}

public typealias PlatformAccountManager = MusicAuthManager

private extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] { await withCheckedContinuation { continuation in getAllCookies { continuation.resume(returning: $0) } } }
}
