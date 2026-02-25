import Foundation

extension WhisperState {
    // MARK: - Qwen3 MLX（qwen3-asr-swift 首次 transcribe 時自動下載）

    func isQwen3MLXModelDownloaded(_ model: Qwen3Model) -> Bool {
        // MLX 路徑在 fromPretrained() 時自動下載並快取，無法預先查詢
        return false
    }
}
