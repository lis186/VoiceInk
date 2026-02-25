import Foundation
import FluidAudio

extension WhisperState {
    // MARK: - Qwen3 FluidAudio

    private func qwen3DefaultsKey(for modelName: String) -> String {
        "Qwen3ModelDownloaded_\(modelName)"
    }

    func isQwen3ModelDownloaded(named modelName: String) -> Bool {
        UserDefaults.standard.bool(forKey: qwen3DefaultsKey(for: modelName))
    }

    func isQwen3ModelDownloaded(_ model: Qwen3Model) -> Bool {
        isQwen3ModelDownloaded(named: model.name)
    }

    @MainActor
    func downloadQwen3FluidAudioModel(_ model: Qwen3Model) async {
        guard !isQwen3ModelDownloaded(model) else { return }

        let modelName = model.name
        downloadProgress[modelName] = 0.0

        do {
            if #available(macOS 15, iOS 18, *) {
                _ = try await Qwen3AsrModels.downloadAndLoad(variant: .int8)
            }
            UserDefaults.standard.set(true, forKey: qwen3DefaultsKey(for: modelName))
            downloadProgress[modelName] = 1.0
        } catch {
            UserDefaults.standard.set(false, forKey: qwen3DefaultsKey(for: modelName))
        }
    }

    // MARK: - Qwen3 MLX（qwen3-asr-swift 首次 transcribe 時自動下載）

    func isQwen3MLXModelDownloaded(_ model: Qwen3Model) -> Bool {
        // MLX 路徑在 fromPretrained() 時自動下載並快取，無法預先查詢
        return false
    }
}
