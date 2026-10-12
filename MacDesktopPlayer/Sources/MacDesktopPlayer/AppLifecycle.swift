import AppKit

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

/// Composes the macOS application. Feature implementations stay behind the
/// player, library, wallpaper, and controls boundaries instead of owning the
/// process lifecycle themselves.
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
        }, onArtworkChange: { [weak self] image in
            self?.updateArtwork(image)
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
            self?.updateArtwork(image)
        }, onOpenSongList: { [weak self] screen in
            self?.wallpaper?.openSongList(on: screen)
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

    private func updateArtwork(_ image: NSImage?) {
        audio.setArtwork(image)
        wallpaper?.setArtwork(image)
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
