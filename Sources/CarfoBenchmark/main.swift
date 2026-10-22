import Foundation
import Darwin
import CarfoCore

if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--media" {
    try await benchmarkMedia(directory: URL(fileURLWithPath: CommandLine.arguments[2]), output: URL(fileURLWithPath: CommandLine.arguments[3]))
    exit(0)
}
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--audio" {
    try await benchmarkAudio(url: URL(fileURLWithPath: CommandLine.arguments[2]), output: URL(fileURLWithPath: CommandLine.arguments[3]))
    exit(0)
}

func measured<T>(_ body: () throws -> T) rethrows -> (T, Double) {
    let start = ContinuousClock.now
    let result = try body()
    let duration = start.duration(to: .now).components
    return (result, Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
}

let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
let root = FileManager.default.temporaryDirectory.appendingPathComponent("CarfoBenchmark-\(UUID())")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
var rows: [[String: Any]] = []
for count in [100, 500, 1000] {
    let store = try LibraryStore(directory: root.appendingPathComponent("\(count)"))
    let folder = FootageFolder(path: "/synthetic")
    var manifest = LibraryManifest()
    manifest.folders = [folder]
    let vector: [Float] = [1] + Array(repeating: 0, count: 767)
    manifest.clips = (0..<count).map { index in
        FootageClip(folderID: folder.id, path: "/synthetic/clip \(index).mov", duration: 120, hasAudio: true,
            segments: (0..<10).map { offset in VideoSegment(start: Double(offset * 12), end: Double((offset + 1) * 12), visualEmbedding: vector, audioEmbedding: vector) })
    }
    let db = try store.database()
    let (_, initialWrite) = try measured { try db.saveManifest(manifest) }
    let (_, metadataRead) = try measured { try db.loadManifest(metadataOnly: true) }
    let (_, fullRead) = try measured { try db.loadManifest() }
    var textTimes: [Double] = [], vectorTimes: [Double] = []
    for _ in 0..<7 {
        textTimes.append(measured { SearchEngine.search(clips: manifest.clips, query: "clip 42") }.1)
        vectorTimes.append(measured { SearchEngine.search(clips: manifest.clips, query: "unlabeled", embedding: vector) }.1)
    }
    var segment = manifest.clips[0].segments[0]
    segment.audioEmbedding = [0, 1] + Array(repeating: 0, count: 766)
    let (_, incremental) = try measured { try db.saveSegment(clipID: manifest.clips[0].id, segment: segment) }
    var stats = LibraryStats(manifest.clips)
    var changed = manifest.clips[0]
    changed.segments[0] = segment
    let (_, statsDelta) = measured { stats.replace(manifest.clips[0], with: changed) }
    rows.append(["clips": count, "segments": count * 10, "initialWriteMS": initialWrite,
                 "metadataReadMS": metadataRead, "fullReadMS": fullRead, "textMedianMS": textTimes.sorted()[3],
                 "vectorMedianMS": vectorTimes.sorted()[3], "singleSegmentWriteMS": incremental, "statsDeltaMS": statsDelta])
}
var usage = rusage()
getrusage(RUSAGE_SELF, &usage)
var machine = utsname(); uname(&machine)
let hardware = withUnsafePointer(to: &machine.machine) { pointer in
    pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: machine.machine)) { String(cString: $0) }
}
var report: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()), "build": "2.0-candidate",
    "hardware": hardware, "processors": ProcessInfo.processInfo.activeProcessorCount,
    "memoryBytes": ProcessInfo.processInfo.physicalMemory, "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "cache": "fresh databases; seven warm in-memory searches; no OS cache flush", "dimensions": 768,
    "scope": "synthetic index only; excludes inference, UI rendering and media decoding", "peakRSSBytes": usage.ru_maxrss, "measurements": rows]
if CommandLine.arguments.count > 2 {
    let resources = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("Contents/Resources")
    let engine = LocalEngine(installation: LocalModelInstallation(modelDirectory: resources.appendingPathComponent("Model"),
        pythonExecutable: resources.appendingPathComponent("Python/bin/python3"), whisperDirectory: resources.appendingPathComponent("Whisper")),
        script: resources.appendingPathComponent("Engine/worker.py"), logDirectory: root, idleSeconds: 0.1)
    let coldStart = ContinuousClock.now
    _ = try await engine.verify()
    let ready = coldStart.duration(to: .now)
    let warmStart = ContinuousClock.now
    _ = try await engine.embed(query: "pantai", mode: .video)
    let warm = warmStart.duration(to: .now)
    try await Task.sleep(for: .milliseconds(300))
    let idleStart = ContinuousClock.now
    _ = try await engine.embed(query: "pantai", mode: .video)
    let afterIdle = idleStart.duration(to: .now)
    let task = Task { try await engine.embed(documents: Array(repeating: "Transkrip untuk mengukur pembatalan", count: 128)) }
    try await Task.sleep(for: .milliseconds(30))
    let stopStart = ContinuousClock.now
    task.cancel(); await engine.stop()
    let stop = stopStart.duration(to: .now)
    _ = try? await task.value
    func ms(_ duration: Duration) -> Double { Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15 }
    report["inference"] = ["modelReadyMS": ms(ready), "warmQueryMS": ms(warm), "afterForcedIdleQueryMS": ms(afterIdle),
                            "stopMS": ms(stop), "forcedIdleSeconds": 0.1, "productionIdleSeconds": 300]
}
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
if let output { try data.write(to: output, options: .atomic) }
print(String(decoding: data, as: UTF8.self))
