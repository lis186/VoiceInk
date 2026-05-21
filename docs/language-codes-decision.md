# Language Code Architecture — Decision & Tradeoffs

> 2026-05-21 · 紀錄 zh-TW / Qwen3 顯示問題的修復決策、放棄的替代方案、與未來路徑

## 背景

`5915f06 feat: add Traditional Chinese (zh-TW)` 和 `0c7ef5a feat: add Qwen3Model` 等
commits 把 zh-TW 語言選項與 Qwen3-ASR 本地模型加進來,所有相關程式碼也都編譯
進 binary。但**使用者在 UI 看不到任何一個**。

調查發現三個獨立的 filter bug:

### Bug 1 — Whisper 的 `whisperLanguageCodes` 沒包含 `zh-TW`

`VoiceInk/Models/LanguageDictionary.swift` 的 `whisperLanguageCodes` 是一個 Set,
給 `LanguageDictionary.forProvider(... provider: .whisper)` 用來過濾 `all` 字典。
這個 set 原本只含 `"zh"`,所以即使 `all` 裡有 `"zh-TW": "Chinese Traditional (繁體中文)"`,
被 Whisper 模型選中時就會被過濾掉。

下游的 `LibWhisper.swift:41`(`selectedLanguage == "zh-TW" ? "auto" : selectedLanguage`)
跟 `WhisperPrompt.swift`、`TranscriptionOutputFilter.swift`(Hans→Hant CFStringTransform)
都已經正確處理 zh-TW,只是入口被堵住,後面的邏輯永遠跑不到。

### Bug 2 — `ModelManagementView` 的 Local 分頁 filter 漏 Qwen3

`VoiceInk/Views/AI Models/ModelManagementView.swift` 的 `filteredModels` 在
`.local` case 只允許三個 provider:

```swift
($0.provider == .whisper || $0.provider == .nativeApple || $0.provider == .fluidAudio)
```

`qwen3FluidAudio` 與 `qwen3MLX` 不在內,所以兩個 Qwen3 模型已註冊但
完全不顯示在 UI 上。

### Bug 3 — Qwen3 註冊時用了 Whisper 的語言過濾

`TranscriptionModelRegistry.swift` 第 51 / 61 行的 Qwen3 註冊用
`LanguageDictionary.forProvider(isMultilingual: true)`,沒指定 provider,
所以採用預設值 `.whisper`,套用了同樣的 `whisperLanguageCodes` 過濾,
連帶把 zh-TW 從 Qwen3 的語言選單刪掉(即使 Bug 1 修了,Qwen3 也得另外處理)。

## 修復(P0,已套用)

最小破壞面、純加法的三點修改:

| 檔案 | 改動 | 行為 |
|---|---|---|
| `LanguageDictionary.swift` | `whisperLanguageCodes` 末尾加 `"zh-TW"` | Whisper 語言選單出現繁中 |
| `LanguageDictionary.swift` | `forProvider` 加 `.qwen3FluidAudio, .qwen3MLX` case 回傳 `all` | Qwen3 取得完整語言集(含繁中) |
| `ModelManagementView.swift` | Local filter 加 `qwen3FluidAudio` `qwen3MLX` | Local 分頁出現 Qwen3 兩個模型 |
| `TranscriptionModelRegistry.swift` | Qwen3 註冊改用 `provider: .qwen3FluidAudio / .qwen3MLX` | 走自己的 case,不被 Whisper filter 拖累 |

**不改任何既有 language code**。`"zh"` 還是 `"zh"`,`"zh-TW"` 還是 `"zh-TW"`。
UserDefaults 不需 migration。其他 cloud provider 不受影響。

## 替代方案(已評估、放棄)

### A. 把 `"zh"` 改名為 `"zh-CN"`

優點:跟 `"zh-TW"` 語意對稱(都是 BCP-47 region tag)、跟 `appleNative` 字典
一致(那邊本來就用 `"zh-CN"`)。

缺點:

1. **Whisper 不認 `zh-CN`** — whisper.cpp 只接受 ISO 639-1 的 `zh`。
   要嘛在 `LibWhisper.swift:41` 加 `zh-CN → zh` 映射,要嘛 Whisper 對中文壞掉。
2. **UserDefaults 遷移** — 既有用戶選的 `"zh"` 在升級後失配,Whisper 中文
   靜默退回 fallback。Migration 邏輯要橫跨 PowerMode profiles、Custom Cloud
   Models、Transcription history 多個儲存點。
3. **跟 PowerMode profile JSON 的相容性** — 每個 PowerMode 自存一份語言偏好,
   一次性 migration 跨不過去。

對「能不能修 bug」沒幫助,純粹是語意整齊化。**放棄**。

### B. Script-based 重構 `"zh-Hans"` / `"zh-Hant"` + Provider Adapter

優點:架構上最乾淨,Hans/Hant 是字形(用戶在乎的東西)而非地域,符合
Unicode CLDR / Apple `Locale.Script` 標準,政治中性。Provider Adapter 模式
能把語言識別跟輸出腳本拆開,未來加新 provider 不會再踩同一個洞。

事前驗屍 — 假設這次重構失敗了,可能原因:

| 致命度 | 風險 | 說明 |
|---|---|---|
| 🔴 | UserDefaults 不是唯一儲存點 | PowerMode profiles、Custom Cloud Models、 Transcription history 各自儲存 language code,一次性 migration 必漏 |
| 🔴 | Whisper `zh-TW → auto` 的 code-switching 行為 | `LibWhisper.swift:41` 刻意把 zh-TW 映成 `"auto"` 讓 Whisper 自動偵測中英文混雜 — 重構時很容易寫成 `zh-Hant → "zh"`,反而退步 |
| 🟠 | `zh-Hant` 把 HK 跟 TW collapse | 港式繁體跟台灣繁體用詞差很多,未來想加 HK 專用 prompt 又得拆一次 |
| 🟠 | Cloud provider mapping spec 各家不同 | 10+ cloud providers 各有自己的中文 code 慣例,沒人是專家,容易漏映射導致 `400 unsupported language` |
| 🟠 | 估時嚴重低估 | 真實成本含驗證是 1-2 天,不是 30 分鐘 |
| 🟡 | 寫死字串比對散落各處 | `selectedLanguage == "zh-TW"` 在多處檔案,漏改一處就失去 prompt biasing |
| 🟡 | 沒有自動化測試保護 | 重構回歸只能手動測,改錯只有用戶會發現 |
| 🟢 | Sparkle 降版地獄 | 升級後 UserDefaults 寫成 `"zh-Hans"`,降版讀不到 fallback 到英文 |

**最可能的失敗劇情**:「migration 漏掉 PowerMode 與部分 cloud provider mapping
→ 升級後一部分用戶語言選擇靜默壞掉 → 緊急 hotfix」。

`zh-Hant` / `zh-Hans` 在程式碼層次比較對,但**用戶看的是「簡體中文」「繁體中文」
的顯示名稱**,不在乎內部 code 是什麼。為了標準性付出 1-2 天 + 跨多個儲存點的
migration 風險,沒有對應的明確使用者價值。**放棄**。

## 未來路徑(條件性,**不**主動排程)

按優先順序、發生條件如下:

### P1 — 加 `mapLanguageCode(_:)` 到 `TranscriptionModel` protocol

**觸發條件**:有第三個 provider 需要中文 code 跟 Whisper 不一樣
(例如:新接的 cloud provider 要 `zh-Hans` / `zh-Hant`)。

**做法**:在 protocol 加 default 實作回傳原 code,只有需要映射的 provider override。
這是純加法,不改既有 code 字典,不需要 UserDefaults migration。

**範圍**:1-2 小時。

### P2 — Storage 改 script-based

**觸發條件**:同時有兩個以上的需求:
1. HK 繁體跟 TW 繁體要區分(`zh-Hant-HK` vs `zh-Hant-TW`)
2. 多 provider 之間的中文行為不一致已經造成實際 bug
3. 願意付 1-2 天的 migration + 跨儲存點協調成本

**做法**:見前面「替代方案 B」。**重要**:做之前先把所有儲存 language 的位置
列出來(`grep -r "SelectedLanguage\|selectedLanguage\|languageCode"` 全 repo),
寫一個 unified migration,先 dry-run 過 100 個樣本 UserDefaults 確認。

**範圍**:1-2 工作天,含驗證。

### Qwen3 supportedLanguages 精細化

目前 `LanguageDictionary.forProvider(provider: .qwen3FluidAudio)` 回傳 `all`,
是 overstatement(Qwen3 實際是 52 語言 + 22 中文方言)。等 Qwen3 跑得起來、
有實測語言清單再回來收斂這個 case。改點集中在
`LanguageDictionary.swift` 的 `.qwen3FluidAudio, .qwen3MLX` case,單一改點。

## 一個關鍵原則

語言 code 在 VoiceInk 內部其實同時做了三件事:**模型輸入碼**、
**輸出腳本判斷依據**、**UI 顯示鍵**。`"zh-TW"` 目前同時做這三件事,
能跑是因為各層各自有 `== "zh-TW"` 的特判。

這條原則違反「單一職責」,但**修起來不便宜**(見 P2 的成本估計),
而且 BCP-47 region tag 對用戶體驗已經夠用。記下來,別忘記它存在,
等真的有人為它流血再動手。
