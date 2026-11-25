import AVFoundation
import Foundation

/// Estimates the presentation-time offset between a song and a music video.
/// `videoTime = songTime + offset`.
enum MVAudioAlignment {
    struct Result: Sendable {
        let offset: Double
        let correlation: Double
        let songDuration: Double
        let videoDuration: Double
    }

    enum Error: Swift.Error, LocalizedError {
        case noAudio
        case unsupportedAudio
        case decodeFailed
        case insufficientOverlap
        case silence
        case lowSimilarity
        case ambiguous
        case durationMismatch

        var errorDescription: String? {
            switch self {
            case .noAudio: return "缺少音频轨道。"
            case .unsupportedAudio: return "音频格式不受支持。"
            case .decodeFailed: return "音频解码失败。"
            case .insufficientOverlap: return "可匹配的音频时长不足。"
            case .silence: return "音频有效信号不足。"
            case .lowSimilarity: return "音频相似度过低。"
            case .ambiguous: return "音频偏移结果不明确。"
            case .durationMismatch: return "音频时长差异过大。"
            }
        }
    }

    private static let binDuration = 0.1

    static func align(songURL: URL, videoAsset: AVAsset) async throws -> Result {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let song = try decode(url: songURL)
            try Task.checkCancellation()
            let video = try decode(asset: videoAsset)
            return try findAlignment(song: song, video: video)
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    private struct Envelope {
        var values: [Double]
        let duration: Double
    }

    private static func decode(url: URL) throws -> Envelope {
        try decode(asset: AVURLAsset(url: url))
    }

    private static func decode(asset: AVAsset) throws -> Envelope {
        let tracks = asset.tracks(withMediaType: .audio)
        guard let track = tracks.first else { throw Error.noAudio }
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration >= binDuration, duration <= 720 else { throw Error.insufficientOverlap }
        let count = Int(ceil(duration / binDuration)) + 1
        var energy = Array(repeating: 0.0, count: count)
        var samples = Array(repeating: 0, count: count)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw Error.unsupportedAudio }
        reader.add(output)
        guard reader.startReading() else { throw Error.decodeFailed }
        var sampleRate = 0.0
        var channels = 0
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let format = CMSampleBufferGetFormatDescription(buffer),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  asbd.mBitsPerChannel == 32,
                  asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0 else { throw Error.unsupportedAudio }
            sampleRate = Double(asbd.mSampleRate); channels = Int(asbd.mChannelsPerFrame)
            guard channels > 0, sampleRate > 0,
                  let block = CMSampleBufferGetDataBuffer(buffer) else { throw Error.decodeFailed }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                              totalLengthOut: &length, dataPointerOut: &pointer) == kCMBlockBufferNoErr,
                  let pointer else { throw Error.decodeFailed }
            let frameBytes = channels * MemoryLayout<Float>.size
            let frameCount = length / frameBytes
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
            guard pts.isFinite else { throw Error.decodeFailed }
            let floats = UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                if frame & 2047 == 0 { try Task.checkCancellation() }
                let time = pts + Double(frame) / sampleRate
                guard time.isFinite else { throw Error.decodeFailed }
                let index = Int(floor(time / binDuration))
                guard index >= 0, index < count else { continue }
                var sum = 0.0
                for channel in 0..<channels { let value = Double(floats[frame * channels + channel]); sum += value * value }
                energy[index] += sum / Double(channels); samples[index] += 1
            }
        }
        guard reader.status == .completed else { throw Error.decodeFailed }
        guard sampleRate > 0 else { throw Error.unsupportedAudio }
        return Envelope(values: zip(energy, samples).map { $0.1 > 0 ? sqrt($0.0 / Double($0.1)) : 0 }, duration: duration)
    }

    private static func findAlignment(song: Envelope, video: Envelope) throws -> Result {
        guard min(song.duration, video.duration) >= 20.0 else { throw Error.insufficientOverlap }
        let durationDelta = abs(song.duration - video.duration)
        guard durationDelta <= 60.0 else { throw Error.durationMismatch }
        guard song.values.max() ?? 0 > 1e-5, video.values.max() ?? 0 > 1e-5 else { throw Error.silence }
        // A few seconds apart is a trimmed intro or outro of the same recording.
        // Search wide enough for that trim to sit on either end.
        let nearSameLength = durationDelta <= 15
        let extraVideoDuration = max(0, video.duration - song.duration)
        let extraSongDuration = max(0, song.duration - video.duration)
        let trimAllowance = nearSameLength
            ? min(12.0, max(8.0, durationDelta))
            : min(12.0, max(3.0, durationDelta * 0.25))
        let minimumOffset = -extraSongDuration - trimAllowance
        let maximumOffset = extraVideoDuration + trimAllowance
        var candidates: [(offset: Double, correlation: Double)] = []
        var offset = minimumOffset
        while offset <= maximumOffset + 0.0001 {
            try Task.checkCancellation()
            if let c = correlation(song, video, offset: offset, start: 0, length: nil) { candidates.append((offset, c)) }
            offset += binDuration
        }
        let globalMinimum = nearSameLength ? 0.82 : 0.85
        guard let best = candidates.max(by: { $0.correlation < $1.correlation }), best.correlation >= globalMinimum else {
            NSLog("[MVAlign] 校准失败：候选不足或整体相似度低于门槛，歌曲=%.2fs，MV音轨=%.2fs，偏移搜索=[%.2f, %.2f]s，最佳相关系数=%.4f",
                  song.duration, video.duration, minimumOffset, maximumOffset, candidates.map(\.correlation).max() ?? -1)
            throw Error.lowSimilarity
        }
        let competitor = candidates.filter { abs($0.offset - best.offset) > 1.0 }.max(by: { $0.correlation < $1.correlation })?.correlation ?? -1
        // Near-equal lengths produce a broad peak: a one-second neighbor stays
        // close even when the best offset is the right trim.
        let gapMinimum = nearSameLength && best.correlation >= 0.90 ? 0.03 : 0.08
        guard best.correlation - competitor >= gapMinimum else {
            NSLog("[MVAlign] 校准歧义：偏移=%.2fs，最佳相关系数=%.4f，次优相关系数=%.4f，差值=%.4f，门槛=%.2f",
                  best.offset, best.correlation, competitor, best.correlation - competitor, gapMinimum)
            throw Error.ambiguous
        }
        let overlapStart = max(0, -best.offset)
        let overlapEnd = min(song.duration, video.duration - best.offset)
        let overlap = overlapEnd - overlapStart
        guard overlap >= max(20, song.duration * 0.80) else {
            NSLog("[MVAlign] 校准失败：重叠时长=%.2fs，歌曲时长=%.2fs，覆盖率=%.3f", overlap, song.duration, overlap / song.duration)
            throw Error.insufficientOverlap
        }
        let section = max(6.0, min(12.0, overlap / 3.0))
        let starts = [overlapStart, overlapStart + (overlap - section) / 2, overlapEnd - section]
        var sectionScores = [Double]()
        for start in starts {
            try Task.checkCancellation()
            // -1 marks a window with no usable signal, such as a fade at a trimmed edge.
            sectionScores.append(correlation(song, video, offset: best.offset, start: start, length: section) ?? -1)
        }
        // The head and tail windows sit on the intro and outro join. A few seconds
        // of trim, or a fade with no usable signal, should not reject a recording
        // the full song has already matched.
        let edgeMinimum: Double
        let middleMinimum: Double
        if nearSameLength && best.correlation >= 0.90 {
            edgeMinimum = 0.72
            middleMinimum = 0.80
        } else if best.correlation >= 0.92 {
            edgeMinimum = 0.80
            middleMinimum = 0.85
        } else {
            edgeMinimum = 0.85
            middleMinimum = 0.85
        }
        let minimums = [edgeMinimum, middleMinimum, edgeMinimum]
        let edgeMayBeSilent = nearSameLength && best.correlation >= 0.90
        let sectionPassed = sectionScores.count == minimums.count && zip(sectionScores, minimums).enumerated().allSatisfy { index, pair in
            if pair.0 < 0 { return edgeMayBeSilent && index != 1 }
            return pair.0 >= pair.1
        }
        guard sectionPassed else {
            NSLog("[MVAlign] 校准失败：歌曲=%.2fs，MV音轨=%.2fs，偏移=%.2fs，整体相关系数=%.4f，分段相关系数=[%.4f, %.4f, %.4f]，分段门槛=[%.2f, %.2f, %.2f]",
                  song.duration, video.duration, best.offset, best.correlation,
                  sectionScores.first ?? -1, sectionScores.dropFirst().first ?? -1, sectionScores.last ?? -1,
                  minimums[0], minimums[1], minimums[2])
            throw Error.lowSimilarity
        }
        NSLog("[MVAlign] 校准通过：歌曲=%.2fs，MV音轨=%.2fs，偏移=%.2fs，额外MV时长=%.2fs，重叠=%.2fs，整体相关系数=%.4f，分段相关系数=[%.4f, %.4f, %.4f]",
              song.duration, video.duration, best.offset, extraVideoDuration, overlap, best.correlation,
              sectionScores[0], sectionScores[1], sectionScores[2])
        return Result(offset: best.offset, correlation: best.correlation, songDuration: song.duration, videoDuration: video.duration)
    }

    private static func correlation(_ song: Envelope, _ video: Envelope, offset: Double, start: Double, length: Double?) -> Double? {
        let end = min(length.map { start + $0 } ?? song.duration, song.duration, video.duration - offset)
        let first = max(start, 0, -offset), last = end
        guard last - first >= 6 else { return nil }
        let shift = Int((offset / binDuration).rounded())
        var a = [Double](), b = [Double](), i = Int(ceil(first / binDuration))
        while Double(i) * binDuration < last {
            let j = i + shift
            guard i < song.values.count, j >= 0, j < video.values.count else { i += 1; continue }
            a.append(song.values[i]); b.append(video.values[j]); i += 1
        }
        guard a.count >= 60 else { return nil }
        let meanA = a.reduce(0, +) / Double(a.count), meanB = b.reduce(0, +) / Double(b.count)
        let va = a.reduce(0) { $0 + ($1 - meanA) * ($1 - meanA) }, vb = b.reduce(0) { $0 + ($1 - meanB) * ($1 - meanB) }
        guard va > 1e-10, vb > 1e-10 else { return nil }
        return zip(a, b).reduce(0) { $0 + ($1.0 - meanA) * ($1.1 - meanB) } / sqrt(va * vb)
    }
}
