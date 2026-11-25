import AVFoundation
import CryptoKit
import Foundation

/// Lyric timestamps, published time claims, and one whole-song spectrum pass
/// can enter this cache, together with the downloaded MV file. A later play of
/// the same audio file reuses both and does not call the model again.
/// Playback never re-decides the MV from live FFT peaks.
@objc(MVTimelineCoordinator)
final class MVTimelineCoordinator: NSObject {
    @objc static let shared = MVTimelineCoordinator()
    private static let policy = "source-lrc-official-v4"

    @objc(analyzeSongURL:title:artist:completion:)
    func analyze(songURL: URL, title: String, artist: String,
                 completion: @escaping (URL?, [[String: Any]]?, Bool, String?) -> Void) -> Progress {
        analyze(songURL: songURL, title: title, artist: artist, preferredVideoID: nil, preferredVideoTitle: nil, completion: completion)
    }

    @objc(analyzeSongURL:title:artist:preferredVideoID:preferredVideoTitle:completion:)
    func analyze(songURL: URL, title: String, artist: String, preferredVideoID: String?, preferredVideoTitle: String?,
                 completion: @escaping (URL?, [[String: Any]]?, Bool, String?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let settings = LLMAPISettings.shared()
        let endpoint = settings.serviceURL
        let key = settings.apiKey
        let model = settings.model
        let task = Task.detached(priority: .utility) {
            do {
                let digest = try Self.fileDigest(songURL)
                let cacheURL = try Self.cacheURL(digest: digest)
                let saved = Self.readCache(cacheURL, digest: digest)
                let pinnedID = preferredVideoID?.hasPrefix("BV") == true ? preferredVideoID : nil
                let savedID = saved?["bvid"] as? String
                if let saved, let savedID, savedID.hasPrefix("BV"), pinnedID == nil || pinnedID == savedID,
                   let moments = saved["moments"] as? [[String: Any]] {
                    if let local = Self.localVideoURL(saved, digest: digest) {
                        try Task.checkCancellation()
                        NSLog("[MVTimeline] 命中本地 MV 与时间表，跳过模型，BV=%@，片段数=%ld", savedID, moments.count)
                        await MainActor.run {
                            if !progress.isCancelled { completion(local, moments, true, nil) }
                        }
                        return
                    }
                    let titleText = (saved["videoTitle"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? savedID
                    let video = BilibiliVideoClient.Video(id: savedID, title: titleText, author: "", duration: "", coverURL: nil)
                    NSLog("[MVTimeline] 时间表已缓存，补存 MV 文件并跳过模型，BV=%@", savedID)
                    let playback = try await PlatformMusicService.shared.bilibiliPlaybackInfo(for: video)
                    try Task.checkCancellation()
                    let (temp, _) = try await Self.downloadWithFallback(playback.url)
                    defer { try? FileManager.default.removeItem(at: temp) }
                    let local = try Self.persistVideo(from: temp, digest: digest)
                    var updated = saved
                    updated["videoFile"] = local.lastPathComponent
                    if let data = try? JSONSerialization.data(withJSONObject: updated) {
                        try? data.write(to: cacheURL, options: .atomic)
                    }
                    await MainActor.run {
                        if !progress.isCancelled { completion(local, moments, true, nil) }
                    }
                    return
                }
                let video: BilibiliVideoClient.Video
                if let pinnedID {
                    video = .init(id: pinnedID, title: preferredVideoTitle?.isEmpty == false ? preferredVideoTitle! : pinnedID, author: "", duration: "", coverURL: nil)
                    NSLog("[BiliMV] 使用手动指定视频：BV=%@，标题=%@", video.id, video.title)
                } else {
                    let track = ProviderTrack(id: "mv-\(digest)", platform: .netease, name: title, artist: artist)
                    let choices = try await PlatformMusicService.shared.searchBilibiliVideos(for: track)
                    guard let chosen = BilibiliMVResolverBridge.bestMatch(choices, song: title, artist: artist) else {
                        throw Self.failure("没有找到匹配视频，跳过自动播放。")
                    }
                    video = chosen
                }
                try Task.checkCancellation()
                let playback = try await PlatformMusicService.shared.bilibiliPlaybackInfo(for: video)
                guard let endpoint, endpoint.scheme == "https", !key.isEmpty, !model.isEmpty else {
                    throw Self.failure("请在 AI 设置配置接口；没有真实歌词或来源时不生成猜测时间表。")
                }
                let audio = try AVAudioFile(forReading: songURL)
                let songDuration = Double(audio.length) / audio.processingFormat.sampleRate
                async let lyricRequest = MVLyricsTimelineSelector.select(songURL: songURL, title: title, artist: artist,
                    songDuration: songDuration, endpoint: endpoint, apiKey: key, model: model)
                async let sourceRequest = MVSourceTimelineSelector.select(videoID: video.id, title: title, artist: artist,
                    duration: playback.duration, endpoint: endpoint, apiKey: key, model: model)
                let lyricRows = (try? await lyricRequest) ?? []
                let sourceRows = (try? await sourceRequest) ?? []
                try Task.checkCancellation()
                NSLog("[MVTimeline] 真实 LRC 候选=%ld，外部时间来源候选=%ld", lyricRows.count, sourceRows.count)
                // Alignment is waveform matching. The spectrum pass reads the finished
                // song once and only contributes schedule rows.
                async let spectrumRequest = Self.spectrumMoments(songURL: songURL)
                let (temp, selectedURL) = try await Self.downloadWithFallback(playback.url)
                defer { try? FileManager.default.removeItem(at: temp) }
                let asset = AVURLAsset(url: temp)
                let aligned = try await MVAudioAlignment.align(songURL: songURL, videoAsset: asset)
                let spectrum = await spectrumRequest
                try Task.checkCancellation()
                var mapped = [[String: Any]]()
                for original in sourceRows + lyricRows {
                    guard let start = original["start"] as? Double, let end = original["end"] as? Double else { continue }
                    var row = original
                    if original["timelineBasis"] as? String == "song" {
                        row["videoStart"] = start + aligned.offset
                        row["videoEnd"] = end + aligned.offset
                    } else {
                        row["start"] = start - aligned.offset
                        row["end"] = end - aligned.offset
                    }
                    guard let mappedStart = row["start"] as? Double, let mappedEnd = row["end"] as? Double,
                          let videoStart = row["videoStart"] as? Double, let videoEnd = row["videoEnd"] as? Double,
                          mappedStart >= 0, mappedEnd <= aligned.songDuration, videoStart >= 0, videoEnd <= aligned.videoDuration else { continue }
                    mapped.append(row)
                }
                let chosen = Self.withoutOverlaps(mapped)
                let moments = Self.mergeSpectrum(spectrum, into: chosen, songDuration: aligned.songDuration, videoDuration: aligned.videoDuration, offset: aligned.offset)
                guard !moments.isEmpty else { throw Self.failure("没有歌词、来源或整曲频谱段落，已跳过视频。") }
                guard Self.valid(moments, songDuration: aligned.songDuration, videoDuration: aligned.videoDuration, offset: aligned.offset) else {
                    throw Self.failure("AI 返回的媒体证据或时间范围未通过校验，已跳过。")
                }
                try Task.checkCancellation()
                // Reject files modified while the analysis was in flight.
                guard digest == (try Self.fileDigest(songURL)) else { throw Self.failure("音频文件已变化，丢弃本次分析。") }
                let stored = try? Self.persistVideo(from: temp, digest: digest)
                var record: [String: Any] = ["policy": Self.policy, "digest": digest,
                    "bvid": video.id, "cid": playback.cid, "videoTitle": video.title,
                    "songDuration": aligned.songDuration, "videoDuration": aligned.videoDuration,
                    "offset": aligned.offset, "correlation": aligned.correlation,
                    "model": model, "moments": moments]
                if let stored { record["videoFile"] = stored.lastPathComponent }
                let data = try JSONSerialization.data(withJSONObject: record)
                try Task.checkCancellation()
                try data.write(to: cacheURL, options: .atomic)
                let playbackURL = stored ?? selectedURL
                await MainActor.run {
                    if !progress.isCancelled { progress.completedUnitCount = 1; completion(playbackURL, moments, false, nil) }
                }
            } catch {
                guard !Task.isCancelled, !progress.isCancelled else { return }
                // Do not return provider bodies, authenticated URLs, or secrets.
                let message: String
                if (error as NSError).domain == "MVTimeline" {
                    message = error.localizedDescription
                } else if let alignmentError = error as? MVAudioAlignment.Error {
                    message = "音视频校准失败：\(alignmentError.localizedDescription)"
                } else {
                    message = "来源检索、视频加载或音视频校准失败，已跳过视频；音乐继续播放。"
                }
                await MainActor.run { if !progress.isCancelled { completion(nil, nil, false, message) } }
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "MVTimeline", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func fileDigest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            try Task.checkCancellation()
            let bytes = try handle.read(upToCount: 256 * 1024) ?? Data()
            if bytes.isEmpty { break }
            hash.update(data: bytes)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func supportDirectory() throws -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MVSourceTimelines", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cacheURL(digest: String) throws -> URL {
        try supportDirectory().appendingPathComponent("\(policy)-\(digest).json")
    }

    private static func videoFileName(digest: String) -> String {
        "\(policy)-\(digest).mp4"
    }

    /// The video stays beside the timeline. Application Support is not cleared between plays.
    private static func persistVideo(from temp: URL, digest: String) throws -> URL {
        let dest = try supportDirectory().appendingPathComponent(videoFileName(digest: digest))
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: temp, to: dest)
        var excluded = dest
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
        return dest
    }

    private static func localVideoURL(_ row: [String: Any], digest: String) -> URL? {
        guard let name = row["videoFile"] as? String, name == videoFileName(digest: digest),
              let url = try? supportDirectory().appendingPathComponent(name),
              let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
              size.int64Value > 0 else { return nil }
        return url
    }

    private static func readCache(_ url: URL, digest: String) -> [String: Any]? {
        if let row = loadCache(url, digest: digest) { return row }
        let legacy = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MVSourceTimelines", isDirectory: true)
            .appendingPathComponent(url.lastPathComponent)
        guard let row = loadCache(legacy, digest: digest) else { return nil }
        if let data = try? Data(contentsOf: legacy) { try? data.write(to: url, options: .atomic) }
        return row
    }

    private static func loadCache(_ url: URL, digest: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url), data.count < 1_000_000,
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              row["policy"] as? String == policy, row["digest"] as? String == digest,
              let songDuration = row["songDuration"] as? Double,
              let videoDuration = row["videoDuration"] as? Double,
              let offset = row["offset"] as? Double,
              let correlation = row["correlation"] as? Double, correlation.isFinite, correlation >= 0.85,
              let moments = row["moments"] as? [[String: Any]],
              valid(moments, songDuration: songDuration, videoDuration: videoDuration, offset: offset) else { return nil }
        return row
    }

    private static func valid(_ rows: [[String: Any]], songDuration: Double, videoDuration: Double, offset: Double) -> Bool {
        guard songDuration.isFinite, videoDuration.isFinite, offset.isFinite, songDuration > 0, videoDuration > 0 else { return false }
        var lastEnd = 0.0
        for row in rows {
            guard let start = row["start"] as? Double, let end = row["end"] as? Double,
                  let videoStart = row["videoStart"] as? Double, let videoEnd = row["videoEnd"] as? Double,
                  let label = row["label"] as? String,
                  ["kaisa_solo", "group_dance", "signature_dance", "social_hotspot", "chorus", "drop", "climax", "energy_peak", "instrument_focus"].contains(label),
                  let evidence = row["evidence"] as? String, !evidence.isEmpty,
                  let excerpt = row["sourceExcerpt"] as? String, !excerpt.isEmpty,
                  let type = row["evidenceType"] as? String,
                  ["provider_lrc_anchor", "published_timestamp", "spectrum_schedule"].contains(type),
                  start.isFinite, end.isFinite, videoStart.isFinite, videoEnd.isFinite,
                  start >= lastEnd - 0.001, end <= songDuration, end - start >= 4, end - start <= 24,
                  videoStart >= 0, videoEnd <= videoDuration,
                  abs(videoStart - start - offset) < 0.001,
                  abs(videoEnd - videoStart - (end - start)) < 0.001 else { return false }
            if type == "provider_lrc_anchor" {
                guard let source = row["sourceURL"] as? String, URL(string: source)?.scheme == "https",
                      row["startLineID"] is String, row["endLineID"] is String,
                      row["lyricSHA256"] is String, ["model_inference", "lrc_repetition"].contains(row["semanticStatus"] as? String),
                      !["kaisa_solo", "group_dance", "signature_dance", "social_hotspot", "energy_peak", "instrument_focus"].contains(label) else { return false }
            } else if type == "spectrum_schedule" {
                guard ["energy_peak", "instrument_focus"].contains(label), row["semanticStatus"] as? String == "whole_song_spectrum" else { return false }
            } else {
                guard let source = row["sourceURL"] as? String, URL(string: source)?.scheme == "https",
                      row["sourceID"] is String, row["sourceTimestamp"] is String,
                      excerpt.contains(evidence) else { return false }
            }
            lastEnd = end
        }
        return true
    }

    private static func spectrumMoments(songURL: URL) async -> [[String: Any]] {
        await withCheckedContinuation { continuation in
            MVMomentAnalyzer.shared().analyzeFile(at: songURL) { moments, _, _ in
                let rows = (moments ?? []).compactMap { item -> [String: Any]? in
                    guard let start = item["start"]?.doubleValue, let end = item["end"]?.doubleValue, end - start >= 4 else { return nil }
                    return ["start": start, "end": end, "score": item["score"]?.doubleValue ?? 0, "kind": item["kind"]?.intValue ?? 1]
                }
                continuation.resume(returning: rows)
            }
        }
    }

    private static func withoutOverlaps(_ rows: [[String: Any]]) -> [[String: Any]] {
        var chosen = [[String: Any]]()
        for row in rows.sorted(by: { ($0["start"] as? Double ?? 0) < ($1["start"] as? Double ?? 0) }) {
            let start = row["start"] as? Double ?? 0, end = row["end"] as? Double ?? 0
            if chosen.contains(where: { start < ($0["end"] as? Double ?? 0) && end > ($0["start"] as? Double ?? 0) }) { continue }
            chosen.append(row)
        }
        return chosen
    }

    /// Loud spectrum runs confirm an existing section. At most two runs that do not
    /// sit on a lyric or source section become their own schedule rows.
    private static func mergeSpectrum(_ raw: [[String: Any]], into rows: [[String: Any]], songDuration: Double, videoDuration: Double, offset: Double) -> [[String: Any]] {
        var annotated = rows
        var added = 0
        for item in raw.sorted(by: { ($0["score"] as? Double ?? 0) > ($1["score"] as? Double ?? 0) }) {
            guard let rawStart = item["start"] as? Double, let rawEnd = item["end"] as? Double else { continue }
            let span = rawEnd - rawStart
            let length = min(span, 16)
            guard length >= 4 else { continue }
            let start = rawStart + (span - length) / 2
            let end = start + length
            let bright = (item["kind"] as? Int) == 2
            if let index = annotated.firstIndex(where: { row in
                let left = row["start"] as? Double ?? 0, right = row["end"] as? Double ?? 0
                return min(end, right) - max(start, left) >= min(4, length * 0.5)
            }) {
                if annotated[index]["spectrumSupport"] == nil { annotated[index]["spectrumSupport"] = bright ? "bright" : "energy" }
                continue
            }
            guard added < 2, start >= 0, end <= songDuration, start + offset >= 0, end + offset <= videoDuration else { continue }
            if annotated.contains(where: { row in
                let left = row["start"] as? Double ?? 0, right = row["end"] as? Double ?? 0
                return start < right + 8 && end > left - 8
            }) { continue }
            let evidence = bright
                ? "整曲频谱里这一段高频占比高、整体能量低于副歌，按乐器突出段排入时间表，不是播放中实时触发。"
                : "整曲频谱里这一段同时处于高能量和高占比高频，按高能高潮排入时间表，不是播放中实时触发。"
            annotated.append(["start": start, "end": end, "videoStart": start + offset, "videoEnd": end + offset,
                              "label": bright ? "instrument_focus" : "energy_peak", "score": item["score"] ?? 0,
                              "evidence": evidence, "evidenceType": "spectrum_schedule", "sourceExcerpt": evidence,
                              "timelineBasis": "song", "semanticStatus": "whole_song_spectrum"])
            added += 1
        }
        let moments = annotated.sorted { ($0["start"] as? Double ?? 0) < ($1["start"] as? Double ?? 0) }
        NSLog("[MVTimeline] 整曲频谱候选=%ld，独立写入=%ld，与已有段落吻合=%ld", raw.count, added, moments.filter { $0["spectrumSupport"] != nil }.count)
        return moments
    }

    private static func downloadWithFallback(_ url: URL) async throws -> (URL, URL) {
        for candidate in BiliPlaybackSupport.candidates(for: url) {
            try Task.checkCancellation()
            do { return (try await download(candidate), candidate) }
            catch {
                try Task.checkCancellation()
                BiliPlaybackSupport.log(error: error as NSError, host: candidate.host ?? "未知", stage: "后台对齐资源加载失败，尝试下一节点")
            }
        }
        throw failure("所有视频节点的分析资源均不可用，音乐继续播放。")
    }

    private static func download(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 180
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue(BiliPlaybackSupport.userAgent, forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        let limit = 200 * 1024 * 1024
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              response.expectedContentLength <= limit else { throw failure("视频分析资源过大或不可访问。") }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("mv-analysis-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let file = try FileHandle(forWritingTo: destination)
        var complete = false
        defer { try? file.close(); if !complete { try? FileManager.default.removeItem(at: destination) } }
        var chunk = Data(); var count = 0
        for try await byte in bytes {
            count += 1
            if count > limit { throw failure("视频超过后台分析大小限制。") }
            chunk.append(byte)
            if chunk.count >= 64 * 1024 {
                try Task.checkCancellation()
                try file.write(contentsOf: chunk); chunk.removeAll(keepingCapacity: true)
            }
        }
        try Task.checkCancellation()
        if !chunk.isEmpty { try file.write(contentsOf: chunk) }
        complete = true
        return destination
    }
}
