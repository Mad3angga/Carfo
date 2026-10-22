import Foundation
@preconcurrency import AVFoundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import CryptoKit
#if canImport(AppKit)
import AppKit
#endif

public struct MediaMetadata: Sendable {
    public var duration: Double
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var hasAudio: Bool
}

public enum MediaError: LocalizedError {
    case unreadable(String), noAudio, exportFailed
    public var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "Video \(name) tidak dapat dibaca oleh macOS."
        case .noAudio: return "Video ini tidak memiliki trek audio."
        case .exportFailed: return "Potongan media tidak dapat disiapkan."
        }
    }
}

public enum MediaProcessor {
    public static func metadata(url: URL) async throws -> MediaMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let video = try await asset.loadTracks(withMediaType: .video)
        guard duration.isFinite, duration > 0, let track = video.first else { throw MediaError.unreadable(url.lastPathComponent) }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: size).applying(transform)
        let fps = try await track.load(.nominalFrameRate)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        return MediaMetadata(duration: duration, width: Int(abs(bounds.width)), height: Int(abs(bounds.height)), frameRate: Double(fps), hasAudio: !audio.isEmpty)
    }
    public static func frame(url: URL, at seconds: Double, destination: URL) async throws {
        let decoder = FrameDecoder(url: url)
        try await decoder.write(at: max(0, seconds), destination: destination)
    }
    public static func frames(url: URL, segment: VideoSegment, directory: URL, decoder: FrameDecoder? = nil) async throws -> [URL] {
        try await (decoder ?? FrameDecoder(url: url)).write(times: SegmentPlanner.sampleTimes(in: segment), directory: directory)
    }
    public static func audio(url: URL, segment: VideoSegment, destination: URL) async throws {
        try Task.checkCancellation()
        guard segment.start.isFinite, segment.end.isFinite, segment.start >= 0,
              segment.end > segment.start, segment.end - segment.start <= 4 * 3600 else { throw MediaError.exportFailed }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw MediaError.noAudio }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: segment.start, preferredTimescale: 16000), duration: CMTime(seconds: segment.end - segment.start, preferredTimescale: 16000))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw MediaError.exportFailed }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? MediaError.exportFailed }
        guard FileManager.default.createFile(atPath: destination.path, contents: Data(repeating: 0, count: 44)) else { throw MediaError.exportFailed }
        let file = try FileHandle(forWritingTo: destination)
        var finished = false
        defer {
            reader.cancelReading()
            try? file.close()
            if !finished { try? FileManager.default.removeItem(at: destination) }
        }
        try file.seekToEnd()
        var pcmCount = 0
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); throw CancellationError() }
            try autoreleasepool {
                guard let block = CMSampleBufferGetDataBuffer(sample) else { throw MediaError.exportFailed }
                let count = CMBlockBufferGetDataLength(block)
                var bytes = [UInt8](repeating: 0, count: count)
                let status = bytes.withUnsafeMutableBytes { buffer in
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count, destination: buffer.baseAddress!)
                }
                guard status == kCMBlockBufferNoErr else { throw MediaError.exportFailed }
                try file.write(contentsOf: bytes)
                pcmCount += count
            }
        }
        guard reader.status == .completed, pcmCount > 0 else { throw reader.error ?? MediaError.exportFailed }
        var wav = Data()
        func string(_ value: String) { wav.append(contentsOf: value.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) } }
        string("RIFF"); integer(UInt32(36 + pcmCount)); string("WAVEfmt "); integer(UInt32(16))
        integer(UInt16(1)); integer(UInt16(1)); integer(UInt32(16000)); integer(UInt32(32000))
        integer(UInt16(2)); integer(UInt16(16)); string("data"); integer(UInt32(pcmCount))
        try file.seek(toOffset: 0)
        try file.write(contentsOf: wav)
        finished = true
    }
}

/// One generator serves all samples in a segment. A 100 ms tolerance avoids unrelated keyframes.
public final class FrameDecoder {
    private let generator: AVAssetImageGenerator
    public init(url: URL) {
        generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 480)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore
    }
    public func write(at seconds: Double, destination: URL) async throws {
        try Task.checkCancellation()
        defer { generator.cancelAllCGImageGeneration() }
        try await withTaskCancellationHandler {
            let (image, actual) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            try Task.checkCancellation()
            guard abs(actual.seconds - seconds) <= 0.101 else { throw MediaError.exportFailed }
            try save(image, to: destination)
        } onCancel: { [generator] in generator.cancelAllCGImageGeneration() }
    }
    public func write(times: [Double], directory: URL) async throws -> [URL] {
        try Task.checkCancellation()
        defer { generator.cancelAllCGImageGeneration() }
        return try await withTaskCancellationHandler {
            let requested = times.map { CMTime(seconds: $0, preferredTimescale: 600) }
            let destinations = times.indices.map { directory.appendingPathComponent("frame-\($0).jpg") }
            var completed = Set<Int>()
            for await result in generator.images(for: requested) {
                try Task.checkCancellation()
                switch result {
                case .success(let time, let image, let actual):
                    guard abs(time.seconds - actual.seconds) <= 0.101,
                          let index = requested.firstIndex(of: time) else { throw MediaError.exportFailed }
                    try save(image, to: destinations[index])
                    completed.insert(index)
                case .failure(_, let error): throw error
                }
            }
            guard completed.count == times.count else { throw MediaError.exportFailed }
            return destinations
        } onCancel: { [generator] in generator.cancelAllCGImageGeneration() }
    }
    private func save(_ image: CGImage, to destination: URL) throws {
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw MediaError.exportFailed }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw MediaError.exportFailed }
    }
}

public struct ScanReport: Sendable {
    public var clips: [FootageClip]
    public var errors: [String]
}

public enum LibraryScanner {
    public static let extensions: Set<String> = MediaType.videoExtensions.union(MediaType.imageExtensions).union(MediaType.audioExtensions)

    /// Extract image dimensions from a file URL using CGImageSource or AppKit for SVG.
    public static func imageMetadata(url: URL) throws -> (width: Int, height: Int) {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            if width > 0 && height > 0 {
                return (width, height)
            }
        }
        #if canImport(AppKit)
        if let image = NSImage(contentsOf: url) {
            let size = image.size
            if size.width > 0 && size.height > 0 {
                return (Int(size.width), Int(size.height))
            }
        }
        #endif
        throw MediaError.unreadable(url.lastPathComponent)
    }

    /// Extract duration from an audio-only file.
    public static func audioMetadata(url: URL) async throws -> (duration: Double, hasAudio: Bool) {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw MediaError.unreadable(url.lastPathComponent) }
        return (duration, true)
    }

    /// Generate a raster JPEG thumbnail for an SVG vector image using AppKit.
    public static func svgThumbnail(url: URL, destination: URL, maxDimension: CGFloat = 480) throws {
        #if canImport(AppKit)
        guard let image = NSImage(contentsOf: url) else {
            throw MediaError.unreadable(url.lastPathComponent)
        }
        let origSize = image.size
        guard origSize.width > 0, origSize.height > 0 else {
            throw MediaError.unreadable(url.lastPathComponent)
        }
        let scale = min(maxDimension / origSize.width, maxDimension / origSize.height, 1.0)
        let targetWidth = max(1, Int(origSize.width * scale))
        let targetHeight = max(1, Int(origSize.height * scale))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth,
            pixelsHigh: targetHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw MediaError.exportFailed
        }

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = ctx
        ctx?.cgContext.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx?.cgContext.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        image.draw(in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight), from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw MediaError.exportFailed
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try jpegData.write(to: destination)
        #else
        throw MediaError.unreadable(url.lastPathComponent)
        #endif
    }

    /// Generate a thumbnail for an image by copying and resizing it.
    public static func imageThumbnail(url: URL, destination: URL) throws {
        if url.pathExtension.lowercased() == "svg" {
            try svgThumbnail(url: url, destination: destination)
            return
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            if (try? svgThumbnail(url: url, destination: destination)) != nil { return }
            throw MediaError.unreadable(url.lastPathComponent)
        }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            if (try? svgThumbnail(url: url, destination: destination)) != nil { return }
            // Fall back to copying the original file as thumbnail
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            return
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw MediaError.exportFailed
        }
        CGImageDestinationAddImage(output, thumb, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw MediaError.exportFailed }
    }

    /// Reported every few files so callers can save partial results and show progress.
    public struct ScanProgress: Sendable {
        public var processed: Int
        public var total: Int
        /// Clips produced since the previous report.
        public var clips: [FootageClip]
    }

    public static func scan(folder: FootageFolder, previous: [FootageClip], thumbnails: URL, progress: (@Sendable (ScanProgress) async -> Void)? = nil) async throws -> ScanReport {
        let root = URL(fileURLWithPath: folder.path)
        guard FileManager.default.isReadableFile(atPath: root.path) else { throw CocoaError(.fileReadNoPermission) }
        var errors: [String] = []
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in
            errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            return true
        }) else { throw CocoaError(.fileReadNoPermission) }
        let old = Dictionary(previous.filter { $0.folderID == folder.id }.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var files: [URL] = []
        while let url = iterator.nextObject() as? URL {
            try Task.checkCancellation()
            if extensions.contains(url.pathExtension.lowercased()) { files.append(url) }
        }
        files.sort { $0.path < $1.path }
        await progress?(ScanProgress(processed: 0, total: files.count, clips: []))
        var clips: [FootageClip] = []
        var reported = 0
        for (index, url) in files.enumerated() {
            try Task.checkCancellation()
            do {
                if let clip = try await scanFile(url: url, folder: folder, root: root, old: old, thumbnails: thumbnails) {
                    clips.append(clip)
                    if let error = clip.transcriptError { errors.append("\(clip.name): \(error)") }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            if let progress, (index + 1) % 10 == 0 || index + 1 == files.count {
                await progress(ScanProgress(processed: index + 1, total: files.count, clips: Array(clips[reported...])))
                reported = clips.count
            }
        }
        return ScanReport(clips: clips, errors: errors)
    }

    private static func scanFile(url: URL, folder: FootageFolder, root: URL, old: [String: FootageClip], thumbnails: URL) async throws -> FootageClip? {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        let size = Int64(values.fileSize ?? 0)
        let date = values.contentModificationDate ?? .distantPast
        let fileMediaType = MediaType.from(extension: url.pathExtension)

        if var cached = old[url.path], cached.fileSize == size, cached.modifiedAt == date {
            cached.mediaType = fileMediaType
            if cached.thumbnail == nil && fileMediaType != .audio {
                cached.thumbnail = "\(cached.id.uuidString).jpg"
            }
            if let name = cached.thumbnail, !FileManager.default.fileExists(atPath: thumbnails.appendingPathComponent(name).path) {
                switch fileMediaType {
                case .image:
                    try imageThumbnail(url: url, destination: thumbnails.appendingPathComponent(name))
                case .video:
                    try await MediaProcessor.frame(url: url, at: min(1, cached.duration / 2), destination: thumbnails.appendingPathComponent(name))
                case .audio:
                    break // Audio files have no visual thumbnail
                }
            }
            cached.indexError = nil
            refreshSubtitles(for: &cached)
            return cached
        }

        let id = old[url.path]?.id ?? UUID()
        let thumbnail = fileMediaType == .audio ? nil : "\(id.uuidString).jpg"
        let relativePath = String(url.path.dropFirst(root.path.count + 1))

        switch fileMediaType {
        case .image:
            let dims = try imageMetadata(url: url)
            if let thumbnail {
                try imageThumbnail(url: url, destination: thumbnails.appendingPathComponent(thumbnail))
            }
            return FootageClip(
                id: id, folderID: folder.id, path: url.path,
                relativePath: relativePath,
                fileSize: size, modifiedAt: date, duration: 0,
                width: dims.width, height: dims.height, frameRate: 0, hasAudio: false,
                thumbnail: thumbnail,
                segments: [VideoSegment(start: 0, end: 0)],
                mediaType: .image
            )

        case .audio:
            let meta = try await audioMetadata(url: url)
            var clip = FootageClip(
                id: id, folderID: folder.id, path: url.path,
                relativePath: relativePath,
                fileSize: size, modifiedAt: date, duration: meta.duration,
                width: 0, height: 0, frameRate: 0, hasAudio: true,
                thumbnail: nil,
                segments: SegmentPlanner.segments(duration: meta.duration),
                mediaType: .audio
            )
            refreshSubtitles(for: &clip)
            return clip

        case .video:
            let metadata = try await MediaProcessor.metadata(url: url)
            if let thumbnail {
                try await MediaProcessor.frame(url: url, at: min(1, metadata.duration / 2), destination: thumbnails.appendingPathComponent(thumbnail))
            }
            var clip = FootageClip(
                id: id, folderID: folder.id, path: url.path,
                relativePath: relativePath,
                fileSize: size, modifiedAt: date, duration: metadata.duration,
                width: metadata.width, height: metadata.height, frameRate: metadata.frameRate,
                hasAudio: metadata.hasAudio, thumbnail: thumbnail,
                segments: SegmentPlanner.segments(duration: metadata.duration),
                mediaType: .video
            )
            refreshSubtitles(for: &clip)
            return clip
        }
    }

    public static func refreshSubtitles(for clip: inout FootageClip) {
        guard !clip.isImage else { return }
        let sidecar = ["srt", "vtt"].map { clip.url.deletingPathExtension().appendingPathExtension($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        guard let sidecar else {
            if clip.transcriptSource == "subtitle" {
                clip.transcripts = []; clip.transcribedAt = nil; clip.transcriptOffset = 0
                clip.transcriptSource = nil; clip.subtitleFingerprint = nil
            }
            return
        }
        guard let data = try? Data(contentsOf: sidecar) else {
            clip.transcriptError = "Subtitle tidak dapat dibaca: \(sidecar.lastPathComponent)"
            return
        }
        let fingerprint = sidecar.lastPathComponent + ":" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard fingerprint != clip.subtitleFingerprint else { return }
        let cues = SubtitleParser.parse(text: String(data: data, encoding: .utf8) ?? "")
        guard !cues.isEmpty else {
            clip.transcriptError = "Subtitle tidak valid: \(sidecar.lastPathComponent)"
            return
        }
        clip.transcripts = cues; clip.transcriptSource = "subtitle"
        clip.subtitleFingerprint = fingerprint; clip.transcribedAt = Date()
        clip.transcriptOffset = clip.duration; clip.transcriptError = nil
    }
}

public enum SubtitleParser {
    public static func parse(url: URL) -> [TranscriptCue] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text: content)
    }
    public static func parse(text: String) -> [TranscriptCue] {
        var cues: [TranscriptCue] = []
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            guard lines.count >= 2 else { continue }
            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timeLine = lines[timeIndex]
            let parts = timeLine.components(separatedBy: "-->")
            guard parts.count == 2 else { continue }
            guard let startToken = parts[0].split(whereSeparator: { $0.isWhitespace }).first,
                  let endToken = parts[1].split(whereSeparator: { $0.isWhitespace }).first,
                  let start = parseTime(String(startToken)), let end = parseTime(String(endToken)) else { continue }
            let textLines = lines.dropFirst(timeIndex + 1)
            let cueText = textLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !cueText.isEmpty, end > start else { continue }
            cues.append(TranscriptCue(start: start, end: end, text: cueText))
        }
        return cues
    }
    private static func parseTime(_ string: String) -> Double? {
        let clean = string.replacingOccurrences(of: ",", with: ".")
        let parts = clean.split(separator: ":", omittingEmptySubsequences: false)
        let components = parts.compactMap { Double($0) }
        guard components.count == parts.count, (2...3).contains(parts.count),
              components.allSatisfy({ $0.isFinite && $0 >= 0 }),
              components.last! < 60, components[components.count - 2] < 60 else { return nil }
        if components.count == 3 {
            return components[0] * 3600 + components[1] * 60 + components[2]
        } else if components.count == 2 {
            return components[0] * 60 + components[1]
        }
        return nil
    }
}
