import AppKit
import AVFoundation
import CryptoKit
import MetalKit
#if SWIFT_PACKAGE
import RealtimeDSP
import YAMNetMac
#endif

func bundledResource(_ name: String, _ ext: String) -> URL? {
#if SWIFT_PACKAGE
    Bundle.module.url(forResource: name, withExtension: ext)
#else
    Bundle.main.url(forResource: name, withExtension: ext)
#endif
}

struct VisualAudio {
    var time: Float
    var bass: Float
    var mid: Float
    var treble: Float
    var aspectRatio: Float
    var guitar: Float
    var piano: Float
    var drums: Float
    var playbackTime: Float
    var electricGuitarConfidence: Float
    var vocal: Float
    var guitarPeak: Float
    var playing: Float
    var other: Float
    // Aligned feature groups from the shared HPSS/FFT analyzer.
    var dspFeatureSignals: SIMD4<Float>
    var dspFeatureTexture: SIMD4<Float>
}

struct DesktopDotParticle {
    var position: SIMD4<Float>
    var pointSize: Float
    var color: SIMD3<Float>
    var opacity: Float
    var height: Float
}

enum DesktopBackgroundEffect: Int {
    case aurora = 0
    case tyndall = 1
    case coverDots = 2
    case cellularHive = 3

    var title: String {
        switch self {
        case .aurora: "极光波纹"
        case .tyndall: "丁达尔光束"
        case .coverDots: "封面点阵"
        case .cellularHive: "深空蜂巢"
        }
    }
    static var saved: DesktopBackgroundEffect {
        let stored = DesktopBackgroundEffect(rawValue: UserDefaults.standard.integer(forKey: "desktopBackgroundEffect")) ?? .aurora
        return stored
    }
}

func resolvePlatformArtwork(title: String, artist: String, album: String?, fallbackURL: URL?) async -> NSImage? {
    if let data = await AppleArtworkLookupService.shared.lookup(
        title: title, artist: artist, album: album, filePath: nil
    ), let image = NSImage(data: data) {
        return image
    }
    guard let fallbackURL else { return nil }
    return try? await PlatformBridgeClient.shared.coverImage(for: fallbackURL)
}

extension Notification.Name {
    static let desktopMusicLibraryChanged = Notification.Name("DesktopMusicLibraryChanged")
}
