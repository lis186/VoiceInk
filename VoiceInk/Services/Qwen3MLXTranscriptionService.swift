import Foundation
import AVFoundation
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
