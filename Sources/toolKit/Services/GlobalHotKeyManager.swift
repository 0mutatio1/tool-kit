import Carbon
import Foundation

@MainActor
final class GlobalHotKeyManager {
    struct Shortcut {
        let keyCode: UInt32
        let modifiers: UInt32
        let displayText: String

        static let defaultClipShortcut = Shortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(controlKey | optionKey | cmdKey),
            displayText: "⌃⌥⌘C"
        )
    }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var registeredHotKeyID: EventHotKeyID?
    var onKeyDown: (() -> Void)?

    func register(_ shortcut: Shortcut = .defaultClipShortcut) {
        unregister()

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let hotKeyID = EventHotKeyID(signature: FourCharCode("OCRM"), id: 1)

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else {
                    return noErr
                }

                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr, hotKeyID.signature == manager.registeredHotKeyID?.signature, hotKeyID.id == manager.registeredHotKeyID?.id else {
                    return noErr
                }

                Task { @MainActor in
                    manager.onKeyDown?()
                }
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        registeredHotKeyID = hotKeyID
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        registeredHotKeyID = nil
    }
}

private extension FourCharCode {
    init(_ string: String) {
        self = string.utf16.reduce(0) { partialResult, next in
            (partialResult << 8) + FourCharCode(next)
        }
    }
}
