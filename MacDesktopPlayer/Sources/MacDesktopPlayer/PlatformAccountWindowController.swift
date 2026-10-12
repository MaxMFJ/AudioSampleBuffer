import AppKit

@MainActor
final class PlatformAccountWindowController: NSWindowController {
    private let content = PlatformAccountView()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "第三方平台账号"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = content
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
private final class PlatformAccountView: NSView {
    private let stack = NSStackView()
    private let status = NSTextField(labelWithString: "正在读取平台状态…")
    private var rows: [PlatformProvider: NSTextField] = [:]
    private var loginWindows: [PlatformProvider: PlatformLoginWindowController] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "第三方平台账号")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "登录状态保存在本机 Bridge；不会上传平台 Cookie。")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 5
        stack.addArrangedSubview(heading)

        for provider in PlatformProvider.allCases {
            let row = makeRow(provider)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        stack.addArrangedSubview(status)

        let refresh = NSButton(title: "刷新全部状态", target: self, action: #selector(refreshAll))
        refresh.bezelStyle = .rounded
        let bridge = NSButton(title: "启动并打开 Bridge", target: self, action: #selector(openBridge))
        bridge.bezelStyle = .rounded
        let actions = NSStackView(views: [refresh, bridge])
        actions.orientation = .horizontal
        actions.spacing = 10
        stack.addArrangedSubview(actions)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24)
        ])
        refreshAll()
    }

    required init?(coder: NSCoder) { nil }

    private func makeRow(_ provider: PlatformProvider) -> NSView {
        let title = NSTextField(labelWithString: provider.title)
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.widthAnchor.constraint(equalToConstant: 92).isActive = true

        let state = NSTextField(labelWithString: "检查中…")
        state.textColor = .secondaryLabelColor
        state.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rows[provider] = state

        let login = NSButton(title: "内嵌登录", target: self, action: #selector(openLogin(_:)))
        login.bezelStyle = .rounded
        login.tag = provider.rawValue.hashValue
        login.identifier = NSUserInterfaceItemIdentifier(provider.rawValue)
        let refresh = NSButton(title: "刷新", target: self, action: #selector(refreshLogin(_:)))
        refresh.bezelStyle = .rounded
        refresh.identifier = NSUserInterfaceItemIdentifier(provider.rawValue)

        let row = NSStackView(views: [title, state, login, refresh])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return row
    }

    @objc private func openLogin(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let provider = PlatformProvider(rawValue: raw) else { return }
        let controller = PlatformLoginWindowController(provider: provider)
        loginWindows[provider] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        status.stringValue = "已打开 \(provider.title) 内嵌登录窗口；登录完成后会自动同步凭据。"
    }

    @objc private func refreshLogin(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let provider = PlatformProvider(rawValue: raw) else { return }
        refresh(provider)
    }

    @objc private func refreshAll() {
        status.stringValue = "正在启动并读取本机 Bridge…"
        Task { [weak self] in
            let result = await PlatformBridgeRuntime.shared.ensureRunning()
            guard let self else { return }
            switch result {
            case .success:
                self.status.stringValue = "Bridge 已连接，正在读取平台状态…"
                for provider in PlatformProvider.allCases { self.refresh(provider) }
            case .failure(let error):
                self.status.stringValue = error.localizedDescription
                for provider in PlatformProvider.allCases {
                    self.rows[provider]?.stringValue = "Bridge 未启动"
                    self.rows[provider]?.textColor = .systemOrange
                }
            }
        }
    }

    private func refresh(_ provider: PlatformProvider) {
        rows[provider]?.stringValue = "检查中…"
        Task { [weak self] in
            do {
                let info = try await PlatformBridgeClient.shared.loginStatus(for: provider)
                guard let self else { return }
                let account = info.nickname ?? info.userID ?? "已连接"
                self.rows[provider]?.stringValue = info.loggedIn ? "已登录 · \(account)" : "未登录"
                self.rows[provider]?.textColor = info.loggedIn ? .systemGreen : .secondaryLabelColor
                self.status.stringValue = "状态来自本机 Bridge"
            } catch {
                guard let self else { return }
                self.rows[provider]?.stringValue = "Bridge 未连接"
                self.rows[provider]?.textColor = .systemOrange
                self.status.stringValue = error.localizedDescription
            }
        }
    }

    @objc private func openBridge() {
        Task { [weak self] in
            let result = await PlatformBridgeRuntime.shared.ensureRunning()
            guard let self else { return }
            switch result {
            case .success:
                guard let url = URL(string: "http://127.0.0.1:3000/") else { return }
                NSWorkspace.shared.open(url)
                self.status.stringValue = "Bridge 已启动"
            case .failure(let error):
                self.status.stringValue = error.localizedDescription
            }
        }
    }
}
