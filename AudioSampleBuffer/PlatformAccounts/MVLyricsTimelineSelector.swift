import Foundation
import CryptoKit

/// Selects lyric anchored timeline evidence. Timestamps and section bounds come
/// from the provider LRC. A repeated opening line is not treated as the section.
enum MVLyricsTimelineSelector {
    private struct Line { let id: String; let time: Double; let text: String; let raw: String }
    private struct Pattern { let length: Int; let starts: [Int] }
    private enum SelectionError: Error { case unavailable, invalidLyrics }

    static func select(songURL: URL, title: String, artist: String, songDuration: Double,
                       endpoint _: URL, apiKey _: String, model _: String) async throws -> [[String: Any]] {
        let provider = try await providerLyrics(path: songURL.path, title: title, artist: artist)
        guard let lrc = provider["lrc"] as? String,
              let sourceURL = provider["sourceURL"] as? String else { throw SelectionError.unavailable }
        try Task.checkCancellation()
        if provider["versionConfirmed"] as? Bool != true {
            guard let matched = provider["matchedDuration"] as? Double, matched > 0, abs(matched - songDuration) <= 1.5 else { throw SelectionError.unavailable }
        }
        let lines = parse(lrc: lrc, duration: songDuration)
        guard lines.count >= 12 else { throw SelectionError.invalidLyrics }
        let hash = SHA256.hash(data: Data(lrc.utf8)).map { String(format: "%02x", $0) }.joined()
        let usable = repeatedPatterns(lines).filter { pattern in
            pattern.starts.contains { lines[$0].time >= songDuration * 0.15 && lines[$0].time <= songDuration * 0.75 }
        }
        let chorus = usable.max { lhs, rhs in
            if lhs.starts.count != rhs.starts.count { return lhs.starts.count < rhs.starts.count }
            return lhs.length < rhs.length
        }
        var spans: [(start: Int, end: Int, label: String)] = []
        if let chorus {
            let ranges = chorus.starts.enumerated().compactMap { offset, start -> (Int, Int)? in
                let next = offset + 1 < chorus.starts.count ? chorus.starts[offset + 1] : nil
                return bounded(lines, start: start, length: chorus.length, limit: next)
            }
            let climaxIndex = ranges.lastIndex { lines[$0.0].time >= songDuration * 0.65 }
            for (index, range) in ranges.enumerated() {
                spans.append((range.0, range.1, index == climaxIndex ? "climax" : "chorus"))
            }
        }
        var occupied = spans.map { (lines[$0.start].time, lines[$0.end].time) }
        for (index, line) in lines.enumerated() where line.text.range(of: "beat.?drop|drop", options: [.regularExpression, .caseInsensitive]) != nil {
            guard let range = dropWindow(lines, index: index) else { continue }
            let interval = (lines[range.0].time, lines[range.1].time)
            guard !occupied.contains(where: { $0.0 < interval.1 && interval.0 < $0.1 }) else { continue }
            spans.append((range.0, range.1, "drop"))
            occupied.append(interval)
        }
        let result = spans.map { span -> [String: Any] in
            let start = lines[span.start], end = lines[span.end]
            let selected = lines.filter { $0.time >= start.time && $0.time <= end.time }
            return ["start": start.time, "end": end.time, "duration": end.time - start.time,
                    "score": 0.0, "label": span.label, "evidence": selected.map(\.text).joined(separator: "\n"),
                    "evidenceType": "provider_lrc_anchor", "sourceURL": sourceURL,
                    "sourceTimestamp": start.raw, "sourceExcerpt": selected.map(\.raw).joined(separator: "\n"),
                    "providerProvenance": provider["provenance"] ?? "unknown", "versionConfirmed": provider["versionConfirmed"] ?? false, "matchedDuration": provider["matchedDuration"] ?? 0,
                    "lyricSHA256": hash, "startLineID": start.id, "endLineID": end.id,
                    "timelineBasis": "song", "semanticStatus": "lrc_repetition"]
        }
        var disjoint = [[String: Any]](); var cursor = 0.0
        for row in result.sorted(by: { ($0["start"] as! Double) < ($1["start"] as! Double) }) {
            if (row["start"] as! Double) >= cursor { disjoint.append(row); cursor = row["end"] as! Double }
        }
        let summary = disjoint.map { row in
            let start = row["start"] as? Double ?? 0, end = row["end"] as? Double ?? 0
            return String(format: "%@ %.2f–%.2f", row["label"] as? String ?? "", start, end)
        }.joined(separator: "，")
        NSLog("[MVLyrics] 采用歌词原文段落 %ld 个：%@", disjoint.count, summary.isEmpty ? "无" : summary)
        return disjoint
    }

    /// A chorus is the repeated multi-line block that also occurs in the body of the
    /// song. An intro line that only returns at the outro never qualifies.
    private static func repeatedPatterns(_ lines: [Line]) -> [Pattern] {
        let keys = lines.map { normalized($0.text) }
        var seen = Set<String>()
        var patterns = [Pattern]()
        for i in lines.indices where keys[i].count >= 5 {
            for j in (i + 1)..<lines.count where keys[j] == keys[i] {
                var length = 1
                while i + length < j, j + length < lines.count, keys[i + length].count >= 5, keys[i + length] == keys[j + length] { length += 1 }
                guard length >= 2 else { continue }
                let signature = keys[i..<(i + length)].joined(separator: "\n")
                guard seen.insert(signature).inserted else { continue }
                var starts = [Int](), cursor = 0
                while cursor + length <= lines.count {
                    if keys[cursor..<(cursor + length)].joined(separator: "\n") == signature {
                        starts.append(cursor); cursor += length
                    } else { cursor += 1 }
                }
                if starts.count >= 2 { patterns.append(Pattern(length: length, starts: starts)) }
            }
        }
        return patterns
    }

    private static func bounded(_ lines: [Line], start: Int, length: Int, limit: Int?) -> (Int, Int)? {
        var end = start + length - 1
        let stop = limit ?? lines.count
        while end > start, lines[end].time - lines[start].time > 24 { end -= 1 }
        while end + 1 < stop, lines[end].time - lines[start].time < 4 {
            let gap = lines[end + 1].time - lines[end].time
            guard gap <= 8, lines[end + 1].time - lines[start].time <= 24 else { break }
            end += 1
        }
        let span = lines[end].time - lines[start].time
        guard end > start, span >= 4, span <= 24 else { return nil }
        return (start, end)
    }

    private static func dropWindow(_ lines: [Line], index: Int) -> (Int, Int)? {
        var start = index
        while start > 0, lines[index].time - lines[start - 1].time <= 6 { start -= 1 }
        var end = index
        while end + 1 < lines.count, lines[end + 1].time - lines[index].time <= 8 { end += 1 }
        if lines[end].time - lines[start].time < 4, end + 1 < lines.count, lines[end + 1].time - lines[start].time <= 12 { end += 1 }
        let span = lines[end].time - lines[start].time
        guard end > start, span >= 4, span <= 24 else { return nil }
        return (start, end)
    }

    private static func providerLyrics(path: String, title: String, artist: String) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            MVLyricsProvider.fetch(songPath: path, title: title, artist: artist) { result in
                guard let result else { continuation.resume(throwing: SelectionError.unavailable); return }
                continuation.resume(returning: result.reduce(into: [String: Any]()) { dict, entry in if let key = entry.key as? String { dict[key] = entry.value } })
            }
        }
    }

    private static func parse(lrc: String, duration: Double) -> [Line] {
        let expression = try! NSRegularExpression(pattern: #"\[(\d+):([0-5]\d)(?:\.(\d{1,3}))?\]"#)
        let offsetExpression = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let full = lrc as NSString
        var offset = 0.0
        if let match = offsetExpression.firstMatch(in: lrc, range: NSRange(location: 0, length: full.length)) {
            offset = (Double(full.substring(with: match.range(at: 1))) ?? 0) / 1000
        }
        var output = [Line]()
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = expression.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.range(of: #"^(作词|作曲|编曲|制作|词[:：]|曲[:：]|lyricist|composer)"#, options: [.regularExpression, .caseInsensitive]) == nil else { continue }
            for match in matches {
                let fraction = match.range(at: 3).location == NSNotFound ? "0" : "0." + ns.substring(with: match.range(at: 3))
                let time = (Double(ns.substring(with: match.range(at: 1))) ?? 0) * 60 + (Double(ns.substring(with: match.range(at: 2))) ?? 0) + (Double(fraction) ?? 0) + offset
                guard time >= 0, time <= duration else { continue }
                output.append(Line(id: "l\(output.count)", time: time, text: text, raw: raw))
            }
        }
        return output.sorted { $0.time < $1.time }
    }
    private static func normalized(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).filter { !$0.isWhitespace && !$0.isPunctuation } }
    private static func artistTokens(_ s: String) -> [String] { s.split(whereSeparator: { $0 == "," || $0 == "/" || $0 == "、" }).map(String.init).filter { !$0.isEmpty } }
}
