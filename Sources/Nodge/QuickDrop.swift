import AppKit
import ApplicationServices
import Carbon

/// Globale Tastenkürzel:
/// ⌘⇧Leertaste → Auswahl in die Ablage KOPIEREN (Finder: Dateien, andere Apps: markierter Text)
/// ⌘⇧↑        → markierte Finder-Dateien AUSSCHNEIDEN (verschoben erst beim Herausziehen) (nur aktiv, solange der Finder vorne ist,
///               damit ⌘⇧↑ in Text-Apps weiterhin "bis zum Anfang markieren" bleibt)
final class QuickDrop {
    static let shortcutLabel = "⌘⇧Leertaste"
    static let moveShortcutLabel = "⌘⇧↑"

    private enum Shortcut: UInt32 { case copy = 1, move = 2 }

    private let shelf: ShelfStore
    private let notch: NotchController
    private var copyRef: EventHotKeyRef?
    private var moveRef: EventHotKeyRef?
    private var activationObserver: NSObjectProtocol?
    private static weak var current: QuickDrop?
    private static let signature = OSType(0x4E4F_4447) // "NODG"
    private static let finderID = "com.apple.finder"

    init(shelf: ShelfStore, notch: NotchController) {
        self.shelf = shelf
        self.notch = notch
        Self.current = self
        installHandler()
        copyRef = register(.copy, keyCode: kVK_Space)
        updateMoveShortcut()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateMoveShortcut() }
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            let id = hotKey.id
            DispatchQueue.main.async {
                switch Shortcut(rawValue: id) {
                case .copy: QuickDrop.current?.trigger()
                case .move: QuickDrop.current?.moveFinderSelection()
                case nil: break
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private func register(_ shortcut: Shortcut, keyCode: Int) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: shortcut.rawValue)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(cmdKey | shiftKey), id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr { NSLog("Nodge: Tastenkürzel \(shortcut) konnte nicht registriert werden (\(status))") }
        return ref
    }

    /// ⌘⇧↑ nur belegen, solange der Finder im Vordergrund ist
    private func updateMoveShortcut() {
        let finderActive = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finderID
        if finderActive, moveRef == nil {
            moveRef = register(.move, keyCode: kVK_UpArrow)
        } else if !finderActive, let ref = moveRef {
            UnregisterEventHotKey(ref)
            moveRef = nil
        }
    }

    func trigger() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier == Self.finderID {
            let files = finderSelection()
            if !files.isEmpty {
                shelf.ingest(files.map { .file($0) })
                notch.showBriefly()
            } else {
                NSSound.beep()
            }
        } else {
            copySelectionFromFrontApp()
        }
    }

    /// Markierte Finder-Dateien "ausschneiden": Sie bleiben am Originalort, bis sie
    /// aus der Island an einen anderen Ort gezogen werden – dann werden sie verschoben.
    func moveFinderSelection() {
        let files = finderSelection()
        guard !files.isEmpty else { return NSSound.beep() }
        shelf.ingest(files.map { .cutFile($0) })
        notch.showBriefly()
    }

    // MARK: - Finder

    private func finderSelection() -> [URL] {
        let source = """
        tell application "Finder"
            set out to {}
            repeat with i in (get selection)
                set end of out to POSIX path of (i as alias)
            end repeat
            return out
        end tell
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
            NSLog("Nodge: Finder-Auswahl nicht lesbar: \(error ?? [:])")
            return []
        }
        guard result.numberOfItems > 0 else { return [] }
        return (1...result.numberOfItems).compactMap { index in
            result.atIndex(index)?.stringValue.map { URL(fileURLWithPath: $0) }
        }
    }

    // MARK: - Andere Apps

    private func copySelectionFromFrontApp() {
        // ⌘C simulieren braucht die Bedienungshilfen-Berechtigung (einmalig)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }

        let pb = NSPasteboard.general
        let before = pb.changeCount
        let src = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if pb.changeCount != before {
                self.shelf.addFromPasteboard(pb)
                self.notch.showBriefly()
            } else {
                NSSound.beep()
            }
        }
    }
}
