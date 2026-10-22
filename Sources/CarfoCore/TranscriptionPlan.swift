import Foundation

public struct TranscriptionChunk: Sendable {
    public let start: Double
    public let end: Double
    public let extraction: VideoSegment
}

public enum TranscriptionPlan {
    public static let maximumDuration: Double = 4 * 3600
    public static func chunks(duration: Double, resumeAt: Double = 0, length: Double = 60, overlap: Double = 2) throws -> [TranscriptionChunk] {
        guard duration.isFinite, duration > 0, duration <= maximumDuration,
              resumeAt.isFinite, resumeAt >= 0, length.isFinite, length > 0,
              overlap.isFinite, overlap >= 0 else { throw MediaError.exportFailed }
        return stride(from: min(resumeAt, duration), to: duration, by: length).map { start in
            let end = min(duration, start + length)
            return TranscriptionChunk(start: start, end: end,
                extraction: VideoSegment(start: max(0, start - overlap), end: min(duration, end + overlap)))
        }
    }
    public static func cues(_ local: [TranscriptCue], in chunk: TranscriptionChunk) -> [TranscriptCue] {
        local.compactMap { cue in
            var cue = cue
            cue.start += chunk.extraction.start; cue.end += chunk.extraction.start
            let midpoint = (cue.start + cue.end) / 2
            guard midpoint >= chunk.start, midpoint < chunk.end else { return nil }
            cue.start = max(0, cue.start); cue.end = min(chunk.extraction.end, cue.end)
            return cue.end > cue.start ? cue : nil
        }
    }
}

public struct LibraryStats: Equatable, Sendable {
    public private(set) var video = 0, image = 0, audio = 0, indexed = 0, transcribed = 0, needsTranscript = 0
    public private(set) var folderCounts: [UUID: Int] = [:]
    public init(_ clips: [FootageClip] = []) { for clip in clips { apply(clip, delta: 1) } }
    public mutating func replace(_ old: FootageClip?, with new: FootageClip?) {
        if let old { apply(old, delta: -1) }
        if let new { apply(new, delta: 1) }
    }
    private mutating func apply(_ clip: FootageClip, delta: Int) {
        switch clip.mediaType {
        case .video: video += delta
        case .image: image += delta
        case .audio: audio += delta
        }
        if clip.isIndexed { indexed += delta }
        if clip.transcribedAt != nil { transcribed += delta }
        if clip.needsTranscript { needsTranscript += delta }
        folderCounts[clip.folderID, default: 0] += delta
    }
}
