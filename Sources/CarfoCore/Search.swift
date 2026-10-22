import Foundation
import Accelerate

public enum VectorMath {
    /// Normalizes a vector to unit length (L2 norm) using Accelerate vDSP.
    public static func normalized(_ vector: [Float]) -> [Float]? {
        guard !vector.isEmpty, vector.allSatisfy(\.isFinite) else { return nil }
        var sumSquares: Float = 0
        vDSP_svesq(vector, 1, &sumSquares, vDSP_Length(vector.count))
        guard sumSquares > 0, sumSquares.isFinite else { return nil }
        let magnitude = sqrt(sumSquares)
        var result = [Float](repeating: 0, count: vector.count)
        var divisor = magnitude
        vDSP_vsdiv(vector, 1, &divisor, &result, 1, vDSP_Length(vector.count))
        return result
    }

    /// Fast dot product of two vectors using Accelerate vDSP (SIMD / AMX).
    public static func dot(_ lhs: [Float], _ rhs: [Float]) -> Float? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        var result: Float = 0
        vDSP_dotpr(lhs, 1, rhs, 1, &result, vDSP_Length(lhs.count))
        return result.isFinite ? result : nil
    }

    /// Cosine similarity between two vectors using Accelerate vDSP.
    public static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float? {
        guard lhs.count == rhs.count, let a = normalized(lhs), let b = normalized(rhs) else { return nil }
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result.isFinite ? result : nil
    }

    /// Computes cosine similarity between a pre-normalized query vector and a candidate vector.
    /// Fast-paths unit vectors directly to vDSP dot product with ZERO heap allocations.
    public static func similarity(normalizedQuery: [Float], candidate: [Float]) -> Float? {
        guard normalizedQuery.count == candidate.count, !candidate.isEmpty else { return nil }
        var sumSquares: Float = 0
        vDSP_svesq(candidate, 1, &sumSquares, vDSP_Length(candidate.count))
        guard sumSquares > 0, sumSquares.isFinite else { return nil }
        var dotProduct: Float = 0
        vDSP_dotpr(normalizedQuery, 1, candidate, 1, &dotProduct, vDSP_Length(candidate.count))
        guard dotProduct.isFinite else { return nil }
        if abs(sumSquares - 1.0) < 0.005 {
            return dotProduct
        }
        let score = dotProduct / sqrt(sumSquares)
        return score.isFinite ? score : nil
    }
}

public struct SearchResult: Identifiable, Sendable {
    public var id: String {
        if let cue = matchedCue { return clip.id.uuidString + cue.id.uuidString }
        return clip.id.uuidString + (segment?.id.uuidString ?? "file")
    }
    public var clip: FootageClip
    public var segment: VideoSegment?
    public var score: Float
    public var matchedCue: TranscriptCue?
    public var contextCues: [TranscriptCue]
    public var isSampleData: Bool
    public init(clip: FootageClip, segment: VideoSegment? = nil, score: Float = 0, matchedCue: TranscriptCue? = nil, contextCues: [TranscriptCue] = [], isSampleData: Bool = false) {
        self.clip = clip; self.segment = segment; self.score = score
        self.matchedCue = matchedCue; self.contextCues = contextCues; self.isSampleData = isSampleData
    }
}

private final class ConcurrentResultCollector: @unchecked Sendable {
    private var storage: [SearchResult] = []
    private let lock = NSLock()
    func append(_ batch: [SearchResult]) {
        guard !batch.isEmpty else { return }
        lock.lock()
        storage.append(contentsOf: batch)
        lock.unlock()
    }
    func results() -> [SearchResult] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

public enum SearchEngine {
    /// Minimum cosine between a query and a transcript line for a meaning-only match.
    /// Measured on EmbeddingGemma 2: related Indonesian pairs score about 0.82 to 0.91, unrelated 0.58 to 0.70.
    public static let dialogueSemanticFloor: Float = 0.78

    public static func search(clips: [FootageClip], query: String, mode: SearchMode = .video, folderID: UUID? = nil, embedding: [Float]? = nil, textEmbedding: [Float]? = nil, limit: Int = 40) -> [SearchResult] {
        guard limit > 0 else { return [] }
        let folderFiltered = clips.filter { folderID == nil || $0.folderID == folderID }
        // Filter by relevant media types per mode
        let candidates: [FootageClip]
        switch mode {
        case .video:
            candidates = folderFiltered.filter { $0.mediaType == .video }
        case .visual:
            candidates = folderFiltered.filter { $0.mediaType == .image }
        case .sound:
            candidates = folderFiltered.filter { $0.mediaType == .audio || ($0.mediaType == .video && $0.hasAudio) }
        case .dialogue:
            candidates = folderFiltered.filter { $0.hasAudio }
        }
        let tokens = normalized(query).split(separator: " ").map(String.init)

        // Pre-normalize query vectors once to eliminate redundant normalizations during segment scans
        let queryVector = embedding.flatMap { VectorMath.normalized($0) }
        let textQueryVector = textEmbedding.flatMap { VectorMath.normalized($0) }
        let effectiveVector = mode == .dialogue ? (textQueryVector ?? queryVector) : queryVector

        if mode == .dialogue {
            let transcribed = candidates.filter { $0.transcribedAt != nil || !$0.transcripts.isEmpty }
            if !transcribed.isEmpty {
                guard !tokens.isEmpty else { return [] }
                var dialogueResults = dialogueMatches(in: transcribed, tokens: tokens, textEmbedding: textEmbedding, prenormalizedQuery: textQueryVector)
                let matchedClipIDs = Set(dialogueResults.map(\.clip.id))
                let audioQuery = textQueryVector ?? queryVector

                for clip in candidates where !matchedClipIDs.contains(clip.id) {
                    let filename = normalized(clip.name + " " + clip.relativePath)
                    if tokens.allSatisfy({ filename.contains($0) }) {
                        dialogueResults.append(SearchResult(clip: clip, score: 0))
                    } else if let audioQuery {
                        // Hybrid fallback: check untranscribed clips or clips with no dialogue matches using audio embedding
                        var bestSegment: VideoSegment?
                        var bestScore: Float = 0
                        for segment in clip.segments {
                            if let aEmbed = segment.audioEmbedding,
                               let s = VectorMath.similarity(normalizedQuery: audioQuery, candidate: aEmbed),
                               s >= dialogueSemanticFloor,
                               s > bestScore {
                                bestScore = s
                                bestSegment = segment
                            }
                        }
                        if let bestSegment {
                            dialogueResults.append(SearchResult(clip: clip, segment: bestSegment, score: bestScore))
                        }
                    }
                }
                return Array(dialogueResults.sorted { a, b in
                    if a.score == b.score { return (a.matchedCue?.start ?? 0) < (b.matchedCue?.start ?? 0) }
                    return a.score > b.score
                }.prefix(limit))
            }
            if clips.isEmpty {
                let samples = SampleDialogue.sampleResults
                guard !tokens.isEmpty else { return Array(samples.prefix(limit)) }
                return samples.filter { item in
                    let cueNorm = normalized(item.matchedCue?.text ?? "")
                    return tokens.contains { cueNorm.contains($0) }
                }
            }
            // Footage exists but nothing is transcribed yet: fall back to approximate audio-vector search below using effectiveVector.
        }

        if tokens.isEmpty {
            return candidates.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .prefix(limit).map { SearchResult(clip: $0) }
        }

        let evaluateCandidate: (FootageClip) -> SearchResult? = { clip in
            let filename = normalized(clip.name + " " + clip.relativePath)
            let filenameMatch = tokens.allSatisfy { filename.contains($0) }
            var best: SearchResult?
            if let activeVector = effectiveVector {
                for segment in clip.segments {
                    var score: Float?
                    switch mode {
                    case .video:
                        let vScore = segment.visualEmbedding.flatMap { VectorMath.similarity(normalizedQuery: activeVector, candidate: $0) }
                        let aScore = segment.audioEmbedding.flatMap { VectorMath.similarity(normalizedQuery: activeVector, candidate: $0) }
                        if let vScore, let aScore {
                            let primary = max(vScore, aScore)
                            let secondary = min(vScore, aScore)
                            // Multi-modal boost: if both visual and audio match the query, reward dual-signal relevance
                            if secondary > 0.3 {
                                score = primary + (secondary - 0.3) * 0.25
                            } else {
                                score = primary
                            }
                        } else {
                            score = vScore ?? aScore
                        }
                    case .visual:
                        score = segment.visualEmbedding.flatMap { VectorMath.similarity(normalizedQuery: activeVector, candidate: $0) }
                    case .sound, .dialogue:
                        score = segment.audioEmbedding.flatMap { VectorMath.similarity(normalizedQuery: activeVector, candidate: $0) }
                    }
                    guard let score else { continue }
                    if best == nil || score > best!.score {
                        best = SearchResult(clip: clip, segment: segment, score: score)
                    }
                }
            }
            if let best { return best }
            else if filenameMatch { return SearchResult(clip: clip, score: 0) }
            return nil
        }

        let results: [SearchResult]
        if candidates.count >= 24 && effectiveVector != nil {
            let processorCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
            let chunkSize = max(8, (candidates.count + processorCount - 1) / processorCount)
            let chunkCount = (candidates.count + chunkSize - 1) / chunkSize
            let collector = ConcurrentResultCollector()
            DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
                let start = chunkIndex * chunkSize
                let end = min(candidates.count, start + chunkSize)
                let batch = candidates[start..<end].compactMap(evaluateCandidate)
                collector.append(batch)
            }
            results = collector.results()
        } else {
            results = candidates.compactMap(evaluateCandidate)
        }

        return Array(results.sorted { a, b in
            if a.score == b.score { return a.clip.name.localizedStandardCompare(b.clip.name) == .orderedAscending }
            return a.score > b.score
        }.prefix(limit))
    }

    public static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "id_ID"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Scores every transcript line: exact phrase > all words > most words, plus meaning similarity.
    static func dialogueMatches(in clips: [FootageClip], tokens: [String], textEmbedding: [Float]?, prenormalizedQuery: [Float]? = nil) -> [SearchResult] {
        let phrase = tokens.joined(separator: " ")
        let queryVector = prenormalizedQuery ?? textEmbedding.flatMap { VectorMath.normalized($0) }
        var results: [SearchResult] = []
        for clip in clips {
            let cues = clip.transcripts.sorted { $0.start < $1.start }
            for (index, cue) in cues.enumerated() {
                let text = normalized(cue.text)
                let matched = tokens.filter { text.contains($0) }.count
                let fraction = Float(matched) / Float(tokens.count)
                let lexical: Float = text.contains(phrase) ? 1.0 : matched == tokens.count ? 0.8 : fraction >= 0.5 ? 0.5 * fraction : 0
                let similarity = queryVector.flatMap { q in cue.embedding.flatMap { VectorMath.similarity(normalizedQuery: q, candidate: $0) } }
                let semantic = similarity.map { $0 >= dialogueSemanticFloor } ?? false
                guard lexical > 0 || semantic else { continue }
                let context = [index > 0 ? cues[index - 1] : nil, cue, index + 1 < cues.count ? cues[index + 1] : nil].compactMap { $0 }
                results.append(SearchResult(clip: clip, segment: VideoSegment(start: cue.start, end: cue.end), score: lexical + (similarity ?? 0), matchedCue: cue, contextCues: context))
            }
        }
        return results.sorted { a, b in
            if a.score == b.score { return (a.matchedCue?.start ?? 0) < (b.matchedCue?.start ?? 0) }
            return a.score > b.score
        }
    }
}

