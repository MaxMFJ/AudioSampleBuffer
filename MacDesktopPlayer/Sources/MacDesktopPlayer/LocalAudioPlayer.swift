import AppKit
import AVFoundation
import Accelerate
import Foundation
#if SWIFT_PACKAGE
import RealtimeDSP
#endif

enum PlaybackRepeatMode: Int {
    case off = 0
    case all = 1
    case one = 2

    var title: String {
        switch self {
        case .off: return "顺序播放"
        case .all: return "循环播放"
        case .one: return "单曲循环"
        }
    }

    var symbolName: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

@MainActor
final class LocalAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let audioControlQueue = DispatchQueue(label: "app.audiosamplebuffer.audio-control", qos: .userInitiated)
    private let analyzerLock = NSLock()
    private var dsp: OpaquePointer?
    private var file: AVAudioFile?
    private var playbackQueue: [LocalTrack] = []
    private var currentTrackID: String?
    private var activePlaybackOffset: Double = 0
    private var pausedPlaybackTime: Double?
    private var playbackScheduleGeneration: UInt64 = 0
    private var playRequestGeneration: UInt64 = 0
    private(set) var currentTitle = "尚未播放"
    private(set) var currentArtist: String?
    private(set) var currentArtwork: NSImage?
    private(set) var levels: (Float, Float, Float) = (0, 0, 0)
    private(set) var currentURL: URL?
    let lyricsController = DesktopLyricsController()
    var electricGuitarConfidence: Float = 0
    private(set) var guitarSurgeEnabled = UserDefaults.standard.object(forKey: "desktopGuitarSurgeEnabled") == nil
        ? true : UserDefaults.standard.bool(forKey: "desktopGuitarSurgeEnabled")
    var onTrackStart: ((URL) -> Void)?
    var onPlatformAdjacentTrack: ((Int) -> Bool)?
    private(set) var repeatMode: PlaybackRepeatMode = PlaybackRepeatMode(rawValue: UserDefaults.standard.integer(forKey: "desktopRepeatMode")) ?? .off
    private var stemCurves: [[Float]] = []
    private var vocalCurve: [Float] = []
    private var visualGuitarPeak: Float = 0
#if !SWIFT_PACKAGE
    private var trackGeneration = 0
    private var demucsEnabled = UserDefaults.standard.bool(forKey: "desktopHTDemucsEnabled")
#endif

    init() {
        engine.attach(player)
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
        playRequestGeneration &+= 1
        let request = playRequestGeneration
        stopPlayback { [weak self] in
            guard let self, self.playRequestGeneration == request else { return }
            self.beginPlayback(url: url, title: title, artist: artist)
        }
    }

    private func beginPlayback(url: URL, title: String?, artist: String?) {
        do {
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
            // Configure both ends before installing the analysis tap. A tap can
            // change the player's format without updating an existing mixer
            // input, causing 48 kHz audio to be consumed at 44.1 kHz.
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
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
            NSLog("[AudioPlayback] file=%@ source=%.0fHz/%uch player=%.0fHz mixerInput=%.0fHz mixerOutput=%.0fHz device=%.0fHz",
                  url.lastPathComponent, format.sampleRate, format.channelCount,
                  player.outputFormat(forBus: 0).sampleRate,
                  engine.mainMixerNode.inputFormat(forBus: 0).sampleRate,
                  engine.mainMixerNode.outputFormat(forBus: 0).sampleRate,
                  engine.outputNode.outputFormat(forBus: 0).sampleRate)
            let generation = playbackScheduleGeneration
            player.scheduleSegment(audioFile, startingFrame: 0, frameCount: AVAudioFrameCount(min(audioFile.length, Int64(UInt32.max))), at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in self?.handlePlaybackFinished(generation: generation) }
            }
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
        playRequestGeneration &+= 1
        stopPlayback(completion: nil)
    }

    private func stopPlayback(completion: (() -> Void)?) {
        // stop() also completes pending schedules. Invalidate them before it
        // runs so a stopped song cannot restart or advance the new song.
        playbackScheduleGeneration &+= 1
        lyricsController.clear()
#if !SWIFT_PACKAGE
        trackGeneration += 1
        HTDemucsMacAnalyzer.shared().cancelCurrentAnalysis()
#endif
        let oldFile = file
        let player = self.player
        let engine = self.engine
        let controlQueue = audioControlQueue
        let finishOnMain = { [weak self] in
            guard let self else { return }
            self.analyzerLock.lock()
            if let dsp = self.dsp {
                AnalyzerDSP_Destroy(dsp)
                self.dsp = nil
            }
            self.analyzerLock.unlock()
            completion?()
        }
        controlQueue.async {
            player.stop()
            player.removeTap(onBus: 0)
            engine.stop()
            // Retain the old file until AVAudioPlayerNode has unscheduled it.
            _ = oldFile
            DispatchQueue.main.async(execute: finishOnMain)
        }
        levels = (0, 0, 0)
        stemCurves = []
        vocalCurve = []
        visualGuitarPeak = 0
        currentURL = nil
        file = nil
        activePlaybackOffset = 0
        pausedPlaybackTime = nil
        currentTitle = "尚未播放"
        currentArtist = nil
        setArtwork(nil)
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
        playbackScheduleGeneration &+= 1
        let generation = playbackScheduleGeneration
        playRequestGeneration &+= 1
        let request = playRequestGeneration
        activePlaybackOffset = target
        pausedPlaybackTime = wasPlaying ? nil : target
        let scheduledFile = file
        let player = self.player
        audioControlQueue.async { [weak self] in
            player.stop()
            DispatchQueue.main.async {
                guard let self, self.playRequestGeneration == request,
                      self.playbackScheduleGeneration == generation,
                      self.file === scheduledFile else { return }
                self.schedule(file: scheduledFile, startingFrame: frame,
                              frameCount: AVAudioFrameCount(min(remaining, Int64(UInt32.max))),
                              generation: generation, shouldPlay: wasPlaying)
            }
        }
    }

    private func schedule(file: AVAudioFile, startingFrame: AVAudioFramePosition,
                          frameCount: AVAudioFrameCount, generation: UInt64, shouldPlay: Bool) {
        player.scheduleSegment(file, startingFrame: startingFrame, frameCount: frameCount,
                               at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handlePlaybackFinished(generation: generation) }
        }
        if shouldPlay { player.play() }
    }

    @discardableResult func playAdjacentTrack(_ direction: Int) -> LocalTrack? {
        if onPlatformAdjacentTrack?(direction) == true { return nil }
        guard let currentTrackID, let index = playbackQueue.firstIndex(where: { $0.id == currentTrackID }) else { return nil }
        let nextIndex = index + direction
        guard playbackQueue.indices.contains(nextIndex) else { return nil }
        let track = playbackQueue[nextIndex]
        self.currentTrackID = track.id
        play(url: URL(fileURLWithPath: track.path), title: track.title, artist: track.artist)
        return track
    }

    func setArtwork(_ image: NSImage?) {
        currentArtwork = image
    }

    func cycleRepeatMode() {
        let next = (repeatMode.rawValue + 1) % 3
        repeatMode = PlaybackRepeatMode(rawValue: next) ?? .off
        UserDefaults.standard.set(repeatMode.rawValue, forKey: "desktopRepeatMode")
    }

    private func handlePlaybackFinished(generation: UInt64) {
        guard generation == playbackScheduleGeneration, file != nil else { return }
        playbackScheduleGeneration &+= 1
        switch repeatMode {
        case .one:
            let url = currentURL
            let title = currentTitle
            let artist = currentArtist
            let artwork = currentArtwork
            guard let url else { return }
            play(url: url, title: title, artist: artist)
            setArtwork(artwork)
        case .all:
            guard let currentTrackID, !playbackQueue.isEmpty,
                  let index = playbackQueue.firstIndex(where: { $0.id == currentTrackID }) else {
                let url = currentURL
                let title = currentTitle
                let artist = currentArtist
                let artwork = currentArtwork
                if let url {
                    play(url: url, title: title, artist: artist)
                    setArtwork(artwork)
                }
                return
            }
            let next = playbackQueue[(index + 1) % playbackQueue.count]
            self.currentTrackID = next.id
            play(url: URL(fileURLWithPath: next.path), title: next.title, artist: next.artist)
        case .off:
            activePlaybackOffset = duration
            pausedPlaybackTime = duration
        }
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

    func visualAudio(time: Float, aspectRatio: Float, isolatedInstruments: Bool = false,
                     coverDotSensitivity: Bool = false) -> VisualAudio {
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
        let separatedGuitar = curve(0)
        let guitar = hasGuitarStem
            ? ((coverDotSensitivity || separatedGuitar >= 0.08) ? separatedGuitar : 0)
            : (isolatedInstruments ? 0 : fftGuitar)
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
                           piano: hasPianoStem
                            ? ((coverDotSensitivity || curve(1) >= 0.08) ? curve(1) : 0)
                            : (isolatedInstruments ? 0 : min(max(levels.1 * 0.55, 0), 1)),
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


