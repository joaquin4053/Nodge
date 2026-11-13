import SwiftUI

/// Debug & Doku (ohne Bildschirmaufnahme-Rechte, alle Daten fiktiv):
/// - `NODGE_SNAPSHOT=/pfad Nodge` rendert die Island-Zustände als PNG und beendet sich.
/// - `NODGE_DEMO=/pfad NODGE_DEMO_FILES=/beispieldateien Nodge` rendert die Einzelbilder
///   für das Demo-Video (transparent, siehe tools/make_demo.py).
@MainActor
enum Snapshot {
    static var active = false

    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["NODGE_DEMO"] {
            active = true
            renderDemo(to: URL(fileURLWithPath: dir), samples: env["NODGE_DEMO_FILES"].map(URL.init(fileURLWithPath:)))
            exit(0)
        }
        guard let dir = env["NODGE_SNAPSHOT"] else { return }
        active = true
        renderStates(to: URL(fileURLWithPath: dir))
        exit(0)
    }

    // MARK: - Fiktive Beispieldaten

    static let noteText = "Workshop-Notizen\nKickoff Projekt Atlas: Termin am 4. Dezember, Raum Bergsicht. Offene Punkte: Moodboard finalisieren, Offerte prüfen, Einladungen verschicken."

    static let history: [ClipEntry] = [
        ClipEntry(id: UUID(), kind: .text, text: "Treffpunkt: Bahnhof Bellinzona, Gleis 3, 09:12 Uhr",
                  date: Date().addingTimeInterval(-25), appBundleID: "com.apple.MobileSMS"),
        ClipEntry(id: UUID(), kind: .text, text: "./build.sh --install",
                  date: Date().addingTimeInterval(-300), appBundleID: "com.apple.Terminal"),
        ClipEntry(id: UUID(), kind: .text, text: noteText,
                  date: Date().addingTimeInterval(-1500), appBundleID: "com.apple.Notes"),
        ClipEntry(id: UUID(), kind: .text, text: "hallo@atelier-nordlicht.example",
                  date: Date().addingTimeInterval(-7200), appBundleID: "com.apple.mail"),
    ]

    static func song(_ title: String, _ artist: String, _ album: String, duration: Double,
                     elapsed: Double, playing: Bool) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: artist, album: album, duration: duration, elapsed: elapsed,
                       timestamp: Date(), rate: 1, isPlaying: playing, bundleID: "com.apple.Music",
                       appPath: "/System/Applications/Music.app")
    }

    /// Erfundenes Albumcover: Farbverlauf mit Sonne und Bergen
    static func artwork(_ top: NSColor, _ bottom: NSColor, sun: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(starting: top, ending: bottom)?.draw(in: rect, angle: -90)
            sun.setFill()
            NSBezierPath(ovalIn: NSRect(x: 150, y: 150, width: 90, height: 90)).fill()
            NSColor.black.withAlphaComponent(0.35).setFill()
            let back = NSBezierPath()
            back.move(to: .zero); back.line(to: NSPoint(x: 0, y: 120)); back.line(to: NSPoint(x: 110, y: 190))
            back.line(to: NSPoint(x: 210, y: 110)); back.line(to: NSPoint(x: 300, y: 160)); back.line(to: NSPoint(x: 300, y: 0))
            back.fill()
            NSColor.black.withAlphaComponent(0.55).setFill()
            let front = NSBezierPath()
            front.move(to: .zero); front.line(to: NSPoint(x: 0, y: 60)); front.line(to: NSPoint(x: 90, y: 100))
            front.line(to: NSPoint(x: 180, y: 50)); front.line(to: NSPoint(x: 300, y: 95)); front.line(to: NSPoint(x: 300, y: 0))
            front.fill()
            return true
        }
    }

    // MARK: - Rendern

    private static func render(_ name: String, to out: URL, shelf: ShelfStore, history: ClipboardHistory,
                               np: NowPlaying, canvas: CGSize, background: Color?,
                               configure: (NotchViewModel) -> Void) {
        let vm = NotchViewModel()
        vm.notchSize = CGSize(width: 179, height: 32)
        configure(vm)
        let view = ZStack(alignment: .top) {
            if let background { background }
            NotchView(vm: vm, shelf: shelf, history: history, nowPlaying: np)
        }
        .frame(width: canvas.width, height: canvas.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let image = renderer.nsImage { writePNG(image, to: out.appendingPathComponent("\(name).png")) }
    }

    /// Immer als 8-Bit-sRGB speichern: Mit App-Symbolen/Covern rendert ImageRenderer sonst
    /// in einem erweiterten Farbraum, und das PNG wirkt matt.
    private static func writePNG(_ image: NSImage, to url: URL) {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let flat = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    /// Klassische Zustandsübersicht (NODGE_SNAPSHOT)
    private static func renderStates(to out: URL) {
        let items = [
            ShelfItem(id: UUID(), kind: .file, createdAt: Date(), fileName: "Projekt Atlas", sourcePath: "/System/Library/Desktop Pictures"),
            ShelfItem(id: UUID(), kind: .text, createdAt: Date(), text: noteText),
            ShelfItem(id: UUID(), kind: .link, createdAt: Date(), text: "https://tessin.example/wandern"),
        ]
        let media = NowPlaying(preview: song("Neon Horizon", "Luma Drift", "Midnight Lakes", duration: 214, elapsed: 61, playing: true),
                               artwork: artwork(NSColor(red: 0.45, green: 0.2, blue: 0.85, alpha: 1), NSColor(red: 1, green: 0.45, blue: 0.3, alpha: 1), sun: NSColor(red: 1, green: 0.85, blue: 0.35, alpha: 1)))
        let noMedia = NowPlaying()
        let full = ShelfStore(preview: items)
        let empty = ShelfStore(preview: [])
        let hist = ClipboardHistory(preview: history)
        let bg = Color(red: 0.55, green: 0.62, blue: 0.75)
        let canvas = CGSize(width: 760, height: 260)
        func r(_ name: String, _ shelf: ShelfStore, np: NowPlaying? = nil, _ c: (NotchViewModel) -> Void) {
            render(name, to: out, shelf: shelf, history: hist, np: np ?? noMedia, canvas: canvas, background: bg, configure: c)
        }
        r("1-closed-empty", empty) { _ in }
        r("2-closed-items", full) { _ in }
        r("3-peek", full) { $0.isPeeking = true }
        r("4-open-empty", empty) { $0.isOpen = true }
        r("5-open-items", full) { $0.isOpen = true }
        r("6-open-drop", full) { $0.isOpen = true; $0.isDropTargeted = true }
        r("7-open-history", full) { $0.isOpen = true; $0.tab = .history }
        r("8-media-closed", empty, np: media) { $0.showsMedia = true }
        r("9-media-closed-items", full, np: media) { $0.showsMedia = true }
        r("10-media-open", full, np: media) { $0.showsMedia = true; $0.isMediaOpen = true }
    }

    /// Einzelbilder fürs Demo-Video (NODGE_DEMO): transparent, 900×300 pt bei 2×
    private static func renderDemo(to out: URL, samples: URL?) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nodge-demo-files", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        DemoFiles.root = root

        // Beispieldateien wie in der echten Ablage unter Files/<id>/ ablegen
        func fileItem(_ name: String, cut: Bool = false) -> ShelfItem {
            let id = UUID()
            let src = samples?.appendingPathComponent(name)
            if cut { return ShelfItem(id: id, kind: .file, createdAt: Date(), fileName: name, sourcePath: src?.path) }
            let dir = root.appendingPathComponent(id.uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let src { try? FileManager.default.copyItem(at: src, to: dir.appendingPathComponent(name)) }
            return ShelfItem(id: id, kind: .file, createdAt: Date(), fileName: name)
        }
        let pdf = fileItem("Offerte Gartenhaus.pdf")
        let photo = fileItem("Moodboard Tessin.jpg")
        let note = ShelfItem(id: UUID(), kind: .text, createdAt: Date(), text: noteText)
        let link = ShelfItem(id: UUID(), kind: .link, createdAt: Date(), text: "https://tessin.example/wandern")
        let folder = fileItem("Projekt Atlas", cut: true)

        // Vorschaubilder vorab laden (ImageRenderer wartet nicht auf QuickLook)
        let store = ShelfStore(preview: [pdf, photo, folder])
        var pending = 0
        for item in [pdf, photo, folder] {
            guard let url = store.fileURL(for: item) else { continue }
            pending += 2
            Thumbnails.shared.load(url, size: 52) { _ in pending -= 1 }
            Thumbnails.shared.load(url, size: 128) { _ in pending -= 1 }
        }
        let deadline = Date().addingTimeInterval(6)
        while pending > 0 && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        for item in [pdf, photo, folder] {
            guard let url = store.fileURL(for: item) else { continue }
            // Symbol für den fiktiven Schreibtisch: Vorschaubild wie im Finder, sonst Datei-Symbol
            let icon = Thumbnails.shared.cached(url, size: 128) ?? NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 128, height: 128)
            writePNG(icon, to: out.appendingPathComponent("icon-\(item.fileName ?? "file").png"))
        }

        let hist = ClipboardHistory(preview: history)
        let none = NowPlaying()
        let songA = NowPlaying(preview: song("Neon Horizon", "Luma Drift", "Midnight Lakes", duration: 214, elapsed: 61, playing: true),
                               artwork: artwork(NSColor(red: 0.45, green: 0.2, blue: 0.85, alpha: 1), NSColor(red: 1, green: 0.45, blue: 0.3, alpha: 1), sun: NSColor(red: 1, green: 0.85, blue: 0.35, alpha: 1)))
        let songAPaused = NowPlaying(preview: song("Neon Horizon", "Luma Drift", "Midnight Lakes", duration: 214, elapsed: 64, playing: false),
                                     artwork: artwork(NSColor(red: 0.45, green: 0.2, blue: 0.85, alpha: 1), NSColor(red: 1, green: 0.45, blue: 0.3, alpha: 1), sun: NSColor(red: 1, green: 0.85, blue: 0.35, alpha: 1)))
        let songB = NowPlaying(preview: song("Paper Satellites", "The Quiet Arcade", "Orbit Café", duration: 187, elapsed: 3, playing: true),
                               artwork: artwork(NSColor(red: 0.1, green: 0.75, blue: 0.8, alpha: 1), NSColor(red: 0.15, green: 0.2, blue: 0.6, alpha: 1), sun: NSColor(red: 1, green: 0.45, blue: 0.65, alpha: 1)))

        let canvas = CGSize(width: 900, height: 300)
        func r(_ name: String, _ items: [ShelfItem], np: NowPlaying? = nil, _ c: (NotchViewModel) -> Void = { _ in }) {
            render(name, to: out, shelf: ShelfStore(preview: items), history: hist, np: np ?? none,
                   canvas: canvas, background: nil, configure: c)
        }

        // Jede Ablage-Stufe in allen Grundzuständen
        let stages: [(String, [ShelfItem])] = [
            ("0", []), ("1", [pdf]), ("2", [pdf, photo]), ("3", [pdf, photo, note]),
            ("4", [pdf, photo, note, link]), ("5", [pdf, photo, note, link, folder]),
            ("4b", [photo, note, link, folder]),
        ]
        for (n, items) in stages {
            r("closed-\(n)", items)
            r("peek-\(n)", items) { $0.isPeeking = true }
            r("drop-\(n)", items) { $0.isOpen = true; $0.isDropTargeted = true }
            r("open-\(n)", items) { $0.isOpen = true }
            r("history-\(n)", items) { $0.isOpen = true; $0.tab = .history }
        }
        let five = stages[5].1, rest = stages[6].1
        r("open-5-copied", five) { $0.isOpen = true; $0.flashedID = note.id }
        r("media-closed", rest, np: songA) { $0.showsMedia = true }
        r("media-open", rest, np: songA) { $0.showsMedia = true; $0.isMediaOpen = true }
        r("media-open-paused", rest, np: songAPaused) { $0.showsMedia = true; $0.isMediaOpen = true }
        r("media-open-next", rest, np: songB) { $0.showsMedia = true; $0.isMediaOpen = true }
        r("media-closed-next", rest, np: songB) { $0.showsMedia = true }
        r("media-closed-empty", [], np: songB) { $0.showsMedia = true }
    }
}

/// Ersetzt im Demo-Modus den Ablage-Ordner, damit nichts Echtes angefasst wird
enum DemoFiles {
    static var root: URL?
}
