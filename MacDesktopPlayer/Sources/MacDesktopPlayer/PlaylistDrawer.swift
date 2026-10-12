import AppKit
import Foundation

private enum DrawerGeometry {
    static let width: CGFloat = 324
    static let handleWidth: CGFloat = 72
    static let handleHeight: CGFloat = 120
}

@MainActor
final class PlaylistDrawerController {
    private let audio: LocalAudioPlayer
    private let library: MusicLibraryStore
    private let onOpenControls: () -> Void
    private let onArtworkChange: (NSImage?) -> Void
    private let panel = PlaylistDrawerPanel(contentRect: NSRect(x: 0, y: 0, width: DrawerGeometry.handleWidth, height: DrawerGeometry.handleHeight),
                                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var drawerView: PlaylistDrawerView?
    private var expanded = false
    private var transitionGeneration = 0
    private var displayScreen: NSScreen?

    init(audio: LocalAudioPlayer, library: MusicLibraryStore, onOpenControls: @escaping () -> Void,
         onArtworkChange: @escaping (NSImage?) -> Void) {
        self.audio = audio
        self.library = library
        self.onOpenControls = onOpenControls
        self.onArtworkChange = onArtworkChange
    }

    func show(on screen: NSScreen) {
        displayScreen = screen
        panel.setFrame(collapsedFrame(on: screen), display: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        let content = PlaylistDrawerView(audio: audio, library: library,
            onOpenControls: onOpenControls,
            onArtworkChange: onArtworkChange,
            onExpansionChange: { [weak self] expanded in self?.setExpanded(expanded, screen: screen) })
        drawerView = content
        panel.contentView = content
        panel.orderFrontRegardless()
    }

    func openFromControls() {
        guard let screen = displayScreen else { return }
        // Bring the drawer above the console when explicitly opened from it.
        panel.level = .floating
        setExpanded(true, screen: screen)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func collapsedFrame(on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.minX, y: screen.frame.midY - DrawerGeometry.handleHeight / 2,
               width: DrawerGeometry.handleWidth, height: DrawerGeometry.handleHeight)
    }

    private func setExpanded(_ expanded: Bool, screen: NSScreen) {
        guard self.expanded != expanded else { return }
        self.expanded = expanded
        transitionGeneration += 1
        let generation = transitionGeneration
        if expanded {
            // Keep the window stationary during the slide so text and blur are never squeezed.
            panel.setFrame(NSRect(x: screen.frame.minX, y: screen.frame.minY,
                                  width: DrawerGeometry.width + DrawerGeometry.handleWidth, height: screen.frame.height), display: true)
            drawerView?.layoutSubtreeIfNeeded()
        }
        drawerView?.setExpanded(expanded) { [weak self] in
            guard let self, self.transitionGeneration == generation else { return }
            if !expanded {
                self.panel.setFrame(self.collapsedFrame(on: screen), display: true)
                self.panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            }
        }
    }
}

@MainActor
final class PlaylistDrawerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class DrawerToggleButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Treat the entire handle as the target, including its empty margins.
        guard isEnabled else { return }
        sendAction(action, to: target)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { contentTintColor = .white.withAlphaComponent(0.72) }

    override func mouseExited(with event: NSEvent) { contentTintColor = .white }
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
final class PlaylistHorizontalScrollView: NSScrollView {
    var documentWidth: CGFloat = 300 {
        didSet { needsLayout = true }
    }

    override func layout() {
        super.layout()
        // Keep the document independent of the clip view's moving bounds.
        documentView?.setFrameSize(NSSize(width: documentWidth, height: contentSize.height))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let documentView,
              documentView.frame.width > contentView.bounds.width else {
            super.scrollWheel(with: event)
            return
        }
        // A normal mouse wheel also navigates the horizontal playlist strip.
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 20
        let maximum = max(0, documentView.frame.width - contentView.bounds.width)
        let x = min(maximum, max(0, contentView.bounds.minX - delta * multiplier))
        contentView.scroll(to: NSPoint(x: x, y: 0))
        reflectScrolledClipView(contentView)
    }
}

@MainActor
final class PlaylistDrawerView: NSView, NSSearchFieldDelegate {
    private let audio: LocalAudioPlayer
    private let library: MusicLibraryStore
    private let onOpenControls: () -> Void
    private let onArtworkChange: (NSImage?) -> Void
    private let onExpansionChange: (Bool) -> Void
    private var expanded = false
    private let surface = NSView()
    private var animating = false
    private let arrowButton = DrawerToggleButton()
    private let heading = NSTextField(labelWithString: "歌曲")
    private let sourceControl = NSSegmentedControl(labels: ["本地", "平台"], trackingMode: .selectOne, target: nil, action: nil)
    private let searchField = NSSearchField()
    private let songStack = DrawerSongStack()
    private let scrollView = NSScrollView()
    private let platformPlaylistScroll = PlaylistHorizontalScrollView()
    private let platformPlaylistStack = NSStackView()
    private let playbackLoadingView = PlatformPlaybackLoadingView()
    private let platformLoadMoreButton = NSButton(title: "加载更多", target: nil, action: nil)
    private var platformLoadMoreWidthConstraint: NSLayoutConstraint!
    private let controlsButton = NSButton(title: "打开控制面板", target: nil, action: nil)
    private var expandedVerticalConstraints: [NSLayoutConstraint] = []
    private var localScrollTopConstraint: NSLayoutConstraint!
    private var platformScrollTopConstraint: NSLayoutConstraint!
    private var platformPlaylistConstraints: [NSLayoutConstraint] = []
    private var libraryObserver: NSObjectProtocol?
    private var platformScrollObserver: NSObjectProtocol?
    private var platformPlaylists: [PlatformPlaylist] = []
    private var platformTracks: [PlatformTrack] = []
    private var selectedPlatformPlaylist: PlatformPlaylist?
    private var platformLoading = false
    private var platformLoadingMore = false
    private var platformHasMore = false
    private let platformPageSize = 40
    private var platformArtworkGeneration = 0
    private var currentPlatformTrackID: String?
    private var currentPlatformCachedPath: String?
    private var platformTrackSwitchInProgress = false
    private var platformPlaybackRequestGeneration = 0

    init(audio: LocalAudioPlayer, library: MusicLibraryStore, onOpenControls: @escaping () -> Void,
         onArtworkChange: @escaping (NSImage?) -> Void,
         onExpansionChange: @escaping (Bool) -> Void) {
        self.audio = audio
        self.library = library
        self.onOpenControls = onOpenControls
        self.onArtworkChange = onArtworkChange
        self.onExpansionChange = onExpansionChange
        super.init(frame: NSRect(x: 0, y: 0, width: DrawerGeometry.handleWidth, height: DrawerGeometry.handleHeight))
        audio.onPlatformAdjacentTrack = { [weak self] direction in
            self?.playAdjacentPlatformTrack(direction) ?? false
        }
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
        arrowButton.toolTip = "展开或收起歌曲列表"
        arrowButton.target = self
        arrowButton.action = #selector(toggleExpanded)
        addSubview(arrowButton)

        heading.font = .systemFont(ofSize: 19, weight: .semibold)
        heading.textColor = .white
        heading.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(heading)
        sourceControl.selectedSegment = 0
        sourceControl.segmentStyle = .texturedRounded
        sourceControl.target = self
        sourceControl.action = #selector(sourceChanged(_:))
        sourceControl.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(sourceControl)
        searchField.placeholderString = "搜索歌曲 / 歌手"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(searchField)

        songStack.orientation = .vertical
        songStack.alignment = .leading
        songStack.spacing = 8
        songStack.translatesAutoresizingMaskIntoConstraints = false
        platformLoadMoreWidthConstraint = platformLoadMoreButton.widthAnchor.constraint(equalTo: songStack.widthAnchor)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView = DrawerClipView()
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = songStack
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(scrollView)
        platformPlaylistStack.orientation = .horizontal
        platformPlaylistStack.alignment = .centerY
        platformPlaylistStack.distribution = .fill
        platformPlaylistStack.spacing = 8
        platformPlaylistStack.translatesAutoresizingMaskIntoConstraints = true
        platformPlaylistStack.frame = NSRect(x: 0, y: 0, width: 300, height: 58)
        platformPlaylistScroll.drawsBackground = false
        platformPlaylistScroll.hasHorizontalScroller = true
        platformPlaylistScroll.hasVerticalScroller = false
        platformPlaylistScroll.scrollerStyle = .legacy
        platformPlaylistScroll.autohidesScrollers = false
        platformPlaylistScroll.documentView = platformPlaylistStack
        platformPlaylistScroll.translatesAutoresizingMaskIntoConstraints = false
        platformPlaylistScroll.isHidden = true
        surface.addSubview(platformPlaylistScroll)
        playbackLoadingView.translatesAutoresizingMaskIntoConstraints = false
        playbackLoadingView.isHidden = true
        surface.addSubview(playbackLoadingView)
        controlsButton.bezelStyle = .rounded
        controlsButton.target = self
        controlsButton.action = #selector(openControls)
        controlsButton.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(controlsButton)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            sourceControl.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            sourceControl.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
            searchField.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
            scrollView.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -12),
            playbackLoadingView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            playbackLoadingView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            playbackLoadingView.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 4),
            playbackLoadingView.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -4),
            playbackLoadingView.widthAnchor.constraint(equalToConstant: 292),
            playbackLoadingView.heightAnchor.constraint(equalToConstant: 92),
            platformPlaylistScroll.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 12),
            platformPlaylistScroll.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -12),
            songStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            songStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            songStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            controlsButton.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            controlsButton.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
        ])
        expandedVerticalConstraints = [
            heading.topAnchor.constraint(equalTo: surface.topAnchor, constant: 34),
            sourceControl.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            sourceControl.heightAnchor.constraint(equalToConstant: 28),
            searchField.topAnchor.constraint(equalTo: sourceControl.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: controlsButton.topAnchor, constant: -16),
            controlsButton.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -28),
            controlsButton.heightAnchor.constraint(equalToConstant: 34)
        ]
        localScrollTopConstraint = scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14)
        platformScrollTopConstraint = scrollView.topAnchor.constraint(equalTo: platformPlaylistScroll.bottomAnchor, constant: 10)
        platformPlaylistConstraints = [
            platformPlaylistScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            platformPlaylistScroll.heightAnchor.constraint(equalToConstant: 58)
        ]
        NSLayoutConstraint.activate([localScrollTopConstraint])
        platformScrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.loadMorePlatformTracksIfNeeded() }
        }
        libraryObserver = NotificationCenter.default.addObserver(forName: .desktopMusicLibraryChanged,
            object: library, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if self?.expanded == true { self?.refreshRows() } }
            }
    }

    required init?(coder: NSCoder) { nil }
    deinit {
        if let libraryObserver { NotificationCenter.default.removeObserver(libraryObserver) }
        if let platformScrollObserver { NotificationCenter.default.removeObserver(platformScrollObserver) }
    }

    override func layout() {
        super.layout()
        guard !animating else { return }
        surface.frame = NSRect(x: expanded ? 0 : -324, y: 0, width: 324, height: bounds.height)
        arrowButton.frame = NSRect(x: expanded ? DrawerGeometry.width : 0,
                                   y: bounds.midY - DrawerGeometry.handleHeight / 2,
                                   width: DrawerGeometry.handleWidth, height: DrawerGeometry.handleHeight)
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
            arrowButton.animator().setFrameOrigin(NSPoint(x: expanded ? DrawerGeometry.width : 0,
                                                          y: bounds.midY - DrawerGeometry.handleHeight / 2))
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
        guard sourceControl.selectedSegment == 0 else {
            refreshPlatformRows()
            return
        }
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
                    self.currentPlatformTrackID = nil
                    self.currentPlatformCachedPath = nil
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

    private func refreshPlatformRows() {
        let needle = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // This constraint connects the load-more button to songStack. It must
        // be inactive while the old button is outside the stack hierarchy.
        platformLoadMoreWidthConstraint?.isActive = false
        songStack.arrangedSubviews.forEach { songStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let tracks = platformTracks.filter {
            needle.isEmpty || $0.name.localizedCaseInsensitiveContains(needle)
                || $0.displayArtist.localizedCaseInsensitiveContains(needle)
        }
        heading.stringValue = selectedPlatformPlaylist.map { "平台 · \($0.name) · \(tracks.count)" } ?? "平台歌曲"
        for (index, track) in tracks.enumerated() {
            let row = PlatformDrawerRow(track: track, index: index, onSelect: { [weak self] in
                self?.playPlatformTrack(track)
            })
            songStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: songStack.widthAnchor).isActive = true
        }
        if tracks.isEmpty {
            let empty = NSTextField(labelWithString: platformLoading ? "正在读取平台歌曲…" : "请选择歌单")
            empty.textColor = .white.withAlphaComponent(0.65)
            songStack.addArrangedSubview(empty)
        }
        if platformHasMore && !tracks.isEmpty {
            platformLoadMoreButton.title = platformLoadingMore ? "正在加载…" : "加载更多 · 已加载 \(platformTracks.count) 首"
            platformLoadMoreButton.bezelStyle = .rounded
            platformLoadMoreButton.font = .systemFont(ofSize: 12, weight: .medium)
            platformLoadMoreButton.contentTintColor = .white.withAlphaComponent(0.86)
            platformLoadMoreButton.target = self
            platformLoadMoreButton.action = #selector(loadMorePlatformTracks)
            platformLoadMoreButton.isEnabled = !platformLoadingMore
            songStack.addArrangedSubview(platformLoadMoreButton)
            // Activate only after the button has a common ancestor with the
            // stack. Activating it before addArrangedSubview causes an
            // NSGenericException during playlist opening.
            platformLoadMoreWidthConstraint.isActive = true
        }
    }

    private func loadPlatformPlaylists() {
        guard !platformLoading else { return }
        platformLoading = true
        refreshPlatformRows()
        Task { [weak self] in
            do {
                let bridge = await PlatformBridgeRuntime.shared.ensureRunning()
                if case .failure(let error) = bridge { throw error }
                let playlists = try await PlatformBridgeClient.shared.userPlaylists(for: .netease)
                guard let self else { return }
                self.platformLoading = false
                self.platformPlaylists = playlists
                self.renderPlatformPlaylists()
                if let first = playlists.first { self.selectPlatformPlaylist(first) }
                else { self.refreshPlatformRows() }
            } catch {
                self?.platformLoading = false
                self?.statusMessage("平台歌单读取失败：\(error.localizedDescription)")
                self?.refreshPlatformRows()
            }
        }
    }

    private func renderPlatformPlaylists() {
        platformPlaylistStack.arrangedSubviews.forEach { platformPlaylistStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let chipWidth: CGFloat = 140
        let chipSpacing: CGFloat = 8
        platformPlaylistScroll.documentWidth = max(1, CGFloat(platformPlaylists.count) * (chipWidth + chipSpacing) - chipSpacing)
        // NSStackView lays out every arranged chip against its document view's
        // width. Set that width before inserting fixed-width chips so AppKit
        // never tries to squeeze the whole playlist into the initial 300pt.
        platformPlaylistStack.setFrameSize(NSSize(width: platformPlaylistScroll.documentWidth, height: 58))
        for playlist in platformPlaylists {
            let button = NSButton(title: playlist.name, target: self, action: #selector(platformPlaylistPressed(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(playlist.id)
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.contentTintColor = .white.withAlphaComponent(0.9)
            button.alignment = .left
            button.lineBreakMode = .byTruncatingTail
            button.cell?.usesSingleLineMode = true
            button.cell?.wraps = false
            button.cell?.truncatesLastVisibleLine = true
            button.cell?.lineBreakMode = .byTruncatingTail
            button.wantsLayer = true
            button.layer?.masksToBounds = true
            button.cell?.lineBreakMode = .byTruncatingTail
            button.cell?.truncatesLastVisibleLine = true
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.widthAnchor.constraint(equalToConstant: chipWidth).isActive = true
            button.heightAnchor.constraint(equalToConstant: 42).isActive = true
            platformPlaylistStack.addArrangedSubview(button)
        }
        platformPlaylistScroll.contentView.scroll(to: .zero)
        platformPlaylistScroll.reflectScrolledClipView(platformPlaylistScroll.contentView)
    }

    private func selectPlatformPlaylist(_ playlist: PlatformPlaylist) {
        selectedPlatformPlaylist = playlist
        platformTracks = []
        platformHasMore = true
        platformLoadingMore = false
        refreshPlatformRows()
        statusMessage("正在读取：\(playlist.name)…")
        Task { [weak self] in
            do {
                let tracks = try await PlatformBridgeClient.shared.playlistTracks(playlist, provider: .netease,
                                                                                   limit: self?.platformPageSize ?? 40,
                                                                                   offset: 0)
                guard let self else { return }
                self.platformTracks = tracks
                self.platformHasMore = tracks.count == self.platformPageSize
                self.refreshPlatformRows()
                self.statusMessage("\(playlist.name) · \(tracks.count) 首 · 点击即可播放")
            } catch { self?.statusMessage("平台歌曲读取失败：\(error.localizedDescription)") }
        }
    }

    @objc private func loadMorePlatformTracks() {
        guard let playlist = selectedPlatformPlaylist, platformHasMore, !platformLoadingMore else { return }
        platformLoadingMore = true
        refreshPlatformRows()
        let offset = platformTracks.count
        Task { [weak self] in
            do {
                let tracks = try await PlatformBridgeClient.shared.playlistTracks(playlist, provider: .netease,
                                                                                   limit: self?.platformPageSize ?? 40,
                                                                                   offset: offset)
                guard let self, self.selectedPlatformPlaylist?.id == playlist.id else { return }
                self.platformTracks.append(contentsOf: tracks)
                self.platformHasMore = tracks.count == self.platformPageSize
                self.platformLoadingMore = false
                self.refreshPlatformRows()
            } catch {
                self?.platformLoadingMore = false
                self?.statusMessage("加载更多失败：\(error.localizedDescription)")
                self?.refreshPlatformRows()
            }
        }
    }

    private func loadMorePlatformTracksIfNeeded() {
        guard expanded,
              sourceControl.selectedSegment == 1,
              platformHasMore,
              !platformLoadingMore,
              let documentView = scrollView.documentView else { return }
        let visibleBottom = scrollView.contentView.bounds.maxY
        let remaining = documentView.bounds.height - visibleBottom
        // Start the next page before the user reaches the end so the list
        // keeps moving without waiting on the network at the bottom edge.
        guard remaining <= 520 else { return }
        loadMorePlatformTracks()
    }

    private func playPlatformTrack(_ track: PlatformTrack) {
        platformPlaybackRequestGeneration += 1
        let request = platformPlaybackRequestGeneration
        playbackLoadingView.dismiss()
        currentPlatformTrackID = track.id
        currentPlatformCachedPath = nil
        platformTrackSwitchInProgress = true
        statusMessage("正在获取播放地址：\(track.name)…")
        Task { [weak self] in
            do {
                let cacheHit = await PlatformBridgeClient.shared.hasCachedAudioFile(for: track)
                guard let self, self.platformPlaybackRequestGeneration == request else { return }
                if !cacheHit, self.sourceControl.selectedSegment == 1 {
                    self.playbackLoadingView.present(trackName: track.name)
                }
                let prepared = try await PlatformBridgeClient.shared.preparedAudioFile(for: track)
                guard self.platformPlaybackRequestGeneration == request else { return }
                self.playbackLoadingView.dismiss()
                self.currentPlatformCachedPath = prepared.fileURL.path
                self.platformTrackSwitchInProgress = false
                self.audio.play(url: prepared.fileURL, title: track.name, artist: track.displayArtist)
                self.platformArtworkGeneration += 1
                let generation = self.platformArtworkGeneration
                self.onArtworkChange(nil)
                Task { [weak self] in
                    let image = await resolvePlatformArtwork(title: track.name, artist: track.displayArtist,
                                                             album: track.album, fallbackURL: track.coverURL ?? prepared.remoteURL)
                    guard let self, self.platformArtworkGeneration == generation else { return }
                    self.onArtworkChange(image)
                }
                self.statusMessage("正在播放：\(track.name) · 已进入实时分析")
                if let index = self.platformTracks.firstIndex(where: { $0.id == track.id }),
                   self.platformTracks.indices.contains(index + 1) {
                    let nextTrack = self.platformTracks[index + 1]
                    Task { _ = try? await PlatformBridgeClient.shared.preparedAudioFile(for: nextTrack) }
                }
            } catch {
                guard let self, self.platformPlaybackRequestGeneration == request else { return }
                self.playbackLoadingView.dismiss()
                self.platformTrackSwitchInProgress = false
                self.statusMessage("平台播放失败：\(error.localizedDescription)")
            }
        }
    }

    private func playAdjacentPlatformTrack(_ direction: Int) -> Bool {
        guard let currentPlatformTrackID else { return false }
        if platformTrackSwitchInProgress { return true }
        guard let currentPlatformCachedPath,
              audio.currentURL?.path == currentPlatformCachedPath else { return false }
        guard let index = platformTracks.firstIndex(where: { $0.id == currentPlatformTrackID }) else { return true }
        let targetIndex = index + direction
        guard platformTracks.indices.contains(targetIndex) else { return true }
        platformTrackSwitchInProgress = true
        playPlatformTrack(platformTracks[targetIndex])
        return true
    }

    private func statusMessage(_ message: String) {
        heading.stringValue = message
        controlsButton.toolTip = message
    }

    @objc private func sourceChanged(_ sender: NSSegmentedControl) {
        let platform = sender.selectedSegment == 1
        searchField.placeholderString = platform ? "筛选平台歌曲 / 歌手" : "搜索歌曲 / 歌手"
        if platform {
            localScrollTopConstraint.isActive = false
            platformPlaylistConstraints.forEach { $0.isActive = true }
            platformScrollTopConstraint.isActive = true
            platformPlaylistScroll.isHidden = false
            loadPlatformPlaylists()
        } else {
            platformPlaybackRequestGeneration += 1
            playbackLoadingView.dismiss()
            platformScrollTopConstraint.isActive = false
            platformPlaylistConstraints.forEach { $0.isActive = false }
            localScrollTopConstraint.isActive = true
            platformPlaylistScroll.isHidden = true
            refreshRows()
        }
        layoutSubtreeIfNeeded()
    }

    @objc private func platformPlaylistPressed(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let playlist = platformPlaylists.first(where: { $0.id == id }) else { return }
        selectPlatformPlaylist(playlist)
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
final class PlatformDrawerRow: NSView {
    private let track: PlatformTrack
    private let onSelect: () -> Void
    private let coverView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private var artworkTask: Task<Void, Never>?
    private var tracking: NSTrackingArea?

    init(track: PlatformTrack, index: Int, onSelect: @escaping () -> Void) {
        self.track = track
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 68))
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 68).isActive = true

        coverView.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "专辑封面")
        coverView.contentTintColor = NSColor.white.withAlphaComponent(0.58)
        coverView.imageScaling = .scaleProportionallyUpOrDown
        coverView.wantsLayer = true
        coverView.layer?.cornerRadius = 10
        coverView.layer?.masksToBounds = true
        coverView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        coverView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coverView)

        titleLabel.stringValue = track.name
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        artistLabel.stringValue = track.album.map { "\(track.displayArtist) · \($0)" } ?? track.displayArtist
        artistLabel.font = .systemFont(ofSize: 11, weight: .regular)
        artistLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        addSubview(artistLabel)

        let button = NSButton(title: "", target: self, action: #selector(selectPressed))
        button.isBordered = false
        button.focusRingType = .none
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            coverView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            coverView.centerYAnchor.constraint(equalTo: centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: 48),
            coverView.heightAnchor.constraint(equalToConstant: 48),
            titleLabel.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            artistLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            artistLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        menu = NSMenu(title: "平台歌曲操作")
        menu?.addItem(withTitle: "播放", action: #selector(selectPressed), keyEquivalent: "")
        artworkTask = Task { [weak self] in
            guard let url = track.coverURL,
                  let image = try? await PlatformBridgeClient.shared.coverImage(for: url),
                  !Task.isCancelled else { return }
            guard let self else { return }
            self.coverView.image = image
            self.coverView.contentTintColor = nil
        }
        animateEntrance(delay: min(Double(index) * 0.035, 0.28))
    }

    required init?(coder: NSCoder) { nil }

    private func animateEntrance(delay: Double) {
        alphaValue = 0
        layer?.setAffineTransform(CGAffineTransform(translationX: 28, y: 0))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.42
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.92, 0.25, 1)
                self.animator().alphaValue = 1
                self.layer?.setAffineTransform(.identity)
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { animateHover(true) }
    override func mouseExited(with event: NSEvent) { animateHover(false) }

    private func animateHover(_ hovered: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.24)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1))
        coverView.layer?.setAffineTransform(hovered ? CGAffineTransform(scaleX: 1.08, y: 1.08).translatedBy(x: 2, y: 0) : .identity)
        layer?.backgroundColor = (hovered ? NSColor.white.withAlphaComponent(0.13) : NSColor.white.withAlphaComponent(0.06)).cgColor
        CATransaction.commit()
    }

    @objc private func selectPressed() { onSelect() }
    deinit { artworkTask?.cancel() }
}


