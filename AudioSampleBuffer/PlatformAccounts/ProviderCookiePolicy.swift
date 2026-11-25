import Foundation
import WebKit

public struct ProviderCookiePolicy: Sendable {
    public let allowedDomains: Set<String>
    public let allowedCookieNames: Set<String>?
    public let requiredCookieAlternatives: [Set<String>]

    public init(allowedDomains: Set<String>, allowedCookieNames: Set<String>? = nil, requiredCookieAlternatives: [Set<String>] = []) {
        self.allowedDomains = allowedDomains; self.allowedCookieNames = allowedCookieNames; self.requiredCookieAlternatives = requiredCookieAlternatives
    }
    public func indicatesLogin(_ cookies: [HTTPCookie]) -> Bool {
        let names = Set(cookies.map { $0.name.lowercased() })
        return requiredCookieAlternatives.contains { !$0.isEmpty && $0.isSubset(of: names) }
    }

    public func accepts(_ cookie: HTTPCookie) -> Bool {
        let host = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let domainOK = allowedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
        let cookieName = cookie.name.lowercased()
        let allowedNames = allowedCookieNames?.map { $0.lowercased() }
        return domainOK && (allowedNames == nil || allowedNames!.contains(cookieName))
    }

    public static func policy(for platform: AccountPlatform) -> ProviderCookiePolicy {
        switch platform {
        case .netease: return .init(allowedDomains: ["163.com", "music.163.com"], requiredCookieAlternatives: [["music_u"]])
        case .qqMusic: return .init(allowedDomains: ["qq.com", "y.qq.com"], requiredCookieAlternatives: [["uin", "qm_keyst"], ["uin", "qqmusic_key"], ["wxuin", "wxskey"], ["p_uin", "p_skey"]])
        case .kugou: return .init(allowedDomains: ["kugou.com", "www.kugou.com"], requiredCookieAlternatives: [["kg_mid"], ["kugooid"], ["userid"]])
        case .bilibili: return .init(allowedDomains: ["bilibili.com"], allowedCookieNames: ["SESSDATA", "DedeUserID", "bili_jct", "sid", "DedeUserID__ckMd5"], requiredCookieAlternatives: [["sessdata"]])
        }
    }
}
