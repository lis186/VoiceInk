import Foundation
import Qwen3ASR
import FluidAudio
import os.log

class Qwen3MLXTranscriptionService: TranscriptionService {
    private var asrModel: Qwen3ASRModel?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink.qwen3", category: "MLX")

    private func ensureModelLoaded() async throws {
        if asrModel != nil { return }
        // 首次使用自動從 HuggingFace 下載 ~400MB 並快取
        asrModel = try await Qwen3ASRModel.fromPretrained()
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        try await ensureModelLoaded()
        guard let asrModel = asrModel else {
            throw ASRError.notInitialized
        }
        let audioSamples = try readAudioSamples(from: audioURL)
        // transcribe() 是同步方法，包進 Task.detached 避免阻塞 caller thread
        return await Task.detached(priority: .userInitiated) {
            asrModel.transcribe(audio: audioSamples, sampleRate: 16000)
        }.value
    }

    private func readAudioSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count > 44, (data.count - 44) % 2 == 0 else { throw ASRError.invalidAudioData }
        return stride(from: 44, to: data.count, by: 2).map {
            data[$0..<$0 + 2].withUnsafeBytes {
                let short = Int16(littleEndian: $0.load(as: Int16.self))
                return max(-1.0, min(Float(short) / 32767.0, 1.0))
            }
        }
    }
}
