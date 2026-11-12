import Carbon
import Foundation

enum GlobalShortcut: String, CaseIterable, Identifiable {
    case controlOptionG, commandOptionG, controlOptionSpace, disabled
    var id: String { rawValue }
    var display: String {
        switch self {
        case .controlOptionG: return "⌃⌥G"
        case .commandOptionG: return "⌥⌘G"
        case .controlOptionSpace: return "⌃⌥Space"
        case .disabled: return L("关闭快捷键")
        }
    }
    var keyCode: UInt32 { UInt32(self == .controlOptionSpace ? kVK_Space : kVK_ANSI_G) }
    var modifiers: UInt32 {
        UInt32(self == .commandOptionG ? cmdKey | optionKey : controlKey | optionKey)
    }
}

/// Carbon registers one specific key combination without observing other keyboard input.
final class GlobalHotKey {
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var registered: GlobalShortcut = .disabled
    private let action: () -> Void
    private static let signature: OSType = 0x54464C44 // TFLD

    init(action: @escaping () -> Void) { self.action = action }

    func register(_ shortcut: GlobalShortcut) -> OSStatus {
        if registered == shortcut { return noErr }
        if shortcut == .disabled {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil
            registered = .disabled
            return noErr
        }
        if eventHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                              nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard result == noErr, identifier.signature == GlobalHotKey.signature, identifier.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action()
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
            guard status == noErr else { return status }
        }
        var candidate: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier, GetApplicationEventTarget(), 0, &candidate)
        guard status == noErr else { return status }
        // Keep the working shortcut registered if the new combination is unavailable.
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = candidate
        registered = shortcut
        return noErr
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
