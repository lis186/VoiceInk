import Foundation
import SwiftData
import os
import AppKit

@MainActor
final class ModelPrewarmService: ObservableObject {
    private let whisperState: WhisperState
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ModelPrewarm")
    // NOTE: We intentionally do NOT create a separate TranscriptionServiceRegistry here.
    // Using whisperState.serviceRegistry ensures the model is loaded into the shared
    // WhisperContext, preventing the model from being loaded twice into memory.
    private let prewarmAudioURL = Bundle.main.url(forResource: "esc", withExtension: "wav")
    private let prewarmEnabledKey = "PrewarmModelOnWake"

    init(whisperState: WhisperState, modelContext: ModelContext) {
        self.whisperState = whisperState
        self.modelContext = modelContext
        setupNotifications()
        schedulePrewarmOnAppLaunch()
    }

    // MARK: - Notification Setup

    private func setupNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        // Trigger on wake from sleep
        center.addObserver(
            self,
            selector: #selector(schedulePrewarm),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        logger.notice("🌅 ModelPrewarmService initialized - listening for wake and app launch")
    }

    // MARK: - Trigger Handlers

    /// Trigger on app launch (cold start)
    private func schedulePrewarmOnAppLaunch() {
        logger.notice("🌅 App launched, scheduling prewarm")
        Task {
            try? await Task.sleep(for: .seconds(3))
            await performPrewarm()
        }
    }

    /// Trigger on wake from sleep or screen unlock
    @objc private func schedulePrewarm() {
        logger.notice("🌅 Mac activity detected (wake/unlock), scheduling prewarm")
        Task {
            try? await Task.sleep(for: .seconds(3))
            await performPrewarm()
        }
    }

    // MARK: - Core Prewarming Logic

    private func performPrewarm() async {
        guard shouldPrewarm() else { return }

        guard let audioURL = prewarmAudioURL else {
            logger.error("❌ Prewarm audio file (esc.wav) not found")
            return
        }

        guard let currentModel = whisperState.currentTranscriptionModel else {
            logger.notice("🌅 No model selected, skipping prewarm")
            return
        }

        logger.notice("🌅 Prewarming \(currentModel.displayName)")
        logger.memoryUsage("prewarm-start")
        let startTime = Date()

        do {
            // For local Whisper models: load via the main WhisperState so only one
            // WhisperContext exists in memory. Without this, prewarm and the user's
            // first recording would each create their own context (2× model RAM).
            if currentModel.provider == .local {
                if !whisperState.isModelLoaded,
                   let localModel = whisperState.availableModels.first(where: { $0.name == currentModel.name }) {
                    try await whisperState.loadModel(localModel)
                }
                // Run a short inference pass through the shared context for Metal warmup.
                let _ = try await whisperState.serviceRegistry.transcribe(audioURL: audioURL, model: currentModel)
            } else if currentModel.provider == .parakeet {
                // Parakeet: use the shared parakeet service to avoid a second model load.
                if let parakeetModel = currentModel as? ParakeetModel {
                    try? await whisperState.serviceRegistry.parakeetTranscriptionService.loadModel(for: parakeetModel)
                }
            }
            // Cloud models don't need prewarming.

            let duration = Date().timeIntervalSince(startTime)
            logger.notice("🌅 Prewarm completed in \(String(format: "%.2f", duration))s")
            logger.memoryUsage("prewarm-end")

        } catch {
            logger.error("❌ Prewarm failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Validation

    private func shouldPrewarm() -> Bool {
        // Check if user has enabled prewarming
        let isEnabled = UserDefaults.standard.bool(forKey: prewarmEnabledKey)
        guard isEnabled else {
            logger.notice("🌅 Prewarm disabled by user")
            return false
        }

        // Only prewarm local models (Parakeet and Whisper need ANE compilation)
        guard let model = whisperState.currentTranscriptionModel else {
            return false
        }

        switch model.provider {
        case .local, .parakeet:
            return true
        default:
            logger.notice("🌅 Skipping prewarm - cloud models don't need it")
            return false
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.notice("🌅 ModelPrewarmService deinitialized")
    }
}
