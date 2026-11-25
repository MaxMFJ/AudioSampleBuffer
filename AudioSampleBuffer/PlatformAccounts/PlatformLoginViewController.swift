import UIKit
import WebKit

public protocol PlatformLoginViewControllerDelegate: AnyObject {
    func loginController(_ controller: PlatformLoginViewController, didObserve cookies: [HTTPCookie], for platform: AccountPlatform)
}

public final class PlatformLoginViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    public let platform: AccountPlatform
    public weak var delegate: PlatformLoginViewControllerDelegate?
    public private(set) var webView: WKWebView!
    private let policy: ProviderCookiePolicy
    private let dataStore: WKWebsiteDataStore
    private var didWarmUpQQPlaybackSession = false

    public init(platform: AccountPlatform, dataStore: WKWebsiteDataStore = .default(), policy: ProviderCookiePolicy? = nil) {
        self.platform = platform; self.dataStore = dataStore; self.policy = policy ?? .policy(for: platform)
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    public override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        if #available(iOS 14.0, *), platform == .qqMusic {
            configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        if platform == .qqMusic {
            // QQ Music's mobile site tries to hand authentication to its app.
            // Desktop Safari mode keeps the web QR login flow in this WebView.
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        }
        view = webView
    }
    public override func viewDidLoad() { super.viewDidLoad(); webView.load(URLRequest(url: platform.candidateLoginURL)) }
    public override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); dataStore.httpCookieStore.add(self); observeCookies() }
    public override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); dataStore.httpCookieStore.remove(self) }
    deinit { dataStore.httpCookieStore.remove(self) }
    public func observeCookies() {
        dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let accepted = cookies.filter { self.policy.accepts($0) }
            if self.platform == .qqMusic {
                let names = Set(accepted.map { $0.name.lowercased() })
                let hasAccountSession = ["uin", "qqmusic_uin", "wxuin", "p_uin"].contains(where: names.contains)
                    && ["p_skey", "skey", "qm_keyst", "qqmusic_key", "music_key", "wxskey"].contains(where: names.contains)
                let hasPlaybackTicket = ["qm_keyst", "qqmusic_key", "music_key", "wxskey"].contains(where: names.contains)
                if hasAccountSession && !hasPlaybackTicket && !self.didWarmUpQQPlaybackSession {
                    self.didWarmUpQQPlaybackSession = true
                    DispatchQueue.main.async {
                        self.webView.load(URLRequest(url: URL(string: "https://y.qq.com/n/ryqq/player")!))
                    }
                }
            }
            DispatchQueue.main.async { self.delegate?.loginController(self, didObserve: accepted, for: self.platform) }
        }
    }
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { observeCookies() }
    public func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { observeCookies() }

    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        webView.load(navigationAction.request)
        return nil
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard platform == .qqMusic || platform == .bilibili,
              let scheme = navigationAction.request.url?.scheme?.lowercased(),
              scheme != "http", scheme != "https", scheme != "about", scheme != "blob" else {
            decisionHandler(.allow)
            return
        }
        // Block custom app URL schemes so the user remains in the in-app QR flow.
        decisionHandler(.cancel)
    }
}
