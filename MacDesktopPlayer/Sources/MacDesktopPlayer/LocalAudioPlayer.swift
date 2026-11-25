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
    // AVAudioPlayerNode.stop() can synchronously wait for AVAudioEngine's
    // default-QoS render/control threads. Keep teardown at matching QoS so a
    // user-initiated worker does not block behind lower-priority audio work.
    private let audioControlQueue = DispatchQueue(label: "app.audiosamplebuffer.audio-control", qos: .default)
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
    private(set) var dspFeatureSignals = SIMD4<Float>(repeating: 0)
    private(set) var dspFeatureTexture = SIMD4<Float>(repeating: 0)
    private(set) var currentURL: URL?
    private(set) var currentNeteaseTrackID: String?
    let lyricsController = DesktopLyricsController()
    private let signatureMV = SignatureMVClipPlayer()
    var electricGuitarConfidence: Float = 0
    private(set) var guitarSurgeEnabled = UserDefaults.standard.object(forKey: "desktopGuitarSurgeEnabled") == nil
        ? true : UserDefaults.standard.bool(forKey: "desktopGuitarSurgeEnabled")
    var onTrackStart: ((URL) -> Void)?
    var onPlatformAdjacentTrack: ((Int) -> Bool)?
    private(set) var repeatMode: PlaybackRepeatMode = PlaybackRepeatMode(rawValue: UserDefaults.standard.integer(forKey: "desktopRepeatMode")) ?? .off
    private var stemCurves: [[Float]] = []
    private var vocalCurve: [Float] = []
    private var visualGuitarPeak: Float = 0
    private var visualBPM: Float = 120
    private var visualEnergy: Float = 0
    private var visualBassEnergy: Float = 0
    private var visualHighEnergy: Float = 0
    private var visualSubBass: Float = 0
    private var visualSubOnly: Float = 0
    private var visualTransient: Float = 0
    private var visualBassHistory: [Float] = []
    private var visualTransientHistory: [Float] = []
    private var visualBeatTimes: [Float] = []
    private var visualLastBassHit: Float = -10
    private var visualLastTransientHit: Float = -10
    private var visualBeatSequence: UInt64 = 0
    private enum VectorSegment { case unknown, intro, verse, chorus, bridge, outro }
    private var vectorSegment: VectorSegment = .unknown
    private var vectorSegmentStart: Float = 0
    private var vectorEnergyEnvelope: [Float] = []
    private var vectorLongEnergy: Float = 0
    private var vectorShortEnergy: Float = 0
    private var vectorPeakEnergy: Float = 0
    private var vectorAverageEnergy: Float = 0
    private var vectorChorusThreshold: Float = 0
    private var vectorChorusCount = 0
    private var vectorIntroDetected = false
    private var vectorOutroStableFrames = 0
    private var visualLastSampleTime: Float = -1
    private var visualBeatUntil: Float = -1
    private var visualBeatStrength: Float = 0
    private var visualBeatKind: Float = 1
    private var visualBeatIntervals: [Float] = []
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

    func play(url: URL, title: String? = nil, artist: String? = nil, neteaseTrackID: String? = nil) {
        playRequestGeneration &+= 1
        let request = playRequestGeneration
        stopPlayback { [weak self] in
            guard let self, self.playRequestGeneration == request else { return }
            self.beginPlayback(url: url, title: title, artist: artist, neteaseTrackID: neteaseTrackID)
        }
    }

    private func beginPlayback(url: URL, title: String?, artist: String?, neteaseTrackID: String? = nil) {
        do {
            electricGuitarConfidence = 0
            dspFeatureSignals = SIMD4<Float>(repeating: 0)
            dspFeatureTexture = SIMD4<Float>(repeating: 0)
            vocalCurve = []
            visualGuitarPeak = 0
            resetVectorRhythm()
            let audioFile = try AVAudioFile(forReading: url)
            file = audioFile
            currentURL = url
            activePlaybackOffset = 0
            pausedPlaybackTime = nil
            currentTitle = title ?? url.deletingPathExtension().lastPathComponent
            currentArtist = artist
            currentNeteaseTrackID = neteaseTrackID
            signatureMV.prepare(trackID: neteaseTrackID, title: currentTitle)
            lyricsController.load(for: url, title: title ?? url.deletingPathExtension().lastPathComponent,
                                 artist: artist, neteaseTrackID: neteaseTrackID, duration: duration)
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
                    self?.levels = (values.low, values.mid, values.high)
                    self?.dspFeatureSignals = values.signals
                    self?.dspFeatureTexture = values.texture
                    self?.updateVectorRhythm(energy: values.energy, bassEnergy: values.bassEnergy,
                                             highEnergy: values.highEnergy, subBass: values.subBass,
                                             subOnly: values.subOnly, transient: values.transient)
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
        signatureMV.stop()
        currentNeteaseTrackID = nil
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
            play(url: url, title: title, artist: artist, neteaseTrackID: currentNeteaseTrackID)
            setArtwork(artwork)
        case .all:
            guard let currentTrackID, !playbackQueue.isEmpty,
                  let index = playbackQueue.firstIndex(where: { $0.id == currentTrackID }) else {
                let url = currentURL
                let title = currentTitle
                let artist = currentArtist
                let artwork = currentArtwork
                if let url {
                    play(url: url, title: title, artist: artist, neteaseTrackID: currentNeteaseTrackID)
                    setArtwork(artwork)
                }
                return
            }
            let next = playbackQueue[(index + 1) % playbackQueue.count]
            self.currentTrackID = next.id
            play(url: URL(fileURLWithPath: next.path), title: next.title, artist: next.artist)
        case .off:
            // Sequential playback advances within the current queue and stops
            // naturally when there is no following track. This also routes
            // platform playlists through their existing adjacent-track handler.
            if onPlatformAdjacentTrack?(1) != true {
                if let currentTrackID,
                   let index = playbackQueue.firstIndex(where: { $0.id == currentTrackID }),
                   playbackQueue.indices.contains(index + 1) {
                    let next = playbackQueue[index + 1]
                    self.currentTrackID = next.id
                    play(url: URL(fileURLWithPath: next.path), title: next.title, artist: next.artist)
                } else {
                    activePlaybackOffset = duration
                    pausedPlaybackTime = duration
                }
            }
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
                let names = ["guitar", "piano", "drums", "other"]
                self.stemCurves = names.map { name in
                    (stems[name]?["frames"] as? [NSNumber] ?? []).map(\.floatValue)
                }
                NSLog("[DemucsMac] 吉他、钢琴、鼓、其他音源分离曲线已就绪。")
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
        signatureMV.tick(title: currentTitle, time: Double(playbackTime), playing: isPlaying, lines: lyricsController.lyricLines)
        return VisualAudio(time: time, bass: levels.0, mid: levels.1, treble: levels.2,
                           aspectRatio: aspectRatio, guitar: guitar,
                           piano: hasPianoStem
                            ? ((coverDotSensitivity || curve(1) >= 0.08) ? curve(1) : 0)
                            : (isolatedInstruments ? 0 : min(max(levels.1 * 0.55, 0), 1)),
                           drums: hasDrumStem ? curve(2) : 0, playbackTime: playbackTime,
                           electricGuitarConfidence: electricGuitarConfidence, vocal: vocal,
                           guitarPeak: visualGuitarPeak, playing: isPlaying ? 1 : 0,
                           other: curve(3),
                           dspFeatureSignals: dspFeatureSignals,
                           dspFeatureTexture: dspFeatureTexture,
                           visualVideoActive: signatureMV.isShowingVideo ? 1 : 0,
                           bpm: visualBPM,
                           songIdentity: currentURL?.absoluteString.hashValue ?? 0,
                           beatDetected: isPlaying && playbackTime <= visualBeatUntil ? 1 : 0,
                           beatSequence: visualBeatSequence,
                           beatIntensity: visualBeatStrength,
                           beatKind: visualBeatKind,
                           activityEnergy: visualEnergy,
                           vectorSubBass: min(1, visualSubBass * 4.6),
                           activityClimax: vectorSegment == .chorus ? min(1, 0.58 + visualEnergy * 0.42) : 0)
    }

    private func interpolated(_ curve: [Float], at time: Float, interval: Float) -> Float {
        guard !curve.isEmpty else { return 0 }
        let position = max(0, time / interval)
        let low = min(Int(position), curve.count - 1)
        let high = min(low + 1, curve.count - 1)
        return curve[low] + (curve[high] - curve[low]) * (position - Float(low))
    }

    func setVocalCurve(_ values: [Float]) { vocalCurve = values }

    private func resetVectorRhythm() {
        visualBPM = 120
        visualEnergy = 0
        visualBassEnergy = 0
        visualHighEnergy = 0
        visualSubBass = 0
        visualSubOnly = 0
        visualTransient = 0
        visualBassHistory.removeAll()
        visualTransientHistory.removeAll()
        visualBeatTimes.removeAll()
        visualLastBassHit = -10
        visualLastTransientHit = -10
        visualLastSampleTime = -1
        visualBeatUntil = -1
        visualBeatStrength = 0
        vectorSegment = .unknown
        vectorSegmentStart = 0
        vectorEnergyEnvelope.removeAll()
        vectorLongEnergy = 0
        vectorShortEnergy = 0
        vectorPeakEnergy = 0
        vectorAverageEnergy = 0
        vectorChorusThreshold = 0
        vectorChorusCount = 0
        vectorIntroDetected = false
        vectorOutroStableFrames = 0
    }

    private static func adaptiveHit(_ value: Float, history: inout [Float], floor: Float,
                             sigma: Float, interval: Float, lastHit: inout Float, time: Float) -> Bool {
        history.append(value)
        if history.count > 32 { history.removeFirst() }
        guard history.count >= 8 else { return false }
        let mean = history.reduce(0, +) / Float(history.count)
        let variance = history.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / Float(history.count)
        guard time - lastHit > interval, value > max(floor, mean + sigma * sqrt(variance)) else { return false }
        lastHit = time
        return true
    }

    private func updateVectorRhythm(energy: Float, bassEnergy: Float, highEnergy: Float,
                                    subBass: Float, subOnly: Float, transient: Float) {
        let time = Float(currentPlaybackTime)
        if time + 0.05 < visualLastSampleTime { resetVectorRhythm() }
        visualLastSampleTime = time
        guard isPlaying else { return }
        visualEnergy = min(1, 0.3 * energy + 0.7 * visualEnergy)
        visualBassEnergy = min(1, 0.3 * bassEnergy + 0.7 * visualBassEnergy)
        visualHighEnergy = min(1, 0.3 * highEnergy + 0.7 * visualHighEnergy)
        visualSubBass = 0.28 * subBass + 0.72 * visualSubBass
        visualSubOnly = 0.28 * subOnly + 0.72 * visualSubOnly
        visualTransient = 0.24 * transient + 0.76 * visualTransient
        updateVectorSegment(at: time)
        let low = min(1, max(visualSubBass * 4.6, visualSubOnly * 6.2))
        let transientLevel = min(1, visualTransient * 7.2)
        let bassHit = Self.adaptiveHit(min(1, visualSubBass * 4.6), history: &visualBassHistory,
                                  floor: 0.10, sigma: 1.85, interval: 0.23,
                                  lastHit: &visualLastBassHit, time: time)
        let transientHit = Self.adaptiveHit(transientLevel, history: &visualTransientHistory,
                                       floor: 0.08, sigma: 1.65, interval: 0.08,
                                       lastHit: &visualLastTransientHit, time: time)
        guard bassHit || (transientHit && visualSubBass * 4.6 > 0.10) else { return }
        visualBeatSequence &+= 1
        visualBeatUntil = time + 0.08
        visualBeatStrength = min(1, max(low, transientLevel))
        visualBeatKind = bassHit ? 1 : 2
        if bassHit {
            visualBeatTimes.append(time)
            if visualBeatTimes.count > 128 { visualBeatTimes.removeFirst() }
            guard visualBeatTimes.count >= 4 else { return }
            let intervals = zip(visualBeatTimes.dropFirst(), visualBeatTimes).map { pair in pair.0 - pair.1 }.filter { $0 > 0.2 && $0 < 2 }
            if !intervals.isEmpty {
                let average = intervals.reduce(0, +) / Float(intervals.count)
                visualBPM = 0.1 * min(200, max(60, 60 / average)) + 0.9 * visualBPM
            }
        }
    }

    // The same energy statistics and chorus hysteresis used by iOS's
    // AudioFeatureExtractor. The grid only sees a climax signal in chorus.
    private func updateVectorSegment(at time: Float) {
        let energy = visualEnergy
        vectorLongEnergy = 0.008 * energy + 0.992 * vectorLongEnergy
        vectorShortEnergy = 0.1 * energy + 0.9 * vectorShortEnergy
        vectorEnergyEnvelope.append(energy)
        if vectorEnergyEnvelope.count > 300 { vectorEnergyEnvelope.removeFirst() }
        vectorAverageEnergy = vectorEnergyEnvelope.reduce(0, +) / Float(vectorEnergyEnvelope.count)
        if energy > vectorPeakEnergy {
            vectorPeakEnergy = energy
            vectorChorusThreshold = energy * 0.75
        }
        let elapsed = time - vectorSegmentStart
        var next = vectorSegment
        if elapsed >= 6 || vectorSegment == .unknown {
            if !vectorIntroDetected {
                if time < 8 || (time < 20 && (vectorAverageEnergy <= 0.01 || energy / vectorAverageEnergy < 1.15)) {
                    next = .intro
                } else {
                    vectorIntroDetected = true
                }
            }
            if vectorIntroDetected {
                if time > 120 && vectorEnergyEnvelope.count >= 60 {
                    let recent = vectorEnergyEnvelope.suffix(60)
                    let first = recent.prefix(30).reduce(0, +) / 30
                    let second = recent.suffix(30).reduce(0, +) / 30
                    vectorOutroStableFrames = second - first < -0.01 &&
                        vectorShortEnergy < vectorAverageEnergy * 0.7 ? vectorOutroStableFrames + 1 : 0
                    if vectorOutroStableFrames > 90 { next = .outro }
                }
                if next != .outro {
                    let energyRatio = vectorAverageEnergy > 0.005 ? energy / vectorAverageEnergy : 1
                    let shortLong = vectorLongEnergy > 0.005 ? vectorShortEnergy / vectorLongEnergy : 1
                    let flux = min(1, visualTransient * 7.2)
                    var score: Float = 0
                    if vectorPeakEnergy < 0.2 {
                        if energyRatio > 1.15 { score += 0.4 }
                        if shortLong > 1.1 { score += 0.3 }
                        if flux > 0.1 { score += 0.3 }
                    } else if vectorPeakEnergy < 0.35 {
                        if energyRatio > 1.2 { score += 0.35 }
                        if shortLong > 1.15 { score += 0.25 }
                        if flux > 0.15 { score += 0.2 }
                        if visualBassEnergy > vectorAverageEnergy { score += 0.2 }
                    } else {
                        if energy > vectorChorusThreshold { score += 0.3 }
                        if energyRatio > 1.25 { score += 0.25 }
                        if shortLong > 1.2 { score += 0.2 }
                        if visualHighEnergy > 0.25 { score += 0.15 }
                        if visualBassEnergy > 0.3 { score += 0.1 }
                    }
                    let inChorus = vectorSegment == .chorus
                    let shouldChorus = score >= (inChorus ? 0.35 : 0.55) &&
                        (inChorus || vectorChorusCount < 5)
                    if inChorus && elapsed < 8 {
                        next = .chorus
                    } else if shouldChorus {
                        if !inChorus {
                            vectorChorusCount += 1
                            if vectorChorusCount == 1 { vectorChorusThreshold = energy * 0.85 }
                        }
                        next = .chorus
                    } else if inChorus {
                        next = .bridge
                    } else if vectorSegment == .bridge && elapsed >= 4 || vectorSegment == .intro || vectorSegment == .unknown {
                        next = .verse
                    }
                }
            }
        }
        if next != vectorSegment {
            vectorSegment = next
            vectorSegmentStart = time
        }
    }

    private func analyze(_ buffer: AVAudioPCMBuffer) -> (low: Float, mid: Float, high: Float, signals: SIMD4<Float>, texture: SIMD4<Float>, energy: Float, bassEnergy: Float, highEnergy: Float, subBass: Float, subOnly: Float, transient: Float) {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else {
            return (0, 0, 0, SIMD4<Float>(repeating: 0), SIMD4<Float>(repeating: 0), 0, 0, 0, 0, 0, 0)
        }
        analyzerLock.lock()
        defer { analyzerLock.unlock() }
        guard let dsp else { return (0, 0, 0, SIMD4<Float>(repeating: 0), SIMD4<Float>(repeating: 0), 0, 0, 0, 0, 0, 0) }
        var bands = [Float](repeating: 0, count: 80)
        var categories = AnalyzerCategoryFeatures()
        bands.withUnsafeMutableBufferPointer { output in
            AnalyzerDSP_ProcessChannelExtended(
                dsp,
                channels[0],
                Int32(buffer.frameLength),
                0,
                5,
                Float(buffer.format.sampleRate),
                output.baseAddress,
                nil,
                nil,
                nil,
                &categories
            )
        }
        // The existing desktop effects use the enlarged band levels below.
        // Vector Assault's activity model uses the unscaled 80-band average,
        // matching the iOS live analyzer's amplitude level of 5.
        let low = bands[0..<10].reduce(0, +) / 10
        let mid = bands[20..<50].reduce(0, +) / 30
        let high = bands[50..<80].reduce(0, +) / 30
        let clamp01: (Float) -> Float = { min(max($0, 0), 1) }
        let transient = clamp01(categories.transient * 20)
        // HPSS residual magnitudes are intentionally small; expand their range
        // before mixing with flatness so ordinary tracks can visibly drive FX.
        let noise = clamp01(categories.noise * 12)
        let harmonic = clamp01(categories.harmonic * 5 + categories.harmonicPeakRatio * 0.06)
        let flatness = clamp01(categories.spectralFlatness)
        let electric = clamp01(noise * 0.52 + flatness * 0.78)
        let bassBand = bands[0..<17].reduce(0, +) / 17
        let highBand = bands[49..<80].reduce(0, +) / 31
        return (low * 5, mid * 5, high * 5,
                SIMD4<Float>(transient, electric, flatness, harmonic),
                SIMD4<Float>(categories.harmonicPeakRatio, categories.subBass, categories.bass, categories.lowEnergy),
                bands.reduce(0, +) / Float(bands.count) * 3,
                bassBand * 4, highBand * 5,
                categories.lowEnergy, categories.subBass, categories.transient)
    }
}


