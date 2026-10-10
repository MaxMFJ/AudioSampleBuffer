import AppKit

enum DesktopLyricsSurface {
    case overlay
    case coverStage
}

/// Positions use viewport fractions, with (0, 0) at the top left.
struct DesktopLyricsConfiguration {
    enum Window { case grouped, centered }
    enum Layout { case column, scattered([CGPoint]) }
    enum FontSize {
        case fixed(CGFloat)
        case relativeToHeight(fraction: CGFloat, minimum: CGFloat, maximum: CGFloat)

        func points(in viewport: CGSize) -> CGFloat {
            switch self {
            case .fixed(let points): return max(1, points)
            case .relativeToHeight(let fraction, let minimum, let maximum):
                return min(max(viewport.height * fraction, minimum), maximum)
            }
        }
    }

    var isEnabled = true
    var lineCount = 5
    var window: Window = .centered
    var layout: Layout = .column
    var position = CGPoint(x: 0.5, y: 0.5)
    var lineSpacing: CGFloat = 0.07
    var maxWidthFraction: CGFloat = 0.82
    var fontSize: FontSize = .relativeToHeight(fraction: 0.058, minimum: 40, maximum: 58)
    var inactiveFontScale: CGFloat = 0.78
    var inactiveOpacity: CGFloat = 0.46
    var activeWeight: NSFont.Weight = .semibold
    var inactiveWeight: NSFont.Weight = .semibold

    static let coverStage = DesktopLyricsConfiguration()
    static let overlay: DesktopLyricsConfiguration = {
        var value = DesktopLyricsConfiguration()
        value.lineCount = 4
        value.window = .grouped
        value.layout = .scattered([
            CGPoint(x: -0.22, y: -0.16), CGPoint(x: 0.22, y: 0.15),
            CGPoint(x: 0.22, y: -0.16), CGPoint(x: -0.22, y: 0.15)
        ])
        value.maxWidthFraction = 0.42
        value.fontSize = .fixed(27)
        value.inactiveFontScale = 19.0 / 27.0
        value.inactiveOpacity = 0.5
        value.activeWeight = .bold
        value.inactiveWeight = .medium
        return value
    }()
}

/// Shared input for AppKit, Metal and future lyric effects. Renderers do not select lines.
struct DesktopLyricsFrame {
    struct Row {
        let text: String
        let timelineIndex: Int
        let isActive: Bool
        let progress: Float
        let position: CGPoint
        let fontSize: CGFloat
        let fontWeight: NSFont.Weight
        let opacity: CGFloat
        let maxWidthFraction: CGFloat
    }
    let activeIndex: Int
    let rows: [Row]
}

@MainActor
final class DesktopLyricsController {
    private let source = DesktopLyricsSource()
    var overlayConfiguration: DesktopLyricsConfiguration {
        didSet { save(overlayConfiguration, for: .overlay) }
    }
    var stageConfiguration: DesktopLyricsConfiguration {
        didSet { save(stageConfiguration, for: .coverStage) }
    }

    init() {
        overlayConfiguration = Self.restore(for: .overlay, default: .overlay)
        stageConfiguration = Self.restore(for: .coverStage, default: .coverStage)
    }

    func configuration(for surface: DesktopLyricsSurface) -> DesktopLyricsConfiguration {
        surface == .overlay ? overlayConfiguration : stageConfiguration
    }

    func setConfiguration(_ configuration: DesktopLyricsConfiguration, for surface: DesktopLyricsSurface) {
        if surface == .overlay { overlayConfiguration = configuration }
        else { stageConfiguration = configuration }
    }

    func resetConfiguration(for surface: DesktopLyricsSurface) {
        setConfiguration(surface == .overlay ? .overlay : .coverStage, for: surface)
    }

    private static func preferenceKey(for surface: DesktopLyricsSurface) -> String {
        surface == .overlay ? "desktopLyrics.overlay.v1" : "desktopLyrics.coverStage.v1"
    }

    private func save(_ configuration: DesktopLyricsConfiguration, for surface: DesktopLyricsSurface) {
        var values: [String: Any] = [
            "enabled": configuration.isEnabled, "lines": configuration.lineCount,
            "window": configuration.window == .centered ? "centered" : "grouped",
            "x": Double(configuration.position.x), "y": Double(configuration.position.y),
            "spacing": Double(configuration.lineSpacing), "width": Double(configuration.maxWidthFraction),
            "scale": Double(configuration.inactiveFontScale), "opacity": Double(configuration.inactiveOpacity),
            "activeWeight": Double(configuration.activeWeight.rawValue),
            "inactiveWeight": Double(configuration.inactiveWeight.rawValue)
        ]
        switch configuration.layout {
        case .column: values["layout"] = "column"
        case .scattered(let offsets):
            values["layout"] = "scattered"
            values["offsets"] = offsets.map { [Double($0.x), Double($0.y)] }
        }
        switch configuration.fontSize {
        case .fixed(let points): values["font"] = "fixed"; values["points"] = Double(points)
        case .relativeToHeight(let fraction, let minimum, let maximum):
            values["font"] = "relative"; values["fraction"] = Double(fraction)
            values["minimum"] = Double(minimum); values["maximum"] = Double(maximum)
        }
        UserDefaults.standard.set(values, forKey: Self.preferenceKey(for: surface))
    }

    private static func restore(for surface: DesktopLyricsSurface,
                                default fallback: DesktopLyricsConfiguration) -> DesktopLyricsConfiguration {
        guard let values = UserDefaults.standard.dictionary(forKey: preferenceKey(for: surface)) else { return fallback }
        func number(_ key: String, _ fallback: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
            guard let value = values[key] as? Double, value.isFinite else { return fallback }
            return min(max(CGFloat(value), range.lowerBound), range.upperBound)
        }
        var config = fallback
        config.isEnabled = values["enabled"] as? Bool ?? fallback.isEnabled
        config.lineCount = min(max(values["lines"] as? Int ?? fallback.lineCount, 1), 12)
        if let mode = values["window"] as? String { config.window = mode == "grouped" ? .grouped : .centered }
        if values["layout"] as? String == "column" { config.layout = .column }
        else if let offsets = values["offsets"] as? [[Double]] {
            config.layout = .scattered(offsets.prefix(12).compactMap { pair in
                guard pair.count == 2, pair.allSatisfy(\.isFinite) else { return nil }
                return CGPoint(x: pair[0], y: pair[1])
            })
        }
        config.position = CGPoint(x: number("x", fallback.position.x, 0...1), y: number("y", fallback.position.y, 0...1))
        config.lineSpacing = number("spacing", fallback.lineSpacing, 0.01...0.3)
        config.maxWidthFraction = number("width", fallback.maxWidthFraction, 0.05...1)
        config.inactiveFontScale = number("scale", fallback.inactiveFontScale, 0.1...1)
        config.inactiveOpacity = number("opacity", fallback.inactiveOpacity, 0...1)
        config.activeWeight = NSFont.Weight(rawValue: number("activeWeight", fallback.activeWeight.rawValue, -1...1))
        config.inactiveWeight = NSFont.Weight(rawValue: number("inactiveWeight", fallback.inactiveWeight.rawValue, -1...1))
        if values["font"] as? String == "fixed" {
            config.fontSize = .fixed(number("points", 36, 8...160))
        } else if values["font"] as? String == "relative" {
            let minimum = number("minimum", 40, 8...160)
            config.fontSize = .relativeToHeight(fraction: number("fraction", 0.058, 0.01...0.2),
                minimum: minimum, maximum: max(minimum, number("maximum", 58, 8...160)))
        }
        return config
    }

    func load(for url: URL, title: String, artist: String?) { source.load(for: url, title: title, artist: artist) }
    func clear() { source.clear() }

    func frame(at time: Double, surface: DesktopLyricsSurface, viewport: CGSize) -> DesktopLyricsFrame {
        let configuration = surface == .overlay ? overlayConfiguration : stageConfiguration
        let lines = source.lines
        let index = Self.activeIndex(in: lines, at: time)
        guard configuration.isEnabled else { return DesktopLyricsFrame(activeIndex: index, rows: []) }
        let count = min(max(configuration.lineCount, 1), 12)
        let first: Int
        switch configuration.window {
        case .grouped: first = index >= 0 ? (index / count) * count : -count
        case .centered: first = index >= 0 ? index - count / 2 : -count
        }
        let baseFontSize = configuration.fontSize.points(in: viewport)
        let rows = (0..<count).map { slot -> DesktopLyricsFrame.Row in
            let lineIndex = first + slot
            let text = lines.indices.contains(lineIndex)
                ? lines[lineIndex].text.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let active = lineIndex == index && !text.isEmpty
            let offset: CGPoint
            switch configuration.layout {
            case .scattered(let positions) where positions.indices.contains(slot): offset = positions[slot]
            default: offset = CGPoint(x: 0, y: CGFloat(slot - count / 2) * configuration.lineSpacing)
            }
            return DesktopLyricsFrame.Row(text: text, timelineIndex: lineIndex, isActive: active,
                progress: active ? Self.progress(in: lines, index: index, at: time) : 0,
                position: CGPoint(x: configuration.position.x + offset.x, y: configuration.position.y + offset.y),
                fontSize: baseFontSize * (active ? 1 : max(0.1, configuration.inactiveFontScale)),
                fontWeight: active ? configuration.activeWeight : configuration.inactiveWeight,
                opacity: active ? 1 : min(max(configuration.inactiveOpacity, 0), 1),
                maxWidthFraction: min(max(configuration.maxWidthFraction, 0.05), 1))
        }
        return DesktopLyricsFrame(activeIndex: index, rows: rows)
    }

    static func activeIndex(in lines: [TimedLyric], at time: Double) -> Int {
        guard time.isFinite else { return -1 }
        var low = 0, high = lines.count - 1, result = -1
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= time { result = mid; low = mid + 1 }
            else { high = mid - 1 }
        }
        return result
    }

    static func progress(in lines: [TimedLyric], index: Int, at time: Double) -> Float {
        guard lines.indices.contains(index), time.isFinite else { return 0 }
        let start = lines[index].time
        let end = lines.indices.contains(index + 1) ? lines[index + 1].time : start + 4
        return Float(min(max((time - start) / max(end - start, 0.1), 0), 1))
    }
}
