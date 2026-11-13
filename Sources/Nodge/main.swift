import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let shelf = ShelfStore()
    private let history = ClipboardHistory()
    private let nowPlaying = NowPlaying()
    private var notch: NotchController!
    private var statusItem: NSStatusItem!
    private var quickDrop: QuickDrop!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Snapshot.runIfRequested()
        notch = NotchController(shelf: shelf, history: history, nowPlaying: nowPlaying)
        notch.show()
        history.start()
        nowPlaying.start()
        quickDrop = QuickDrop(shelf: shelf, notch: notch)
        setupStatusItem()
    }

    // MARK: - Menüleisten-Symbol

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "Nodge")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func item(_ title: String, key: String = "", state: Bool? = nil, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
        if let state { item.state = state ? .on : .off }
        return item
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Menü bei jedem Öffnen neu aufbauen, damit Häkchen aktuell sind
    func menuNeedsUpdate(_ menu: NSMenu) {
        let settings = AppSettings.shared
        menu.removeAllItems()
        menu.addItem(item("Island öffnen / schliessen") { [weak self] in self?.notch.toggle() })
        menu.addItem(item("Auswahl ablegen  (\(QuickDrop.shortcutLabel))") { [weak self] in self?.quickDrop.trigger() })
        menu.addItem(item("Finder-Auswahl ausschneiden  (\(QuickDrop.moveShortcutLabel), im Finder)") { [weak self] in
            self?.quickDrop.moveFinderSelection()
        })
        menu.addItem(item("Ablage-Ordner im Finder zeigen") { NSWorkspace.shared.open(AppPaths.files) })
        menu.addItem(.separator())
        menu.addItem(item("Zwischenablage aufzeichnen", state: settings.recordClipboard) {
            settings.recordClipboard.toggle()
        })
        menu.addItem(item("Jetzt läuft anzeigen", state: settings.showNowPlaying) {
            settings.showNowPlaying.toggle()
        })
        menu.addItem(item("Beim Login starten", state: settings.launchAtLogin) {
            settings.launchAtLogin.toggle()
        })
        menu.addItem(.separator())
        menu.addItem(item("Ablage leeren") { [weak self] in self?.shelf.removeAll() })
        menu.addItem(item("Verlauf leeren") { [weak self] in self?.history.removeAll() })
        menu.addItem(.separator())
        menu.addItem(item("Nodge beenden", key: "q") { NSApp.terminate(nil) })
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
