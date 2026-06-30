import Foundation
import AVFoundation
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

    // VoiceInk 的 WAV 用 Core Audio kAudioFileWAVEType 寫入，
    // 會加 FLLR padding chunk 讓音訊資料對齊 4096 bytes（offset 並非固定 44）。
    // 必須用 AVAudioFile 解析，不能硬編碼 skip 44 bytes。
    private func readAudioSamples(from url: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ASRError.invalidAudioData
        }
        try audioFile.read(into: buffer)
        guard let floatData = buffer.floatChannelData else {
            throw ASRError.invalidAudioData
        }
        return Array(UnsafeBufferPointer(start: floatData[0], count: Int(buffer.frameLength)))
    }
}
