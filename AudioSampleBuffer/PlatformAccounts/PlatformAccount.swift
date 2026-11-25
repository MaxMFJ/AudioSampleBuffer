import Foundation

public enum MusicPlatform: String, CaseIterable, Codable, Sendable {
    case netease
    case qqMusic
    case kugou
    case bilibili

    /// Candidate web entry points only. A successful page load does not imply login or scan support.
    public var candidateLoginURL: URL {
        switch self {
        case .netease: return URL(string: "https://music.163.com/#/login")!
        case .qqMusic: return URL(string: "https://y.qq.com/n/ryqq/profile")!
        case .kugou: return URL(string: "https://www.kugou.com/")!
        case .bilibili: return URL(string: "https://passport.bilibili.com/login")!
        }
    }

    var keychainAccount: String { "platform-\(rawValue)" }
}

public typealias AccountPlatform = MusicPlatform

public struct PlatformCredential: Codable, Equatable, Sendable {
    public let accessToken: String?
    public let refreshToken: String?
    public let accountIdentifier: String?
    public let cookieHeader: String?

    private enum CodingKeys: String, CodingKey { case accessToken, refreshToken, accountIdentifier, cookieHeader }

    public init(accessToken: String? = nil, refreshToken: String? = nil, accountIdentifier: String? = nil, cookieHeader: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountIdentifier = accountIdentifier
        self.cookieHeader = cookieHeader
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        accountIdentifier = try container.decodeIfPresent(String.self, forKey: .accountIdentifier)
        cookieHeader = try container.decodeIfPresent(String.self, forKey: .cookieHeader)
    }
}

public struct AccountLoginState: Equatable, Sendable {
    public let platform: AccountPlatform
    public let detectedLogin: Bool
    public let verifiedLogin: Bool
    public let playbackAuthorized: Bool

    public init(platform: AccountPlatform, detectedLogin: Bool, verifiedLogin: Bool, playbackAuthorized: Bool = false) {
        self.platform = platform
        self.detectedLogin = detectedLogin
        self.verifiedLogin = verifiedLogin
        self.playbackAuthorized = playbackAuthorized
    }
}
