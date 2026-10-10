import AppKit
import AVFoundation
import CryptoKit
import MetalKit
#if SWIFT_PACKAGE
import RealtimeDSP
import YAMNetMac
#endif

private func bundledResource(_ name: String, _ ext: String) -> URL? {
#if SWIFT_PACKAGE
    Bundle.module.url(forResource: name, withExtension: ext)
#else
    Bundle.main.url(forResource: name, withExtension: ext)
#endif
}

struct VisualAudio {
    var time: Float
    var bass: Float
    var mid: Float
    var treble: Float
    var aspectRatio: Float
    var guitar: Float
    var piano: Float
    var drums: Float
    var playbackTime: Float
    var electricGuitarConfidence: Float
    var vocal: Float
    var guitarPeak: Float
    var playing: Float
}

struct DesktopMoodColors {
    var atmosphere = SIMD4<Float>(1.0, 0.88, 0.72, 1)
    var volumetricBeam = SIMD4<Float>(1.0, 0.85, 0.65, 1)
    var topLightArray = SIMD4<Float>(0.3, 0.6, 1.0, 1)
    var laserFanBlue = SIMD4<Float>(0.25, 0.55, 1.0, 1)
    var laserFanGreen = SIMD4<Float>(0.35, 1.0, 0.45, 1)
    var rotatingBeam = SIMD4<Float>(1.0, 0.4, 0.8, 1)
    var rotatingBeamExtra = SIMD4<Float>(1.0, 0.5, 0.9, 1)
    var edgeLight = SIMD4<Float>(1.0, 0.75, 0.35, 1)
    var coronaFilaments = SIMD4<Float>(0.9, 0.6, 0.8, 1)
    var pulseRing = SIMD4<Float>(0.8, 0.3, 1.0, 1)

    init() {}

    init(json: [String: Any]) {
        self.init()
        func color(_ key: String, _ fallback: SIMD4<Float>) -> SIMD4<Float> {
            guard let values = json[key] as? [NSNumber], values.count == 3 else { return fallback }
            return SIMD4<Float>(min(max(values[0].floatValue, 0), 1),
                                min(max(values[1].floatValue, 0), 1),
                                min(max(values[2].floatValue, 0), 1), 1)
        }
        atmosphere = color("atmosphere", atmosphere)
        volumetricBeam = color("volumetricBeam", volumetricBeam)
        topLightArray = color("topLightArray", topLightArray)
        laserFanBlue = color("laserFanBlue", laserFanBlue)
        laserFanGreen = color("laserFanGreen", laserFanGreen)
        rotatingBeam = color("rotatingBeam", rotatingBeam)
        rotatingBeamExtra = color("rotatingBeamExtra", rotatingBeamExtra)
        edgeLight = color("edgeLight", edgeLight)
        coronaFilaments = color("coronaFilaments", coronaFilaments)
        pulseRing = color("pulseRing", pulseRing)
    }
}

@MainActor
final class DesktopMoodService {
    static let shared = DesktopMoodService()
    private(set) var colors = DesktopMoodColors()
    private var generation = 0
    private let defaults = UserDefaults.standard

    var baseURL: String { defaults.string(forKey: "DesktopMood.baseURL") ?? "https://api.deepseek.com" }
    var model: String { defaults.string(forKey: "DesktopMood.model") ?? "deepseek-chat" }
    var apiKey: String { defaults.string(forKey: "DesktopMood.apiKey") ?? "" }

    func configure(baseURL: String, model: String, apiKey: String) {
        defaults.set(baseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "DesktopMood.baseURL")
        defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "DesktopMood.model")
        defaults.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "DesktopMood.apiKey")
    }

    func analyze(title: String, artist: String?) {
        generation += 1
        let requestGeneration = generation
        colors = DesktopMoodColors()
        guard !apiKey.isEmpty else { return }
        let cacheKey = "DesktopMood.colors." + SHA256.hash(data: Data("\(model)|\(title)|\(artist ?? "")".utf8)).map { String(format: "%02x", $0) }.joined()
        if let cached = defaults.dictionary(forKey: cacheKey) {
            colors = DesktopMoodColors(json: cached)
            return
        }
        var components = URLComponents(string: baseURL)
        guard components?.scheme?.lowercased() == "https", components?.host != nil else { return }
        if components?.path.isEmpty == true || components?.path == "/" || components?.path == "/v1" {
            components?.path = "/v1/chat/completions"
        }
        guard let url = components?.url else { return }
        let prompt = "请为歌曲《\(title)》\(artist.map { " - \($0)" } ?? "")设计情绪氛围光。只返回 JSON 对象，包含 colors 对象，字段 atmosphere、volumetricBeam、topLightArray、laserFanBlue、laserFanGreen、rotatingBeam、rotatingBeamExtra、edgeLight、coronaFilaments、pulseRing；每个字段为 0 到 1 的 RGB 三元素数组。让颜色贴合歌曲情绪，主色与鼓点强调色有清楚区别。深空蜂巢的吉他颜色波依次使用 pulseRing、coronaFilaments、volumetricBeam、rotatingBeam；请让这四种颜色形成符合歌曲情绪的色组，彼此有清晰区分，并避免所有歌曲都落在同一组紫/蓝色。"
        let payload: [String: Any] = ["model": model, "messages": [
            ["role": "system", "content": "你是音乐舞台灯光设计师。只输出有效 JSON。"],
            ["role": "user", "content": prompt]
        ], "temperature": 0.7, "max_tokens": 600]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 25
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = envelope["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let content = message["content"] as? String,
                      let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"),
                      let json = try JSONSerialization.jsonObject(with: Data(content[start...end].utf8)) as? [String: Any],
                      let colorJSON = json["colors"] as? [String: Any] else { return }
                guard requestGeneration == generation else { return }
                defaults.set(colorJSON, forKey: cacheKey)
                colors = DesktopMoodColors(json: colorJSON)
            } catch {
                NSLog("[DesktopMood] 配色请求失败：%@", error.localizedDescription)
            }
        }
    }
}

struct DesktopDotParticle {
    var position: SIMD4<Float>
    var pointSize: Float
    var color: SIMD3<Float>
    var opacity: Float
    var height: Float
}

enum DesktopBackgroundEffect: Int {
    case aurora = 0
    case tyndall = 1
    case coverDots = 2
    case cellularHive = 3

    var title: String {
        switch self {
        case .aurora: "极光波纹"
        case .tyndall: "丁达尔光束"
        case .coverDots: "封面点阵"
        case .cellularHive: "深空蜂巢"
        }
    }
    static var saved: DesktopBackgroundEffect {
        let stored = DesktopBackgroundEffect(rawValue: UserDefaults.standard.integer(forKey: "desktopBackgroundEffect")) ?? .aurora
        return stored
    }
}

@main
@MainActor
struct MacDesktopPlayerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var wallpaper: WallpaperController?
    private var controls: NSWindow?
    private weak var controlsView: ControlsView?
    private let audio = LocalAudioPlayer()
    private let library = MusicLibraryStore()
    private var statusBarPlayer: StatusBarPlayerController?
    private var controlsAwaitingActivation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        wallpaper = WallpaperController(audio: audio, library: library, onOpenControls: { [weak self] in
            self?.showControls()
        })
        wallpaper?.show()
        buildControls()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func buildControls() {
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false
        )
        panel.title = "桌面音乐"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 1040, height: 700)
        let content = ControlsView(audio: audio, library: library, onBackgroundEffectChange: { [weak self] effect in
            self?.wallpaper?.setEffect(effect)
        }, onArtworkChange: { [weak self] image in
            self?.wallpaper?.setArtwork(image)
        })
        panel.contentView = content
        controlsView = content
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.setFrame(NSRect(x: 0, y: 0, width: 1040, height: 700), display: true, animate: true)
        panel.center()
        controls = panel
        statusBarPlayer = StatusBarPlayerController(audio: audio, library: library, onOpenControls: { [weak self] in
            self?.showControls()
        })

        let menu = NSMenu()
        let appMenu = NSMenuItem()
        menu.addItem(appMenu)
        let submenu = NSMenu()
        submenu.addItem(withTitle: "显示控制器", action: #selector(showControls), keyEquivalent: "o")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "退出桌面音乐", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.submenu = submenu
        NSApplication.shared.mainMenu = menu
    }

    @objc private func showControls() {
        guard let controls else { return }
        controlsAwaitingActivation = !NSApplication.shared.isActive
        NSApplication.shared.unhide(nil)
        if controls.isMiniaturized { controls.deminiaturize(nil) }
        NSApplication.shared.activate(ignoringOtherApps: true)
        controls.makeKeyAndOrderFront(nil)
        controls.orderFrontRegardless()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard controlsAwaitingActivation else { return }
        controlsAwaitingActivation = false
        controls?.makeKeyAndOrderFront(nil)
        controls?.orderFrontRegardless()
    }
}

@MainActor
final class StatusBarPlayerController: NSObject, NSPopoverDelegate {
    private let audio: LocalAudioPlayer
    private let library: MusicLibraryStore
    private let onOpenControls: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var opensControlsAfterClose = false

    init(audio: LocalAudioPlayer, library: MusicLibraryStore, onOpenControls: @escaping () -> Void) {
        self.audio = audio
        self.library = library
        self.onOpenControls = onOpenControls
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "音乐播放控制")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 252)
        popover.contentViewController = StatusBarPlayerViewController(audio: audio, library: library, onOpenControls: { [weak self] in
            guard let self else { return }
            self.opensControlsAfterClose = true
            self.popover.performClose(nil)
        })
    }

    func popoverDidClose(_ notification: Notification) {
        guard opensControlsAfterClose else { return }
        opensControlsAfterClose = false
        DispatchQueue.main.async { [weak self] in self?.onOpenControls() }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
}

@MainActor
final class StatusBarPlayerViewController: NSViewController {
    private let audio: LocalAudioPlayer
    private let library: MusicLibraryStore
    private let titleLabel = NSTextField(labelWithString: "尚未播放")
    private let artistLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let durationLabel = NSTextField(labelWithString: "0:00")
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let playButton = NSButton()
    private let openControlsButton = NSButton()
    private let artworkView = NSImageView()
    private var timer: Timer?
    private var artworkTask: Task<Void, Never>?
    private var artworkTrackPath: String?
    private let onOpenControls: () -> Void

    init(audio: LocalAudioPlayer, library: MusicLibraryStore, onOpenControls: @escaping () -> Void) {
        self.audio = audio
        self.library = library
        self.onOpenControls = onOpenControls
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 252))
        root.appearance = NSAppearance(named: .darkAqua)
        root.wantsLayer = true
        root.layer?.cornerRadius = 22
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.17, alpha: 1).cgColor
        root.layer?.borderWidth = 0.5
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        artworkView.imageScaling = .scaleProportionallyUpOrDown
        artworkView.wantsLayer = true
        artworkView.layer?.contentsGravity = .resizeAspectFill
        artworkView.translatesAutoresizingMaskIntoConstraints = false
        let overlay = NSView()
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
        overlay.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(artworkView)
        root.addSubview(overlay)
        NSLayoutConstraint.activate([
            artworkView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            artworkView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            artworkView.topAnchor.constraint(equalTo: root.topAnchor),
            artworkView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: root.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        artistLabel.font = .systemFont(ofSize: 11, weight: .medium)
        artistLabel.textColor = NSColor.white.withAlphaComponent(0.76)
        artistLabel.alignment = .center
        let metadata = NSStackView(views: [titleLabel, artistLabel])
        metadata.orientation = .vertical
        metadata.alignment = .centerX
        metadata.spacing = 4
        metadata.widthAnchor.constraint(equalToConstant: 312).isActive = true

        let times = NSStackView(views: [timeLabel, slider, durationLabel])
        times.orientation = .horizontal
        times.alignment = .centerY
        times.spacing = 8
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        timeLabel.textColor = NSColor.white.withAlphaComponent(0.76)
        durationLabel.textColor = NSColor.white.withAlphaComponent(0.76)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(seek(_:))
        timeLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true
        durationLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true
        times.widthAnchor.constraint(equalToConstant: 312).isActive = true
        times.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let previous = transportButton("backward.end.fill", action: #selector(previousTrack))
        playButton.target = self
        playButton.action = #selector(togglePlayback)
        playButton.bezelStyle = .regularSquare
        playButton.isBordered = false
        playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "播放")
        playButton.imagePosition = .imageOnly
        playButton.contentTintColor = .white
        playButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        playButton.heightAnchor.constraint(equalToConstant: 42).isActive = true
        let next = transportButton("forward.end.fill", action: #selector(nextTrack))
        let buttons = NSStackView(views: [previous, playButton, next])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 34
        buttons.distribution = .gravityAreas
        buttons.heightAnchor.constraint(equalToConstant: 42).isActive = true

        openControlsButton.title = "打开控制台"
        openControlsButton.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        openControlsButton.imagePosition = .imageLeading
        openControlsButton.imageHugsTitle = true
        openControlsButton.font = .systemFont(ofSize: 12, weight: .semibold)
        openControlsButton.contentTintColor = NSColor.white.withAlphaComponent(0.92)
        openControlsButton.bezelStyle = .regularSquare
        openControlsButton.isBordered = false
        openControlsButton.wantsLayer = true
        openControlsButton.layer?.cornerRadius = 8
        openControlsButton.layer?.backgroundColor = NSColor.clear.cgColor
        openControlsButton.target = self
        openControlsButton.action = #selector(openControls)
        openControlsButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let stack = NSStackView(views: [metadata, times, buttons, openControlsButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            buttons.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
            openControlsButton.centerXAnchor.constraint(equalTo: stack.centerXAnchor)
        ])
        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateState()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateState() }
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        timer?.invalidate()
        timer = nil
        artworkTask?.cancel()
    }

    private func transportButton(_ symbol: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.contentTintColor = NSColor.white.withAlphaComponent(0.84)
        button.wantsLayer = true
        button.layer?.cornerRadius = 12
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

    private func updateState() {
        titleLabel.stringValue = audio.currentTitle
        artistLabel.stringValue = audio.currentArtist ?? ""
        let length = audio.duration
        slider.maxValue = max(length, 1)
        if !slider.isHighlighted { slider.doubleValue = min(audio.currentPlaybackTime, length) }
        timeLabel.stringValue = Self.timeString(audio.currentPlaybackTime)
        durationLabel.stringValue = Self.timeString(length)
        playButton.image = NSImage(systemSymbolName: audio.isPlaying ? "pause.fill" : "play.fill", accessibilityDescription: audio.isPlaying ? "暂停" : "播放")
        let trackPath = audio.currentURL?.path
        guard trackPath != artworkTrackPath else { return }
        artworkTrackPath = trackPath
        artworkTask?.cancel()
        artworkView.image = nil
        guard let trackPath, let track = library.tracks.first(where: { $0.path == trackPath }) else { return }
        artworkTask = Task { [weak self, library] in
            let image = await library.artwork(for: track)
            guard !Task.isCancelled, let self, self.artworkTrackPath == trackPath else { return }
            self.artworkView.layer?.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }

    private static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = max(0, Int(seconds))
        return "\(value / 60):\(String(format: "%02d", value % 60))"
    }

    @objc private func seek(_ sender: NSSlider) { audio.seek(to: sender.doubleValue) }
    @objc private func openControls() { onOpenControls() }
    @objc private func togglePlayback() { audio.togglePlayback(); updateState() }
    @objc private func previousTrack() { _ = audio.playAdjacentTrack(-1); updateState() }
    @objc private func nextTrack() { _ = audio.playAdjacentTrack(1); updateState() }
}

@MainActor
final class PlaylistDrawerController {
    private let audio: LocalAudioPlayer
    private let library: MusicLibraryStore
    private let onOpenControls: () -> Void
    private let panel = PlaylistDrawerPanel(contentRect: NSRect(x: 0, y: 0, width: 56, height: 88),
                                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var drawerView: PlaylistDrawerView?
    private var expanded = false
    private var transitionGeneration = 0

    init(audio: LocalAudioPlayer, library: MusicLibraryStore, onOpenControls: @escaping () -> Void) {
        self.audio = audio
        self.library = library
        self.onOpenControls = onOpenControls
    }

    func show(on screen: NSScreen) {
        panel.setFrame(collapsedFrame(on: screen), display: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        let content = PlaylistDrawerView(audio: audio, library: library,
            onOpenControls: onOpenControls,
            onExpansionChange: { [weak self] expanded in self?.setExpanded(expanded, screen: screen) })
        drawerView = content
        panel.contentView = content
        panel.orderFrontRegardless()
    }

    private func collapsedFrame(on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.minX, y: screen.frame.midY - 44, width: 56, height: 88)
    }

    private func setExpanded(_ expanded: Bool, screen: NSScreen) {
        guard self.expanded != expanded else { return }
        self.expanded = expanded
        transitionGeneration += 1
        let generation = transitionGeneration
        if expanded {
            // Keep the window stationary during the slide so text and blur are never squeezed.
            panel.setFrame(NSRect(x: screen.frame.minX, y: screen.frame.minY,
                                  width: 380, height: screen.frame.height), display: true)
            drawerView?.layoutSubtreeIfNeeded()
        }
        drawerView?.setExpanded(expanded) { [weak self] in
            guard let self, self.transitionGeneration == generation else { return }
            if !expanded { self.panel.setFrame(self.collapsedFrame(on: screen), display: true) }
        }
    }
}

@MainActor
final class PlaylistDrawerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DrawerClipView: NSClipView {
    override var isFlipped: Bool { true }
}

@MainActor
final class DrawerSongStack: NSStackView {
    override var isFlipped: Bool { true }
}

@MainActor
final class PlaylistDrawerView: NSView, NSSearchFieldDelegate {
    private let audio: LocalAudioPlayer
    private let library: MusicLibraryStore
    private let onOpenControls: () -> Void
    private let onExpansionChange: (Bool) -> Void
    private var expanded = false
    private let surface = NSView()
    private var animating = false
    private let arrowButton = NSButton()
    private let heading = NSTextField(labelWithString: "歌曲")
    private let searchField = NSSearchField()
    private let songStack = DrawerSongStack()
    private let scrollView = NSScrollView()
    private let controlsButton = NSButton(title: "打开控制面板", target: nil, action: nil)
    private var expandedVerticalConstraints: [NSLayoutConstraint] = []
    private var libraryObserver: NSObjectProtocol?

    init(audio: LocalAudioPlayer, library: MusicLibraryStore, onOpenControls: @escaping () -> Void,
         onExpansionChange: @escaping (Bool) -> Void) {
        self.audio = audio
        self.library = library
        self.onOpenControls = onOpenControls
        self.onExpansionChange = onExpansionChange
        super.init(frame: NSRect(x: 0, y: 0, width: 56, height: 88))
        // Auto Layout evaluates the surface's child constraints as soon as the
        // panel is ordered front. Give it its real drawer width before that
        // first layout pass (layout() will update the height afterward).
        surface.frame = NSRect(x: -324, y: 0, width: 324, height: bounds.height)
        wantsLayer = true
        layer?.masksToBounds = true
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 16
        surface.layer?.masksToBounds = true
        surface.layer?.borderWidth = 0.5
        surface.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        surface.appearance = NSAppearance(named: .darkAqua)
        surface.isHidden = true
        addSubview(surface)

        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.alphaValue = 0.42
        glass.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            glass.topAnchor.constraint(equalTo: surface.topAnchor),
            glass.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])

        arrowButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "展开歌曲列表")
        arrowButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        arrowButton.bezelStyle = .regularSquare
        arrowButton.isBordered = false
        arrowButton.focusRingType = .none
        arrowButton.contentTintColor = .white
        arrowButton.target = self
        arrowButton.action = #selector(toggleExpanded)
        addSubview(arrowButton)

        heading.font = .systemFont(ofSize: 19, weight: .semibold)
        heading.textColor = .white
        heading.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(heading)
        searchField.placeholderString = "搜索歌曲 / 歌手"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(searchField)

        songStack.orientation = .vertical
        songStack.alignment = .leading
        songStack.spacing = 8
        songStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView = DrawerClipView()
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = songStack
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(scrollView)
        controlsButton.bezelStyle = .rounded
        controlsButton.target = self
        controlsButton.action = #selector(openControls)
        controlsButton.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(controlsButton)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
            scrollView.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -12),
            songStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            songStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            songStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            controlsButton.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            controlsButton.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
        ])
        expandedVerticalConstraints = [
            heading.topAnchor.constraint(equalTo: surface.topAnchor, constant: 34),
            searchField.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 14),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),
            scrollView.bottomAnchor.constraint(equalTo: controlsButton.topAnchor, constant: -16),
            controlsButton.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -28),
            controlsButton.heightAnchor.constraint(equalToConstant: 34)
        ]
        libraryObserver = NotificationCenter.default.addObserver(forName: .desktopMusicLibraryChanged,
            object: library, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if self?.expanded == true { self?.refreshRows() } }
            }
    }

    required init?(coder: NSCoder) { nil }
    deinit { if let libraryObserver { NotificationCenter.default.removeObserver(libraryObserver) } }

    override func layout() {
        super.layout()
        guard !animating else { return }
        surface.frame = NSRect(x: expanded ? 0 : -324, y: 0, width: 324, height: bounds.height)
        arrowButton.frame = NSRect(x: expanded ? 324 : 0, y: bounds.midY - 44, width: 56, height: 88)
    }

    func setExpanded(_ expanded: Bool, completion: @escaping () -> Void) {
        if expanded {
            surface.isHidden = false
            refreshRows()
            NSLayoutConstraint.activate(expandedVerticalConstraints)
        }
        layoutSubtreeIfNeeded()
        self.expanded = expanded
        animating = true
        arrowButton.image = NSImage(systemSymbolName: expanded ? "chevron.left" : "chevron.right",
                                    accessibilityDescription: expanded ? "收起歌曲列表" : "展开歌曲列表")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.34
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.25, 1)
            surface.animator().setFrameOrigin(NSPoint(x: expanded ? 0 : -324, y: 0))
            arrowButton.animator().setFrameOrigin(NSPoint(x: expanded ? 324 : 0, y: bounds.midY - 44))
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.animating = false
                self?.needsLayout = true
                if self?.expanded == false {
                    self?.surface.isHidden = true
                    NSLayoutConstraint.deactivate(self?.expandedVerticalConstraints ?? [])
                }
                completion()
            }
        }
    }

    private func refreshRows() {
        let needle = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        songStack.arrangedSubviews.forEach { songStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let songs = library.tracks.filter {
            needle.isEmpty || $0.title.localizedCaseInsensitiveContains(needle)
                || ($0.artist?.localizedCaseInsensitiveContains(needle) ?? false)
        }
        heading.stringValue = "歌曲 · \(library.tracks.count)"
        for track in songs {
            let row = PlaylistDrawerRow(title: track.title, artist: track.artist,
                onSelect: { [weak self] in
                    guard let self else { return }
                    self.audio.setPlaybackQueue(self.library.tracks, currentID: track.id)
                    self.audio.play(url: URL(fileURLWithPath: track.path), title: track.title, artist: track.artist)
                }, onDelete: { [weak self] in
                    guard let self else { return }
                    self.library.removeFromLibrary(track.id)
                    if let current = self.library.tracks.first(where: { $0.path == self.audio.currentURL?.path }) {
                        self.audio.setPlaybackQueue(self.library.tracks, currentID: current.id)
                    } else if self.audio.currentURL?.path == track.path {
                        self.audio.stop()
                    }
                })
            songStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: songStack.widthAnchor).isActive = true
        }
        if songs.isEmpty {
            let empty = NSTextField(labelWithString: needle.isEmpty ? "暂无歌曲，请从控制面板导入" : "没有匹配的歌曲")
            empty.textColor = .white.withAlphaComponent(0.65)
            songStack.addArrangedSubview(empty)
        }
    }

    func controlTextDidChange(_ notification: Notification) { refreshRows() }
    @objc private func toggleExpanded() { onExpansionChange(!expanded) }
    @objc private func openControls() { onOpenControls() }
}

@MainActor
final class PlaylistDrawerRow: NSView {
    private let onSelect: () -> Void
    private let onDelete: () -> Void
    private let foreground = NSView()

    init(title: String, artist: String?, onSelect: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onDelete = onDelete
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 55))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 55).isActive = true

        foreground.wantsLayer = true
        foreground.layer?.cornerRadius = 12
        foreground.layer?.masksToBounds = true
        foreground.layer?.borderWidth = 0.5
        foreground.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        foreground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(foreground)
        NSLayoutConstraint.activate([
            foreground.leadingAnchor.constraint(equalTo: leadingAnchor),
            foreground.trailingAnchor.constraint(equalTo: trailingAnchor),
            foreground.topAnchor.constraint(equalTo: topAnchor),
            foreground.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.alphaValue = 0.38
        glass.translatesAutoresizingMaskIntoConstraints = false
        foreground.addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: foreground.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: foreground.trailingAnchor),
            glass.topAnchor.constraint(equalTo: foreground.topAnchor),
            glass.bottomAnchor.constraint(equalTo: foreground.bottomAnchor)
        ])
        let button = NSButton()
        button.title = artist.map { title + "   ·   " + $0 } ?? title
        button.font = .systemFont(ofSize: 14, weight: .medium)
        button.contentTintColor = .white
        button.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "播放")
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.lineBreakMode = .byTruncatingTail
        button.isBordered = false
        button.focusRingType = .none
        button.target = self
        button.action = #selector(selectPressed)
        button.translatesAutoresizingMaskIntoConstraints = false
        foreground.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: foreground.leadingAnchor, constant: 12),
            button.trailingAnchor.constraint(equalTo: foreground.trailingAnchor, constant: -12),
            button.topAnchor.constraint(equalTo: foreground.topAnchor),
            button.bottomAnchor.constraint(equalTo: foreground.bottomAnchor)
        ])

        let contextMenu = NSMenu(title: "歌曲操作")
        let deleteItem = NSMenuItem(title: "删除", action: #selector(deletePressed), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除歌曲")
        contextMenu.addItem(deleteItem)
        // The button and the exposed glass margins both use the same native context menu.
        menu = contextMenu
        foreground.menu = contextMenu
        glass.menu = contextMenu
        button.menu = contextMenu
    }

    required init?(coder: NSCoder) { nil }

    @objc private func selectPressed() { onSelect() }
    @objc private func deletePressed() { onDelete() }
}

@MainActor
final class WallpaperController {
    private let audio: LocalAudioPlayer
    private let library: MusicLibraryStore
    private let onOpenControls: () -> Void
    private var windows: [WallpaperPanel] = []
    private var playlistDrawers: [PlaylistDrawerController] = []
    private(set) var effect = DesktopBackgroundEffect.saved

    init(audio: LocalAudioPlayer, library: MusicLibraryStore, onOpenControls: @escaping () -> Void) {
        self.audio = audio
        self.library = library
        self.onOpenControls = onOpenControls
    }

    func show() {
        for screen in NSScreen.screens {
            let view = DesktopMetalView(frame: NSRect(origin: .zero, size: screen.frame.size), audio: audio, effect: effect)
            let window = WallpaperPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen
            )
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            // NSPanel defaults to hiding when its app deactivates. This panel is
            // the desktop wallpaper and must keep rendering while Finder owns focus.
            window.hidesOnDeactivate = false
            // Match the established live-wallpaper layer: above the static wallpaper, below Finder icons.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
            let drawer = PlaylistDrawerController(audio: audio, library: library, onOpenControls: onOpenControls)
            drawer.show(on: screen)
            playlistDrawers.append(drawer)
        }
    }

    func setEffect(_ effect: DesktopBackgroundEffect) {
        self.effect = effect
        UserDefaults.standard.set(effect.rawValue, forKey: "desktopBackgroundEffect")
        windows.compactMap { $0.contentView as? DesktopMetalView }.forEach { $0.setEffect(effect) }
    }

    func setArtwork(_ image: NSImage?) {
        windows.compactMap { $0.contentView as? DesktopMetalView }.forEach { $0.setArtwork(image) }
    }
}

@MainActor
final class WallpaperPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DesktopMetalView: MTKView {
    private var renderer: DesktopRenderer?
    private let lyricOverlay = DesktopLyricsOverlay()

    init(frame: NSRect, audio: LocalAudioPlayer, effect: DesktopBackgroundEffect) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("此 Mac 不支持 Metal")
        }
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        preferredFramesPerSecond = 60
        isPaused = false
        enableSetNeedsDisplay = false
        clearColor = MTLClearColor(red: 0.006, green: 0.009, blue: 0.025, alpha: 1)
        lyricOverlay.frame = bounds
        lyricOverlay.autoresizingMask = [.width, .height]
        lyricOverlay.isHidden = true
        addSubview(lyricOverlay)
        renderer = DesktopRenderer(view: self, audio: audio, effect: effect)
        delegate = renderer
    }

    func setEffect(_ effect: DesktopBackgroundEffect) {
        preferredFramesPerSecond = 60
        renderer?.setEffect(effect)
    }
    func setArtwork(_ image: NSImage?) { renderer?.setArtwork(image) }

    fileprivate func hideFlatLyrics() { lyricOverlay.isHidden = true }

    fileprivate func setLyrics(_ frame: DesktopLyricsFrame, highlight: NSColor) {
        lyricOverlay.update(frame, highlight: highlight)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

@MainActor
final class DesktopRenderer: NSObject, MTKViewDelegate {
    private weak var view: MTKView?
    private let audio: LocalAudioPlayer
    private let queue: MTLCommandQueue
    private let device: MTLDevice
    private let library: MTLLibrary
    private var effectRenderer: any DesktopEffectRenderer
    private let coverRecordRenderer: CoverDotDesktopEffectRenderer
    private var guitarSurgeRenderer: GuitarSurgeOverlayRenderer
    private var currentArtwork: NSImage?
    private let startedAt = ProcessInfo.processInfo.systemUptime

    init(view: MTKView, audio: LocalAudioPlayer, effect: DesktopBackgroundEffect) {
        self.view = view
        self.audio = audio
        guard let device = view.device,
              let queue = device.makeCommandQueue() else {
            fatalError("无法初始化桌面 Metal 渲染器")
        }
#if SWIFT_PACKAGE
        let shaderNames = ["Aurora", "Tyndall", "CoverDotMatrix", "CellularHive"]
        let shaderSources = shaderNames.compactMap { name -> String? in
            guard let url = bundledResource(name, "metal") else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        guard shaderSources.count == shaderNames.count,
              let library = try? device.makeLibrary(source: shaderSources.joined(separator: "\n"), options: nil) else {
            fatalError("无法加载桌面 Metal shader")
        }
#else
        guard let library = try? device.makeDefaultLibrary(bundle: .main) else {
            fatalError("无法加载 Xcode 编译的 Metal library")
        }
#endif
        self.device = device
        self.queue = queue
        self.library = library
        self.effectRenderer = DesktopEffectFactory.make(effect: effect, device: device, pixelFormat: view.colorPixelFormat, library: library)
        self.coverRecordRenderer = CoverDotDesktopEffectRenderer(device: device, pixelFormat: view.colorPixelFormat, library: library)
        self.guitarSurgeRenderer = GuitarSurgeOverlayRenderer(device: device, pixelFormat: view.colorPixelFormat, library: library)
        super.init()
    }

    func setEffect(_ effect: DesktopBackgroundEffect) {
        guard effectRenderer.effect != effect else { return }
        effectRenderer = DesktopEffectFactory.make(effect: effect, device: device, pixelFormat: view?.colorPixelFormat ?? .bgra8Unorm, library: library)
        effectRenderer.setArtwork(currentArtwork, device: device)
    }

    func setArtwork(_ image: NSImage?) {
        currentArtwork = image
        effectRenderer.setArtwork(image, device: device)
        coverRecordRenderer.setArtwork(image, device: device)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let values = audio.visualAudio(time: Float(ProcessInfo.processInfo.systemUptime - startedAt),
                                       aspectRatio: Float(view.drawableSize.width / max(view.drawableSize.height, 1)),
                                       isolatedInstruments: effectRenderer.effect == .tyndall)
        let squareCover = effectRenderer.effect == .coverDots
        let showCoverStage = squareCover || centerRecordVisible
        if let desktopView = view as? DesktopMetalView {
            let frame = audio.lyricsController.frame(at: Double(values.playbackTime),
                surface: showCoverStage ? .coverStage : .overlay, viewport: view.bounds.size)
            let accent = DesktopMoodService.shared.colors.pulseRing
            if showCoverStage {
                desktopView.hideFlatLyrics()
                coverRecordRenderer.setLyrics(frame)
            } else {
                desktopView.setLyrics(frame, highlight: NSColor(calibratedRed: CGFloat(accent.x), green: CGFloat(accent.y), blue: CGFloat(accent.z), alpha: 1))
            }
        }
        effectRenderer.draw(encoder: encoder, view: view, audio: values)
        guitarSurgeRenderer.draw(encoder: encoder, audio: values,
                                 enabled: audio.guitarSurgeEnabled && effectRenderer.effect != .tyndall,
                                 drumOverlayEnabled: true)
        if showCoverStage {
            coverRecordRenderer.draw(encoder: encoder, view: view, audio: values, squareCover: squareCover)
        }
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }

    private var centerRecordVisible: Bool {
        UserDefaults.standard.object(forKey: "desktopCenterRecordVisible") as? Bool ?? true
    }
}

private struct GuitarSurgeUniforms {
    var cyclePhase: Float
    var beatPhase: Float
    var bpm: Float
    var guitar: Float
    var drumPulse: Float
    var activity: Float
}

@MainActor
private final class GuitarSurgeOverlayRenderer {
    private let pipeline: MTLRenderPipelineState
    private var lastTime: Float = 0
    private var previousBass: Float = 0
    private var previousDrums: Float = 0
    private var previousGuitar: Float = 0
    private var lastBeatTime: Float = -10
    private var beatIntervals: [Float] = []
    private var beatPosition: Float = 0
    private var hasBeatAnchor = false
    private var lastPlaybackTime: Float = 0
    private var bpm: Float = 120
    private var beatPulse: Float = 0
    private var guitarActivity: Float = 0
    private var guitarWasActive = false

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, library: MTLLibrary) {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "DesktopGuitarSurgeOverlay"
        descriptor.vertexFunction = library.makeFunction(name: "guitarSurgeVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "guitarSurgeFragment")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            fatalError("无法创建吉他高潮灯光管线")
        }
        self.pipeline = pipeline
    }

    func draw(encoder: MTLRenderCommandEncoder, audio: VisualAudio, enabled: Bool, drumOverlayEnabled: Bool) {
        let now = audio.time
        let dt = lastTime > 0 ? min(max(now - lastTime, 0), 0.1) : 0
        lastTime = now
        guard dt > 0 else { return }
        if audio.playbackTime + 0.1 < lastPlaybackTime {
            beatIntervals.removeAll()
            bpm = 120
            beatPosition = 0
            hasBeatAnchor = false
            lastBeatTime = -10
            beatPulse = 0
            guitarActivity = 0
            guitarWasActive = false
        }
        lastPlaybackTime = audio.playbackTime

        let bass = min(max(audio.bass, 0), 1)
        let drums = min(max(audio.drums, 0), 1)
        let guitar = min(max(audio.guitar, 0), 1)
        let bassHit = bass > 0.18 && bass - previousBass > max(0.055, bass * 0.14)
        let drumHit = drums > 0.58 && drums - previousDrums > 0.10
        let beatHit = bassHit || drumHit
        if beatHit, now - lastBeatTime > 0.24 {
            let interval = now - lastBeatTime
            if interval >= 0.28 && interval <= 1.0 {
                let candidate = 60 / interval
                let normalized = candidate > 180 ? candidate / 2 : (candidate < 70 ? candidate * 2 : candidate)
                if normalized >= 70 && normalized <= 180 {
                    beatIntervals.append(normalized)
                    if beatIntervals.count > 6 { beatIntervals.removeFirst() }
                    let sorted = beatIntervals.sorted()
                    let median = sorted[sorted.count / 2]
                    bpm += (median - bpm) * 0.20
                }
            }
            lastBeatTime = now
            if hasBeatAnchor {
                beatPosition = (beatPosition + 1).truncatingRemainder(dividingBy: 4)
            } else {
                beatPosition = 0
                hasBeatAnchor = true
            }
            beatPulse = max(beatPulse, drumHit ? max(drums, 0.65) : max(bass, 0.45))
        }
        beatPulse *= exp(-8.5 * dt)
        previousBass = bass
        previousDrums = drums

        let electricClassified = audio.electricGuitarConfidence >= 0.28
        let spectralGuitar = min(max(audio.mid * 0.55 + audio.treble * 0.85, 0), 1)
        let guitarDrive = max(guitar, electricClassified ? spectralGuitar * audio.electricGuitarConfidence : 0)
        let guitarGate: Bool
        if guitarWasActive {
            guitarGate = guitarDrive >= (electricClassified ? 0.36 : 0.62) && audio.treble >= 0.18
        } else {
            guitarGate = (electricClassified && guitarDrive >= 0.50 && audio.treble >= 0.22)
                || (guitar >= 0.76 && audio.treble >= 0.28)
                || (audio.mid >= 0.42 && audio.treble >= 0.43)
        }
        guitarWasActive = guitarGate
        let target = enabled && guitarGate ? max(guitarDrive, 0.58) : 0
        let smoothing: Float = target > guitarActivity ? 7.0 : 2.2
        guitarActivity += (target - guitarActivity) * (1 - exp(-smoothing * dt))
        previousGuitar = guitar

        let overlayBeatPulse = drumOverlayEnabled ? beatPulse : 0
        guard enabled, guitarActivity > 0.015 || overlayBeatPulse > 0.02 else { return }
        let beatDuration = 60 / max(bpm, 70)
        let beatPhase = max(0, now - lastBeatTime) / beatDuration
        let normalizedBeatPhase = beatPhase.truncatingRemainder(dividingBy: 1)
        var uniforms = GuitarSurgeUniforms(
            cyclePhase: ((beatPosition + normalizedBeatPhase) / 4).truncatingRemainder(dividingBy: 1),
            beatPhase: normalizedBeatPhase,
            bpm: bpm,
            guitar: guitarDrive,
            drumPulse: overlayBeatPulse,
            activity: guitarActivity
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GuitarSurgeUniforms>.stride, index: 0)
        var mood = DesktopMoodService.shared.colors
        encoder.setFragmentBytes(&mood, length: MemoryLayout<DesktopMoodColors>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}

@MainActor
final class LocalAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let analyzerLock = NSLock()
    private var dsp: OpaquePointer?
    private var file: AVAudioFile?
    private var playbackQueue: [LocalTrack] = []
    private var currentTrackID: String?
    private var activePlaybackOffset: Double = 0
    private var pausedPlaybackTime: Double?
    private(set) var currentTitle = "尚未播放"
    private(set) var currentArtist: String?
    private(set) var levels: (Float, Float, Float) = (0, 0, 0)
    private(set) var currentURL: URL?
    let lyricsController = DesktopLyricsController()
    var electricGuitarConfidence: Float = 0
    private(set) var guitarSurgeEnabled = UserDefaults.standard.object(forKey: "desktopGuitarSurgeEnabled") == nil
        ? true : UserDefaults.standard.bool(forKey: "desktopGuitarSurgeEnabled")
    var onTrackStart: ((URL) -> Void)?
    private var stemCurves: [[Float]] = []
    private var vocalCurve: [Float] = []
    private var visualGuitarPeak: Float = 0
#if !SWIFT_PACKAGE
    private var trackGeneration = 0
    private var demucsEnabled = UserDefaults.standard.bool(forKey: "desktopHTDemucsEnabled")
#endif

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
    }

    var duration: Double {
        guard let file, file.processingFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    var currentPlaybackTime: Double {
        if let pausedPlaybackTime { return pausedPlaybackTime }
        guard currentURL != nil, let renderTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: renderTime), playerTime.sampleRate > 0 else {
            return min(activePlaybackOffset, duration)
        }
        return min(max(activePlaybackOffset + Double(playerTime.sampleTime) / playerTime.sampleRate, 0), duration)
    }

    var isPlaying: Bool { player.isPlaying }

    func setPlaybackQueue(_ tracks: [LocalTrack], currentID: String) {
        playbackQueue = tracks
        currentTrackID = currentID
    }

    func openAndPlay() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        playbackQueue = []
        currentTrackID = nil
        play(url: url)
    }

    func play(url: URL, title: String? = nil, artist: String? = nil) {
        do {
            stop()
            electricGuitarConfidence = 0
            vocalCurve = []
            visualGuitarPeak = 0
            let audioFile = try AVAudioFile(forReading: url)
            file = audioFile
            currentURL = url
            activePlaybackOffset = 0
            pausedPlaybackTime = nil
            currentTitle = title ?? url.deletingPathExtension().lastPathComponent
            currentArtist = artist
            lyricsController.load(for: url, title: title ?? url.deletingPathExtension().lastPathComponent, artist: artist)
            let format = audioFile.processingFormat
            analyzerLock.lock()
            if let dsp { AnalyzerDSP_Destroy(dsp) }
            dsp = AnalyzerDSP_Create(4096, 80, 50, 18_000, Float(format.sampleRate))
            analyzerLock.unlock()
            player.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                let values = self.analyze(buffer)
                Task { @MainActor [weak self] in
                    self?.levels = values
                }
            }
            if !engine.isRunning { try engine.start() }
            player.scheduleSegment(audioFile, startingFrame: 0, frameCount: AVAudioFrameCount(min(audioFile.length, Int64(UInt32.max))), at: nil)
            player.play()
#if !SWIFT_PACKAGE
            if demucsEnabled { startDemucsAnalysis(at: url) }
#endif
            onTrackStart?(url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func stop() {
        lyricsController.clear()
#if !SWIFT_PACKAGE
        trackGeneration += 1
        HTDemucsMacAnalyzer.shared().cancelCurrentAnalysis()
#endif
        player.stop()
        player.removeTap(onBus: 0)
        engine.stop()
        levels = (0, 0, 0)
        stemCurves = []
        vocalCurve = []
        currentURL = nil
        file = nil
        activePlaybackOffset = 0
        pausedPlaybackTime = nil
        currentTitle = "尚未播放"
        currentArtist = nil
    }

    func togglePlayback() {
        guard file != nil else { return }
        if player.isPlaying {
            let time = currentPlaybackTime
            player.pause()
            pausedPlaybackTime = time
        }
        else if !engine.isRunning {
            do { try engine.start(); pausedPlaybackTime = nil; player.play() } catch { NSAlert(error: error).runModal() }
        } else { pausedPlaybackTime = nil; player.play() }
    }

    func seek(to seconds: Double) {
        guard let file else { return }
        let target = min(max(seconds, 0), duration)
        let wasPlaying = player.isPlaying
        let format = file.processingFormat
        let frame = AVAudioFramePosition(target * format.sampleRate)
        guard frame < file.length else { return }
        let remaining = file.length - frame
        player.stop()
        activePlaybackOffset = target
        pausedPlaybackTime = wasPlaying ? nil : target
        player.scheduleSegment(file, startingFrame: frame, frameCount: AVAudioFrameCount(min(remaining, Int64(UInt32.max))), at: nil)
        if wasPlaying { player.play() }
    }

    @discardableResult func playAdjacentTrack(_ direction: Int) -> LocalTrack? {
        guard let currentTrackID, let index = playbackQueue.firstIndex(where: { $0.id == currentTrackID }) else { return nil }
        let nextIndex = index + direction
        guard playbackQueue.indices.contains(nextIndex) else { return nil }
        let track = playbackQueue[nextIndex]
        self.currentTrackID = track.id
        play(url: URL(fileURLWithPath: track.path), title: track.title, artist: track.artist)
        return track
    }

    func setHTDemucsEnabled(_ enabled: Bool) {
#if !SWIFT_PACKAGE
        demucsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "desktopHTDemucsEnabled")
        if enabled, let currentURL {
            startDemucsAnalysis(at: currentURL)
        } else {
            trackGeneration += 1
            HTDemucsMacAnalyzer.shared().cancelCurrentAnalysis()
            stemCurves = []
        }
#endif
    }

    func setGuitarSurgeEnabled(_ enabled: Bool) {
        guitarSurgeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "desktopGuitarSurgeEnabled")
    }

#if !SWIFT_PACKAGE
    private func startDemucsAnalysis(at url: URL) {
        trackGeneration += 1
        let generation = trackGeneration
        HTDemucsMacAnalyzer.shared().analyzeAudio(at: url) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.trackGeneration == generation, self.demucsEnabled else { return }
                guard let result,
                      let stems = result["stems"] as? [String: [String: Any]] else {
                    if let error { NSLog("[DemucsMac] 曲线分析失败，将继续使用实时 FFT: %@", error.localizedDescription) }
                    return
                }
                let names = ["guitar", "piano", "drums"]
                self.stemCurves = names.map { name in
                    (stems[name]?["frames"] as? [NSNumber] ?? []).map(\.floatValue)
                }
                NSLog("[DemucsMac] 吉他、钢琴、鼓分离曲线已就绪。")
            }
        }
    }
#endif

    func visualAudio(time: Float, aspectRatio: Float, isolatedInstruments: Bool = false) -> VisualAudio {
        let playbackTime = Float(currentPlaybackTime)
        func curve(_ index: Int) -> Float {
            guard stemCurves.indices.contains(index), !stemCurves[index].isEmpty else { return 0 }
            let position = max(0, playbackTime / 0.05)
            let low = min(Int(position), stemCurves[index].count - 1)
            let high = min(low + 1, stemCurves[index].count - 1)
            return stemCurves[index][low] + (stemCurves[index][high] - stemCurves[index][low]) * (position - Float(low))
        }
        let hasGuitarStem = stemCurves.indices.contains(0) && !stemCurves[0].isEmpty
        let fftGuitar = min(max(levels.1 * 0.55 + levels.2 * 0.85, 0), 1)
        let hasPianoStem = stemCurves.indices.contains(1) && !stemCurves[1].isEmpty
        let hasDrumStem = stemCurves.indices.contains(2) && !stemCurves[2].isEmpty
        let guitar = hasGuitarStem ? curve(0) : (isolatedInstruments ? 0 : fftGuitar)
        let electricClassified = electricGuitarConfidence >= 0.28
        let guitarDrive = max(guitar, electricClassified ? levels.1 * 0.55 + levels.2 * 0.85 : 0)
        let gate = electricClassified
            ? guitarDrive >= 0.50 && levels.2 >= 0.22
            : guitar >= 0.76 && levels.2 >= 0.28
        // A separated guitar crest can drive Tyndall even when the optional
        // full-screen guitar-surge overlay is switched off.
        let peakTarget: Float = hasGuitarStem
            ? (guitar >= 0.72 ? guitar : 0)
            : (isolatedInstruments ? 0 : (gate ? max(guitarDrive, 0.58) : 0))
        let peakRate: Float = peakTarget > visualGuitarPeak ? 7.0 : 2.2
        if isolatedInstruments && !hasGuitarStem {
            visualGuitarPeak = 0
        } else {
            visualGuitarPeak += (peakTarget - visualGuitarPeak) * (1 - exp(-peakRate / 60.0))
        }
        let vocal = vocalCurve.isEmpty ? 0 : interpolated(vocalCurve, at: playbackTime, interval: 0.48)
        return VisualAudio(time: time, bass: levels.0, mid: levels.1, treble: levels.2,
                           aspectRatio: aspectRatio, guitar: guitar,
                           piano: hasPianoStem ? curve(1) : (isolatedInstruments ? 0 : min(max(levels.1 * 0.55, 0), 1)),
                           drums: hasDrumStem ? curve(2) : levels.0, playbackTime: playbackTime,
                           electricGuitarConfidence: electricGuitarConfidence, vocal: vocal,
                           guitarPeak: visualGuitarPeak, playing: isPlaying ? 1 : 0)
    }

    private func interpolated(_ curve: [Float], at time: Float, interval: Float) -> Float {
        guard !curve.isEmpty else { return 0 }
        let position = max(0, time / interval)
        let low = min(Int(position), curve.count - 1)
        let high = min(low + 1, curve.count - 1)
        return curve[low] + (curve[high] - curve[low]) * (position - Float(low))
    }

    func setVocalCurve(_ values: [Float]) { vocalCurve = values }

    private func analyze(_ buffer: AVAudioPCMBuffer) -> (Float, Float, Float) {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return (0, 0, 0) }
        analyzerLock.lock()
        defer { analyzerLock.unlock() }
        guard let dsp else { return (0, 0, 0) }
        var bands = [Float](repeating: 0, count: 80)
        bands.withUnsafeMutableBufferPointer { output in
            AnalyzerDSP_ProcessChannel(
                dsp,
                channels[0],
                Int32(buffer.frameLength),
                0,
                5,
                Float(buffer.format.sampleRate),
                output.baseAddress
            )
        }
        // Match iOS Tyndall's exact FFT windows (0–9, 20–49, 50–79).
        // Mac DSP uses amplitudeLevel 5; scale by 5 to match iOS's 25.
        let low = bands[0..<10].reduce(0, +) / 10
        let mid = bands[20..<50].reduce(0, +) / 30
        let high = bands[50..<80].reduce(0, +) / 30
        return (low * 5, mid * 5, high * 5)
    }
}

@MainActor
private final class OnlineMusicResultsView: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 900, height: 150))
    private var results: [QQMusicSearchResult] = []
    var onDownload: ((String) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        contentView.drawsBackground = false
        hasVerticalScroller = true
        scrollerStyle = .overlay
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.rowHeight = 44
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.selectionHighlightStyle = .none
        table.columnAutoresizingStyle = .noColumnAutoresizing
        for (id, width) in [("song", CGFloat(600)), ("artist", CGFloat(180)), ("download", CGFloat(100))] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.width = width
            column.minWidth = id == "song" ? 120 : (id == "artist" ? 100 : 92)
            column.resizingMask = []
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        documentView = table
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }

    override func tile() {
        super.tile()
        fitColumnsToViewport()
    }

    private func fitColumnsToViewport() {
        let width = contentView.bounds.width
        guard width > 0, table.tableColumns.count == 3 else { return }
        let downloadWidth: CGFloat = 92
        let artistWidth = min(180, max(100, floor(width * 0.24)))
        let widths = [max(120, width - artistWidth - downloadWidth), artistWidth, downloadWidth]
        for (column, columnWidth) in zip(table.tableColumns, widths) where abs(column.width - columnWidth) > 0.5 {
            column.width = columnWidth
        }
        if abs(table.frame.width - width) > 0.5 {
            table.setFrameSize(NSSize(width: width, height: table.frame.height))
        }
    }

    func show(_ results: [QQMusicSearchResult]) {
        self.results = results
        table.reloadData()
        fitColumnsToViewport()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let result = results[row]
        let cell = NSTableCellView()
        if id == "download" {
            let button = NSButton(title: "下载", target: self, action: #selector(download(_:)))
            button.bezelStyle = .rounded
            button.identifier = NSUserInterfaceItemIdentifier(result.rid)
            button.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 72),
                button.heightAnchor.constraint(equalToConstant: 28)
            ])
        } else {
            let label = NSTextField(labelWithString: id == "song" ? result.name : result.artist)
            label.font = .systemFont(ofSize: id == "song" ? 14 : 12, weight: id == "song" ? .medium : .regular)
            label.textColor = id == "song" ? .labelColor : .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        return cell
    }

    @objc private func download(_ sender: NSButton) {
        guard let rid = sender.identifier?.rawValue else { return }
        onDownload?(rid)
    }
}

@MainActor
final class ControlsView: NSView {
    private let audio: LocalAudioPlayer
    private var lyricsSettingsWindow: DesktopLyricsSettingsWindowController?
    private let library: MusicLibraryStore
    private var libraryObserver: NSObjectProtocol?
    private var selectedPlaylistID: String?
    private var currentTrackID: String?
    private var visibleTracks: [LocalTrack] = []
    private var artworkLoadGeneration = 0
    private var yamnetAnalysisGeneration = 0
    private var isShowingOnlineSearch = false
    private var onlineResults: [QQMusicSearchResult] = []
    private var searchTask: Task<Void, Never>?
    private enum LibraryFilter { case all, recent, favorites }
    private var filter: LibraryFilter = .all
    private let playlistStack = NSStackView()
    private var effectButtons: [NSButton] = []
    private let searchResultsView = OnlineMusicResultsView()
    private let libraryActions = NSStackView()
    private let sectionTitle = NSTextField(labelWithString: "所有歌曲")
    private let nowPlaying = NSTextField(labelWithString: "尚未播放")
    private let yamnetToggle = NSButton(checkboxWithTitle: "YAMNet 音乐识别", target: nil, action: nil)
    private let demucsToggle = NSButton(checkboxWithTitle: "HTDemucs 乐器分离", target: nil, action: nil)
    private let guitarSurgeToggle = NSButton(checkboxWithTitle: "吉他高潮全屏扫光（鼓点同步）", target: nil, action: nil)
    private let coverRecordToggle = NSButton(checkboxWithTitle: "其他特效显示圆形唱片", target: nil, action: nil)
    private let moodSettingsButton = NSButton(title: "氛围光 AI 设置…", target: nil, action: nil)
    private let searchField = NSTextField()
    private let searchStatus = NSTextField(labelWithString: "搜索在线音乐")
    private let onlineSearchControls = NSStackView()
    private let onBackgroundEffectChange: (DesktopBackgroundEffect) -> Void
    private let onArtworkChange: (NSImage?) -> Void

    init(audio: LocalAudioPlayer, library: MusicLibraryStore,
         onBackgroundEffectChange: @escaping (DesktopBackgroundEffect) -> Void,
         onArtworkChange: @escaping (NSImage?) -> Void) {
        self.audio = audio
        self.library = library
        self.onBackgroundEffectChange = onBackgroundEffectChange
        self.onArtworkChange = onArtworkChange
        super.init(frame: NSRect(x: 0, y: 0, width: 1040, height: 700))
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        audio.onTrackStart = { [weak self] url in
            Task { @MainActor [weak self] in
                guard let self else { return }
                DesktopMoodService.shared.analyze(title: self.audio.currentTitle, artist: self.audio.currentArtist)
                if let track = self.library.tracks.first(where: { $0.path == url.path }) {
                    self.currentTrackID = track.id
                    self.library.markPlayed(track.id)
                    self.nowPlaying.stringValue = track.title
                    self.artworkLoadGeneration += 1
                    let generation = self.artworkLoadGeneration
                    self.onArtworkChange(nil)
                    Task { [weak self] in
                        guard let self else { return }
                        let image = await self.library.artwork(for: track)
                        guard generation == self.artworkLoadGeneration else { return }
                        self.onArtworkChange(image)
                    }
                }
                if self.yamnetToggle.state == .on { self.analyzeCurrentTrack() }
            }
        }

        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 28
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        glass.layer?.masksToBounds = true
        glass.translatesAutoresizingMaskIntoConstraints = false

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20
        root.translatesAutoresizingMaskIntoConstraints = false
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .equalSpacing
        let brand = NSTextField(labelWithString: "SOUND DESK")
        brand.font = .systemFont(ofSize: 11, weight: .bold)
        brand.textColor = .secondaryLabelColor
        brand.attributedStringValue = NSAttributedString(string: "SOUND DESK", attributes: [.kern: 2])
        sectionTitle.stringValue = "音乐控制台"
        sectionTitle.font = .systemFont(ofSize: 25, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "搜索、聆听与塑造你的声音空间")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        let titleGroup = NSStackView(views: [sectionTitle, subtitle])
        titleGroup.orientation = .vertical
        titleGroup.alignment = .leading
        titleGroup.spacing = 4
        header.addArrangedSubview(titleGroup)
        let lyricsButton = NSButton(title: "歌词管理", target: self, action: #selector(showLyricsSettings))
        lyricsButton.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "歌词管理")
        lyricsButton.imagePosition = .imageLeading
        lyricsButton.bezelStyle = .rounded
        lyricsButton.font = .systemFont(ofSize: 13, weight: .medium)
        let headerActions = NSStackView(views: [brand, lyricsButton])
        headerActions.orientation = .horizontal
        headerActions.alignment = .centerY
        headerActions.spacing = 18
        header.addArrangedSubview(headerActions)
        header.translatesAutoresizingMaskIntoConstraints = false

        let searchButton = NSButton(title: "搜索", target: self, action: #selector(searchOnlineSongs))
        searchButton.bezelStyle = .rounded
        searchButton.font = .systemFont(ofSize: 13, weight: .medium)
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        searchButton.heightAnchor.constraint(equalToConstant: 38).isActive = true
        searchButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let searchSurface = NSView()
        searchSurface.wantsLayer = true
        searchSurface.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.065).cgColor
        searchSurface.layer?.borderWidth = 0.5
        searchSurface.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        searchSurface.layer?.cornerRadius = 14
        searchSurface.translatesAutoresizingMaskIntoConstraints = false
        let searchIcon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) ?? NSImage())
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "搜索歌曲或歌手"
        searchField.target = self
        searchField.action = #selector(searchOnlineSongs)
        searchField.font = .systemFont(ofSize: 14)
        searchField.usesSingleLineMode = true
        searchField.lineBreakMode = .byTruncatingTail
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.setAccessibilityLabel("搜索歌曲或歌手")
        searchSurface.addSubview(searchIcon)
        searchSurface.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchSurface.heightAnchor.constraint(equalToConstant: 44),
            searchIcon.leadingAnchor.constraint(equalTo: searchSurface.leadingAnchor, constant: 14),
            searchIcon.centerYAnchor.constraint(equalTo: searchSurface.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 16),
            searchIcon.heightAnchor.constraint(equalToConstant: 16),
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: searchSurface.trailingAnchor, constant: -14),
            searchField.centerYAnchor.constraint(equalTo: searchSurface.centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 22)
        ])
        let searchRow = NSStackView(views: [searchSurface, searchButton])
        searchRow.orientation = .horizontal
        searchRow.alignment = .centerY
        searchRow.spacing = 10
        searchRow.translatesAutoresizingMaskIntoConstraints = false
        searchStatus.font = .systemFont(ofSize: 11)
        searchStatus.textColor = .secondaryLabelColor
        onlineSearchControls.orientation = .vertical
        onlineSearchControls.alignment = .leading
        onlineSearchControls.spacing = 10
        onlineSearchControls.addArrangedSubview(searchRow)
        onlineSearchControls.addArrangedSubview(searchStatus)
        onlineSearchControls.translatesAutoresizingMaskIntoConstraints = false
        onlineSearchControls.isHidden = false

        let resultScroll = searchResultsView
        searchResultsView.onDownload = { [weak self] rid in self?.downloadOnlineSong(rid: rid) }
        resultScroll.translatesAutoresizingMaskIntoConstraints = false

        let effectsTitle = NSTextField(labelWithString: "视觉效果")
        effectsTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        effectsTitle.textColor = .secondaryLabelColor
        let effectsRow = NSStackView()
        effectsRow.orientation = .horizontal
        effectsRow.alignment = .centerY
        effectsRow.distribution = .fillEqually
        effectsRow.spacing = 9
        effectsRow.translatesAutoresizingMaskIntoConstraints = false
        let effects: [(DesktopBackgroundEffect, String)] = [
            (.aurora, "sparkles"), (.tyndall, "sunbeams.fill"),
            (.coverDots, "circle.grid.3x3.fill"), (.cellularHive, "hexagon.fill")
        ]
        effectButtons = effects.map { effect, symbol in
            let button = NSButton(title: effect.title, target: self, action: #selector(changeBackgroundEffect(_:)))
            button.tag = effect.rawValue
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: effect.title)
            button.imagePosition = .imageLeading
            button.alignment = .center
            button.bezelStyle = .rounded
            button.setButtonType(.toggle)
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 10
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 42).isActive = true
            button.widthAnchor.constraint(equalToConstant: 150).isActive = true
            effectsRow.addArrangedSubview(button)
            return button
        }
        updateEffectSelection(DesktopBackgroundEffect.saved)
        coverRecordToggle.state = (UserDefaults.standard.object(forKey: "desktopCenterRecordVisible") as? Bool ?? true) ? .on : .off
        coverRecordToggle.target = self
        coverRecordToggle.action = #selector(toggleCenterRecord(_:))
        nowPlaying.textColor = .secondaryLabelColor
        nowPlaying.font = .systemFont(ofSize: 14, weight: .medium)
        let previousButton = transportButton("backward.end.fill", title: "上一首", action: #selector(previousTrack))
        let playButton = NSButton(title: "选择本地歌曲", target: self, action: #selector(openMusic))
        let nextButton = transportButton("forward.end.fill", title: "下一首", action: #selector(nextTrack))
        let stopButton = transportButton("stop.fill", title: "停止", action: #selector(stopMusic))
        let favoriteButton = transportButton("heart", title: "喜欢", action: #selector(toggleFavorite))
        nowPlaying.lineBreakMode = .byTruncatingTail
        nowPlaying.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nowPlaying.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for button in [previousButton, playButton, nextButton, stopButton, favoriteButton] { button.bezelStyle = .rounded }
        yamnetToggle.state = UserDefaults.standard.bool(forKey: "desktopYAMNetEnabled") ? .on : .off
        yamnetToggle.target = self
        yamnetToggle.action = #selector(toggleYAMNet(_:))
        demucsToggle.state = UserDefaults.standard.bool(forKey: "desktopHTDemucsEnabled") ? .on : .off
        demucsToggle.target = self
        demucsToggle.action = #selector(toggleHTDemucs(_:))
        guitarSurgeToggle.state = audio.guitarSurgeEnabled ? .on : .off
        guitarSurgeToggle.target = self
        guitarSurgeToggle.action = #selector(toggleGuitarSurge(_:))
        moodSettingsButton.target = self
        moodSettingsButton.action = #selector(showMoodSettings)
        let fftHint = NSTextField(labelWithString: "关闭识别与分离时，使用实时 FFT")
        fftHint.textColor = .secondaryLabelColor
        let transport = NSStackView(views: [previousButton, playButton, nextButton, stopButton, favoriteButton, nowPlaying])
        transport.orientation = .horizontal
        transport.alignment = .centerY
        transport.spacing = 10
        transport.translatesAutoresizingMaskIntoConstraints = false
        let toggleRow = NSStackView(views: [yamnetToggle, demucsToggle])
        toggleRow.orientation = .horizontal
        toggleRow.alignment = .centerY
        toggleRow.distribution = .fillEqually
        toggleRow.spacing = 12
        let effectToggleRow = NSStackView(views: [guitarSurgeToggle, coverRecordToggle, moodSettingsButton])
        effectToggleRow.orientation = .horizontal
        effectToggleRow.alignment = .centerY
        effectToggleRow.distribution = .fillEqually
        effectToggleRow.spacing = 12
        let toggles = NSStackView(views: [toggleRow, effectToggleRow])
        toggles.orientation = .vertical
        toggles.alignment = .leading
        toggles.spacing = 8
        toggles.translatesAutoresizingMaskIntoConstraints = false
        let controlHint = NSStackView(views: [fftHint, toggles])
        controlHint.orientation = .vertical
        controlHint.alignment = .leading
        controlHint.spacing = 10
        controlHint.translatesAutoresizingMaskIntoConstraints = false

        root.addArrangedSubview(header)
        root.addArrangedSubview(onlineSearchControls)
        root.addArrangedSubview(resultScroll)
        root.addArrangedSubview(effectsTitle)
        root.addArrangedSubview(effectsRow)
        root.addArrangedSubview(transport)
        root.addArrangedSubview(controlHint)
        addSubview(glass)
        glass.addSubview(root)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), glass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            glass.topAnchor.constraint(equalTo: topAnchor, constant: 18), glass.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            root.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 28), root.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: glass.topAnchor, constant: 24), root.bottomAnchor.constraint(equalTo: glass.bottomAnchor, constant: -24),
            header.widthAnchor.constraint(equalTo: root.widthAnchor), onlineSearchControls.widthAnchor.constraint(equalTo: root.widthAnchor),
            searchRow.widthAnchor.constraint(equalTo: onlineSearchControls.widthAnchor), searchSurface.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            resultScroll.widthAnchor.constraint(equalTo: root.widthAnchor), resultScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 130),
            effectsRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            transport.widthAnchor.constraint(equalTo: root.widthAnchor), controlHint.widthAnchor.constraint(equalTo: root.widthAnchor), toggles.widthAnchor.constraint(equalTo: root.widthAnchor),
            toggleRow.widthAnchor.constraint(equalTo: toggles.widthAnchor), effectToggleRow.widthAnchor.constraint(equalTo: toggles.widthAnchor)
        ])
        refresh()
        libraryObserver = NotificationCenter.default.addObserver(forName: .desktopMusicLibraryChanged,
            object: library, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
    }

    deinit { if let libraryObserver { NotificationCenter.default.removeObserver(libraryObserver) } }
    required init?(coder: NSCoder) { nil }
    private func transportButton(_ symbol: String, title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            button.image = image
            button.imagePosition = .imageOnly
            button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        }
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 38).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }
    @objc private func openMusic() { audio.openAndPlay() }
    @objc private func previousTrack() { _ = audio.playAdjacentTrack(-1) }
    @objc private func nextTrack() { _ = audio.playAdjacentTrack(1) }
    @objc private func changeBackgroundEffect(_ sender: NSButton) {
        guard let effect = DesktopBackgroundEffect(rawValue: sender.tag) else { return }
        updateEffectSelection(effect)
        onBackgroundEffectChange(effect)
    }

    private func updateEffectSelection(_ effect: DesktopBackgroundEffect) {
        for button in effectButtons {
            let selected = button.tag == effect.rawValue
            button.state = selected ? .on : .off
            button.contentTintColor = selected ? .systemBlue : .labelColor
            if let choice = DesktopBackgroundEffect(rawValue: button.tag) {
                button.image = NSImage(systemSymbolName: selected ? "checkmark.circle.fill" : "circle",
                                       accessibilityDescription: choice.title)
            }
            button.layer?.backgroundColor = selected
                ? NSColor.systemBlue.withAlphaComponent(0.22).cgColor
                : NSColor.white.withAlphaComponent(0.055).cgColor
            button.layer?.borderWidth = selected ? 1 : 0
            button.layer?.borderColor = selected
                ? NSColor.systemBlue.withAlphaComponent(0.78).cgColor
                : NSColor.clear.cgColor
        }
    }

    @objc private func toggleCenterRecord(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "desktopCenterRecordVisible")
    }
    @objc private func stopMusic() { audio.stop() }
    @objc private func toggleYAMNet(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "desktopYAMNetEnabled")
        if enabled {
            analyzeCurrentTrack()
        } else {
            yamnetAnalysisGeneration += 1
            audio.electricGuitarConfidence = 0
            audio.setVocalCurve([])
        }
    }
    @objc private func toggleHTDemucs(_ sender: NSButton) {
        audio.setHTDemucsEnabled(sender.state == .on)
    }
    @objc private func toggleGuitarSurge(_ sender: NSButton) {
        audio.setGuitarSurgeEnabled(sender.state == .on)
    }
    @objc private func showLyricsSettings() {
        if lyricsSettingsWindow == nil {
            lyricsSettingsWindow = DesktopLyricsSettingsWindowController(controller: audio.lyricsController)
        }
        guard let settings = lyricsSettingsWindow, let window = settings.window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApplication.shared.activate(ignoringOtherApps: true)
        settings.showWindow(self)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
    @objc private func showMoodSettings() {
        let settings = DesktopMoodService.shared
        let alert = NSAlert()
        alert.messageText = "氛围光 AI 设置"
        alert.informativeText = "沿用 iOS 的歌曲情绪配色格式。配置保存在这台 Mac 的应用设置中。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 110))
        let baseField = NSTextField(string: settings.baseURL)
        let modelField = NSTextField(string: settings.model)
        let keyField = NSSecureTextField(string: settings.apiKey)
        for (labelText, field, y) in [("Base URL", baseField as NSTextField, CGFloat(76)),
                                      ("Model", modelField as NSTextField, CGFloat(43)),
                                      ("API Key", keyField as NSTextField, CGFloat(10))] {
            let label = NSTextField(labelWithString: labelText)
            label.frame = NSRect(x: 0, y: y + 3, width: 78, height: 20)
            field.frame = NSRect(x: 85, y: y, width: 310, height: 25)
            accessory.addSubview(label)
            accessory.addSubview(field)
        }
        alert.accessoryView = accessory
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let base = baseField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: base), components.scheme?.lowercased() == "https",
              components.host != nil, !model.isEmpty else {
            let error = NSAlert()
            error.messageText = "请填写有效的 HTTPS 地址和模型名称"
            error.runModal()
            return
        }
        settings.configure(baseURL: base, model: model, apiKey: keyField.stringValue)
        if audio.currentURL != nil { settings.analyze(title: audio.currentTitle, artist: audio.currentArtist) }
    }
    @objc private func toggleFavorite() {
        guard let currentTrackID else { return }
        library.toggleFavorite(currentTrackID)
        refresh()
    }
    @objc private func analyzeCurrentTrack() {
        guard yamnetToggle.state == .on, let url = audio.currentURL else {
            nowPlaying.stringValue = "先从曲库选择一首歌"
            return
        }
        yamnetAnalysisGeneration += 1
        let generation = yamnetAnalysisGeneration
        nowPlaying.stringValue = "YAMNet 正在分析整首歌曲…"
        let analyzer = YAMNetAudioAnalyzer.shared()
        let runAnalysis = { [weak self] in
            analyzer.analyzeAudio(at: url) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self, self.yamnetToggle.state == .on,
                          self.yamnetAnalysisGeneration == generation else { return }
                    if let error {
                        self.nowPlaying.stringValue = "YAMNet 分析失败：\(error.localizedDescription)"
                        return
                    }
                    let patches = result?["patches"] as? [[String: Any]] ?? []
                    let guitar = patches.compactMap { ($0["scores"] as? [NSNumber])?[135].doubleValue }.max() ?? 0
                    let electric = patches.compactMap { ($0["scores"] as? [NSNumber])?[136].doubleValue }.max() ?? 0
                    self.audio.setVocalCurve(patches.compactMap { ($0["scores"] as? [NSNumber])?[24].floatValue })
                    self.audio.electricGuitarConfidence = Float(electric)
                    self.nowPlaying.stringValue = "YAMNet 完成 · 吉他 \(Int(guitar * 100))% · 电吉他 \(Int(electric * 100))%"
                }
            }
        }
#if SWIFT_PACKAGE
        if !analyzer.modelInstalled, let modelURL = bundledResource("YAMNet", "mlpackage") {
            analyzer.installModel(at: modelURL) { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self, self.yamnetToggle.state == .on,
                          self.yamnetAnalysisGeneration == generation else { return }
                    if let error { self.nowPlaying.stringValue = "YAMNet 模型安装失败：\(error.localizedDescription)" }
                    else { runAnalysis() }
                }
            }
        } else {
            runAnalysis()
        }
#else
        runAnalysis()
#endif
    }

    private func sidebarButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .roundRect
        button.alignment = .left
        button.setButtonType(.momentaryPushIn)
        return button
    }

    private func refresh() {
        onlineSearchControls.isHidden = false
        searchResultsView.show(onlineResults)
    }

    @objc private func showAllSongs() { isShowingOnlineSearch = false; selectedPlaylistID = nil; filter = .all; refresh() }
    @objc private func showRecent() { isShowingOnlineSearch = false; selectedPlaylistID = nil; filter = .recent; refresh() }
    @objc private func showFavorites() { isShowingOnlineSearch = false; selectedPlaylistID = nil; filter = .favorites; refresh() }

    @objc private func showOnlineSearch() {
        isShowingOnlineSearch = true
        selectedPlaylistID = nil
        onlineResults = []
        searchStatus.stringValue = "搜索在线音乐"
        refresh()
    }

    @objc private func searchOnlineSongs() {
        let term = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            searchStatus.stringValue = "请输入歌曲名或歌手名"
            return
        }
        searchTask?.cancel()
        onlineResults = []
        refresh()
        searchStatus.stringValue = "正在搜索…"
        var components = URLComponents(string: "https://api.qqmp3.vip/api/songs.php")!
        components.queryItems = [URLQueryItem(name: "type", value: "search"), URLQueryItem(name: "keyword", value: term)]
        guard let url = components.url else { return }
        searchTask = Task { [weak self] in
            do {
                guard let self else { return }
                var request = self.qqMusicRequest(url: url)
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (payload["code"] as? NSNumber)?.intValue == 200,
                      let rows = payload["data"] as? [[String: Any]] else {
                    throw NSError(domain: "QQMusicSearch", code: -2, userInfo: [NSLocalizedDescriptionKey: "在线音乐服务返回了无法识别的数据"])
                }
                guard !Task.isCancelled else { return }
                self.onlineResults = rows.compactMap { row in
                    guard let rid = Self.stringValue(row["rid"]),
                          let name = Self.stringValue(row["name"]),
                          let artist = Self.stringValue(row["artist"]) else { return nil }
                    return QQMusicSearchResult(rid: rid, name: name, artist: artist)
                }
                self.searchStatus.stringValue = self.onlineResults.isEmpty ? "没有找到歌曲" : "找到 \(self.onlineResults.count) 首 · iOS 云端接口"
                self.refresh()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.searchStatus.stringValue = "搜索失败：\(error.localizedDescription)"
            }
        }
    }

    private func downloadOnlineSong(rid: String) {
        guard let result = onlineResults.first(where: { $0.rid == rid }) else { return }
        searchStatus.stringValue = "正在获取歌曲信息：\(result.name)"
        Task { [weak self] in
            guard let self else { return }
            do {
                var components = URLComponents(string: "https://api.qqmp3.vip/api/kw.php")!
                components.queryItems = [
                    URLQueryItem(name: "rid", value: result.rid),
                    URLQueryItem(name: "type", value: "json"),
                    URLQueryItem(name: "level", value: "exhigh"),
                    URLQueryItem(name: "lrc", value: "true")
                ]
                guard let detailURL = components.url else { throw URLError(.badURL) }
                let (detailData, detailResponse) = try await URLSession.shared.data(for: self.qqMusicRequest(url: detailURL))
                guard let detailHTTP = detailResponse as? HTTPURLResponse,
                      (200..<300).contains(detailHTTP.statusCode),
                      let detailPayload = try JSONSerialization.jsonObject(with: detailData) as? [String: Any],
                      (detailPayload["code"] as? NSNumber)?.intValue == 200,
                      let detail = detailPayload["data"] as? [String: Any],
                      let audioURLString = Self.stringValue(detail["url"]),
                      let audioURL = URL(string: audioURLString), audioURL.scheme == "https" else {
                    throw NSError(domain: "QQMusicSearch", code: -3, userInfo: [NSLocalizedDescriptionKey: "没有获取到有效的歌曲下载地址"])
                }
                self.searchStatus.stringValue = "正在下载：\(result.name)"
                let (temporaryURL, downloadResponse) = try await URLSession.shared.download(for: self.qqMusicRequest(url: audioURL))
                guard let downloadHTTP = downloadResponse as? HTTPURLResponse,
                      (200..<300).contains(downloadHTTP.statusCode) else { throw URLError(.badServerResponse) }
                let headerHandle = try FileHandle(forReadingFrom: temporaryURL)
                let bytes = Array(try headerHandle.read(upToCount: 16) ?? Data())
                try headerHandle.close()
                let actualExtension: String?
                if bytes.count >= 4 && Array(bytes[0..<4]) == Array("fLaC".utf8) {
                    actualExtension = "flac"
                } else if bytes.count >= 12 && Array(bytes[0..<4]) == Array("RIFF".utf8) && Array(bytes[8..<12]) == Array("WAVE".utf8) {
                    actualExtension = "wav"
                } else if bytes.count >= 8 && Array(bytes[4..<8]) == Array("ftyp".utf8) {
                    actualExtension = "m4a"
                } else if bytes.count >= 3 && Array(bytes[0..<3]) == Array("ID3".utf8) {
                    actualExtension = "mp3"
                } else if bytes.count >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xF6) == 0xF0 {
                    actualExtension = "aac"
                } else if bytes.count >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0 {
                    actualExtension = "mp3"
                } else {
                    actualExtension = nil
                }
                guard let ext = actualExtension else {
                    throw NSError(domain: "QQMusicDownload", code: -4, userInfo: [NSLocalizedDescriptionKey: "下载内容不是可识别的音频文件，歌曲服务可能返回了错误页或无效数据"])
                }
                let title = Self.stringValue(detail["name"]) ?? result.name
                let artist = Self.stringValue(detail["artist"]) ?? result.artist
                try self.library.addDownloadedFile(at: temporaryURL, fileExtension: ext, title: title, artist: artist, to: nil)
                if let saved = self.library.tracks.first(where: { $0.title == title && $0.artist == artist }) {
                    self.audio.setPlaybackQueue(self.library.tracks, currentID: saved.id)
                }
                self.refresh()
                self.searchStatus.stringValue = "下载完成：\(title)"
            } catch {
                self.searchStatus.stringValue = "下载失败：\(error.localizedDescription)"
            }
        }
    }

    private func qqMusicRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("https://www.qqmp3.vip", forHTTPHeaderField: "Referer")
        request.setValue("https://www.qqmp3.vip", forHTTPHeaderField: "Origin")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        return request
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String { return string.isEmpty ? nil : string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    @objc private func selectPlaylist(_ sender: NSButton) {
        isShowingOnlineSearch = false
        selectedPlaylistID = sender.identifier?.rawValue
        filter = .all
        refresh()
    }

    @objc private func importSongs() {
        isShowingOnlineSearch = false
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        library.add(panel.urls, to: selectedPlaylistID)
        refresh()
    }

    @objc private func downloadAudio() {
        isShowingOnlineSearch = false
        let alert = NSAlert()
        alert.messageText = "下载可直接访问的音频文件"
        alert.informativeText = "粘贴你有权下载的 HTTPS 音频直链。"
        alert.addButton(withTitle: "开始下载")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        field.placeholderString = "https://example.com/audio.mp3"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn,
              let url = URL(string: field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https" else { return }
        nowPlaying.stringValue = "正在下载…"
        URLSession.shared.downloadTask(with: url) { [weak self] temporaryURL, response, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let temporaryURL, error == nil else {
                    self.nowPlaying.stringValue = error?.localizedDescription ?? "下载失败"
                    return
                }
                let suggested = response?.suggestedFilename ?? url.lastPathComponent
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent(suggested)
                try? FileManager.default.removeItem(at: destination)
                do {
                    try FileManager.default.moveItem(at: temporaryURL, to: destination)
                    self.library.add([destination], to: self.selectedPlaylistID)
                    self.refresh()
                    self.nowPlaying.stringValue = "下载完成：\(suggested)"
                } catch {
                    self.nowPlaying.stringValue = "保存失败：\(error.localizedDescription)"
                }
            }
        }.resume()
    }

    @objc private func createPlaylist() {
        isShowingOnlineSearch = false
        let alert = NSAlert()
        alert.messageText = "新建歌单"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "歌单名称"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        selectedPlaylistID = library.createPlaylist(field.stringValue)
        refresh()
    }

    @objc private func playTrack(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let track = library.track(id: id) else { return }
        audio.setPlaybackQueue(visibleTracks, currentID: id)
        audio.play(url: URL(fileURLWithPath: track.path), title: track.title, artist: track.artist)
    }
}

struct LocalTrack: Codable, Identifiable {
    var id: String
    var path: String
    var title: String
    var artist: String?
    var isFavorite = false
    var lastPlayed: Date?

    private enum CodingKeys: String, CodingKey { case id, path, title, artist, isFavorite, lastPlayed }
    init(id: String, path: String, title: String, artist: String?, isFavorite: Bool = false, lastPlayed: Date? = nil) {
        self.id = id; self.path = path; self.title = title; self.artist = artist
        self.isFavorite = isFavorite; self.lastPlayed = lastPlayed
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        path = try values.decode(String.self, forKey: .path)
        title = try values.decode(String.self, forKey: .title)
        artist = try values.decodeIfPresent(String.self, forKey: .artist)
        isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        lastPlayed = try values.decodeIfPresent(Date.self, forKey: .lastPlayed)
    }
}

private struct QQMusicSearchResult {
    let rid: String
    let name: String
    let artist: String
}

struct UserPlaylist: Codable, Identifiable {
    var id: String
    var name: String
    var trackIDs: [String]
}

@MainActor
final class MusicLibraryStore {
    private(set) var tracks: [LocalTrack] = []
    private(set) var playlists: [UserPlaylist] = []
    private let fileURL: URL
    private let audioDirectory: URL
    var recentTracks: [LocalTrack] { tracks.filter { $0.lastPlayed != nil }.sorted { $0.lastPlayed! > $1.lastPlayed! } }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacDesktopPlayer", isDirectory: true)
        fileURL = support.appendingPathComponent("library.json")
        audioDirectory = support.appendingPathComponent("Music", isDirectory: true)
        if let data = try? Data(contentsOf: fileURL),
           let library = try? JSONDecoder().decode(SavedLibrary.self, from: data) {
            tracks = library.tracks
            playlists = library.playlists
        }
    }

    func add(_ urls: [URL], to playlistID: String?) {
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        for source in urls {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            do {
                guard !tracks.contains(where: { $0.title == source.deletingPathExtension().lastPathComponent }) else { continue }
                let id = UUID().uuidString
                let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension
                let destination = audioDirectory.appendingPathComponent("\(id).\(ext)")
                try FileManager.default.copyItem(at: source, to: destination)
                let title = source.deletingPathExtension().lastPathComponent
                let track = LocalTrack(id: id, path: destination.path, title: title, artist: nil)
                tracks.append(track)
                if let playlistID, let index = playlists.firstIndex(where: { $0.id == playlistID }) {
                    playlists[index].trackIDs.append(track.id)
                }
            } catch {
                NSLog("Unable to import audio at %@: %@", source.path, error.localizedDescription)
            }
        }
        save()
    }

    func addDownloadedFile(at source: URL, fileExtension: String, title: String, artist: String, to playlistID: String?) throws {
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let destination = audioDirectory.appendingPathComponent("\(id).\(fileExtension)")
        try FileManager.default.moveItem(at: source, to: destination)
        let track = LocalTrack(id: id, path: destination.path, title: title, artist: artist)
        tracks.append(track)
        if let playlistID, let index = playlists.firstIndex(where: { $0.id == playlistID }) {
            playlists[index].trackIDs.append(track.id)
        }
        save()
    }

    func markPlayed(_ id: String) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].lastPlayed = Date()
        save()
    }

    func toggleFavorite(_ id: String) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].isFavorite.toggle()
        save()
    }

    func createPlaylist(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let id = UUID().uuidString
        playlists.append(UserPlaylist(id: id, name: trimmed, trackIDs: []))
        save()
        return id
    }

    func deletePlaylist(_ id: String) {
        playlists.removeAll { $0.id == id }
        save()
    }

    func removeFromLibrary(_ trackID: String) {
        tracks.removeAll { $0.id == trackID }
        for index in playlists.indices { playlists[index].trackIDs.removeAll { $0 == trackID } }
        save()
    }

    func removeTrack(_ trackID: String, from playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].trackIDs.removeAll { $0 == trackID }
        save()
    }

    func tracks(in playlistID: String?) -> [LocalTrack] {
        guard let playlistID, let playlist = playlists.first(where: { $0.id == playlistID }) else { return tracks }
        return playlist.trackIDs.compactMap { id in tracks.first(where: { $0.id == id }) }
    }

    func playlistName(_ id: String) -> String? { playlists.first(where: { $0.id == id })?.name }
    func track(id: String) -> LocalTrack? { tracks.first(where: { $0.id == id }) }

    func artwork(for track: LocalTrack) async -> NSImage? {
        let fileURL = URL(fileURLWithPath: track.path)
        if let image = sidecarArtwork(for: fileURL) { return image }
        if let cached = await AppleArtworkLookupService.shared.cachedArtwork(forFilePath: track.path),
           let image = NSImage(data: cached) { return image }

        let asset = AVURLAsset(url: fileURL)
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        if let item = AVMetadataItem.metadataItems(
            from: metadata, filteredByIdentifier: .commonIdentifierArtwork
        ).first, let data = try? await item.load(.dataValue), let image = NSImage(data: data) {
            return image
        }

        var values: [String: String] = [:]
        for item in metadata {
            guard let key = item.commonKey?.rawValue,
                  let value = try? await item.load(.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            if values[key] == nil { values[key] = value }
        }
        let title = values[AVMetadataKey.commonKeyTitle.rawValue] ?? track.title
        let artist = track.artist ?? values[AVMetadataKey.commonKeyArtist.rawValue]
        let album = values[AVMetadataKey.commonKeyAlbumName.rawValue]
        guard let data = await AppleArtworkLookupService.shared.lookup(
            title: title, artist: artist, album: album, filePath: track.path
        ) else { return nil }
        return NSImage(data: data)
    }

    private func sidecarArtwork(for audioURL: URL) -> NSImage? {
        let basename = audioURL.deletingPathExtension().lastPathComponent
        let directory = audioURL.deletingLastPathComponent()
        for stem in ["\(basename)_cover", basename] {
            for ext in ["jpg", "jpeg", "png", "webp"] {
                let coverURL = directory.appendingPathComponent(stem).appendingPathExtension(ext)
                if let image = NSImage(contentsOf: coverURL) { return image }
            }
        }
        return nil
    }

    private func save() {
        let library = SavedLibrary(tracks: tracks, playlists: playlists)
        guard let data = try? JSONEncoder().encode(library) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        NotificationCenter.default.post(name: .desktopMusicLibraryChanged, object: self)
    }
}

private struct SavedLibrary: Codable {
    var tracks: [LocalTrack]
    var playlists: [UserPlaylist]
}

private actor AppleArtworkLookupService {
    static let shared = AppleArtworkLookupService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }()
    private let negativeCacheTTL: TimeInterval = 6 * 60 * 60
    private var memoryCache: [String: Data] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private var negativeCache: [String: Date] = [:]

    func cachedArtwork(forFilePath filePath: String) -> Data? {
        let key = "file:\(filePath)"
        if let data = memoryCache[key] { return data }
        guard let data = try? Data(contentsOf: cacheURL(for: key)), NSImage(data: data) != nil else { return nil }
        remember(data, for: key)
        return data
    }

    func lookup(title: String?, artist: String?, album: String?, filePath: String?) async -> Data? {
        let resolvedTitle = trimmed(title)
        let resolvedArtist = trimmed(artist)
        let resolvedAlbum = trimmed(album)
        guard let resolvedTitle, isUsableTitle(resolvedTitle) else { return nil }

        let searchKey = searchCacheKey(title: resolvedTitle, artist: resolvedArtist, album: resolvedAlbum)
        if let cached = cachedData(for: searchKey) {
            persist(cached, searchKey: searchKey, filePath: filePath)
            return cached
        }
        if let failedAt = negativeCache[searchKey], Date().timeIntervalSince(failedAt) < negativeCacheTTL {
            return nil
        }

        let task: Task<Data?, Never>
        if let active = inFlight[searchKey] {
            task = active
        } else {
            task = Task { await self.searchAndDownload(title: resolvedTitle, artist: resolvedArtist, album: resolvedAlbum) }
            inFlight[searchKey] = task
        }
        let imageData = await task.value
        inFlight.removeValue(forKey: searchKey)
        if let imageData {
            negativeCache.removeValue(forKey: searchKey)
            persist(imageData, searchKey: searchKey, filePath: filePath)
        } else {
            negativeCache[searchKey] = Date()
        }
        return imageData
    }

    private func searchAndDownload(title: String, artist: String?, album: String?) async -> Data? {
        let term = [artist, title, album].compactMap { trimmed($0) }.joined(separator: " ")
        for country in storefronts(title: title, artist: artist) {
            let songs = await performSearch(term: term, country: country, entity: "song")
            if let match = bestSongMatch(songs, title: title, artist: artist, album: album),
               let image = await downloadArtwork(result: match) { return image }

            let albums = await performSearch(term: term, country: country, entity: "album")
            if let match = bestAlbumMatch(albums, title: title, artist: artist, album: album),
               let image = await downloadArtwork(result: match) { return image }
        }
        return nil
    }

    private func performSearch(term: String, country: String, entity: String) async -> [[String: Any]] {
        guard var components = URLComponents(string: "https://itunes.apple.com/search") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "lang", value: "zh_cn")
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("MacDesktopPlayer/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = payload["results"] as? [[String: Any]] else { return [] }
            return rows
        } catch {
            NSLog("[Artwork] iTunes search failed: %@", error.localizedDescription)
            return []
        }
    }

    private func bestSongMatch(_ rows: [[String: Any]], title: String, artist: String?, album: String?) -> [String: Any]? {
        let best = rows.max { songScore($0, title: title, artist: artist, album: album) < songScore($1, title: title, artist: artist, album: album) }
        guard let best, songScore(best, title: title, artist: artist, album: album) >= 55 else { return nil }
        return best
    }

    private func bestAlbumMatch(_ rows: [[String: Any]], title: String, artist: String?, album: String?) -> [String: Any]? {
        let targetAlbum = album?.isEmpty == false ? album! : title
        let best = rows.max { albumScore($0, targetAlbum: targetAlbum, artist: artist) < albumScore($1, targetAlbum: targetAlbum, artist: artist) }
        guard let best, albumScore(best, targetAlbum: targetAlbum, artist: artist) >= 50 else { return nil }
        return best
    }

    private func songScore(_ row: [String: Any], title: String, artist: String?, album: String?) -> Double {
        var score = similarity(normalized(row["trackName"] as? String), normalized(title)) * 70
        if let artist, !artist.isEmpty { score += similarity(normalized(row["artistName"] as? String), normalized(artist)) * 25 }
        if let album, !album.isEmpty { score += similarity(normalized(row["collectionName"] as? String), normalized(album)) * 10 }
        return score
    }

    private func albumScore(_ row: [String: Any], targetAlbum: String, artist: String?) -> Double {
        var score = similarity(normalized(row["collectionName"] as? String), normalized(targetAlbum)) * 70
        if let artist, !artist.isEmpty { score += similarity(normalized(row["artistName"] as? String), normalized(artist)) * 30 }
        return score
    }

    private func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        guard lhs.contains(rhs) || rhs.contains(lhs) else { return 0 }
        return Double(min(lhs.count, rhs.count)) / Double(max(lhs.count, rhs.count))
    }

    private func downloadArtwork(result: [String: Any]) async -> Data? {
        guard let imageURL = highResolutionURL(result) else { return nil }
        if let data = await download(urlString: imageURL), NSImage(data: data) != nil { return data }
        if imageURL.contains("1200x1200bb") {
            let fallback = imageURL.replacingOccurrences(of: "1200x1200bb", with: "600x600bb")
            if let data = await download(urlString: fallback), NSImage(data: data) != nil { return data }
        }
        return nil
    }

    private func download(urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            NSLog("[Artwork] cover download failed: %@", error.localizedDescription)
            return nil
        }
    }

    private func highResolutionURL(_ result: [String: Any]) -> String? {
        guard let source = (result["artworkUrl100"] as? String) ?? (result["artworkUrl60"] as? String), !source.isEmpty,
              let regex = try? NSRegularExpression(pattern: "\\d+x\\d+[a-z]*", options: [.caseInsensitive]) else { return nil }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.stringByReplacingMatches(in: source, range: range, withTemplate: "1200x1200bb")
    }

    private func storefronts(title: String, artist: String?) -> [String] {
        let probe = title + (artist ?? "")
        if probe.unicodeScalars.contains(where: { (0xAC00...0xD7AF).contains(Int($0.value)) }) { return ["kr", "us", "cn"] }
        if probe.unicodeScalars.contains(where: { (0x3040...0x30FF).contains(Int($0.value)) }) { return ["jp", "us", "cn"] }
        if probe.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains(Int($0.value)) }) { return ["cn", "hk", "tw", "us"] }
        return ["us", "cn", "jp"]
    }

    private func isUsableTitle(_ value: String) -> Bool {
        let value = normalized(value)
        return value.count >= 2 && !["unknown", "untitled", "track", "未知", "未知歌曲", "无标题"].contains(value)
    }

    private func normalized(_ value: String?) -> String {
        guard let value = trimmed(value) else { return "" }
        var folded = value.lowercased().folding(options: [.widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        if let regex = try? NSRegularExpression(pattern: "\\s*[\\(\\[]?(feat\\.?|ft\\.)\\s+.*$", options: [.caseInsensitive]) {
            let range = NSRange(folded.startIndex..<folded.endIndex, in: folded)
            folded = regex.stringByReplacingMatches(in: folded, range: range, withTemplate: "")
        }
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0.value > 0x7F })
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private func searchCacheKey(title: String, artist: String?, album: String?) -> String {
        "search:\(normalized(artist))|\(normalized(title))|\(normalized(album))"
    }

    private func cachedData(for key: String) -> Data? {
        if let data = memoryCache[key] { return data }
        guard let data = try? Data(contentsOf: cacheURL(for: key)), NSImage(data: data) != nil else { return nil }
        remember(data, for: key)
        return data
    }

    private func remember(_ data: Data, for key: String) {
        memoryCache[key] = data
        if memoryCache.count > 8, let first = memoryCache.keys.first { memoryCache.removeValue(forKey: first) }
    }

    private func persist(_ data: Data, searchKey: String, filePath: String?) {
        remember(data, for: searchKey)
        try? data.write(to: cacheURL(for: searchKey), options: .atomic)
        if let filePath {
            let fileKey = "file:\(filePath)"
            remember(data, for: fileKey)
            try? data.write(to: cacheURL(for: fileKey), options: .atomic)
            writeSidecar(data, filePath: filePath)
        }
    }

    private func writeSidecar(_ data: Data, filePath: String) {
        let fileURL = URL(fileURLWithPath: filePath)
        let directory = fileURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: directory.path) else { return }
        let destination = directory.appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent + "_cover.jpg")
        try? data.write(to: destination, options: .atomic)
    }

    private func cacheURL(for key: String) -> URL {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacDesktopPlayer/AppleMusicArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(digest).appendingPathExtension("art")
    }
}

private extension Notification.Name {
    static let desktopMusicLibraryChanged = Notification.Name("DesktopMusicLibraryChanged")
}
