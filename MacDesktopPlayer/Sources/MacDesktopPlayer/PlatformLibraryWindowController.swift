import AppKit

@MainActor
final class PlatformLibraryWindowController: NSWindowController {
    init(play: @escaping (URL, String, String, URL?) -> Void) {
        let view = PlatformLibraryView(play: play)
        let window = NSWindow(contentViewController: NSViewController())
        window.title = "平台歌单"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 860, height: 560))
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = view
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
private final class PlatformLibraryView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let play: (URL, String, String, URL?) -> Void
    private let playlistsTable = NSTableView()
    private let tracksTable = NSTableView()
    private let status = NSTextField(labelWithString: "正在读取网易云歌单…")
    private var playlists: [PlatformPlaylist] = []
    private var tracks: [PlatformTrack] = []
    private var selectedPlaylist: PlatformPlaylist?
    private let playbackLoadingView = PlatformPlaybackLoadingView()
    private var playbackRequestGeneration = 0

    init(play: @escaping (URL, String, String, URL?) -> Void) {
        self.play = play
        super.init(frame: .zero)
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        buildUI()
        loadPlaylists()
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        let title = NSTextField(labelWithString: "网易云音乐 · 我的歌单")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let refresh = NSButton(title: "刷新", target: self, action: #selector(loadPlaylists))
        refresh.bezelStyle = .rounded
        refresh.translatesAutoresizingMaskIntoConstraints = false

        let playlistColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("playlist"))
        playlistColumn.title = "歌单"
        playlistColumn.width = 230
        playlistsTable.addTableColumn(playlistColumn)
        playlistsTable.headerView = nil
        playlistsTable.dataSource = self
        playlistsTable.delegate = self
        playlistsTable.rowHeight = 42
        playlistsTable.usesAlternatingRowBackgroundColors = true
        let playlistScroll = NSScrollView()
        playlistScroll.hasVerticalScroller = true
        playlistScroll.documentView = playlistsTable
        playlistScroll.translatesAutoresizingMaskIntoConstraints = false

        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.title = "歌曲"
        let artistColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("artist"))
        artistColumn.title = "歌手"
        artistColumn.width = 190
        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionColumn.title = ""
        actionColumn.width = 86
        tracksTable.addTableColumn(titleColumn)
        tracksTable.addTableColumn(artistColumn)
        tracksTable.addTableColumn(actionColumn)
        tracksTable.dataSource = self
        tracksTable.delegate = self
        tracksTable.rowHeight = 40
        tracksTable.usesAlternatingRowBackgroundColors = true
        let trackScroll = NSScrollView()
        trackScroll.hasVerticalScroller = true
        trackScroll.documentView = tracksTable
        trackScroll.translatesAutoresizingMaskIntoConstraints = false

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false

        addSubview(title)
        addSubview(refresh)
        addSubview(playlistScroll)
        addSubview(trackScroll)
        playbackLoadingView.translatesAutoresizingMaskIntoConstraints = false
        playbackLoadingView.isHidden = true
        addSubview(playbackLoadingView)
        addSubview(status)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            refresh.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            refresh.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            playlistScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            playlistScroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 18),
            playlistScroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -12),
            playlistScroll.widthAnchor.constraint(equalToConstant: 240),
            trackScroll.leadingAnchor.constraint(equalTo: playlistScroll.trailingAnchor, constant: 16),
            trackScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            trackScroll.topAnchor.constraint(equalTo: playlistScroll.topAnchor),
            trackScroll.bottomAnchor.constraint(equalTo: playlistScroll.bottomAnchor),
            playbackLoadingView.centerXAnchor.constraint(equalTo: trackScroll.centerXAnchor),
            playbackLoadingView.centerYAnchor.constraint(equalTo: trackScroll.centerYAnchor),
            playbackLoadingView.widthAnchor.constraint(equalToConstant: 292),
            playbackLoadingView.heightAnchor.constraint(equalToConstant: 92),
            status.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            status.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18)
        ])
    }

    @objc private func loadPlaylists() {
        status.stringValue = "正在读取网易云歌单…"
        Task { [weak self] in
            do {
                let bridge = await PlatformBridgeRuntime.shared.ensureRunning()
                if case .failure(let error) = bridge { throw error }
                let playlists = try await PlatformBridgeClient.shared.userPlaylists(for: .netease)
                guard let self else { return }
                self.playlists = playlists
                self.playlistsTable.reloadData()
                if let first = playlists.first {
                    self.selectedPlaylist = first
                    self.playlistsTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                    self.loadTracks(first)
                } else {
                    self.status.stringValue = "没有读取到歌单，请确认网易云已经登录"
                }
            } catch {
                self?.status.stringValue = "读取歌单失败：\(error.localizedDescription)"
            }
        }
    }

    private func loadTracks(_ playlist: PlatformPlaylist) {
        selectedPlaylist = playlist
        tracks = []
        tracksTable.reloadData()
        status.stringValue = "正在读取：\(playlist.name)…"
        Task { [weak self] in
            do {
                let tracks = try await PlatformBridgeClient.shared.playlistTracks(playlist, provider: .netease)
                guard let self else { return }
                self.tracks = tracks
                self.tracksTable.reloadData()
                self.status.stringValue = "\(playlist.name) · \(tracks.count) 首 · 点击播放即可在线播放"
            } catch {
                self?.status.stringValue = "读取歌曲失败：\(error.localizedDescription)"
            }
        }
    }

    private func playTrack(_ track: PlatformTrack) {
        playbackRequestGeneration += 1
        let request = playbackRequestGeneration
        playbackLoadingView.dismiss()
        status.stringValue = "正在获取播放地址：\(track.name)…"
        Task { [weak self] in
            do {
                let cacheHit = await PlatformBridgeClient.shared.hasCachedAudioFile(for: track)
                guard let self, self.playbackRequestGeneration == request else { return }
                if !cacheHit { self.playbackLoadingView.present(trackName: track.name) }
                let prepared = try await PlatformBridgeClient.shared.preparedAudioFile(for: track)
                guard self.playbackRequestGeneration == request else { return }
                self.playbackLoadingView.dismiss()
                self.play(prepared.fileURL, track.name, track.displayArtist, track.coverURL)
                self.status.stringValue = "正在播放：\(track.name)"
                if let index = self.tracks.firstIndex(where: { $0.id == track.id }),
                   self.tracks.indices.contains(index + 1) {
                    let nextTrack = self.tracks[index + 1]
                    Task { _ = try? await PlatformBridgeClient.shared.preparedAudioFile(for: nextTrack) }
                }
            } catch {
                guard let self, self.playbackRequestGeneration == request else { return }
                self.playbackLoadingView.dismiss()
                self.status.stringValue = "播放失败：\(error.localizedDescription)"
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === playlistsTable ? playlists.count : tracks.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        cell.translatesAutoresizingMaskIntoConstraints = false
        guard let column = tableColumn else { return cell }
        if tableView === playlistsTable, playlists.indices.contains(row) {
            let label = NSTextField(labelWithString: playlists[row].name)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }
        guard tracks.indices.contains(row) else { return cell }
        let track = tracks[row]
        if column.identifier.rawValue == "action" {
            let button = NSButton(title: "播放", target: self, action: #selector(play(_:)))
            button.bezelStyle = .rounded
            button.identifier = NSUserInterfaceItemIdentifier(track.id)
            button.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 64)
            ])
        } else {
            let text = column.identifier.rawValue == "title" ? track.name : track.displayArtist
            let label = NSTextField(labelWithString: text)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView, table === playlistsTable else { return }
        let row = table.selectedRow
        guard playlists.indices.contains(row) else { return }
        loadTracks(playlists[row])
    }

    @objc private func play(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let track = tracks.first(where: { $0.id == id }) else { return }
        playTrack(track)
    }
}

@MainActor
final class PlatformPlaybackLoadingView: NSView {
    private let material = NSVisualEffectView()
    private let spinner = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "正在加载歌曲")
    private let detailLabel = NSTextField(labelWithString: "正在连接平台音源…")
    private let progress = NSProgressIndicator()
    private var visibilityGeneration = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 0.7
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        material.material = .hudWindow
        material.blendingMode = .withinWindow
        material.state = .active
        material.translatesAutoresizingMaskIntoConstraints = false
        addSubview(material)
        NSLayoutConstraint.activate([
            material.leadingAnchor.constraint(equalTo: leadingAnchor),
            material.trailingAnchor.constraint(equalTo: trailingAnchor),
            material.topAnchor.constraint(equalTo: topAnchor),
            material.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(spinner)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(titleLabel)

        detailLabel.font = .systemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(detailLabel)

        progress.style = .bar
        progress.isIndeterminate = true
        progress.controlSize = .small
        progress.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(progress)

        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 16),
            spinner.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 18),
            spinner.heightAnchor.constraint(equalToConstant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: material.topAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -14),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            progress.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            progress.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 8),
            progress.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -12)
        ])
        alphaValue = 0
    }

    required init?(coder: NSCoder) { nil }

    func present(trackName: String) {
        visibilityGeneration += 1
        detailLabel.stringValue = trackName
        isHidden = false
        spinner.startAnimation(nil)
        progress.startAnimation(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard !isHidden else { return }
        visibilityGeneration += 1
        let generation = visibilityGeneration
        spinner.stopAnimation(nil)
        progress.stopAnimation(nil)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.visibilityGeneration == generation else { return }
            self.isHidden = true
        })
    }
}
