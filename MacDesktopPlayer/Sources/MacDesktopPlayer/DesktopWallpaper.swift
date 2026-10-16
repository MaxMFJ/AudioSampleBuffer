import AppKit
import MetalKit
import simd

@MainActor
final class WallpaperController {
    private let audio: LocalAudioPlayer
    private let library: MusicLibraryStore
    private let onOpenControls: () -> Void
    private let onArtworkChange: (NSImage?) -> Void
    private var windows: [WallpaperPanel] = []
    private var playlistDrawers: [PlaylistDrawerController] = []
    private var cachedArtwork: NSImage?
    private(set) var effect = DesktopBackgroundEffect.saved

    init(audio: LocalAudioPlayer, library: MusicLibraryStore, onOpenControls: @escaping () -> Void,
         onArtworkChange: @escaping (NSImage?) -> Void) {
        self.audio = audio
        self.library = library
        self.onOpenControls = onOpenControls
        self.onArtworkChange = onArtworkChange
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
            view.setArtwork(cachedArtwork)
            window.orderFrontRegardless()
            windows.append(window)
            let drawer = PlaylistDrawerController(audio: audio, library: library, onOpenControls: onOpenControls,
                                                  onArtworkChange: onArtworkChange)
            drawer.show(on: screen)
            playlistDrawers.append(drawer)
        }
    }

    func setEffect(_ effect: DesktopBackgroundEffect) {
        self.effect = effect
        UserDefaults.standard.set(effect.rawValue, forKey: "desktopBackgroundEffect")
        windows.compactMap { $0.contentView as? DesktopMetalView }.forEach { $0.setEffect(effect) }
    }

    func openSongList(on screen: NSScreen?) {
        let index = screen.flatMap { target in windows.firstIndex { $0.screen === target } } ?? 0
        guard playlistDrawers.indices.contains(index) else { return }
        playlistDrawers[index].openFromControls()
    }

    func setArtwork(_ image: NSImage?) {
        cachedArtwork = image
        windows.compactMap { $0.contentView as? DesktopMetalView }.forEach { $0.setArtwork(image) }
    }
}
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
        let shaderNames = ["GuitarSurge", "Tyndall", "CoverDotMatrix", "CellularHive"]
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
                                       isolatedInstruments: effectRenderer.effect == .tyndall,
                                       coverDotSensitivity: effectRenderer.effect == .coverDots)
        let squareCover = effectRenderer.effect == .coverDots
        let showCoverStage = squareCover || effectRenderer.effect == .tyndall || centerRecordVisible
        if let desktopView = view as? DesktopMetalView {
            let frame = audio.lyricsController.frame(at: Double(values.playbackTime),
                surface: showCoverStage ? .coverStage : .overlay, viewport: view.bounds.size)
            let accent = DesktopMoodService.shared.colors.pulseRing
            if showCoverStage {
                desktopView.hideFlatLyrics()
                coverRecordRenderer.setLyrics(frame,
                    followsCoverRotation: audio.lyricsController.configuration(for: .coverStage).followsCoverRotation,
                    effect: audio.lyricsController.configuration(for: .coverStage).coverEffect,
                    effectIntensity: audio.lyricsController.configuration(for: .coverStage).coverEffectIntensity)
            } else {
                desktopView.setLyrics(frame, highlight: NSColor(calibratedRed: CGFloat(accent.x), green: CGFloat(accent.y), blue: CGFloat(accent.z), alpha: 1))
            }
        }
        effectRenderer.draw(encoder: encoder, view: view, audio: values)
        guitarSurgeRenderer.draw(encoder: encoder, audio: values,
                                 enabled: audio.guitarSurgeEnabled && effectRenderer.effect != .tyndall,
                                 drumOverlayEnabled: true)
        if showCoverStage {
            coverRecordRenderer.draw(encoder: encoder, view: view, audio: values, squareCover: squareCover,
                                     circularBacking: effectRenderer.effect == .tyndall)
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

