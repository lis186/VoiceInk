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
        qwen3DownloadStates[modelName] = true
        downloadProgress[modelName] = 0.0

        let timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { timer in
            Task { @MainActor in
                if let currentProgress = self.downloadProgress[modelName], currentProgress < 0.9 {
                    self.downloadProgress[modelName] = currentProgress + 0.005
                }
            }
        }

        do {
            if #available(macOS 15, iOS 18, *) {
                _ = try await Qwen3AsrModels.downloadAndLoad(variant: .int8)
            }
            UserDefaults.standard.set(true, forKey: qwen3DefaultsKey(for: modelName))
            downloadProgress[modelName] = 1.0
        } catch {
            UserDefaults.standard.set(false, forKey: qwen3DefaultsKey(for: modelName))
        }

        timer.invalidate()
        qwen3DownloadStates[modelName] = false
        downloadProgress[modelName] = nil

        refreshAllAvailableModels()
    }

    // MARK: - Qwen3 MLX（qwen3-asr-swift 首次 transcribe 時自動下載）

    func isQwen3MLXModelDownloaded(_ model: Qwen3Model) -> Bool {
        // MLX 路徑在 fromPretrained() 時自動下載並快取，無法預先查詢
        return false
    }
}
