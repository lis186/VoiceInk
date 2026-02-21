import Foundation
import AppKit
import Carbon
import os

private let logger = Logger(subsystem: "com.VoiceInk", category: "CursorPaster")

class CursorPaster {

    // MARK: - Input source observer

    /// The last QWERTY-compatible input source the *user* explicitly selected.
    /// Updated by the DistributedNotificationCenter observer; ignored when we
    /// are doing a programmatic switch ourselves.
    private static var lastKnownQWERTYSourceID: String?

    /// Set to true while we are programmatically switching input sources so
    /// the observer does not record our own changes as "user choices".
    private static var programmaticSwitchInProgress = false

    /// Register for input-source-change notifications. Call once at app startup.
    static func startObservingInputSourceChanges() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            guard !programmaticSwitchInProgress else { return }
            guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                  let id = sourceID(for: src),
                  isQWERTY(id) else { return }
            lastKnownQWERTYSourceID = id
            logger.notice("Recorded user QWERTY source: \(id, privacy: .public)")
        }
    }

    // MARK: - Public paste entry point

    static func pasteAtCursor(_ text: String) {
        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")

        var savedContents: [(NSPasteboard.PasteboardType, Data)] = []

        if shouldRestoreClipboard {
            let currentItems = pasteboard.pasteboardItems ?? []

            for item in currentItems {
                for type in item.types {
                    if let data = item.data(forType: type) {
                        savedContents.append((type, data))
                    }
                }
            }
        }

        ClipboardManager.setClipboard(text, transient: shouldRestoreClipboard)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            pasteFromClipboard()
        }

        if shouldRestoreClipboard {
            let restoreDelay = UserDefaults.standard.double(forKey: "clipboardRestoreDelay")
            let delay = max(restoreDelay, 0.25)

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if !savedContents.isEmpty {
                    pasteboard.clearContents()
                    for (type, data) in savedContents {
                        pasteboard.setData(data, forType: type)
                    }
                }
            }
        }
    }

    // MARK: - Clipboard paste with input-source fix

    /// Paste from the clipboard using CGEvent, temporarily switching to a
    /// QWERTY-compatible input source so that virtual key 0x09 is reliably
    /// interpreted as "V" for Cmd+V.
    ///
    /// When the current source is an IME (e.g. Zhuyin), we switch to the user's
    /// last known QWERTY source (recorded by the observer) rather than ABC, so
    /// that macOS's input-source history — and the toggle shortcut — remain
    /// unaffected by VoiceInk's temporary switch.
    private static func pasteFromClipboard() {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility not trusted — cannot paste")
            return
        }

        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            logger.error("TISCopyCurrentKeyboardInputSource returned nil")
            return
        }
        let currentID = sourceID(for: currentSource) ?? "unknown"
        let switched = switchToQWERTYInputSource()
        logger.notice("Pasting: inputSource=\(currentID, privacy: .public), switched=\(switched)")

        // Capture which QWERTY layout we just switched to, so we can verify at
        // restore time that the user hasn't manually changed it in the interim.
        let switchedToID: String? = switched
            ? TISCopyCurrentKeyboardInputSource().map { sourceID(for: $0.takeRetainedValue()) } ?? nil
            : nil

        // If we switched input sources, wait 30 ms for the system to apply it
        // before posting the CGEvents. Use asyncAfter instead of usleep so the
        // main thread is not blocked.
        let eventDelay: TimeInterval = switched ? 0.03 : 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + eventDelay) {
            let source = CGEventSource(stateID: .privateState)

            let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
            let vDown   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            let vUp     = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            let cmdUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

            cmdDown?.flags = .maskCommand
            vDown?.flags   = .maskCommand
            vUp?.flags     = .maskCommand

            cmdDown?.post(tap: .cghidEventTap)
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
            cmdUp?.post(tap: .cghidEventTap)

            logger.notice("CGEvents posted for Cmd+V")

            if switched {
                // Restore the original input source after a short delay so the
                // posted events are processed under the QWERTY layout first.
                // Guard: only restore if the current source is still the QWERTY
                // layout we switched to — skip if the user manually changed it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    programmaticSwitchInProgress = true
                    defer { programmaticSwitchInProgress = false }

                    if let targetID = switchedToID,
                       let nowSrc = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                       sourceID(for: nowSrc) == targetID {
                        TISSelectInputSource(currentSource)
                        logger.notice("Restored input source to \(currentID, privacy: .public)")
                    } else {
                        logger.notice("Skipped restore — input source changed during paste")
                    }
                }
            }
        }
    }

    /// Switch to a QWERTY-compatible input source. Returns true if a switch was made.
    ///
    /// Priority:
    ///  1. The user's last known QWERTY source (recorded by the observer) — preserves
    ///     the user's own input-source history and toggle-shortcut behaviour.
    ///  2. ABC or US QWERTY as a fallback (e.g. on first launch before any switch
    ///     has been observed).
    private static func switchToQWERTYInputSource() -> Bool {
        guard let currentSourceRef = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return false }
        if let currentID = sourceID(for: currentSourceRef), isQWERTY(currentID) {
            return false // already QWERTY, nothing to do
        }

        let criteria = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        guard let list = TISCreateInputSourceList(criteria, false)?.takeRetainedValue() as? [TISInputSource] else {
            logger.error("Failed to list input sources")
            return false
        }

        // Build ordered candidate list: user's last known QWERTY first, then ABC/US.
        var candidateIDs: [String] = []
        if let last = lastKnownQWERTYSourceID {
            candidateIDs.append(last)
        }
        for id in ["com.apple.keylayout.ABC", "com.apple.keylayout.US"] {
            if !candidateIDs.contains(id) { candidateIDs.append(id) }
        }

        for targetID in candidateIDs {
            if let match = list.first(where: { sourceID(for: $0) == targetID }) {
                programmaticSwitchInProgress = true
                let status = TISSelectInputSource(match)
                programmaticSwitchInProgress = false
                if status == noErr {
                    logger.notice("Switched input source to \(targetID, privacy: .public)")
                    return true
                } else {
                    logger.error("TISSelectInputSource failed with status \(status)")
                }
            }
        }

        logger.error("No QWERTY input source found to switch to")
        return false
    }

    private static func sourceID(for source: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func isQWERTY(_ id: String) -> Bool {
        let qwertyIDs: Set<String> = [
            "com.apple.keylayout.ABC",
            "com.apple.keylayout.US",
            "com.apple.keylayout.USInternational-PC",
            "com.apple.keylayout.British",
            "com.apple.keylayout.Australian",
            "com.apple.keylayout.Canadian",
            // Dvorak - QWERTY ⌘: shortcuts use QWERTY key positions,
            // so virtualKey 0x09 = Cmd+V without any layout switch.
            "com.apple.keylayout.DVORAK-QWERTYCMD",
        ]
        return qwertyIDs.contains(id)
    }

    // MARK: - Enter key

    /// Simulate pressing the Return / Enter key.
    static func pressEnter() {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .privateState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
    }
}
