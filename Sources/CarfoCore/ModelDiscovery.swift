import Foundation

public struct LocalModelInstallation: Equatable, Sendable {
    public var modelDirectory: URL?
    public var pythonExecutable: URL?
    public var whisperDirectory: URL?
    public var isAvailable: Bool { modelDirectory != nil && pythonExecutable != nil }
    public var canTranscribe: Bool { isAvailable && whisperDirectory != nil }
    public init(modelDirectory: URL? = nil, pythonExecutable: URL? = nil, whisperDirectory: URL? = nil) {
        self.modelDirectory = modelDirectory; self.pythonExecutable = pythonExecutable; self.whisperDirectory = whisperDirectory
    }
    public static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser, modelOverride: String? = nil, pythonOverride: String? = nil) -> LocalModelInstallation {
        let fm = FileManager.default
        var modelPaths: [URL] = []
        if let modelOverride, !modelOverride.isEmpty { modelPaths.append(URL(fileURLWithPath: modelOverride)) }
        if let bundleResources = Bundle.main.resourceURL {
            modelPaths.append(bundleResources.appendingPathComponent("Model"))
            modelPaths.append(bundleResources.appendingPathComponent("Models"))
            modelPaths.append(bundleResources.appendingPathComponent("EmbeddingGemma"))
        }
        modelPaths.append(home.appendingPathComponent("Library/Application Support/Carfo/Model"))
        for repository in ["models--google--embeddinggemma-2", "models--unsloth--embeddinggemma-2"] {
            let root = home.appendingPathComponent(".cache/huggingface/hub/\(repository)/snapshots")
            let snapshots = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)) ?? []
            modelPaths += snapshots.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        let model = modelPaths.first { path in
            guard let data = try? Data(contentsOf: path.appendingPathComponent("config.json")),
                  let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  config["model_type"] as? String == "embedding_gemma2" else { return false }
            return fm.fileExists(atPath: path.appendingPathComponent("model.safetensors").path) || fm.fileExists(atPath: path.appendingPathComponent("model.safetensors.index.json").path)
        }
        var pythonPaths: [String] = []
        if let pythonOverride, !pythonOverride.isEmpty { pythonPaths.append(pythonOverride) }
        if let bundleResources = Bundle.main.resourceURL {
            pythonPaths.append(bundleResources.appendingPathComponent("Python/bin/python").path)
            pythonPaths.append(bundleResources.appendingPathComponent("Runtime/bin/python").path)
            pythonPaths.append(Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/python").path)
        }
        pythonPaths += [home.appendingPathComponent(".unsloth/studio/unsloth_studio/bin/python").path,
                        home.appendingPathComponent(".unsloth/studio/.venv/bin/python").path]
        let python = pythonPaths.first(where: fm.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
        return LocalModelInstallation(modelDirectory: model, pythonExecutable: python, whisperDirectory: discoverWhisper(home: home))
    }
    static func discoverWhisper(home: URL) -> URL? {
        let fm = FileManager.default
        var paths: [URL] = []
        if let bundleResources = Bundle.main.resourceURL { paths.append(bundleResources.appendingPathComponent("Whisper")) }
        paths.append(home.appendingPathComponent("Library/Application Support/Carfo/Whisper"))
        for repository in ["models--mlx-community--whisper-small-mlx", "models--mlx-community--whisper-large-v3-turbo", "models--mlx-community--whisper-base-mlx"] {
            let root = home.appendingPathComponent(".cache/huggingface/hub/\(repository)/snapshots")
            let snapshots = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            paths += snapshots.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        return paths.first { path in
            fm.fileExists(atPath: path.appendingPathComponent("config.json").path)
                && (fm.fileExists(atPath: path.appendingPathComponent("weights.npz").path) || fm.fileExists(atPath: path.appendingPathComponent("weights.safetensors").path))
        }
    }
}
