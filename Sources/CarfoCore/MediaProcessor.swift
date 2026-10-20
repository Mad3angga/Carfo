import Foundation
@preconcurrency import AVFoundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

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
        try Task.checkCancellation()
        try autoreleasepool {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 480)
            let image = try generator.copyCGImage(at: CMTime(seconds: max(0, seconds), preferredTimescale: 600), actualTime: nil)
            guard let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw MediaError.exportFailed }
            CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(output) else { throw MediaError.exportFailed }
        }
    }
    public static func frames(url: URL, segment: VideoSegment, directory: URL) async throws -> [URL] {
        var result: [URL] = []
        for (index, time) in SegmentPlanner.sampleTimes(in: segment).enumerated() {
            let destination = directory.appendingPathComponent("frame-\(index).jpg")
            try await frame(url: url, at: time, destination: destination)
            result.append(destination)
        }
        return result
    }
    public static func audio(url: URL, segment: VideoSegment, destination: URL) async throws {
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
        var pcm = Data()
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); throw CancellationError() }
            autoreleasepool {
                guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
                let count = CMBlockBufferGetDataLength(block)
                var bytes = [UInt8](repeating: 0, count: count)
                let status = bytes.withUnsafeMutableBytes { buffer in
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count, destination: buffer.baseAddress!)
                }
                guard status == kCMBlockBufferNoErr else { return }
                pcm.append(contentsOf: bytes)
            }
        }
        guard reader.status == .completed, !pcm.isEmpty else { throw reader.error ?? MediaError.exportFailed }
        var wav = Data()
        func string(_ value: String) { wav.append(contentsOf: value.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) } }
        string("RIFF"); integer(UInt32(36 + pcm.count)); string("WAVEfmt "); integer(UInt32(16))
        integer(UInt16(1)); integer(UInt16(1)); integer(UInt32(16000)); integer(UInt32(32000))
        integer(UInt16(2)); integer(UInt16(16)); string("data"); integer(UInt32(pcm.count)); wav.append(pcm)
        try wav.write(to: destination, options: .atomic)
    }
}

public struct ScanReport: Sendable {
    public var clips: [FootageClip]
    public var errors: [String]
}

public enum LibraryScanner {
    public static let extensions: Set<String> = MediaType.videoExtensions.union(MediaType.imageExtensions).union(MediaType.audioExtensions)

    /// Extract image dimensions from a file URL using CGImageSource.
    public static func imageMetadata(url: URL) throws -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw MediaError.unreadable(url.lastPathComponent)
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw MediaError.unreadable(url.lastPathComponent)
        }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        return (width, height)
    }

    /// Extract duration from an audio-only file.
    public static func audioMetadata(url: URL) async throws -> (duration: Double, hasAudio: Bool) {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw MediaError.unreadable(url.lastPathComponent) }
        return (duration, true)
    }

    /// Generate a thumbnail for an image by copying and resizing it.
    public static func imageThumbnail(url: URL, destination: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw MediaError.unreadable(url.lastPathComponent)
        }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
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

    public static func scan(folder: FootageFolder, previous: [FootageClip], thumbnails: URL) async throws -> ScanReport {
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
        var clips: [FootageClip] = []
        for url in files.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
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
                    clips.append(cached)
                    continue
                }

                let id = old[url.path]?.id ?? UUID()
                let thumbnail = fileMediaType == .audio ? nil : "\(id.uuidString).jpg"

                switch fileMediaType {
                case .image:
                    let dims = try imageMetadata(url: url)
                    if let thumbnail {
                        try imageThumbnail(url: url, destination: thumbnails.appendingPathComponent(thumbnail))
                    }
                    clips.append(FootageClip(
                        id: id, folderID: folder.id, path: url.path,
                        relativePath: String(url.path.dropFirst(root.path.count + 1)),
                        fileSize: size, modifiedAt: date, duration: 0,
                        width: dims.width, height: dims.height, frameRate: 0, hasAudio: false,
                        thumbnail: thumbnail,
                        segments: [VideoSegment(start: 0, end: 0)],
                        mediaType: .image
                    ))

                case .audio:
                    let meta = try await audioMetadata(url: url)
                    clips.append(FootageClip(
                        id: id, folderID: folder.id, path: url.path,
                        relativePath: String(url.path.dropFirst(root.path.count + 1)),
                        fileSize: size, modifiedAt: date, duration: meta.duration,
                        width: 0, height: 0, frameRate: 0, hasAudio: true,
                        thumbnail: nil,
                        segments: SegmentPlanner.segments(duration: meta.duration),
                        mediaType: .audio
                    ))

                case .video:
                    let metadata = try await MediaProcessor.metadata(url: url)
                    if let thumbnail {
                        try await MediaProcessor.frame(url: url, at: min(1, metadata.duration / 2), destination: thumbnails.appendingPathComponent(thumbnail))
                    }
                    let srtURL = url.deletingPathExtension().appendingPathExtension("srt")
                    let vttURL = url.deletingPathExtension().appendingPathExtension("vtt")
                    var transcripts: [TranscriptCue] = []
                    if FileManager.default.fileExists(atPath: srtURL.path) {
                        transcripts = SubtitleParser.parse(url: srtURL)
                    } else if FileManager.default.fileExists(atPath: vttURL.path) {
                        transcripts = SubtitleParser.parse(url: vttURL)
                    }
                    clips.append(FootageClip(
                        id: id, folderID: folder.id, path: url.path,
                        relativePath: String(url.path.dropFirst(root.path.count + 1)),
                        fileSize: size, modifiedAt: date, duration: metadata.duration,
                        width: metadata.width, height: metadata.height, frameRate: metadata.frameRate,
                        hasAudio: metadata.hasAudio, thumbnail: thumbnail,
                        segments: SegmentPlanner.segments(duration: metadata.duration),
                        transcripts: transcripts, mediaType: .video
                    ))
                }
            } catch is CancellationError { throw CancellationError() }
            catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        return ScanReport(clips: clips, errors: errors)
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
            let timeLine = lines.first { $0.contains("-->") } ?? ""
            guard !timeLine.isEmpty else { continue }
            let parts = timeLine.components(separatedBy: "-->")
            guard parts.count == 2 else { continue }
            let start = parseTime(parts[0].trimmingCharacters(in: .whitespaces))
            let end = parseTime(parts[1].trimmingCharacters(in: .whitespaces))
            let textLines = lines.filter { $0 != timeLine && Int($0) == nil }
            let cueText = textLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !cueText.isEmpty, end > start else { continue }
            cues.append(TranscriptCue(start: start, end: end, text: cueText))
        }
        return cues
    }
    private static func parseTime(_ string: String) -> Double {
        let clean = string.replacingOccurrences(of: ",", with: ".")
        let components = clean.split(separator: ":").compactMap { Double($0) }
        if components.count == 3 {
            return components[0] * 3600 + components[1] * 60 + components[2]
        } else if components.count == 2 {
            return components[0] * 60 + components[1]
        }
        return Double(clean) ?? 0
    }
}
