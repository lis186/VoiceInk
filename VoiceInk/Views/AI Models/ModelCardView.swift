import AppKit
import SwiftUI

struct ModelCardView: View {
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    let model: any TranscriptionModel
    let fluidAudioModelManager: FluidAudioModelManager
    let isDownloaded: Bool
    let downloadProgress: [String: Double]
    let modelURL: URL?
    let isWarming: Bool

    // Actions
    var deleteAction: () -> Void
    var downloadAction: () -> Void
    var editAction: ((CustomCloudModel) -> Void)?
    var body: some View {
        Group {
            switch model.provider {
            case .whisper:
                if let whisperModel = model as? WhisperModel {
                    WhisperModelCardView(
                        model: whisperModel,
                        isDownloaded: isDownloaded,
                        downloadProgress: downloadProgress,
                        modelURL: modelURL,
                        isWarming: isWarming,
                        deleteAction: deleteAction,
                        downloadAction: downloadAction
                    )
                } else if let importedModel = model as? ImportedWhisperModel {
                    ImportedWhisperModelCardView(
                        model: importedModel,
                        isDownloaded: isDownloaded,
                        modelURL: modelURL,
                        deleteAction: deleteAction
                    )
                }
            case .fluidAudio:
                if let fluidAudioModel = model as? FluidAudioModel {
                    FluidAudioModelCardView(
                        model: fluidAudioModel,
                        fluidAudioModelManager: fluidAudioModelManager
                    )
                }
            case .nativeApple:
                if let nativeAppleModel = model as? NativeAppleModel {
                    NativeAppleModelCardView(
                        model: nativeAppleModel
                    )
                }
            case .custom:
                if let customModel = model as? CustomCloudModel {
                    CustomModelCardView(
                        model: customModel,
                        deleteAction: deleteAction,
                        editAction: editAction ?? { _ in }
                    )
                }
            case .qwen3FluidAudio, .qwen3MLX:
                if let qwen3Model = model as? Qwen3Model {
                    Qwen3ModelCardRowView(
                        model: qwen3Model,
                        transcriptionModelManager: transcriptionModelManager
                    )
                }
            default:
                if let cloudModel = model as? CloudModel {
                    CloudModelCardView(
                        model: cloudModel
                    )
                }
            }
        }
    }
}
