import AppKit
import AVFoundation

/// Test playback for FIRESTARTER. The local clip starts when the song reaches 1:30.
@MainActor
final class SignatureMVClipPlayer {
    private struct Moment {
        let titleHints: [String]
        let clipURL: URL
        /// Song position where the clip appears.
        let audioStart: Double

        func matchesTitle(_ title: String) -> Bool {
            let key = Self.normalize(title)
            return titleHints.contains { key.contains($0) }
        }

        private static func normalize(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
        }
    }

    private static let moments = [
        Moment(
            titleHints: ["firestarter", "파이어스타터"],
            clipURL: URL(fileURLWithPath: "/Users/lzz/Downloads/v0300fg10000dbb3kq7og65i3fc40bgg.MP4"),
            audioStart: 90
        )
    ]

    private var panel: NSPanel?
    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var streamURL: URL?
    private var clipDuration = 33.7
    private var visibleStart: Double?
    private var seeking = false
    private var lastSeekAt = 0.0

    var isShowingVideo: Bool { panel?.isVisible == true }

    func prepare(trackID _: String?, title: String) {
        stop()
        guard let moment = Self.moments.first(where: { $0.matchesTitle(title) }) else { return }
        let url = moment.clipURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("[SignatureMV] 测试片段不存在: %@", url.path)
            return
        }
        streamURL = url
        install(url)
        NSLog("[SignatureMV] FIRESTARTER 使用本地测试片段")
    }

    func stop() {
        visibleStart = nil
        seeking = false
        streamURL = nil
        statusObservation = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        panel?.orderOut(nil)
    }

    func tick(title: String, time: Double, playing: Bool, lines _: [TimedLyric]) {
        guard streamURL != nil, let moment = Self.moments.first(where: { $0.matchesTitle(title) }),
              time >= moment.audioStart, time < moment.audioStart + clipDuration else {
            hide()
            return
        }
        let target = time - moment.audioStart
        show()
        guard let player else { return }
        if !playing {
            player.pause()
            return
        }
        let actual = player.currentTime().seconds
        let entered = visibleStart != moment.audioStart
        let drifted = !actual.isFinite || abs(actual - target) > 0.75
        let now = ProcessInfo.processInfo.systemUptime
        if entered || (drifted && !seeking && now - lastSeekAt > 1) {
            visibleStart = moment.audioStart
            seeking = true
            lastSeekAt = now
            let seekTime = CMTime(seconds: max(0, target), preferredTimescale: 600)
            let tolerance = CMTime(seconds: 0.2, preferredTimescale: 600)
            player.seek(to: seekTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
                Task { @MainActor in
                    self?.seeking = false
                    self?.player?.play()
                }
            }
            if entered {
                NSLog("[SignatureMV] 进入标志片段，音频 %.1f 秒，片段 %.1f 秒", time, target)
            }
        } else if player.rate == 0 {
            player.play()
        }
    }

    private func install(_ url: URL) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = self.player ?? AVPlayer()
        player.replaceCurrentItem(with: item)
        player.isMuted = true
        player.volume = 0
        self.player = player
        ensurePanel()
        playerLayer?.player = player
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .readyToPlay {
                let seconds = item.duration.seconds
                if seconds.isFinite, seconds > 0 {
                    Task { @MainActor in self?.clipDuration = seconds }
                }
            } else if item.status == .failed {
                NSLog("[SignatureMV] 播放失败: %@", item.error?.localizedDescription ?? "unknown")
            }
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let size = NSSize(width: 640, height: 296)
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
