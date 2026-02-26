//
//  VoiceInkTests.swift
//  VoiceInkTests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import Testing
import Foundation
import SwiftData
@testable import VoiceInk

struct VoiceInkTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

// MARK: - WhisperState Memory Leak Tests

struct WhisperStateMemoryTests {

    @MainActor
    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return container.mainContext
    }

    /// 修復前：NotificationCenter 持有 WhisperState 強引用 → weak 不會變 nil → 測試失敗
    /// 修復後：deinit 呼叫 removeObserver → weak 變 nil → 測試通過
    @Test @MainActor
    func whisperState_deallocates_when_reference_released() throws {
        let context = try makeInMemoryContext()
        weak var weakState: WhisperState?

        autoreleasepool {
            let state = WhisperState(modelContext: context)
            weakState = state
            // state 在此 scope 結束後應被釋放
        }

        // 修復方法：在 deinit 加入 NotificationCenter.default.removeObserver(self)
        #expect(weakState == nil)
    }
}
