import AppKit
import WebKit

@MainActor
final class PlatformLoginWindowController: NSWindowController, NSWindowDelegate {
    private let provider: PlatformProvider
    private let webView: WKWebView
    private var cookieTimer: Timer?
    private var submitting = false
    private var lastSubmittedCookie: String?

    init(provider: PlatformProvider) {
        self.provider = provider
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: configuration)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "登录 \(provider.title)"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self

        webView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = webView
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            webView.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            webView.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)
        ])
        webView.load(URLRequest(url: loginURL))
        cookieTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.syncCookies() }
        }
    }

    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        cookieTimer?.invalidate()
        cookieTimer = nil
    }

    private var loginURL: URL {
        switch provider {
        case .netease: return URL(string: "https://music.163.com/#/login")!
        case .qq: return URL(string: "https://y.qq.com/n/ryqq/profile")!
        case .kugou: return URL(string: "https://www.kugou.com/")!
        }
    }

    private func syncCookies() {
        guard !submitting else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let cookieHeader = self.cookieHeader(from: cookies)
                guard self.looksLoggedIn(cookieHeader), cookieHeader != self.lastSubmittedCookie else { return }
                self.submitting = true
                self.lastSubmittedCookie = cookieHeader
                defer { self.submitting = false }
                do {
                    let status = try await PlatformBridgeClient.shared.saveLoginCookie(cookieHeader, for: self.provider)
                    if !status.loggedIn {
                        NSLog("平台登录页已检测到 Cookie，但账号验证未通过：%@", status.message ?? "unknown error")
                    }
                } catch {
                    NSLog("平台登录凭据提交失败：%@", error.localizedDescription)
                }
            }
        }
    }

    private func cookieHeader(from cookies: [HTTPCookie]) -> String {
        let allowed: (String) -> Bool`
        switch provider {
        case .netease: allowed = { $0 == "163.com" || $0.hasSuffix(".163.com") || $0 == "netease.com" || $0.hasSuffix(".netease.com") }
        case .qq: allowed = { $0 == "qq.com" || $0.hasSuffix(".qq.com") }
        case .kugou: allowed = { $0 == "kugou.com" || $0.hasSuffix(".kugou.com") }
        }
        var values: [String: HTTPCookie] = [:]
        for cookie in cookies where allowed(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()) {
            let key = cookie.name.lowercased()
            guard !cookie.value.isEmpty else { continue }
            if let current = values[key] {
                let currentDomain = current.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                let candidateDomain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if candidateDomain.count < currentDomain.count { continue }
            }
            values[key] = cookie
        }
        return values.keys.sorted().compactMap { key in
            guard let cookie = values[key] else { return nil }
            return "\(cookie.name)=\(cookie.value)"
        }.joined(separator: "; ")
    }

    private func looksLoggedIn(_ cookie: String) -> Bool {
        switch provider {
        case .netease: return cookie.range(of: #"(?i)(?:^|;\s*)MUSIC_U=[^;\s]+"#, options: .regularExpression) != nil
        case .qq: return cookie.range(of: #"(?:^|;\s*)(uin|wxuin|qm_keyst|qqmusic_key)=[^;\s]+"#, options: .regularExpression) != nil
        case .kugou: return cookie.range(of: #"(?:^|;\s*)(kg_mid|KugooID|userid)=[^;\s]+"#, options: .regularExpression) != nil
        }
    }
}
