import Foundation

public enum VectorMath {
    public static func normalized(_ vector: [Float]) -> [Float]? {
        guard !vector.isEmpty, vector.allSatisfy(\.isFinite) else { return nil }
        let magnitude = sqrt(vector.reduce(Double.zero) { $0 + Double($1) * Double($1) })
        guard magnitude > 0, magnitude.isFinite else { return nil }
        return vector.map { Float(Double($0) / magnitude) }
    }
    public static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float? {
        guard lhs.count == rhs.count, let a = normalized(lhs), let b = normalized(rhs) else { return nil }
        return zip(a, b).reduce(Float.zero) { $0 + $1.0 * $1.1 }
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
        
        if mode == .dialogue {
            let transcribed = candidates.filter { $0.transcribedAt != nil || !$0.transcripts.isEmpty }
            if !transcribed.isEmpty {
                guard !tokens.isEmpty else { return [] }
                var dialogueResults = dialogueMatches(in: transcribed, tokens: tokens, textEmbedding: textEmbedding)
                let matchedClipIDs = Set(dialogueResults.map(\.clip.id))
                for clip in candidates where !matchedClipIDs.contains(clip.id) {
                    let filename = normalized(clip.name + " " + clip.relativePath)
                    if tokens.allSatisfy({ filename.contains($0) }) {
                        dialogueResults.append(SearchResult(clip: clip, score: 0))
                    }
                }
                return Array(dialogueResults.prefix(limit))
            }
            if clips.isEmpty {
                let samples = SampleDialogue.sampleResults
                guard !tokens.isEmpty else { return Array(samples.prefix(limit)) }
                return samples.filter { item in
                    let cueNorm = normalized(item.matchedCue?.text ?? "")
                    return tokens.contains { cueNorm.contains($0) }
                }
            }
            // Footage exists but nothing is transcribed yet: fall back to approximate audio-vector search below.
        }
        
        if tokens.isEmpty {
            return candidates.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .prefix(limit).map { SearchResult(clip: $0) }
        }
        var results: [SearchResult] = []
        for clip in candidates {
            let filename = normalized(clip.name + " " + clip.relativePath)
            let filenameMatch = tokens.allSatisfy { filename.contains($0) }
            var best: SearchResult?
            if let embedding {
                for segment in clip.segments {
                    var score: Float?
                    switch mode {
                    case .video:
                        let vScore = segment.visualEmbedding.flatMap { VectorMath.cosine(embedding, $0) }
                        let aScore = segment.audioEmbedding.flatMap { VectorMath.cosine(embedding, $0) }
                        if let vScore, let aScore { score = max(vScore, aScore) }
                        else { score = vScore ?? aScore }
                    case .visual:
                        score = segment.visualEmbedding.flatMap { VectorMath.cosine(embedding, $0) }
                    case .sound, .dialogue:
                        score = segment.audioEmbedding.flatMap { VectorMath.cosine(embedding, $0) }
                    }
                    guard let score else { continue }
                    if best == nil || score > best!.score { best = SearchResult(clip: clip, segment: segment, score: score) }
                }
            }
            if let best { results.append(best) }
            else if filenameMatch { results.append(SearchResult(clip: clip, score: 0)) }
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
    static func dialogueMatches(in clips: [FootageClip], tokens: [String], textEmbedding: [Float]?) -> [SearchResult] {
        let phrase = tokens.joined(separator: " ")
        var results: [SearchResult] = []
        for clip in clips {
            let cues = clip.transcripts.sorted { $0.start < $1.start }
            for (index, cue) in cues.enumerated() {
                let text = normalized(cue.text)
                let matched = tokens.filter { text.contains($0) }.count
                let fraction = Float(matched) / Float(tokens.count)
                let lexical: Float = text.contains(phrase) ? 1.0 : matched == tokens.count ? 0.8 : fraction >= 0.5 ? 0.5 * fraction : 0
                let similarity = textEmbedding.flatMap { query in cue.embedding.flatMap { VectorMath.cosine(query, $0) } }
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
