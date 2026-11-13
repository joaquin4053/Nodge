import AppKit
import Combine
import ImageIO
import SwiftUI

struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var elapsed: Double
    var timestamp: Date
    var rate: Double
    var isPlaying: Bool
    var bundleID: String?
    var appPath: String?

    /// Aktuelle Position – MediaRemote liefert nur "Stand zum Zeitpunkt X"
    func position(at date: Date) -> Double {
        guard isPlaying else { return elapsed }
        let pos = elapsed + date.timeIntervalSince(timestamp) * max(rate, 1)
        return duration > 0 ? min(duration, max(0, pos)) : max(0, pos)
    }
}

/// "Jetzt läuft" für jede App (Spotify, Musik, YouTube im Browser, …).
/// Apple erlaubt das Auslesen seit macOS 15.4 nur eigenen Prozessen, deshalb läuft
/// der Helfer (Resources/NowPlayingHelper.dylib) im systemeigenen /usr/bin/perl.
final class NowPlaying: ObservableObject {
    enum Command {
        case togglePlayPause
        case next
        case previous
    }

    /// MediaRemote-Befehlsnummern. "Umschalten" (2) ignoriert macOS inzwischen,
    /// deshalb wird gezielt Play oder Pause geschickt.
    private enum RemoteCommand: Int {
        case play = 0, pause = 1, next = 4, previous = 5
    }

    @Published private(set) var info: NowPlayingInfo?
    @Published private(set) var artwork: NSImage?
    /// Anzeige an der Notch: während der Wiedergabe und noch kurz nach dem Pausieren
    @Published private(set) var isVisible = false

    private let pausedGrace: TimeInterval = 120
    private var process: Process?
    private var inputPipe: Pipe?
    private var buffer = Data()
    private var pausedSince: Date?
    private var hideTimer: Timer?
    private var settingsObserver: AnyCancellable?
    private let isPreview: Bool

    private var resources: URL { Bundle.main.resourceURL ?? URL(fileURLWithPath: ".") }
    private var scriptURL: URL { resources.appendingPathComponent("nowplaying.pl") }
    private var libraryURL: URL { resources.appendingPathComponent("NowPlayingHelper.dylib") }

    init() {
        isPreview = false
    }

    /// Nur für Vorschau-Snapshots
    init(preview: NowPlayingInfo, artwork: NSImage?) {
        isPreview = true
        info = preview
        self.artwork = artwork
        isVisible = true
    }

    func start() {
        settingsObserver = AppSettings.shared.$showNowPlaying
            .removeDuplicates()
            .sink { [weak self] enabled in
                DispatchQueue.main.async { enabled ? self?.launch() : self?.stop() }
            }
    }

    // MARK: - Steuerung

    func send(_ command: Command) {
        guard !isPreview else { return }
        let remote: RemoteCommand
        switch command {
        case .togglePlayPause: remote = info?.isPlaying == true ? .pause : .play
        case .next: remote = .next
        case .previous: remote = .previous
        }
        if command == .togglePlayPause, var current = info {
            // Sofort umschalten, die Bestätigung des Systems kommt kurz danach
            current.elapsed = current.position(at: Date())
            current.timestamp = Date()
            current.isPlaying.toggle()
            apply(current)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [scriptURL.path, libraryURL.path, "send"]
        var env = ProcessInfo.processInfo.environment
        env["NODGE_MR_COMMAND"] = String(remote.rawValue)
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// An eine Stelle im Titel springen (Sekunden)
    func seek(to seconds: Double) {
        guard !isPreview, var current = info else { return }
        let target = max(0, current.duration > 0 ? min(seconds, current.duration - 0.5) : seconds)
        current.elapsed = target
        current.timestamp = Date()
        apply(current)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [scriptURL.path, libraryURL.path, "send"]
        var env = ProcessInfo.processInfo.environment
        env["NODGE_MR_SEEK"] = String(target)
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    func openPlayerApp() {
        guard let path = info?.appPath else { return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
    }

    // MARK: - Helfer-Prozess

    private func launch() {
        guard process == nil else { return }
        guard FileManager.default.fileExists(atPath: scriptURL.path),
              FileManager.default.fileExists(atPath: libraryURL.path) else {
            NSLog("Nodge: Jetzt-läuft-Helfer fehlt im App-Bundle")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [scriptURL.path, libraryURL.path, "stream"]
        let out = Pipe()
        let input = Pipe() // bleibt offen; schliesst sich mit Nodge → Helfer beendet sich
        p.standardOutput = out
        p.standardInput = input
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] ended in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard let self, self.process === ended else { return }
                self.process = nil
                if AppSettings.shared.showNowPlaying { self.launch() }
            }
        }
        do {
            try p.run()
            process = p
            inputPipe = input
        } catch {
            NSLog("Nodge: Jetzt-läuft-Helfer startet nicht: \(error)")
        }
    }

    private func stop() {
        let p = process
        process = nil
        p?.terminate()
        inputPipe = nil
        apply(nil)
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                handle(json)
            }
        }
    }

    private func handle(_ json: [String: Any]) {
        guard let title = json["title"] as? String, !title.isEmpty else { return apply(nil) }
        let artist = json["artist"] as? String ?? ""
        let new = NowPlayingInfo(
            title: title,
            artist: artist,
            album: json["album"] as? String ?? "",
            duration: json["duration"] as? Double ?? 0,
            elapsed: json["elapsed"] as? Double ?? 0,
            timestamp: (json["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date(),
            rate: json["rate"] as? Double ?? 0,
            isPlaying: json["playing"] as? Bool ?? false,
            bundleID: json["bundleID"] as? String,
            appPath: json["appPath"] as? String)

        // Der Helfer schickt das Cover nur, wenn es sich geändert hat
        if let b64 = json["artwork"] as? String {
            // Im Hintergrund decodieren und auf 128 px verkleinern (grösste Anzeige: 48 pt @2x)
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let image = Data(base64Encoded: b64).flatMap { Self.thumbnail(from: $0, maxPixels: 128) }
                DispatchQueue.main.async {
                    guard let self, self.info?.title == title else { return }
                    self.artwork = image
                }
            }
        } else if info?.title != title || info?.artist != artist {
            artwork = nil
        }
        apply(new)
    }

    private static func thumbnail(from data: Data, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
    }

    private func apply(_ new: NowPlayingInfo?) {
        // Ohne Animation: jede Feder-Animation zeichnet ~1 s lang mit voller Bildrate neu.
        // Ein-/Ausblenden der Anzeige wird separat über isVisible animiert.
        if info != new { info = new }
        if let new, !new.isPlaying {
            pausedSince = pausedSince ?? Date()
        } else {
            pausedSince = nil
        }
        updateVisibility()
    }

    private func updateVisibility() {
        hideTimer?.invalidate()
        var visible = info != nil
        if let since = pausedSince {
            let remaining = pausedGrace - Date().timeIntervalSince(since)
            visible = visible && remaining > 0
            if remaining > 0 {
                hideTimer = Timer.scheduledTimer(withTimeInterval: remaining + 0.1, repeats: false) { [weak self] _ in
                    self?.updateVisibility()
                }
                hideTimer?.tolerance = 2
            }
        }
        if isVisible != visible {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { isVisible = visible }
        }
    }
}
