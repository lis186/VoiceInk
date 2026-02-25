import Foundation
import FluidAudio
import os.log

@available(macOS 15, iOS 18, *)
class Qwen3FluidAudioTranscriptionService: TranscriptionService {
    private var manager: Qwen3AsrManager?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink.qwen3", category: "FluidAudio")

    private func ensureModelsLoaded() async throws {
        if manager != nil { return }
        // int8 量化版：~900MB，品質與全精度相當
        let cacheDir = Qwen3AsrModels.defaultCacheDirectory(variant: .int8)
        let mgr = Qwen3AsrManager()
        try await mgr.loadModels(from: cacheDir)
        self.manager = mgr
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        try await ensureModelsLoaded()
        guard let manager = manager else {
            throw ASRError.notInitialized
        }
        let audioSamples = try readAudioSamples(from: audioURL)
        // language: nil → 自動偵測，支援中英夾雜
        return try await manager.transcribe(audioSamples: audioSamples, language: nil as String?)
    }

    private func readAudioSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count > 44 else { throw ASRError.invalidAudioData }
        return stride(from: 44, to: data.count, by: 2).map {
            data[$0..<$0 + 2].withUnsafeBytes {
                let short = Int16(littleEndian: $0.load(as: Int16.self))
                return max(-1.0, min(Float(short) / 32767.0, 1.0))
            }
        }
    }
}
