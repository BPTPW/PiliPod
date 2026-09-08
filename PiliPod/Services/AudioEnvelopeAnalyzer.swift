import AVFoundation
import Accelerate

struct AudioEnvelopeFrame: Sendable {
    let time: TimeInterval
    let energy: Float
}

final class AudioEnvelopeAnalyzer: @unchecked Sendable {
    private let headers: [String: String]
    private let onReady: @MainActor ([AudioEnvelopeFrame]) -> Void
    private var task: Task<Void, Never>?

    init(
        headers: [String: String],
        onReady: @escaping @MainActor ([AudioEnvelopeFrame]) -> Void
    ) {
        self.headers = headers
        self.onReady = onReady
    }

    func start(stream: DashStream) {
        task?.cancel()
        task = Task { [headers, onReady] in
            do {
                let materialized = try await Self.materializeAudio(stream: stream, headers: headers)
                let frames = try Self.readEnvelope(from: materialized.url)
                if materialized.isTemporary {
                    try? FileManager.default.removeItem(at: materialized.url)
                }
                guard !Task.isCancelled, !frames.isEmpty else { return }
                await onReady(frames)
            } catch is CancellationError {
                return
            } catch {
                print("Audio envelope analysis failed: \(error)")
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private static func materializeAudio(stream: DashStream, headers: [String: String]) async throws -> MaterializedAudio {
        if stream.audioURL.isFileURL {
            return MaterializedAudio(url: stream.audioURL, isTemporary: false)
        }

        guard let base = stream.audioSegmentBase,
              let initialization = parseRange(base.initialization),
              let indexRange = parseRange(base.indexRange)
        else {
            throw EnvelopeError.missingSegmentIndex
        }

        let indexData = try await fetch(stream.audioURL, range: indexRange, headers: headers)
        let segments = try parseSIDX(indexData, offset: indexRange.start)
        guard !segments.isEmpty else { throw EnvelopeError.emptySegments }

        var data = Data()
        data.append(try await fetch(stream.audioURL, range: initialization, headers: headers))
        for segment in segments {
            try Task.checkCancellation()
            data.append(try await fetch(stream.audioURL, range: segment.range, headers: headers))
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pilipod-audio-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("mp4")
        try data.write(to: url, options: .atomic)
        return MaterializedAudio(url: url, isTemporary: true)
    }

    private static func readEnvelope(from url: URL) throws -> [AudioEnvelopeFrame] {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw EnvelopeError.missingAudioTrack
        }

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMBitDepthKey: 32,
                AVSampleRateKey: 22_050
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw EnvelopeError.readerSetupFailed }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? EnvelopeError.readerSetupFailed }

        let windowSize = 1024
        var rmsFrames: [(time: TimeInterval, rms: Float)] = []
        var windowStartTime: TimeInterval?
        var windowSumOfSquares: Float = 0
        var windowFrameCount = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)
            else { continue }

            let sampleRate = asbd.pointee.mSampleRate
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
            guard timestamp.isFinite, sampleRate > 0, frameCount > 0 else { continue }

            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &pointer
            )
            guard let pointer else { continue }
            let count = length / MemoryLayout<Float>.size
            guard count >= frameCount else { continue }
            let channels = max(count / frameCount, 1)
            let rawPointer = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: Float.self)
            for frameIndex in 0..<frameCount {
                if windowStartTime == nil {
                    windowStartTime = timestamp + Double(frameIndex) / sampleRate
                }
                let sampleStart = frameIndex * channels
                var frameSumOfSquares: Float = 0
                for channel in 0..<channels {
                    let value = rawPointer[sampleStart + channel]
                    frameSumOfSquares += value * value
                }
                windowSumOfSquares += frameSumOfSquares / Float(channels)
                windowFrameCount += 1

                if windowFrameCount == windowSize, let startTime = windowStartTime {
                    rmsFrames.append((
                        time: startTime,
                        rms: sqrtf(windowSumOfSquares / Float(windowFrameCount))
                    ))
                    windowReset(
                        startTime: &windowStartTime,
                        sumOfSquares: &windowSumOfSquares,
                        frameCount: &windowFrameCount
                    )
                }
            }
        }

        guard reader.status == .completed || reader.status == .reading else {
            throw reader.error ?? EnvelopeError.readFailed
        }
        if windowFrameCount > 0, let windowStartTime {
            rmsFrames.append((
                time: windowStartTime,
                rms: sqrtf(windowSumOfSquares / Float(windowFrameCount))
            ))
        }
        guard !rmsFrames.isEmpty else { throw EnvelopeError.emptyAudio }

        let sorted = rmsFrames.map(\.rms).sorted()
        let low = sorted[Int(Double(sorted.count - 1) * 0.10)]
        let high = max(sorted[Int(Double(sorted.count - 1) * 0.95)], low + 0.001)
        return rmsFrames.map { frame in
            let rms = frame.rms
            let normalized = min(max((rms - low) / (high - low), 0), 1)
            return AudioEnvelopeFrame(
                time: frame.time,
                energy: normalized
            )
        }
    }

    private static func windowReset(
        startTime: inout TimeInterval?,
        sumOfSquares: inout Float,
        frameCount: inout Int
    ) {
        startTime = nil
        sumOfSquares = 0
        frameCount = 0
    }

    private static func fetch(_ url: URL, range: ByteRange, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(range.start)-\(range.end)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 20
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw EnvelopeError.networkResponse
        }
        return data
    }

    private static func parseRange(_ value: String?) -> ByteRange? {
        guard let value else { return nil }
        let parts = value.split(separator: "-")
        guard parts.count == 2,
              let start = Int64(parts[0]),
              let end = Int64(parts[1]),
              start >= 0, end >= start
        else { return nil }
        return ByteRange(start: start, end: end)
    }

    private static func parseSIDX(_ data: Data, offset: Int64) throws -> [IndexedSegment] {
        let bytes = [UInt8](data)
        var position = 0
        while position + 8 <= bytes.count {
            let size = Int(u32(bytes, position))
            guard size >= 8 else { throw EnvelopeError.invalidIndex }
            if String(bytes: bytes[(position + 4)..<(position + 8)], encoding: .ascii) == "sidx" { break }
            position += size
        }
        guard position + 32 <= bytes.count else { throw EnvelopeError.invalidIndex }
        let boxSize = Int64(u32(bytes, position))
        let version = bytes[position + 8]
        var cursor = position + 16
        let timescale = u32(bytes, cursor); cursor += 4
        guard timescale > 0 else { throw EnvelopeError.invalidIndex }
        let earliest: UInt64
        let firstOffset: Int64
        if version == 0 {
            earliest = UInt64(u32(bytes, cursor)); cursor += 4
            firstOffset = Int64(u32(bytes, cursor)); cursor += 4
        } else {
            earliest = u64(bytes, cursor); cursor += 8
            firstOffset = Int64(u64(bytes, cursor)); cursor += 8
        }
        cursor += 2
        let count = Int(u16(bytes, cursor)); cursor += 2
        var mediaOffset = offset + Int64(position) + boxSize + firstOffset
        var tick = earliest
        var result: [IndexedSegment] = []
        for _ in 0..<count {
            guard cursor + 12 <= bytes.count else { break }
            let info = u32(bytes, cursor); cursor += 4
            let duration = u32(bytes, cursor); cursor += 4
            cursor += 4
            let length = Int64(info & 0x7fff_ffff)
            guard length > 0, info & 0x8000_0000 == 0 else {
                mediaOffset += max(length, 0)
                continue
            }
            result.append(IndexedSegment(range: ByteRange(start: mediaOffset, end: mediaOffset + length - 1)))
            tick += UInt64(duration)
            mediaOffset += length
        }
        return result
    }

    private static func u16(_ bytes: [UInt8], _ index: Int) -> UInt16 {
        UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
    }

    private static func u32(_ bytes: [UInt8], _ index: Int) -> UInt32 {
        UInt32(bytes[index]) << 24 | UInt32(bytes[index + 1]) << 16 | UInt32(bytes[index + 2]) << 8 | UInt32(bytes[index + 3])
    }

    private static func u64(_ bytes: [UInt8], _ index: Int) -> UInt64 {
        UInt64(u32(bytes, index)) << 32 | UInt64(u32(bytes, index + 4))
    }

    private struct ByteRange {
        let start: Int64
        let end: Int64
    }

    private struct IndexedSegment {
        let range: ByteRange
    }

    private struct MaterializedAudio {
        let url: URL
        let isTemporary: Bool
    }

    private enum EnvelopeError: Error {
        case missingSegmentIndex
        case emptySegments
        case missingAudioTrack
        case readerSetupFailed
        case readFailed
        case emptyAudio
        case invalidIndex
        case networkResponse
    }
}
