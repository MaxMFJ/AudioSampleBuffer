import Foundation
import AVFoundation
import CryptoKit

struct TimedLyric {
    let time: Double
    let text: String
}

@MainActor
final class DesktopLyricsSource {
    private(set) var lines: [TimedLyric] = []
    private var task: Task<Void, Never>?
    private var generation = 0

    func load(for audioURL: URL, title: String, artist: String?, neteaseTrackID: String? = nil, duration: Double? = nil) {
        task?.cancel()
        generation += 1
        let currentGeneration = generation
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacDesktopPlayer/Lyrics", isDirectory: true)
        // Separate provider caches from older QQ matches and avoid basename collisions.
        let identity = neteaseTrackID.map { "netease:\($0)" } ?? "\(audioURL.absoluteString)|\(title)|\(artist ?? "")"
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let cacheURL = support.appendingPathComponent("netease-v1-" + digest).appendingPathExtension("lrc")
        let localCandidates = [audioURL.deletingPathExtension().appendingPathExtension("lrc"), cacheURL]
        if let content = localCandidates.compactMap({ try? String(contentsOf: $0, encoding: .utf8) }).first {
            lines = Self.parseLRC(content)
            task = nil
            return
        }
        lines = []
        task = Task { [weak self] in
            guard let self else { return }
            let asset = AVURLAsset(url: audioURL)
            let metadata = (try? await asset.load(.commonMetadata)) ?? []
            guard !Task.isCancelled else { return }
            if let embedded = metadata.first(where: { $0.commonKey?.rawValue == "lyrics" }),
               let text = try? await embedded.load(.stringValue), !Self.parseLRC(text).isEmpty {
                guard !Task.isCancelled, self.generation == currentGeneration else { return }
                self.lines = Self.parseLRC(text)
                return
            }
            guard !Task.isCancelled else { return }
            let trackID: String?
            if let neteaseTrackID {
                trackID = neteaseTrackID
            } else {
                trackID = try? await NativeNetEaseClient.shared.matchedLyricTrackID(title: title, artist: artist, duration: duration)
            }
            guard !Task.isCancelled, self.generation == currentGeneration,
                  let trackID,
                  let lrc = try? await NativeNetEaseClient.shared.lyrics(trackID: trackID),
                  !Self.parseLRC(lrc).isEmpty,
                  !Task.isCancelled, self.generation == currentGeneration else { return }
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            guard !Task.isCancelled, self.generation == currentGeneration else { return }
            try? lrc.write(to: cacheURL, atomically: true, encoding: .utf8)
            guard !Task.isCancelled, self.generation == currentGeneration else { return }
            self.lines = Self.parseLRC(lrc)
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        generation += 1
        lines = []
    }

    static func parseLRC(_ content: String) -> [TimedLyric] {
        let pattern = #"\[(\d+):(\d+)(?:\.(\d+))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return content.components(separatedBy: .newlines).flatMap { line -> [TimedLyric] in
            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            guard !matches.isEmpty else { return [] }
            let text = regex.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return matches.compactMap { match in
                guard let minRange = Range(match.range(at: 1), in: line),
                      let secRange = Range(match.range(at: 2), in: line),
                      let minutes = Double(line[minRange]), let seconds = Double(line[secRange]) else { return nil }
                var fraction = 0.0
                if match.numberOfRanges > 3, let fractionRange = Range(match.range(at: 3), in: line) {
                    let raw = String(line[fractionRange])
                    fraction = (Double(raw) ?? 0) / pow(10, Double(raw.count))
                }
                return TimedLyric(time: minutes * 60 + seconds + fraction, text: text)
            }
        }.sorted { $0.time < $1.time }
    }

}
