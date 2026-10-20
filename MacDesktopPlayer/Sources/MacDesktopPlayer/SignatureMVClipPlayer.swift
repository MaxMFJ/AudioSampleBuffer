import AppKit
import AVFoundation

/// Plays a muted slice of a NetEase MV while a signature lyric run is on screen.
/// The stream stays remote: nothing is downloaded or written to disk.
@MainActor
final class SignatureMVClipPlayer {
    private struct Moment {
        let titleHints: [String]
        let phrases: [String]
        /// Added to the audio clock to land on the same picture in the MV.
        let videoOffset: Double
        let maxDuration: Double

        func matchesTitle(_ title: String) -> Bool {
            let key = Self.normalize(title)
            return titleHints.contains { key.contains($0) }
        }

        func matchesLine(_ text: String) -> Bool {
            let key = Self.normalize(text)
            guard !key.isEmpty else { return false }
            return phrases.contains { key.contains($0) }
        }

        private static func normalize(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
        }
    }

    private static let moments = [
        Moment(
            titleHints: ["firestarter", "파이어스타터"],
            phrases: ["letsgo", "losecontrol", "dropit", "놀아보자", "얼씨구", "철컥"],
            videoOffset: 0,
            maxDuration: 18
        )
    ]

    private var panel: NSPanel?
    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var generation = 0
    private var streamURL: URL?
    private var visibleStart: Double?
    private var seeking = false
    private var lastSeekAt = 0.0

    func prepare(trackID: String?, title: String) {
        stop()
        guard let trackID, let moment = Self.moments.first(where: { $0.matchesTitle(title) }) else { return }
        generation += 1
        let token = generation
        let offset = moment.videoOffset
        Task { [weak self] in
            do {
                guard let url = try await NativeNetEaseClient.shared.musicVideoURL(trackID: trackID) else {
                    NSLog("[SignatureMV] %@ 没有可播放的 MV", title)
                    return
                }
                await MainActor.run {
                    guard let self, self.generation == token else { return }
                    self.streamURL = url
                    self.install(url)
                    NSLog("[SignatureMV] 已接上 MV，画面偏移 %.1f 秒", offset)
                }
            } catch {
                NSLog("[SignatureMV] 获取 MV 失败: %@", error.localizedDescription)
            }
        }
    }

    func stop() {
        generation += 1
        visibleStart = nil
        seeking = false
        streamURL = nil
        statusObservation = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        panel?.orderOut(nil)
    }

    func tick(title: String, time: Double, playing: Bool, lines: [TimedLyric]) {
        guard streamURL != nil, let moment = Self.moments.first(where: { $0.matchesTitle(title) }),
              let run = activeRun(in: lines, at: time, moment: moment) else {
            hide()
            return
        }
        show()
        guard let player else { return }
        if !playing {
            player.pause()
            return
        }
        let target = max(0, time + moment.videoOffset)
        let actual = player.currentTime().seconds
        let entered = visibleStart != run.start
        let drifted = !actual.isFinite || abs(actual - target) > 0.75
        let now = ProcessInfo.processInfo.systemUptime
        if entered || (drifted && !seeking && now - lastSeekAt > 1) {
            visibleStart = run.start
            seeking = true
            lastSeekAt = now
            let seekTime = CMTime(seconds: target, preferredTimescale: 600)
            let tolerance = CMTime(seconds: 0.2, preferredTimescale: 600)
            player.seek(to: seekTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
                Task { @MainActor in
                    self?.seeking = false
                    self?.player?.play()
                }
            }
            if entered {
                NSLog("[SignatureMV] 进入标志片段，音频 %.1f 秒，画面 %.1f 秒", time, target)
            }
        } else if player.rate == 0 {
            player.play()
        }
    }

    private func activeRun(in lines: [TimedLyric], at time: Double, moment: Moment) -> (start: Double, end: Double)? {
        let hits = lines.indices.filter { moment.matchesLine(lines[$0].text) }
        guard var runEnd = hits.first else { return nil }
        var runs: [(Int, Int)] = []
        var runStart = runEnd
        for index in hits.dropFirst() {
            if lines[index].time - lines[runEnd].time <= 8 {
                runEnd = index
            } else {
                runs.append((runStart, runEnd))
                runStart = index
                runEnd = index
            }
        }
        runs.append((runStart, runEnd))
        for run in runs {
            let start = lines[run.0].time
            let last = lines[run.1].time
            let following = lines.indices.contains(run.1 + 1) ? lines[run.1 + 1].time : last + 4
            let end = min(max(following, last + 1), start + moment.maxDuration)
            if time >= start && time < end { return (start, end) }
        }
        return nil
    }

    private func install(_ url: URL) {
        let headers = [
            "Referer": "https://music.163.com/",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124 Safari/537.36"
        ]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let player = self.player ?? AVPlayer()
        player.replaceCurrentItem(with: item)
        player.isMuted = true
        player.volume = 0
        self.player = player
        ensurePanel()
        playerLayer?.player = player
        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            guard item.status == .failed else { return }
            NSLog("[SignatureMV] 播放失败: %@", item.error?.localizedDescription ?? "unknown")
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let size = NSSize(width: 480, height: 270)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        content.layer?.cornerRadius = 16
        content.layer?.masksToBounds = true
        let playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspect
        playerLayer.frame = content.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        content.layer?.addSublayer(playerLayer)
        let caption = NSTextField(labelWithString: "MV")
        caption.font = .systemFont(ofSize: 12, weight: .semibold)
        caption.textColor = .white
        caption.frame = NSRect(x: 14, y: 10, width: 80, height: 18)
        content.addSubview(caption)
        panel.contentView = content
        self.panel = panel
        self.playerLayer = playerLayer
    }

    private func show() {
        guard let panel else { return }
        if panel.isVisible { return }
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 28, y: visible.minY + 28))
        }
        panel.orderFrontRegardless()
    }

    private func hide() {
        guard visibleStart != nil || panel?.isVisible == true else { return }
        visibleStart = nil
        player?.pause()
        panel?.orderOut(nil)
    }
}
