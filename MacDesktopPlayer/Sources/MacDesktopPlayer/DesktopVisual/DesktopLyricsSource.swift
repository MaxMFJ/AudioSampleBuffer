import Foundation
import AVFoundation

struct TimedLyric {
    let time: Double
    let text: String
}

@MainActor
final class DesktopLyricsSource {
    private(set) var lines: [TimedLyric] = []
    private var task: Task<Void, Never>?
    private var generation = 0

    func load(for audioURL: URL, title: String, artist: String?) {
        task?.cancel()
        generation += 1
        let currentGeneration = generation
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacDesktopPlayer/Lyrics", isDirectory: true)
        let localCandidates = [audioURL.deletingPathExtension().appendingPathExtension("lrc"),
                               support.appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent).appendingPathExtension("lrc")]
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
            guard !Task.isCancelled,
                  let lrc = await Self.fetchQQLyrics(title: title, artist: artist),
                  !Self.parseLRC(lrc).isEmpty,
                  !Task.isCancelled, self.generation == currentGeneration else { return }
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            guard !Task.isCancelled, self.generation == currentGeneration else { return }
            try? lrc.write(to: support.appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent).appendingPathExtension("lrc"), atomically: true, encoding: .utf8)
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

    private static func fetchQQLyrics(title: String, artist: String?) async -> String? {
        var search = URLComponents(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp")!
        search.queryItems = [URLQueryItem(name: "p", value: "1"), URLQueryItem(name: "n", value: "1"),
                             URLQueryItem(name: "w", value: [artist, title].compactMap { $0 }.joined(separator: " ")),
                             URLQueryItem(name: "format", value: "json")]
        guard let searchURL = search.url else { return nil }
        var request = URLRequest(url: searchURL)
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["data"] as? [String: Any], let song = response["song"] as? [String: Any],
              let list = song["list"] as? [[String: Any]], let mid = list.first?["songmid"] as? String else { return nil }
        var lyric = URLComponents(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")!
        lyric.queryItems = [URLQueryItem(name: "songmid", value: mid), URLQueryItem(name: "format", value: "json")]
        guard let lyricURL = lyric.url else { return nil }
        var lyricRequest = URLRequest(url: lyricURL)
        lyricRequest.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        lyricRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        guard let (lyricData, _) = try? await URLSession.shared.data(for: lyricRequest),
              let lyricJSON = try? JSONSerialization.jsonObject(with: lyricData) as? [String: Any],
              let encoded = lyricJSON["lyric"] as? String, let decoded = Data(base64Encoded: encoded) else { return nil }
        return String(data: decoded, encoding: .utf8)
    }
}
