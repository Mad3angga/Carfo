import Foundation
import Darwin
import CarfoCore

private func milliseconds(since start: ContinuousClock.Instant) -> Double {
    let elapsed = start.duration(to: .now).components
    return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
}
private func writeReport(_ report: [String: Any], to output: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: output, options: .atomic)
    print(String(decoding: data, as: UTF8.self))
}
func benchmarkMedia(directory: URL, output: URL) async throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("CarfoMediaBench-\(UUID())")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    var rows: [[String: Any]] = []
    for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) where ["mp4", "mov"].contains(url.pathExtension) {
        print("Benchmarking \(url.lastPathComponent)")
        do {
        let metadata = try await MediaProcessor.metadata(url: url)
        let segments = SegmentPlanner.segments(duration: metadata.duration, length: 1)
        var separate: [Double] = [], batched: [Double] = []
        for _ in 0..<3 {
            let start = ContinuousClock.now
            for segment in segments {
                for (index, time) in SegmentPlanner.sampleTimes(in: segment).enumerated() {
                    try await MediaProcessor.frame(url: url, at: time, destination: temporary.appendingPathComponent("separate-\(index).jpg"))
                }
            }
            separate.append(milliseconds(since: start))
            let batchStart = ContinuousClock.now
            let decoder = FrameDecoder(url: url)
            for segment in segments { _ = try await MediaProcessor.frames(url: url, segment: segment, directory: temporary, decoder: decoder) }
            batched.append(milliseconds(since: batchStart))
        }
        rows.append(["file": url.lastPathComponent, "width": metadata.width, "height": metadata.height,
                     "frames": segments.count * 3, "perFrameGeneratorMedianMS": separate.sorted()[1], "reusedBatchMedianMS": batched.sorted()[1]])
        } catch {
            rows.append(["file": url.lastPathComponent, "error": error.localizedDescription])
        }
    }
    var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
    try writeReport(["date": ISO8601DateFormatter().string(from: Date()), "scope": "three warm runs per codec; async per-frame generators versus reused async batches; includes JPEG writing",
                     "timestampToleranceMS": 100, "peakRSSBytes": usage.ru_maxrss, "measurements": rows], to: output)
}
func benchmarkAudio(url: URL, output: URL) async throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("CarfoAudioBench-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: temporary) }
    let metadata = try await LibraryScanner.audioMetadata(url: url)
    let start = ContinuousClock.now
    try await MediaProcessor.audio(url: url, segment: VideoSegment(start: 0, end: metadata.duration), destination: temporary)
    let duration = milliseconds(since: start)
    var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
    let attrs = try FileManager.default.attributesOfItem(atPath: temporary.path)
    try writeReport(["date": ISO8601DateFormatter().string(from: Date()), "scope": "streaming PCM16 extraction in a fresh process; no model or transcription",
                     "audioSeconds": metadata.duration, "outputBytes": attrs[.size] as? NSNumber ?? 0,
                     "extractionMS": duration, "peakRSSBytes": usage.ru_maxrss], to: output)
}
