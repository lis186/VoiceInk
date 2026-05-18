# Fork Sync Roadmap — sync/upstream-2026q2

Generated 2026-05-18. Synthesizes 4 expert simulations (Scott Chacon, Junio C Hamano, Martin Fowler, Greg Kroah-Hartman) into a concrete plan for integrating `Beingpax/VoiceInk` upstream into `lis186/VoiceInk` fork.

## TL;DR

- **`main`** = old fork HEAD (29d247a) — preserved, untouched
- **`sync/upstream-2026q2`** = upstream HEAD + 1 cherry-picked commit (`feat: add make share target`)
- **`backup/pre-sync-20260518-225119`** = pre-sync safety state with original dirty files

Upstream did a god-object refactor (PR #563: decompose `WhisperState`, rename `VoiceInk/Whisper/` → `VoiceInk/Transcription/Whisper/`). The fork's 32 commits land in three categories: 5 clean, 17 modify/delete, 10 content-conflict.

## Strategy (Fowler + Greg KH consensus)

Stop trying to merge 200 commits in one shot. Reset to upstream tip, then port fork features forward in priority order — simplest first, architecturally entangled last. Open PRs to Beingpax for the orthogonal wins (memory leaks, build tooling, zh-TW) so they stop being your maintenance burden.

## Per-Commit Triage

| Verdict | Meaning | Count |
|---------|---------|-------|
| CLEAN | Cherry-picks without conflict | 5 |
| MODIFY-DELETE | Targets file upstream deleted; needs re-implementation | 17 |
| CONTENT-CONFLICT | Both sides modified; needs semantic merge | 10 |

Full triage table: `/tmp/fork-triage.tsv` (regenerable from fork-commits.txt).

## Priority Order

### Priority 1 — Open PRs to upstream (Greg KH's advice)
These are obvious upstream-friendly fixes; getting them merged removes them from your fork forever.

- **Build tooling** — `64d64eb feat: add make share target` (already applied to sync branch; ready to open PR)
- **Memory leak fixes (CLEAN parts)** — `1912ea1 Merge fix/memory-leaks` itself, plus the orthogonal pieces. The deleted-target pieces need to land as new patches against the decomposed classes.
- **Audio fix** — `cfa2fc0 fix: replace AudioObjectPropertyListener with ListenerBlock API` (content conflict — likely small manual merge in `AudioDeviceManager.swift`)
- **zh-TW localization** — 4 commits; need to land against new `VoiceInk/Transcription/Whisper/WhisperPrompt.swift` path. Open as a single feature PR upstream.

### Priority 2 — Manual conflict resolution (your fork only)
These need domain judgment but can stay on the fork.

- **`3e15e97 Fix input source history corruption during paste`** — Both sides rewrote paste logic in `CursorPaster.swift`. Compare:
  - Fork's approach: input-source-switching for QWERTY-on-command keyboards
  - Upstream's approach: AppleScript fallback for non-QWERTY (commit `dededd4 Fix AppleScript paste for QWERTY-on-command keyboard layouts`)
  - These solve overlapping problems differently. Pick one or merge both ideas.
- **`720f0a8 OSLog privacy annotation`** — Depends on `6f5eda6` adding `Logger.memoryUsage` extension; cherry-pick must follow that.

### Priority 3 — Re-implement Qwen3 on new architecture (the hard part)
Upstream's `decompose WhisperState god object` refactor (PR #563, commit `4c98b44`) split `WhisperState.swift` into multiple single-responsibility classes. Your 12 Qwen3 commits extend the deleted god-object.

**Required reading before re-implementation**:
1. PR #563 — `git log --oneline 4c98b44^..4c98b44 -- VoiceInk/`
2. New transcription provider architecture:
   - `VoiceInk/Transcription/Engine/TranscriptionServiceRegistry.swift`
   - `VoiceInk/Transcription/Whisper/WhisperModelManager.swift`
   - `VoiceInk/Transcription/Whisper/LibWhisper.swift`
3. Upstream's FluidAudio integration: `5722a32`, `04cef98` (FluidAudio rename from Parakeet)

**Per Martin Fowler**: Define one `TranscriptionProvider` abstraction inside the refactored tree. Port Qwen3 as one implementation (`Qwen3FluidAudioProvider`, `Qwen3MLXProvider`); the existing FluidAudio integration is your prior art.

**Re-implementation order**:
1. `5bf5c0e` — add `Qwen3Model` enum + `qwen3FluidAudio/qwen3MLX` ModelProvider cases → adapt to upstream's `TranscriptionModel`
2. `16434a7` — register Qwen3-ASR models in PredefinedModels → upstream renamed/moved this
3. `5198ada` + `bae0189` — Qwen3FluidAudio/MLX services (these triaged CLEAN — apply first, then wire into new registry)
4. `2e2e2fa` — route Qwen3 in TranscriptionServiceRegistry → wire against new registry shape
5. `ce34499` + `4ac52d9` — Qwen3 download helpers → port to new model-manager separation
6. UI commits (`0217fb1`, `1c2fa71`) — adapt to upstream's ModelCardView changes

### Priority 4 — Skip
- `f4163737 Merge remote-tracking branch 'upstream/main'` — old merge; superseded by this sync
- `1912ea1 Merge fix/memory-leaks` — merge commit; cherry-pick children instead
- `bb8dc0e fix: exclude Index.noindex from DerivedData` — upstream's `LOCAL_DERIVED_DATA` path approach (`1e1896d`) supersedes the find-based exclusion

## Concrete Next Actions

1. **Today (~30 min)**: Push `sync/upstream-2026q2` to GitHub as a feature branch. Verify Xcode opens it and builds (will fail until Qwen3 ports land — that's expected).
2. **This week (~2-4 hours)**: Read upstream's PR #563 + FluidAudio integration. Sketch the new `TranscriptionProvider` shape that fits both Whisper, FluidAudio, and Qwen3.
3. **Next week**: Open upstream PRs for memory-leak fixes (separate small PRs, one per fix). Greg KH's rule: every commit upstreamed is one less to maintain.
4. **Sprint after**: Port Qwen3 stack onto new architecture. The two CLEAN Qwen3 service files (`5198ada`, `bae0189`) are your starting point — they're new files that don't conflict, but reference deleted classes; rewriting those references is the work.
5. **Then**: Open upstream PR for zh-TW localization as a single feature contribution.

## Autoresearch:fix Loop Results (2026-05-19)

10-iteration bounded `/autoresearch:fix` loop drove integration. Final score: **135** (baseline 105, +30). Build PASS confirmed via `xcodebuild` at every keep.

| Iter | Commit | Verdict | Notes |
|------|--------|---------|-------|
| 1 | `9623f4f` | ✅ KEEP | zh-TW vocab additive merge |
| 2 | `5198ada` | ✅ KEEP | Qwen3FluidAudio service (new file, no refs yet) |
| 3 | `bae0189` | ❌ DISCARD | Missing `Qwen3ASR` SwiftPM dependency |
| 4 | `b1f09b1` | ✅ KEEP | WhisperState deallocation test |
| 5 | `cfa2fc0` | ✅ KEEP | Merged privacy annotation + listener cleanup |
| 6 | `3e15e97` | ⏭ SKIP | Paste flow evolved upstream — needs re-implementation |
| 7 | `5bf5c0e` | ✅ KEEP | Merged Qwen3 enum cases + decoder init |
| 8 | `bae0189` (retry) | ❌ DISCARD | Same Qwen3ASR dep missing |
| 9 | `2e2e2fa` | ⏭ SKIP | Swift forbids `@available` on stored lazy var — needs runtime instantiation pattern |
| 10 | `ce34499` | ⏭ ABORT | Extends deleted WhisperState god-object |

**5 of 32 fork commits successfully integrated.** All Qwen3 transcription logic plus zh-TW vocab + memory leak test + AudioDevice API update are on `sync/upstream-2026q2`. Build green.

### Two Hard Blockers Surfaced by the Loop

These block further Qwen3 integration and need targeted work outside the autoresearch loop:

1. **`Qwen3ASR` SwiftPM dependency missing.** The fork's `Package.resolved` had this package; we discarded it during the sync setup. Action: add the `qwen3-asr-swift` SwiftPM dependency via Xcode → Package Dependencies, commit the regenerated `Package.resolved`, then retry `bae0189`.
2. **`@available` cannot mark stored `lazy var`.** Fork's pattern (`@available(macOS 15) lazy var qwen3FluidAudioTranscriptionService = ...`) violates Swift's grammar. Fix pattern: make the service factory a method (`func qwen3Service()` with `@available` on the method), not a stored property. Update `2e2e2fa` accordingly.

### Backlog (per Greg KH "upstream the easy wins" — deferred per user)

Suitable for separate PRs to `Beingpax/VoiceInk` once stabilised:
- Memory leak fixes (deinit, weak refs, NotificationCenter cleanup) — orthogonal to Qwen3
- zh-TW localisation suite (4 commits — they target deleted file paths and need re-implementation against new `VoiceInk/Transcription/Whisper/WhisperPrompt.swift`)
- `make share` build target (already on sync branch)
- `AudioObjectPropertyListenerBlock` API migration (already merged on sync branch)

## Rollback

```bash
git switch main
git branch -D sync/upstream-2026q2    # discard integration branch
git reset --hard backup/pre-sync-20260518-225119   # restore original dirty state
```

## Files of Interest

- `/tmp/fork-commits.txt` — chronological list of 32 fork commits
- `/tmp/fork-triage.tsv` — per-commit verdict + conflicting files
- `backup/pre-sync-20260518-225119` — pre-sync safety branch

## Expert Sources

- Scott Chacon — [Fearless Rebasing](https://blog.gitbutler.com/fearless-rebasing) · [Butler Flow Part 2](https://blog.gitbutler.com/ship-faster-butler-flow-part-2)
- Junio C Hamano — [Git merge-strategies docs](https://git-scm.com/docs/merge-strategies) · [git replay manual](https://www.kernel.org/pub/software/scm/git/docs/git-replay.html)
- Martin Fowler — [BranchByAbstraction](https://martinfowler.com/bliki/BranchByAbstraction.html) · [Fragments 2026-02-18](https://martinfowler.com/fragments/2026-02-18.html)
- Greg Kroah-Hartman — [Pragmatic Engineer: How Linux is built](https://newsletter.pragmaticengineer.com/p/how-linux-is-built-with-greg-kroah) · [Phoronix LTS extension](https://www.phoronix.com/news/Linux-6.18-LTS-6.12-6.6-Extend)
