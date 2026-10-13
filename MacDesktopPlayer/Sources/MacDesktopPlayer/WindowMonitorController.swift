import AppKit
import CoreGraphics
import CoreImage
import CoreMedia
import ScreenCaptureKit

@MainActor
final class WindowMonitorController: NSWindowController, NSWindowDelegate {
    private let windowPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let refreshButton = NSButton(title: "刷新窗口", target: nil, action: nil)
    private let permissionButton = NSButton(title: "打开屏幕录制设置", target: nil, action: nil)
    private let revealAppButton = NSButton(title: "在 Finder 显示调试 App", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "选择一个窗口开始实时预览")
    private let preview = NSImageView()
    private var shareableWindows: [SCWindow] = []
    private var stream: SCStream?
    private var streamOutput: WindowMonitorStreamOutput?
    private let outputQueue = DispatchQueue(label: "app.audiosamplebuffer.window-monitor")
    private var didRequestScreenPermission = false

    init() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 310),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
        panel.title = "窗口实时预览"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 340, height: 230)
        super.init(window: panel)
        panel.delegate = self
        buildInterface(in: panel)
        refreshButton.target = self
        refreshButton.action = #selector(refreshWindows)
        permissionButton.target = self
        permissionButton.action = #selector(openScreenCaptureSettings)
        revealAppButton.target = self
        revealAppButton.action = #selector(revealDebugApp)
        revealAppButton.toolTip = Bundle.main.bundleURL.path
        windowPicker.target = self
        windowPicker.action = #selector(selectedWindowChanged)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshWindows()
    }

    func windowWillClose(_ notification: Notification) {
        stopCapture()
    }

    private func buildInterface(in window: NSWindow) {
        guard let content = window.contentView else { return }
        let controls = NSStackView(views: [windowPicker, refreshButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
        let permissionControls = NSStackView(views: [permissionButton, revealAppButton])
        permissionControls.orientation = .horizontal
        permissionControls.alignment = .centerY
        permissionControls.spacing = 8
        windowPicker.controlSize = .small
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        for button in [permissionButton, revealAppButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
        }
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.backgroundColor = NSColor.black.cgColor
        preview.layer?.cornerRadius = 8
        preview.layer?.masksToBounds = true

        let root = NSStackView(views: [controls, permissionControls, statusLabel, preview])
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            controls.heightAnchor.constraint(equalToConstant: 28),
            windowPicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 150)
        ])
    }

    @objc private func refreshWindows() {
        guard CGPreflightScreenCaptureAccess() else {
            if !didRequestScreenPermission {
                didRequestScreenPermission = true
                _ = CGRequestScreenCaptureAccess()
            }
            statusLabel.stringValue = "等待屏幕录制授权。请在系统设置打开“MacDesktopPlayer”，然后退出并重新运行此调试 App。"
            return
        }
        statusLabel.stringValue = "正在查找可预览的窗口…"
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let content else {
                    let detail: String
                    if let error {
                        let nsError = error as NSError
                        detail = nsError.code == -3801
                            ? "系统仍拒绝了屏幕采集（-3801）。请确认当前调试版的权限开关已打开，并重新启动 App。"
                            : "\(nsError.localizedDescription)（\(nsError.domain) \(nsError.code)）"
                    } else {
                        detail = "系统没有返回窗口列表"
                    }
                    self.statusLabel.stringValue = "读取窗口失败：\(detail)"
                    return
                }
                let ownBundleID = Bundle.main.bundleIdentifier
                self.shareableWindows = content.windows.filter { item in
                    item.frame.width > 80 && item.frame.height > 60 &&
                    !(item.owningApplication?.bundleIdentifier == ownBundleID && item.title == self.window?.title)
                }
                self.windowPicker.removeAllItems()
                for (index, item) in self.shareableWindows.enumerated() {
                    let app = item.owningApplication?.applicationName ?? "未知应用"
                    let title = item.title?.isEmpty == false ? item.title! : "无标题窗口"
                    self.windowPicker.addItem(withTitle: "\(app) — \(title)")
                    self.windowPicker.lastItem?.tag = index
                }
                self.windowPicker.isEnabled = !self.shareableWindows.isEmpty
                self.statusLabel.stringValue = self.shareableWindows.isEmpty
                    ? "授权已通过，但没有可用窗口；请打开目标窗口后点“刷新窗口”。"
                    : "窗口内容独立采集，不会被 Xcode 或其他窗口遮挡。"
            }
        }
    }

    @objc private func openScreenCaptureSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealDebugApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    @objc private func selectedWindowChanged() {
        let index = windowPicker.indexOfSelectedItem
        guard shareableWindows.indices.contains(index) else { return }
        startCapture(for: shareableWindows[index])
    }

    private func startCapture(for target: SCWindow) {
        stopCapture()
        let filter = SCContentFilter(desktopIndependentWindow: target)
        let configuration = SCStreamConfiguration()
        let aspect = max(target.frame.width / max(target.frame.height, 1), 0.5)
        configuration.width = min(720, max(320, Int(360 * aspect)))
        configuration.height = 360
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = false

        let output = WindowMonitorStreamOutput { [weak self] image in
            Task { @MainActor [weak self] in self?.preview.image = NSImage(cgImage: image, size: .zero) }
        }
        let capture = SCStream(filter: filter, configuration: configuration, delegate: nil)
        do {
            try capture.addStreamOutput(output, type: .screen, sampleHandlerQueue: outputQueue)
        } catch {
            statusLabel.stringValue = "无法启动窗口采集：\(error.localizedDescription)"
            return
        }
        stream = capture
        streamOutput = output
        statusLabel.stringValue = "正在预览：\(target.owningApplication?.applicationName ?? "窗口") — \(target.title ?? "无标题")"
        Task { @MainActor [weak self] in
            do {
                try await capture.startCapture()
            } catch {
                guard let self else { return }
                self.statusLabel.stringValue = "窗口采集失败：\(error.localizedDescription)"
                self.stream = nil
                self.streamOutput = nil
            }
        }
    }

    private func stopCapture() {
        guard let stream else { return }
        self.stream = nil
        streamOutput = nil
        Task { try? await stream.stopCapture() }
    }
}

private final class WindowMonitorStreamOutput: NSObject, SCStreamOutput {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let onFrame: (CGImage) -> Void

    init(onFrame: @escaping (CGImage) -> Void) { self.onFrame = onFrame }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let image = context.createCGImage(CIImage(cvPixelBuffer: pixelBuffer),
                                                from: CGRect(x: 0, y: 0,
                                                             width: CVPixelBufferGetWidth(pixelBuffer),
                                                             height: CVPixelBufferGetHeight(pixelBuffer))) else { return }
        onFrame(image)
    }
}
