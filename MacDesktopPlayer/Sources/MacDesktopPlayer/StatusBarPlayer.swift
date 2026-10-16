import AppKit

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
        popover.contentSize = NSSize(width: 360, height: 332)
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

private final class AspectFillArtworkView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let drawSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = NSRect(x: bounds.midX - drawSize.width / 2,
                              y: bounds.midY - drawSize.height / 2,
                              width: drawSize.width, height: drawSize.height)
        image.draw(in: drawRect, from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
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
    private let repeatButton = NSButton()
    private let openControlsButton = NSButton()
    private let quitButton = NSButton()
    private let artworkView = AspectFillArtworkView()
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
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 292))
        root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 360),
            root.heightAnchor.constraint(equalToConstant: 292)
        ])
        root.appearance = NSAppearance(named: .darkAqua)
        root.wantsLayer = true
        root.layer?.cornerRadius = 22
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.17, alpha: 1).cgColor
        root.layer?.borderWidth = 0.5
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

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

        repeatButton.bezelStyle = .rounded
        repeatButton.isBordered = false
        repeatButton.font = .systemFont(ofSize: 11, weight: .semibold)
        repeatButton.contentTintColor = NSColor.white.withAlphaComponent(0.86)
        repeatButton.target = self
        repeatButton.action = #selector(toggleRepeatMode)
        repeatButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

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

        quitButton.title = "退出程序"
        quitButton.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quitButton.imagePosition = .imageLeading
        quitButton.imageHugsTitle = true
        quitButton.font = .systemFont(ofSize: 12, weight: .semibold)
        quitButton.contentTintColor = NSColor.systemRed.withAlphaComponent(0.92)
        quitButton.bezelStyle = .regularSquare
        quitButton.isBordered = false
        quitButton.target = NSApplication.shared
        quitButton.action = #selector(NSApplication.terminate(_:))
        quitButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let stack = NSStackView(views: [metadata, times, buttons, repeatButton, openControlsButton, quitButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            buttons.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
            openControlsButton.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
            quitButton.centerXAnchor.constraint(equalTo: stack.centerXAnchor)
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
        repeatButton.title = audio.repeatMode.title
        let trackPath = audio.currentURL?.path
        let hasSharedArtwork = audio.currentArtwork != nil
        guard trackPath != artworkTrackPath || (hasSharedArtwork && artworkView.image == nil) else { return }
        artworkTrackPath = trackPath
        artworkTask?.cancel()
        artworkView.image = audio.currentArtwork
        if hasSharedArtwork { return }
        guard let trackPath, let track = library.tracks.first(where: { $0.path == trackPath }) else { return }
        artworkTask = Task { [weak self, library] in
            let image = await library.artwork(for: track)
            guard !Task.isCancelled, let self, self.artworkTrackPath == trackPath else { return }
            self.artworkView.image = image
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
    @objc private func toggleRepeatMode() { audio.cycleRepeatMode(); updateState() }
    @objc private func previousTrack() { _ = audio.playAdjacentTrack(-1); updateState() }
    @objc private func nextTrack() { _ = audio.playAdjacentTrack(1); updateState() }
}


