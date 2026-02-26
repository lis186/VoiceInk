import Foundation
import SwiftData

/// A utility class that manages automatic cleanup of audio files while preserving transcript data
class AudioCleanupManager {
    static let shared = AudioCleanupManager()

    private var cleanupTimer: Timer?
    
    // Default cleanup settings
    private let defaultRetentionDays = 7
    private let cleanupCheckInterval: TimeInterval = 86400 // Check once per day (in seconds)

    static let keyMaxAudioCount = "MaxAudioFileCount" // 0 = unlimited
    
    private init() {}
    
    /// Start the automatic cleanup process
    func startAutomaticCleanup(modelContext: ModelContext) {
        // Cancel any existing timer
        cleanupTimer?.invalidate()

        // Perform initial cleanup
        Task {
            await performCleanup(modelContext: modelContext)
        }

        // Schedule regular cleanup
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupCheckInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.performCleanup(modelContext: modelContext)
            }
        }
    }
    
    /// Stop the automatic cleanup process
    func stopAutomaticCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }
    
    /// Get information about the files that would be cleaned up
    func getCleanupInfo(modelContext: ModelContext) async -> (fileCount: Int, totalSize: Int64, transcriptions: [Transcription]) {
        // Get retention period from UserDefaults
        let effectiveRetentionDays = UserDefaults.standard.integer(forKey: "AudioRetentionPeriod")

        // Calculate the cutoff date
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -effectiveRetentionDays, to: Date()) else {
            return (0, 0, [])
        }

        do {
            // Execute SwiftData operations on the main thread
            return try await MainActor.run {
                // Create a predicate to find transcriptions with audio files older than the cutoff date
                let descriptor = FetchDescriptor<Transcription>(
                    predicate: #Predicate<Transcription> { transcription in
                        transcription.timestamp < cutoffDate &&
                        transcription.audioFileURL != nil
                    }
                )

                let transcriptions = try modelContext.fetch(descriptor)

                // Calculate stats (can be done on any thread)
                var fileCount = 0
                var totalSize: Int64 = 0
                var eligibleTranscriptions: [Transcription] = []

                for transcription in transcriptions {
                    if let urlString = transcription.audioFileURL,
                       let url = URL(string: urlString),
                       FileManager.default.fileExists(atPath: url.path) {
                        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                           let fileSize = attributes[.size] as? Int64 {
                            totalSize += fileSize
                            fileCount += 1
                            eligibleTranscriptions.append(transcription)
                        }
                    }
                }

                return (fileCount, totalSize, eligibleTranscriptions)
            }
        } catch {
            return (0, 0, [])
        }
    }
    
    /// Perform all cleanup operations (time-based and count-based).
    private func performCleanup(modelContext: ModelContext) async {
        await cleanupByCount(modelContext: modelContext)
        // Get retention period from UserDefaults
        let effectiveRetentionDays = UserDefaults.standard.integer(forKey: "AudioRetentionPeriod")

        // Check if automatic cleanup is enabled
        let isCleanupEnabled = UserDefaults.standard.bool(forKey: "IsAudioCleanupEnabled")
        guard isCleanupEnabled else { return }

        // Calculate the cutoff date
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -effectiveRetentionDays, to: Date()) else {
            return
        }

        do {
            // Execute SwiftData operations on the main thread
            try await MainActor.run {
                // Create a predicate to find transcriptions with audio files older than the cutoff date
                let descriptor = FetchDescriptor<Transcription>(
                    predicate: #Predicate<Transcription> { transcription in
                        transcription.timestamp < cutoffDate &&
                        transcription.audioFileURL != nil
                    }
                )

                let transcriptions = try modelContext.fetch(descriptor)
                var deletedCount = 0

                for transcription in transcriptions {
                    if let urlString = transcription.audioFileURL,
                       let url = URL(string: urlString),
                       FileManager.default.fileExists(atPath: url.path) {
                        do {
                            try FileManager.default.removeItem(at: url)
                            transcription.audioFileURL = nil
                            deletedCount += 1
                        } catch {
                            // Skip this file - don't update audioFileURL if deletion failed
                        }
                    }
                }

                if deletedCount > 0 {
                    try modelContext.save()
                }
            }
        } catch {
            // Silently fail - cleanup is non-critical
        }
    }
    
    /// Run cleanup manually - can be called from settings
    func runManualCleanup(modelContext: ModelContext) async {
        await performCleanup(modelContext: modelContext)
    }
    
    /// Run cleanup on the specified transcriptions
    func runCleanupForTranscriptions(modelContext: ModelContext, transcriptions: [Transcription]) async -> (deletedCount: Int, errorCount: Int) {
        do {
            // Execute SwiftData operations on the main thread
            return try await MainActor.run {
                var deletedCount = 0
                var errorCount = 0

                for transcription in transcriptions {
                    if let urlString = transcription.audioFileURL,
                       let url = URL(string: urlString),
                       FileManager.default.fileExists(atPath: url.path) {
                        do {
                            try FileManager.default.removeItem(at: url)
                            transcription.audioFileURL = nil
                            deletedCount += 1
                        } catch {
                            errorCount += 1
                        }
                    }
                }

                if deletedCount > 0 || errorCount > 0 {
                    try? modelContext.save()
                }

                return (deletedCount, errorCount)
            }
        } catch {
            return (0, 0)
        }
    }
    
    /// Deletes audio files for transcriptions beyond the newest `maxCount`.
    /// Keeps the newest N records intact; removes audio from older ones.
    func cleanupByCount(modelContext: ModelContext) async {
        let maxCount = UserDefaults.standard.integer(forKey: Self.keyMaxAudioCount)
        guard maxCount > 0 else { return }

        do {
            try await MainActor.run {
                var descriptor = FetchDescriptor<Transcription>(
                    predicate: #Predicate<Transcription> { $0.audioFileURL != nil },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                descriptor.propertiesToFetch = [\.audioFileURL, \.timestamp]
                let all = try modelContext.fetch(descriptor)

                let toDelete = all.dropFirst(maxCount)
                var count = 0
                for transcription in toDelete {
                    if let urlString = transcription.audioFileURL,
                       let url = URL(string: urlString),
                       FileManager.default.fileExists(atPath: url.path) {
                        try? FileManager.default.removeItem(at: url)
                        transcription.audioFileURL = nil
                        count += 1
                    }
                }
                if count > 0 {
                    try modelContext.save()
                }
            }
        } catch {
            // Non-critical; silently ignore
        }
    }

    /// Format file size in human-readable form
    func formatFileSize(_ size: Int64) -> String {
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.allowedUnits = [.useKB, .useMB, .useGB]
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(fromByteCount: size)
    }
} 
