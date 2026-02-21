# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

All commands run from the `VoiceInk/` directory (where `Makefile` lives).

```bash
make local      # Build without Apple Developer certificate → ~/Downloads/VoiceInk.app
make whisper    # Clone & build whisper.xcframework (only needed once)
make clean      # Remove ~/VoiceInk-Dependencies and build artifacts
```

**Replacing the app after build:**
```bash
pkill -x VoiceInk 2>/dev/null
rm -rf /Applications/VoiceInk.app && cp -R ~/Downloads/VoiceInk.app /Applications/VoiceInk.app
open /Applications/VoiceInk.app
```

**After every app replacement, reset TCC permissions** (ad-hoc signing invalidates previous grants):
```bash
tccutil reset Accessibility com.prakashjoshipax.VoiceInk
tccutil reset ScreenCapture com.prakashjoshipax.VoiceInk
tccutil reset Microphone com.prakashjoshipax.VoiceInk
```
Then relaunch the app and re-grant permissions via System Settings > Privacy & Security.

The whisper.xcframework is built once into `~/VoiceInk-Dependencies/whisper.cpp/build-apple/` and reused across builds. `make local` uses `LocalBuild.xcconfig` + `VoiceInk.local.entitlements` (no iCloud/keychain).

## Architecture

### Transcription Pipeline

The core flow is: **Recorder → TranscriptionSession → TranscriptionService → WhisperState post-processing**

1. **`WhisperState`** (`Whisper/WhisperState.swift`) — the central `@MainActor` ObservableObject orchestrating recording state, model loading, and the full transcription lifecycle. `transcribeAudio()` is the key method: it calls the service, applies `TranscriptionOutputFilter`, optional Hans-Hant conversion (zh-TW), text formatting, word replacements, AI enhancement, and finally pastes output.

2. **`TranscriptionServiceRegistry`** (`Services/TranscriptionServiceRegistry.swift`) — routes transcription to the correct service based on `ModelProvider`. Supports file-based and streaming sessions. Streaming sessions have a batch fallback model.

3. **Services by provider:**
   - `.local` → `LocalTranscriptionService` → `WhisperContext` (AUHAL + whisper.cpp via `LibWhisper.swift`)
   - `.parakeet` → `ParakeetTranscriptionService`
   - `.nativeApple` → `NativeAppleTranscriptionService`
   - all cloud providers → `CloudTranscriptionService` / `OpenAICompatibleTranscriptionService`
   - streaming → `StreamingTranscriptionService` with provider-specific implementations in `Services/StreamingTranscription/`

4. **`CoreAudioRecorder`** (`CoreAudioRecorder.swift`) — AUHAL-based recorder. Does NOT change the system default audio device. Outputs 16kHz mono PCM Int16. `Recorder.swift` wraps it and handles device switching.

### Language Handling

Language is stored as a string in `UserDefaults["SelectedLanguage"]` (e.g. `"en"`, `"zh"`, `"zh-TW"`, `"auto"`).

- `"zh-TW"` is a UI-only variant — `LibWhisper.swift` maps it to `"auto"` for Whisper (so code-switching works naturally), while `WhisperState.transcribeAudio()` applies `CFStringTransform("Hans-Hant")` post-transcription to convert Simplified → Traditional Chinese. English characters are unaffected by this transform.
- Cloud services map `"zh-TW"` → `"zh"` since most APIs only accept ISO 639-1.
- `WhisperPrompt` manages `initial_prompt` per language to bias Whisper's output style.

### Model System

`TranscriptionModel` protocol (`Models/TranscriptionModel.swift`) is implemented by `LocalModel`, `ParakeetModel`, `NativeAppleModel`, and cloud model types. `PredefinedModels.swift` contains `allLanguages`, `appleNativeLanguages`, and the static list of all built-in models. Custom models are managed by `CustomModelManager`.

### Power Mode

`PowerMode/` contains per-app configuration. `ActiveWindowService` detects the frontmost app/URL and `PowerModeSessionManager` applies the matching config (language, AI prompt, enhancement settings) before each transcription.

### Post-processing Chain (in order)

`TranscriptionOutputFilter` → Hans-Hant (if zh-TW) → `WhisperTextFormatter` (if enabled) → `WordReplacementService` → AI Enhancement → paste via `CursorPaster`

## Key Files to Know

| File | Purpose |
|------|---------|
| `Whisper/WhisperState.swift` | Central state machine; `transcribeAudio()` owns the full pipeline |
| `Whisper/LibWhisper.swift` | whisper.cpp Swift actor; sets language/prompt params |
| `Whisper/WhisperPrompt.swift` | `initial_prompt` strings per language |
| `Models/PredefinedModels.swift` | `allLanguages` dict + all built-in model definitions |
| `Services/TranscriptionServiceRegistry.swift` | Routes to correct service; manages streaming vs batch |
| `CoreAudioRecorder.swift` | AUHAL audio capture |
| `PowerMode/ActiveWindowService.swift` | Per-app config detection |
