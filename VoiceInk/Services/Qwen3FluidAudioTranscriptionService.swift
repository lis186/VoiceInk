import Foundation
import AVFoundation
import Qwen3ASR
import FluidAudio
import os.log

// ponytail: FluidAudio removed Qwen3 CoreML backend (#676), fallback to MLX via Qwen3ASR.
@available(macOS 15, iOS 18, *)
class Qwen3FluidAudioTranscriptionService: TranscriptionService {
    private var asrModel: Qwen3ASRModel?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink.qwen3", category: "FluidAudio")

    private func ensureModelLoaded() async throws {
        if asrModel != nil { return }
        asrModel = try await Qwen3ASRModel.fromPretrained()
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws -> String {
        try await ensureModelLoaded()
        guard let asrModel = asrModel else {
            throw ASRError.notInitialized
        }
        let audioSamples = try readAudioSamples(from: audioURL)
        return await Task.detached(priority: .userInitiated) {
            asrModel.transcribe(
                audio: audioSamples,
                sampleRate: 16000,
                language: nil,
                context: nil
            )
        }.value
    }

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
