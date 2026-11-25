import AVFoundation
import Foundation

/// Keeps signed addresses in memory only. Every address is supplied by playurl;
/// hosts and authentication query parameters are never rewritten.
enum BiliPlaybackSupport {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private static let lock = NSLock()
    private static var groups: [[URL]] = []

    static func register(urls: [URL]) {
        lock.lock(); defer { lock.unlock() }
        groups.removeAll { $0.contains(where: urls.contains) }
        groups.append(urls)
        if groups.count > 16 { groups.removeFirst(groups.count - 16) }
    }

    static func candidates(for url: URL) -> [URL] {
        lock.lock(); defer { lock.unlock() }
        guard let group = groups.last(where: { $0.contains(url) }) else { return [url] }
        return [url] + group.filter { $0 != url }
    }

    static func safeText(_ input: String) -> String {
        var text = input
        for pattern in [#"(?i)https?://[^\s<>\"']+"#,
                        #"(?im)(cookie|authorization|set-cookie)\s*:[^\r\n]*"#,
                        #"[A-Za-z_][A-Za-z0-9_-]*=[^\s&,;]+"#,
                        #"[A-Za-z0-9_+/=-]{32,}"#] {
            text = text.replacingOccurrences(of: pattern, with: "<redacted>", options: .regularExpression)
        }
        return String(text.prefix(400))
    }

    static func log(error: NSError?, host: String, stage: String, depth: Int = 0) {
        guard let error, depth < 8 else { return }
        NSLog("[BiliMV] %@：host=%@，层=%ld，domain=%@，code=%ld，原因=%@", stage, host,
              depth, safeText(error.domain), error.code, safeText(error.localizedDescription))
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            log(error: underlying, host: host, stage: "底层错误", depth: depth + 1)
        }
        if let errors = error.userInfo["NSMultipleUnderlyingErrors"] as? [NSError] {
            for nested in errors.prefix(8) { log(error: nested, host: host, stage: "底层错误", depth: depth + 1) }
        }
    }
}

/// One finite pass through validated primary/backup addresses. The caller owns
/// the session and controls the song clock; replacing an item invalidates seeks.
@objc(BiliPlaybackSession)
final class BiliPlaybackSession: NSObject {
    @objc let player = AVPlayer()
    private let urls: [URL]
    private let automaticallyResume: Bool
    private let itemChanged: (AVPlayerItem) -> Void
    private let status: (String) -> Void
    private var index = 0
    private var generation = 0
    private var stopped = false
    private var itemObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    private var logObserver: NSObjectProtocol?
    private var timeout: DispatchWorkItem?
    private var resumeRate: Float = 1
    private var resumeTime: CMTime = .zero
    private var replacing = false

    @objc(initWithURL:automaticallyResume:itemChanged:status:)
    init(url: URL, automaticallyResume: Bool, itemChanged: @escaping (AVPlayerItem) -> Void,
         status: @escaping (String) -> Void) {
        self.urls = BiliPlaybackSupport.candidates(for: url)
        self.automaticallyResume = automaticallyResume
        self.itemChanged = itemChanged
        self.status = status
        super.init()
        player.isMuted = true
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            guard let self, !self.replacing, player.currentItem?.status != .failed else { return }
            self.resumeRate = player.rate
        }
        DispatchQueue.main.async { [weak self] in self?.install() }
    }

    private func install() {
        guard !stopped, index < urls.count else { return }
        generation += 1
        let token = generation
        clearItemObservers()
        let url = urls[index]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": [
            "Referer": "https://www.bilibili.com/", "User-Agent": BiliPlaybackSupport.userAgent]])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 5
        replacing = true
        player.replaceCurrentItem(with: item)
        replacing = false
        itemChanged(item)
        NSLog("[BiliMV] 加载节点 %ld/%ld，host=%@", index + 1, urls.count, url.host ?? "未知")
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, !self.stopped, self.generation == token else { return }
                if item.status == .failed { self.fail(item, token: token, stage: "AVPlayer 加载失败") }
                if item.status == .readyToPlay {
                    self.timeout?.cancel(); self.timeout = nil
                    NSLog("[BiliMV] AVPlayer 就绪：host=%@", url.host ?? "未知")
                    self.status("ready")
                    if self.automaticallyResume {
                        let rate = self.resumeRate
                        self.player.seek(to: self.resumeTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                            DispatchQueue.main.async {
                                guard let self, finished, !self.stopped, self.generation == token else { return }
                                self.player.rate = rate
                            }
                        }
                    }
                }
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item, queue: .main) { [weak self] note in
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
                self?.fail(item, token: token, stage: "播放中断", notificationError: error)
            }
        logObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemNewErrorLogEntry,
            object: item, queue: .main) { [weak self] _ in
                guard let self, !self.stopped, self.generation == token else { return }
                self.logItem(item)
            }
        let work = DispatchWorkItem { [weak self] in self?.fail(item, token: token, stage: "节点加载超时") }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    private func logItem(_ item: AVPlayerItem) {
        for event in (item.errorLog()?.events ?? []).suffix(8) {
            let host = event.uri.flatMap(URL.init(string:))?.host ?? urls[index].host ?? "未知"
            NSLog("[BiliMV] 媒体错误事件：host=%@，domain=%@，status=%ld，说明=%@", host,
                  BiliPlaybackSupport.safeText(event.errorDomain), event.errorStatusCode,
                  BiliPlaybackSupport.safeText(event.errorComment ?? "无"))
        }
    }

    private func fail(_ item: AVPlayerItem, token: Int, stage: String, notificationError: NSError? = nil) {
        guard !stopped, generation == token, player.currentItem === item else { return }
        generation += 1 // KVO and notification can report the same failure.
        BiliPlaybackSupport.log(error: notificationError ?? item.error as NSError?, host: urls[index].host ?? "未知", stage: stage)
        NSLog("[BiliMV] %@，节点=%ld/%ld", stage, index + 1, urls.count)
        logItem(item)
        let current = player.currentTime()
        if current.seconds.isFinite, current.seconds > 0 { resumeTime = current }
        clearItemObservers()
        index += 1
        guard index < urls.count else {
            player.pause()
            status("failed")
            return
        }
        status("retrying")
        install()
    }

    private func clearItemObservers() {
        timeout?.cancel(); timeout = nil
        itemObservation = nil
        for observer in [failureObserver, logObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        failureObserver = nil; logObserver = nil
    }

    @objc func stop() {
        stopped = true; generation += 1
        clearItemObservers()
        rateObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    deinit {
        timeout?.cancel()
        for observer in [failureObserver, logObserver].compactMap({ $0 }) { NotificationCenter.default.removeObserver(observer) }
    }
}
