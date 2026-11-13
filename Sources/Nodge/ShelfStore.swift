import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case file, text, link }

    let id: UUID
    var kind: Kind
    var createdAt: Date
    /// Dateiname innerhalb von Files/<id>/ (nur bei .file)
    var fileName: String?
    /// Textinhalt oder Link-URL
    var text: String?
    /// Gesetzt bei "Ausschneiden" (⌘⇧↑): Die Datei bleibt am Originalort, bis sie
    /// aus der Island an einen anderen Ort gezogen wird – dann wird sie verschoben.
    var sourcePath: String?

    var isPendingMove: Bool { sourcePath != nil }
}

/// Die dauerhafte Ablage. Dateien werden nach Files/<id>/ kopiert
/// (auf APFS ein Clone: sofort und ohne zusätzlichen Speicherplatz).
final class ShelfStore: ObservableObject {
    enum Incoming {
        case file(URL)
        /// Nur ein Verweis aufs Original – wird beim Herausziehen verschoben
        case cutFile(URL)
        case text(String)
        case link(URL)
        case image(Data)
    }

    static let acceptedTypes: [UTType] = [.fileURL, .url, .image, .utf8PlainText, .plainText, .text]

    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var importing = 0

    private let indexURL = AppPaths.root.appendingPathComponent("shelf.json")
    private let ioQueue = DispatchQueue(label: "nodge.shelf.io", qos: .userInitiated)
    private let fm = FileManager.default

    private let persists: Bool

    init() {
        persists = true
        load()
        pruneMissing()
    }

    /// Nur für Vorschau-Snapshots: nichts wird gelesen oder gespeichert
    init(preview: [ShelfItem]) {
        persists = false
        items = preview
    }

    // MARK: - Zugriff

    func fileURL(for item: ShelfItem) -> URL? {
        guard item.kind == .file, let name = item.fileName else { return nil }
        if let source = item.sourcePath { return URL(fileURLWithPath: source) }
        return (DemoFiles.root ?? AppPaths.files)
            .appendingPathComponent(item.id.uuidString, isDirectory: true)
            .appendingPathComponent(name)
    }

    func linkURL(for item: ShelfItem) -> URL? {
        guard item.kind == .link, let s = item.text else { return nil }
        return URL(string: s)
    }

    // MARK: - Hinzufügen

    func add(providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        let group = DispatchGroup()
        let lock = NSLock()
        var results = [Incoming?](repeating: nil, count: providers.count)
        for (index, provider) in providers.enumerated() {
            group.enter()
            Self.load(provider) { incoming in
                lock.lock(); results[index] = incoming; lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) { self.ingest(results.compactMap { $0 }) }
    }

    func addFromPasteboard(_ pb: NSPasteboard = .general) {
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            ingest(urls.map { .file($0) })
        } else if let s = pb.string(forType: .string),
                  !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ingest([Self.webURL(from: s).map { .link($0) } ?? .text(s)])
        } else if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            ingest([.image(data)])
        } else {
            NSSound.beep()
        }
    }

    func ingest(_ incoming: [Incoming]) {
        guard !incoming.isEmpty else { return }
        importing += 1
        ioQueue.async {
            var newItems = incoming.compactMap { self.makeItem($0) }
            DispatchQueue.main.async {
                self.importing -= 1
                let alreadyCut = Set(self.items.compactMap(\.sourcePath))
                newItems.removeAll { $0.sourcePath.map(alreadyCut.contains) ?? false }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    self.items.insert(contentsOf: newItems, at: 0)
                }
                self.save()
            }
        }
    }

    private func makeItem(_ incoming: Incoming) -> ShelfItem? {
        let id = UUID()
        switch incoming {
        case .text(let s):
            return ShelfItem(id: id, kind: .text, createdAt: Date(), text: s)
        case .link(let url):
            return ShelfItem(id: id, kind: .link, createdAt: Date(), text: url.absoluteString)
        case .file(let src):
            return storeFile(id: id, name: src.lastPathComponent) { try self.fm.copyItem(at: src, to: $0) }
        case .cutFile(let src):
            return ShelfItem(id: id, kind: .file, createdAt: Date(), fileName: src.lastPathComponent,
                             sourcePath: src.standardizedFileURL.path)
        case .image(let data):
            guard let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { return nil }
            let stamp = Self.stampFormatter.string(from: Date())
            return storeFile(id: id, name: "Bild \(stamp).png") { try png.write(to: $0) }
        }
    }

    private func storeFile(id: UUID, name: String, write: (URL) throws -> Void) -> ShelfItem? {
        let dir = AppPaths.files.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try write(dir.appendingPathComponent(name))
            return ShelfItem(id: id, kind: .file, createdAt: Date(), fileName: name)
        } catch {
            NSLog("Nodge: Ablegen fehlgeschlagen: \(error)")
            try? fm.removeItem(at: dir)
            return nil
        }
    }

    // MARK: - Aktionen

    func remove(_ item: ShelfItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            items.removeAll { $0.id == item.id }
        }
        deleteStorage(of: item)
        save()
    }

    func removeAll() {
        let old = items
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { items.removeAll() }
        old.forEach(deleteStorage)
        save()
    }

    func copy(_ item: ShelfItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .file:
            if let url = fileURL(for: item) { pb.writeObjects([url as NSURL]) }
        case .text:
            pb.setString(item.text ?? "", forType: .string)
        case .link:
            pb.declareTypes([.string, .URL], owner: nil)
            pb.setString(item.text ?? "", forType: .string)
            pb.setString(item.text ?? "", forType: .URL)
        }
    }

    func open(_ item: ShelfItem) {
        switch item.kind {
        case .file:
            if let url = fileURL(for: item) { NSWorkspace.shared.open(url) }
        case .link:
            if let url = linkURL(for: item) { NSWorkspace.shared.open(url) }
        case .text:
            // Längere Texte bequem in TextEdit ansehen
            let url = fm.temporaryDirectory.appendingPathComponent("Nodge Text \(item.id.uuidString.prefix(6)).txt")
            try? (item.text ?? "").write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        }
    }

    func revealInFinder(_ item: ShelfItem) {
        if let url = fileURL(for: item) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func pasteboardWriter(for item: ShelfItem) -> NSPasteboardWriting? {
        switch item.kind {
        case .file: return fileURL(for: item) as NSURL?
        case .text: return (item.text ?? "") as NSString
        case .link: return linkURL(for: item) as NSURL?
        }
    }

    /// Ausgeschnittene Dateien werden verschoben, alles andere nur kopiert
    func dragOperations(for item: ShelfItem) -> NSDragOperation {
        item.isPendingMove ? [.move, .copy] : .copy
    }

    /// Nach dem Herausziehen: wurde eine ausgeschnittene Datei verschoben, ist ihr Job erledigt
    func dragEnded(_ item: ShelfItem, operation: NSDragOperation) {
        guard item.isPendingMove else { return }
        if operation.contains(.move) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { items.removeAll { $0.id == item.id } }
            save()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.pruneMissing() }
        }
    }

    /// Entfernt Einträge, deren Datei nicht mehr existiert (z.B. herausgezogen und verschoben).
    func pruneMissing() {
        let missing = items.filter { item in
            guard let url = fileURL(for: item) else { return false }
            return !fm.fileExists(atPath: url.path)
        }
        guard !missing.isEmpty else { return }
        let ids = Set(missing.map(\.id))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { items.removeAll { ids.contains($0.id) } }
        missing.forEach(deleteStorage)
        save()
    }

    // MARK: - Persistenz

    private func deleteStorage(of item: ShelfItem) {
        guard item.kind == .file, !item.isPendingMove else { return }
        try? fm.removeItem(at: AppPaths.files.appendingPathComponent(item.id.uuidString, isDirectory: true))
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard persists else { return }
        let snapshot = items
        ioQueue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: self.indexURL, options: .atomic)
            }
        }
    }

    // MARK: - Helfer

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'um' HH.mm.ss"
        return f
    }()

    static func webURL(from string: String) -> URL? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.contains(where: \.isWhitespace),
              let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let url = item as? URL { return url }
        if let s = item as? String { return URL(string: s) }
        return nil
    }

    /// Reihenfolge: Datei → Bild → Link → Text
    private static func load(_ p: NSItemProvider, completion: @escaping (Incoming?) -> Void) {
        func has(_ type: UTType) -> Bool { p.hasItemConformingToTypeIdentifier(type.identifier) }

        if has(.fileURL) {
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                completion(url(from: item).map { .file($0) })
            }
        } else if has(.image) {
            p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                completion(data.map { .image($0) })
            }
        } else if has(.url) {
            p.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                completion(url(from: item).map { .link($0) })
            }
        } else if p.canLoadObject(ofClass: NSString.self) {
            _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                guard let s = obj as? String, !s.isEmpty else { return completion(nil) }
                completion(webURL(from: s).map { .link($0) } ?? .text(s))
            }
        } else {
            completion(nil)
        }
    }
}
