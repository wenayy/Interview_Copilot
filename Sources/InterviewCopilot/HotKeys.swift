import AppKit
import Carbon.HIToolbox

/// System-wide hotkeys via Carbon's RegisterEventHotKey. Unlike NSEvent global
/// monitors, this works while another app is focused and needs NO Accessibility
/// permission — the fix for "hotkeys don't work during the interview".
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    fileprivate var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var nextID: UInt32 = 1
    private var installed = false

    /// Control+Option — our app modifier, chosen to avoid common conflicts.
    static let ctrlOpt = UInt32(controlKey | optionKey)

    func register(keyCode: UInt32, modifiers: UInt32 = ctrlOpt,
                  action: @escaping () -> Void) {
        installHandlerIfNeeded()
        let id = nextID; nextID += 1
        handlers[id] = action
        let hkID = EventHotKeyID(signature: fourCharCode("ICPT"), id: id)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hkID,
                            GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // The callback is a capture-less C function, invoked on the main thread.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            MainActor.assumeIsolated {
                HotKeyCenter.shared.handlers[hkID.id]?()
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

private func fourCharCode(_ s: String) -> FourCharCode {
    var result: FourCharCode = 0
    for ch in s.utf16 { result = (result << 8) + FourCharCode(ch) }
    return result
}

/// The app's shortcuts, in one place — used both to register them and to render
/// the in-overlay cheat sheet so you never have to remember them.
struct Shortcut {
    let label: String
    let keys: String        // display, e.g. "⌃⌥A"
    let keyCode: UInt32
}

enum Shortcuts {
    // keyCodes: A=0, S=1, H=4, M=46, R=15, Q=12, C=8
    static let answer = Shortcut(label: "Answer (spoken question)", keys: "⌃⌥A", keyCode: 0)
    static let screen = Shortcut(label: "Answer from screen", keys: "⌃⌥S", keyCode: 1)
    static let overlay = Shortcut(label: "Show / hide overlay", keys: "⌃⌥H", keyCode: 4)
    static let mic = Shortcut(label: "Toggle mic listening", keys: "⌃⌥M", keyCode: 46)
    static let resume = Shortcut(label: "Toggle résumé use", keys: "⌃⌥R", keyCode: 15)
    static let askLast = Shortcut(label: "Ask last (what you said)", keys: "⌃⌥Q", keyCode: 12)
    static let compact = Shortcut(label: "Compact / full mode", keys: "⌃⌥C", keyCode: 8)

    static let all = [answer, screen, overlay, mic, resume, askLast, compact]
}
