import UIKit
import AVKit

public extension Notification.Name {
    static let platformMusicDidResolvePlayback = Notification.Name("PlatformMusicDidResolvePlayback")
    static let platformMusicQueueDidChange = Notification.Name("PlatformMusicQueueDidChange")
    static let platformMusicSkipNext = Notification.Name("PlatformMusicSkipNext")
    static let platformMusicSkipPrevious = Notification.Name("PlatformMusicSkipPrevious")
    static let platformMusicReplayCurrent = Notification.Name("PlatformMusicReplayCurrent")
    static let platformMusicClearQueue = Notification.Name("PlatformMusicClearQueue")
    static let platformMusicLoadSource = Notification.Name("PlatformMusicLoadSource")
    static let platformMusicLoadPlaylist = Notification.Name("PlatformMusicLoadPlaylist")
    static let platformMusicLoadMore = Notification.Name("PlatformMusicLoadMore")
    static let platformMusicSearch = Notification.Name("PlatformMusicSearch")
    static let platformMusicPlayTrackAtIndex = Notification.Name("PlatformMusicPlayTrackAtIndex")
    static let platformMusicLibraryDidUpdate = Notification.Name("PlatformMusicLibraryDidUpdate")
    static let platformMusicRequestMoreForQueue = Notification.Name("PlatformMusicRequestMoreForQueue")
}

@objc(PlatformMusicAccountViewController)
public final class PlatformMusicAccountViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, PlatformLoginViewControllerDelegate {
    private enum Row {
        case local(MusicItem)
        case playlist(ProviderPlaylist)
        case track(ProviderTrack)
    }

    private let platforms: [MusicPlatform] = [.netease, .qqMusic, .kugou]
    private let localLibrary = MusicLibraryManager.shared()
    private var selectedPlatform: MusicPlatform = .netease
    private var rows: [Row] = []
    private var libraryRows: [Row] = []
    private var searchTask: Task<Void, Never>?
    private var tableView: UITableView!
    private var searchBar: UISearchBar!
    private var statusLabel: UILabel!
    private var platformControl: UISegmentedControl!
    private var loginButton: UIButton!
    private var refreshButton: UIButton!
    private var bilibiliLoginButton: UIButton!
    private var loading = false
    private var currentPlaylist: ProviderPlaylist?
    private var mvItemObservation: NSKeyValueObservation?

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "播放列表"
        view.backgroundColor = UIColor(red: 0.055, green: 0.065, blue: 0.09, alpha: 1)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "退出登录", style: .plain, target: self, action: #selector(logout))
        buildInterface()
        updateSourceActions(isLocal: true)
        Task {
            await restoreAndRefresh()
            let state = await MusicAuthManager.shared.restoreAndVerify(platform: .bilibili)
            bilibiliLoginButton.setTitle(state.verifiedLogin ? "B站已登录" : "B站登录", for: .normal)
        }
    }

    private func buildInterface() {
        platformControl = UISegmentedControl(items: ["本地", "网易云", "QQ 音乐", "酷狗"])
        platformControl.selectedSegmentIndex = 0
        platformControl.addTarget(self, action: #selector(platformChanged), for: .valueChanged)
        platformControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(platformControl)

        statusLabel = UILabel()
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.text = "尚未验证登录状态"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        let actions = UIStackView()
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        actions.spacing = 12
        actions.translatesAutoresizingMaskIntoConstraints = false
        loginButton = actionButton("网页登录", icon: "qrcode")
        loginButton.addTarget(self, action: #selector(openLogin), for: .touchUpInside)
        refreshButton = actionButton("我的歌单", icon: "music.note.list")
        refreshButton.addTarget(self, action: #selector(loadPlaylists), for: .touchUpInside)
        bilibiliLoginButton = actionButton("B站登录", icon: "qrcode")
        bilibiliLoginButton.addTarget(self, action: #selector(openBilibiliLogin), for: .touchUpInside)
        actions.addArrangedSubview(loginButton)
        actions.addArrangedSubview(refreshButton)
        actions.addArrangedSubview(bilibiliLoginButton)
        view.addSubview(actions)

        searchBar = UISearchBar()
        searchBar.placeholder = "搜索歌曲"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.autocapitalizationType = .none
        searchBar.returnKeyType = .search
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PlatformMusicRow")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            platformControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            platformControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            platformControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            statusLabel.topAnchor.constraint(equalTo: platformControl.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: platformControl.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: platformControl.trailingAnchor),
            actions.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            actions.leadingAnchor.constraint(equalTo: platformControl.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: platformControl.trailingAnchor),
            actions.heightAnchor.constraint(equalToConstant: 46),
            searchBar.topAnchor.constraint(equalTo: actions.bottomAnchor, constant: 8),
            searchBar.leadingAnchor.constraint(equalTo: platformControl.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: platformControl.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func actionButton(_ title: String, icon: String) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: icon)
        config.imagePadding = 7
        config.baseBackgroundColor = UIColor(red: 0.16, green: 0.25, blue: 0.42, alpha: 1)
        config.baseForegroundColor = .white
        return UIButton(configuration: config)
    }

    @objc private func platformChanged() {
        PlatformMusicService.shared.clearPlaybackQueue()
        currentPlaylist = nil
        rows.removeAll()
        tableView.reloadData()
        let selectedIndex = platformControl.selectedSegmentIndex
        let isLocal = selectedIndex == 0
        updateSourceActions(isLocal: isLocal)
        if isLocal {
            loadLocalSongs()
        } else {
            selectedPlatform = platforms[max(0, min(selectedIndex - 1, platforms.count - 1))]
            Task { await restoreAndRefresh() }
        }
    }

    @objc private func openLogin() {
        if platformControl.selectedSegmentIndex == 0 {
            platformControl.selectedSegmentIndex = 1
            selectedPlatform = .netease
            updateSourceActions(isLocal: false)
            rows.removeAll()
            tableView.reloadData()
        }
        let controller = PlatformLoginViewController(platform: selectedPlatform)
        controller.delegate = self
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func loadPlaylists() {
        if platformControl.selectedSegmentIndex == 0 { loadLocalSongs() }
        else { Task { await loadUserPlaylists() } }
    }

    @objc private func logout() {
        let picker = UIAlertController(title: "退出登录", message: "选择要清除的网页登录态", preferredStyle: .actionSheet)
        picker.addAction(UIAlertAction(title: "退出 \(platformTitle(selectedPlatform))", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.logoutPlatform(self.selectedPlatform)
        })
        picker.addAction(UIAlertAction(title: "退出哔哩哔哩", style: .destructive) { [weak self] _ in
            self?.logoutPlatform(.bilibili)
        })
        picker.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = picker.popoverPresentationController { popover.barButtonItem = navigationItem.rightBarButtonItem }
        present(picker, animated: true)
    }

    private func logoutPlatform(_ platform: AccountPlatform) {
        Task {
            do {
                try await MusicAuthManager.shared.logout(platform: platform, dataStore: .default())
                PlatformMusicService.shared.clearPlaybackQueue()
                if platform == .bilibili {
                    bilibiliLoginButton.setTitle("B站登录", for: .normal)
                    statusLabel.text = "已退出哔哩哔哩。"
                } else {
                    rows.removeAll()
                    currentPlaylist = nil
                    tableView.reloadData()
                    statusLabel.text = "已退出 \(platformTitle(platform))。"
                }
            } catch {
                statusLabel.text = "退出登录失败：\(error.localizedDescription)"
            }
        }
    }

    @objc private func openBilibiliLogin() {
        let controller = PlatformLoginViewController(platform: .bilibili)
        controller.delegate = self
        navigationController?.pushViewController(controller, animated: true)
    }

    public func loginController(_ controller: PlatformLoginViewController, didObserve cookies: [HTTPCookie], for platform: AccountPlatform) {
        statusLabel.text = "检测到网页登录状态，正在验证该平台接口…"
        Task {
            await MusicAuthManager.shared.updateDetectedLogin(platform: platform, cookies: cookies)
            let state = await MusicAuthManager.shared.state(for: platform)
            await MainActor.run {
                self.statusLabel.text = self.loginStatusMessage(state)
                if platform == .bilibili {
                    self.bilibiliLoginButton.setTitle(state.verifiedLogin ? "B站已登录" : "B站登录", for: .normal)
                } else if state.verifiedLogin {
                    Task { await self.loadUserPlaylists() }
                }
            }
        }
    }

    @MainActor private func restoreAndRefresh() async {
        guard platformControl.selectedSegmentIndex > 0 else { loadLocalSongs(); return }
        let state = await MusicAuthManager.shared.restoreAndVerify(platform: selectedPlatform)
        if state.verifiedLogin {
            statusLabel.text = loginStatusMessage(state)
            await loadUserPlaylists()
        } else if state.detectedLogin {
            statusLabel.text = "检测到凭据，但平台接口验证未通过，请重新登录。"
        } else {
            statusLabel.text = "尚未登录 \(platformTitle(selectedPlatform))。"
        }
    }

    @MainActor private func loadLocalSongs() {
        let songs = localLibrary.allMusic()
        rows = songs.map(Row.local)
        libraryRows = rows
        currentPlaylist = nil
        statusLabel.text = songs.isEmpty ? "本地音乐库为空。" : "本地歌曲 · \(songs.count) 首"
        tableView.reloadData()
        reapplySearchIfNeeded()
    }

    private func updateSourceActions(isLocal: Bool) {
        navigationItem.rightBarButtonItem?.isHidden = isLocal
        refreshButton.setTitle(isLocal ? "刷新本地歌曲" : "我的歌单", for: .normal)
        loginButton.setTitle(isLocal ? "平台登录" : "网页登录", for: .normal)
    }

    private func loginStatusMessage(_ state: AccountLoginState) -> String {
        guard state.verifiedLogin else {
            return state.detectedLogin ? "检测到登录 Cookie，但平台接口验证未通过。" : "尚未检测到有效登录凭据。"
        }
        if state.platform == .qqMusic && !state.playbackAuthorized {
            return "QQ 账号已登录，歌单可读取；播放授权票据尚未返回。登录页正在尝试同步 QQ 音乐播放态，请继续等待或重新登录。"
        }
        return "\(platformTitle(state.platform)) 登录已通过接口验证。"
    }

    @MainActor private func loadUserPlaylists() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        statusLabel.text = "正在验证并读取用户歌单…"
        do {
            rows = try await PlatformMusicService.shared.playlists(for: selectedPlatform).map(Row.playlist)
            libraryRows = rows
            currentPlaylist = nil
            let qqLoginState = await MusicAuthManager.shared.state(for: .qqMusic)
            let playbackNote = selectedPlatform == .qqMusic && !qqLoginState.playbackAuthorized ? " QQ 播放授权票据尚未返回。" : ""
            statusLabel.text = (rows.isEmpty ? "接口验证通过，但此账号没有返回歌单。" : "读取到 \(rows.count) 个用户歌单。") + playbackNote
            tableView.reloadData()
            reapplySearchIfNeeded()
        } catch {
            statusLabel.text = error.localizedDescription
        }
    }

    private func loadTracks(_ playlist: ProviderPlaylist) {
        Task { @MainActor in
            statusLabel.text = "正在读取《\(playlist.name)》…"
            do {
                let tracks = try await PlatformMusicService.shared.tracks(in: playlist)
                currentPlaylist = playlist
                rows = tracks.map(Row.track)
                libraryRows = rows
                statusLabel.text = tracks.isEmpty ? "该歌单当前没有可显示曲目。" : "《\(playlist.name)》· \(tracks.count) 首，点歌开始播放。"
                tableView.reloadData()
                reapplySearchIfNeeded()
            } catch {
                statusLabel.text = error.localizedDescription
            }
        }
    }

    private func play(_ track: ProviderTrack) {
        Task { @MainActor in
            statusLabel.text = "正在解析《\(track.name)》并准备播放…"
            do {
                let fileURL = try await PlatformMusicService.shared.playFile(for: track)
                let artworkURL = await PlatformMusicService.shared.artworkFile(for: track)
                let tracks = rows.compactMap { row -> ProviderTrack? in
                    if case .track(let value) = row { return value }
                    return nil
                }
                if let index = tracks.firstIndex(of: track) {
                    PlatformMusicService.shared.setPlaybackQueue(tracks, selectedIndex: index, playlistID: currentPlaylist?.id)
                }
                NotificationCenter.default.post(name: .platformMusicDidResolvePlayback, object: nil, userInfo: [
                    "filePath": fileURL.path,
                    "title": track.name,
                    "artist": track.artist,
                    "album": track.album ?? "",
                    "duration": track.duration ?? 0,
                    "artworkFilePath": artworkURL?.path ?? "",
                    "artworkURL": track.artworkURL?.absoluteString ?? "",
                    "platform": track.platform.rawValue,
                    "trackID": track.id,
                    "mediaID": track.mediaID ?? "",
                    "hash": track.hash ?? "",
                    "albumID": track.albumID ?? "",
                    "albumAudioID": track.albumAudioID ?? "",
                    "playlistID": currentPlaylist?.id ?? ""
                ])
                statusLabel.text = "已交给播放器：\(track.name)"
            } catch {
                statusLabel.text = error.localizedDescription
            }
        }
    }

    private var searchKeyword: String {
        searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func reapplySearchIfNeeded() {
        let keyword = searchKeyword
        guard !keyword.isEmpty else { return }
        applySearch(keyword)
    }

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchTask?.cancel()
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty {
            rows = libraryRows
            tableView.reloadData()
            return
        }
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            applySearch(keyword)
        }
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        searchTask?.cancel()
        applySearch(searchKeyword)
    }

    private func applySearch(_ keyword: String) {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            rows = libraryRows
            tableView.reloadData()
            return
        }
        if platformControl.selectedSegmentIndex == 0 {
            rows = libraryRows.filter { row in
                guard case .local(let item) = row else { return false }
                return [item.displayName, item.artist, item.album].compactMap { $0 }.joined(separator: " ").localizedCaseInsensitiveContains(query)
            }
            statusLabel.text = "本地搜索「\(query)」· \(rows.count) 首"
            tableView.reloadData()
            return
        }
        statusLabel.text = "正在搜索「\(query)」…"
        let platform = selectedPlatform
        Task { @MainActor in
            do {
                let tracks = try await PlatformMusicService.shared.searchTracks(on: platform, keyword: query, limit: 30)
                guard self.searchKeyword == query, self.selectedPlatform == platform else { return }
                self.currentPlaylist = nil
                self.rows = tracks.map(Row.track)
                self.statusLabel.text = tracks.isEmpty ? "没有找到与「\(query)」匹配的歌曲。" : "搜索「\(query)」· \(tracks.count) 首，点按即可播放。"
                self.tableView.reloadData()
            } catch {
                guard self.searchKeyword == query else { return }
                self.statusLabel.text = error.localizedDescription
            }
        }
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PlatformMusicRow", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.textProperties.color = .white
        content.secondaryTextProperties.color = .secondaryLabel
        switch rows[indexPath.row] {
        case .local(let item):
            content.text = item.displayName
            content.secondaryText = [item.artist, item.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            cell.accessoryType = .none
        case .playlist(let playlist):
            content.text = playlist.name
            content.secondaryText = playlist.trackCount.map { "\($0) 首" } ?? "\(platformTitle(playlist.platform)) 歌单"
            cell.accessoryType = .disclosureIndicator
        case .track(let track):
            content.text = track.name
            content.secondaryText = [track.artist, track.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            cell.accessoryType = .none
        }
        cell.contentConfiguration = content
        cell.backgroundColor = UIColor(white: 0.12, alpha: 0.75)
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows[indexPath.row] {
        case .local(let item): playLocal(item)
        case .playlist(let playlist): loadTracks(playlist)
        case .track(let track): play(track)
        }
    }

    public func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard case .track(let track) = rows[indexPath.row] else { return nil }
        var actions: [UIContextualAction] = []
        if track.platform == .qqMusic {
            let qqAction = UIContextualAction(style: .normal, title: "QQ MV") { [weak self] _, _, completion in
                self?.searchQQMusicMV(for: track, sourceCell: tableView.cellForRow(at: indexPath))
                completion(true)
            }
            qqAction.backgroundColor = UIColor(red: 0.42, green: 0.22, blue: 0.72, alpha: 1)
            actions.append(qqAction)
        }
        let biliAction = UIContextualAction(style: .normal, title: "B站视频") { [weak self] _, _, completion in
            self?.searchBilibiliVideos(for: track, sourceCell: tableView.cellForRow(at: indexPath))
            completion(true)
        }
        biliAction.backgroundColor = UIColor(red: 0.92, green: 0.35, blue: 0.43, alpha: 1)
        actions.append(biliAction)
        return UISwipeActionsConfiguration(actions: actions)
    }

    private func searchBilibiliVideos(for track: ProviderTrack, sourceCell: UIView?) {
        statusLabel.text = "正在 B 站搜索《\(track.name)》相关视频…"
        NSLog("[BiliMV] iOS 测试入口已触发：歌曲=%@，歌手=%@", track.name, track.artist)
        Task { @MainActor in
            do {
                let candidates = try await PlatformMusicService.shared.searchBilibiliVideos(for: track)
                let picker = UIAlertController(title: "选择 B 站视频", message: "找到 \(candidates.count) 个候选", preferredStyle: .actionSheet)
                for video in candidates {
                    let subtitle = [video.author, video.duration].filter { !$0.isEmpty }.joined(separator: " · ")
                    picker.addAction(UIAlertAction(title: subtitle.isEmpty ? video.title : "\(video.title)\n\(subtitle)", style: .default) { [weak self] _ in
                        self?.confirmBilibiliVideo(video, track: track)
                    })
                }
                picker.addAction(UIAlertAction(title: "取消", style: .cancel))
                if let popover = picker.popoverPresentationController {
                    popover.sourceView = sourceCell ?? view
                    popover.sourceRect = sourceCell?.bounds ?? view.bounds
                }
                present(picker, animated: true)
                statusLabel.text = "B 站搜索成功：\(candidates.count) 个候选。"
            } catch {
                NSLog("[BiliMV] 搜索失败：歌曲=%@，原因=%@", track.name, error.localizedDescription)
                statusLabel.text = "B 站搜索失败：\(error.localizedDescription)"
            }
        }
    }

    private func confirmBilibiliVideo(_ video: BilibiliVideoClient.Video, track: ProviderTrack) {
        let alert = UIAlertController(title: video.title, message: "可以先预览画面，或把这个视频指定为当前歌曲的 MV。指定后会按它重新对齐时间表。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "预览", style: .default) { [weak self] _ in self?.playBilibiliVideo(video) })
        alert.addAction(UIAlertAction(title: "用作当前歌曲 MV", style: .default) { [weak self] _ in
            NotificationCenter.default.post(name: Notification.Name("BilibiliMVUserDidSelectVideo"), object: nil, userInfo: [
                "bvid": video.id, "title": video.title, "song": track.name, "artist": track.artist
            ])
            self?.statusLabel.text = "已指定 \(video.id)，播放器会按这个视频重新对齐。"
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func playBilibiliVideo(_ video: BilibiliVideoClient.Video) {
        statusLabel.text = "正在解析《\(video.title)》的视频地址…"
        Task { @MainActor in
            do {
                let url = try await PlatformMusicService.shared.bilibiliPlaybackURL(for: video)
                mvItemObservation = nil
                let controller = BiliTestPlayerViewController()
                let session = BiliPlaybackSession(url: url, automaticallyResume: true, itemChanged: { _ in }, status: { [weak self] state in
                    switch state {
                    case "ready": self?.statusLabel.text = "B 站视频已就绪；可拖动进度条测试 Seek。"
                    case "retrying": self?.statusLabel.text = "当前视频节点失败，正在切换备用节点…"
                    default: self?.statusLabel.text = "所有视频节点均播放失败，请查看脱敏后的 BiliMV 错误日志。"
                    }
                })
                controller.playbackSession = session
                controller.player = session.player
                controller.entersFullScreenWhenPlaybackBegins = true
                controller.exitsFullScreenWhenPlaybackEnds = true
                present(controller, animated: true)
            } catch {
                BiliPlaybackSupport.log(error: error as NSError, host: "api.bilibili.com", stage: "视频地址获取失败 BV=\(video.id)")
                statusLabel.text = "B 站视频解析失败：\(BiliPlaybackSupport.safeText(error.localizedDescription))"
            }
        }
    }

    private func searchQQMusicMV(for track: ProviderTrack, sourceCell: UIView?) {
        statusLabel.text = "正在 QQ 音乐搜索《\(track.name)》的 MV…"
        NSLog("[QQMV] iOS MV 测试入口已触发：歌曲=%@，歌手=%@", track.name, track.artist)
        Task { @MainActor in
            do {
                let candidates = try await PlatformMusicService.shared.searchQQMusicMVs(for: track)
                let picker = UIAlertController(title: "选择 QQ MV", message: "《\(track.name)》找到 \(candidates.count) 个候选", preferredStyle: .actionSheet)
                for mv in candidates {
                    let detail = [mv.artist, mv.duration.map { "\(Int($0)) 秒" }].compactMap { $0 }.joined(separator: " · ")
                    picker.addAction(UIAlertAction(title: detail.isEmpty ? mv.title : "\(mv.title)\n\(detail)", style: .default) { [weak self] _ in
                        self?.playQQMusicMV(mv)
                    })
                }
                picker.addAction(UIAlertAction(title: "取消", style: .cancel))
                if let popover = picker.popoverPresentationController {
                    popover.sourceView = sourceCell ?? view
                    popover.sourceRect = sourceCell?.bounds ?? view.bounds
                }
                present(picker, animated: true)
                statusLabel.text = "QQ MV 搜索成功：\(candidates.count) 个候选。"
            } catch {
                NSLog("[QQMV] 搜索流程失败：歌曲=%@，原因=%@", track.name, error.localizedDescription)
                statusLabel.text = "QQ MV 搜索失败：\(error.localizedDescription)"
            }
        }
    }

    private func playQQMusicMV(_ mv: QQMusicMV) {
        statusLabel.text = "正在解析《\(mv.title)》的视频流…"
        Task { @MainActor in
            do {
                let url = try await PlatformMusicService.shared.qqMusicMVPlaybackURL(for: mv)
                let item = AVPlayerItem(url: url)
                let player = AVPlayer(playerItem: item)
                player.isMuted = true
                NSLog("[QQMV] AVPlayer 已创建：标题=%@，初始状态=%ld，静音=%@", mv.title, item.status.rawValue, player.isMuted ? "是" : "否")
                let controller = AVPlayerViewController()
                controller.player = player
                controller.entersFullScreenWhenPlaybackBegins = true
                controller.exitsFullScreenWhenPlaybackEnds = true
                mvItemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
                    DispatchQueue.main.async {
                        switch observed.status {
                        case .readyToPlay:
                            let videoTracks = observed.tracks.compactMap { $0.assetTrack?.mediaType.rawValue }.joined(separator: ",")
                            NSLog("[QQMV] AVPlayer 就绪：标题=%@，时长=%.2f 秒，画面=%.0fx%.0f，likelyToKeepUp=%@，轨道=%@", mv.title, observed.duration.seconds, observed.presentationSize.width, observed.presentationSize.height, observed.isPlaybackLikelyToKeepUp ? "是" : "否", videoTracks.isEmpty ? "未读取到轨道信息" : videoTracks)
                            self?.statusLabel.text = "QQ MV 已开始播放；可拖动进度条测试随机 Seek。"
                        case .failed:
                            NSLog("[QQMV] AVPlayer 加载失败：标题=%@，错误域=%@，错误码=%ld，原因=%@", mv.title, observed.error.map { ($0 as NSError).domain } ?? "未知", observed.error.map { ($0 as NSError).code } ?? -1, observed.error?.localizedDescription ?? "未知错误")
                            self?.statusLabel.text = "QQ MV 地址已取得，但 AVPlayer 播放失败：\(observed.error?.localizedDescription ?? "未知错误")"
                        default: break
                        }
                    }
                }
                present(controller, animated: true) { player.play() }
            } catch {
                NSLog("[QQMV] 视频流地址获取失败：标题=%@，VID=%@，原因=%@", mv.title, mv.id, error.localizedDescription)
                statusLabel.text = "QQ MV 地址获取失败：\(error.localizedDescription)"
            }
        }
    }

    private func playLocal(_ item: MusicItem) {
        let path = item.playableFilePath()
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            statusLabel.text = "本地歌曲文件不可用：\(item.displayName)"
            return
        }
        let localItems = rows.compactMap { row -> MusicItem? in
            if case .local(let value) = row { return value }
            return nil
        }
        let selectedIndex = localItems.firstIndex { $0.filePath == item.filePath } ?? 0
        NotificationCenter.default.post(name: Notification.Name("PlatformMusicDidSelectLocalQueue"), object: nil, userInfo: [
            "items": localItems,
            "selectedIndex": selectedIndex
        ])
        PlatformMusicService.shared.clearPlaybackQueue()
        NotificationCenter.default.post(name: .platformMusicDidResolvePlayback, object: nil, userInfo: [
            "filePath": path,
            "title": item.displayName,
            "artist": item.artist ?? "",
            "album": item.album ?? "",
            "duration": item.duration,
            "artworkFilePath": "",
            "platform": "local"
        ])
        statusLabel.text = "正在播放本地歌曲：\(item.displayName)"
    }

    private func platformTitle(_ platform: MusicPlatform) -> String {
        switch platform { case .netease: return "网易云音乐"; case .qqMusic: return "QQ 音乐"; case .kugou: return "酷狗音乐"; case .bilibili: return "哔哩哔哩" }
    }
}

/// Owns the retry session for exactly the lifetime of the test player screen.
private final class BiliTestPlayerViewController: AVPlayerViewController {
    var playbackSession: BiliPlaybackSession?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { playbackSession?.stop() }
    }

    deinit { playbackSession?.stop() }
}
