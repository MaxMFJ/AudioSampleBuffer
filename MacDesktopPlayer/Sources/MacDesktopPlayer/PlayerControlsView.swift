import AppKit
import Foundation
#if SWIFT_PACKAGE
import YAMNetMac
#endif

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
    private var platformAccountWindow: PlatformAccountWindowController?
    private var platformLibraryWindow: PlatformLibraryWindowController?
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
    private let onOpenSongList: (NSScreen?) -> Void

    init(audio: LocalAudioPlayer, library: MusicLibraryStore,
         onBackgroundEffectChange: @escaping (DesktopBackgroundEffect) -> Void,
         onArtworkChange: @escaping (NSImage?) -> Void,
         onOpenSongList: @escaping (NSScreen?) -> Void) {
        self.audio = audio
        self.library = library
        self.onBackgroundEffectChange = onBackgroundEffectChange
        self.onArtworkChange = onArtworkChange
        self.onOpenSongList = onOpenSongList
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
        let accountsButton = NSButton(title: "平台账号", target: self, action: #selector(showPlatformAccounts))
        accountsButton.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "平台账号")
        accountsButton.imagePosition = .imageLeading
        accountsButton.bezelStyle = .rounded
        accountsButton.font = .systemFont(ofSize: 13, weight: .medium)
        let songsButton = NSButton(title: "歌曲列表", target: self, action: #selector(showSongList))
        songsButton.image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "歌曲列表")
        songsButton.imagePosition = .imageLeading
        songsButton.bezelStyle = .rounded
        songsButton.font = .systemFont(ofSize: 13, weight: .medium)
        let platformSongsButton = NSButton(title: "平台歌单", target: self, action: #selector(showPlatformLibrary))
        platformSongsButton.image = NSImage(systemSymbolName: "cloud", accessibilityDescription: "平台歌单")
        platformSongsButton.imagePosition = .imageLeading
        platformSongsButton.bezelStyle = .rounded
        platformSongsButton.font = .systemFont(ofSize: 13, weight: .medium)
        let headerActions = NSStackView(views: [brand, songsButton, lyricsButton, accountsButton])
        headerActions.orientation = .horizontal
        headerActions.alignment = .centerY
        headerActions.addArrangedSubview(platformSongsButton)
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
        let repeatButton = NSButton(title: audio.repeatMode.title, target: self, action: #selector(toggleRepeatMode))
        repeatButton.image = NSImage(systemSymbolName: audio.repeatMode.symbolName, accessibilityDescription: "播放模式")
        repeatButton.imagePosition = .imageLeading
        repeatButton.bezelStyle = .rounded
        repeatButton.font = .systemFont(ofSize: 12, weight: .medium)
        nowPlaying.lineBreakMode = .byTruncatingTail
        nowPlaying.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nowPlaying.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for button in [previousButton, playButton, nextButton, stopButton, favoriteButton, repeatButton] { button.bezelStyle = .rounded }
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
        let transport = NSStackView(views: [previousButton, playButton, nextButton, stopButton, favoriteButton, repeatButton, nowPlaying])
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
    @objc private func showPlatformAccounts() {
        if platformAccountWindow == nil { platformAccountWindow = PlatformAccountWindowController() }
        platformAccountWindow?.showWindow(nil)
        platformAccountWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func previousTrack() { _ = audio.playAdjacentTrack(-1) }
    @objc private func nextTrack() { _ = audio.playAdjacentTrack(1) }
    @objc private func toggleRepeatMode(_ sender: NSButton) {
        audio.cycleRepeatMode()
        sender.title = audio.repeatMode.title
        sender.image = NSImage(systemSymbolName: audio.repeatMode.symbolName, accessibilityDescription: "播放模式")
    }
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
    @objc private func showSongList() {
        onOpenSongList(window?.screen)
    }
    @objc private func showPlatformLibrary() {
        if platformLibraryWindow == nil {
            platformLibraryWindow = PlatformLibraryWindowController { [weak self] url, title, artist, coverURL in
                guard let self else { return }
                self.audio.play(url: url, title: title, artist: artist)
                self.artworkLoadGeneration += 1
                let generation = self.artworkLoadGeneration
                self.onArtworkChange(nil)
                Task { [weak self] in
                    let image = await resolvePlatformArtwork(title: title, artist: artist,
                                                             album: nil, fallbackURL: coverURL)
                    guard let self, self.artworkLoadGeneration == generation else { return }
                    self.onArtworkChange(image)
                }
            }
        }
        platformLibraryWindow?.showWindow(nil)
        platformLibraryWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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


