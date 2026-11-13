import Foundation
import ServiceManagement

/// Alle Daten liegen in ~/Library/Application Support/Nodge
enum AppPaths {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ensure(base.appendingPathComponent("Nodge", isDirectory: true))
    }()
    static let files = ensure(root.appendingPathComponent("Files", isDirectory: true))
    static let history = ensure(root.appendingPathComponent("History", isDirectory: true))

    private static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var recordClipboard: Bool {
        didSet { UserDefaults.standard.set(recordClipboard, forKey: "recordClipboard") }
    }

    @Published var showNowPlaying: Bool {
        didSet { UserDefaults.standard.set(showNowPlaying, forKey: "showNowPlaying") }
    }

    /// Gemerkt statt bei jedem Neuzeichnen abgefragt (die Abfrage ist ein Systemaufruf)
    private var cachedLaunchAtLogin = SMAppService.mainApp.status == .enabled

    var launchAtLogin: Bool {
        get { cachedLaunchAtLogin }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Nodge: Login-Item konnte nicht geändert werden: \(error)")
            }
            cachedLaunchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private init() {
        UserDefaults.standard.register(defaults: ["recordClipboard": true, "showNowPlaying": true])
        recordClipboard = UserDefaults.standard.bool(forKey: "recordClipboard")
        showNowPlaying = UserDefaults.standard.bool(forKey: "showNowPlaying")
    }
}
