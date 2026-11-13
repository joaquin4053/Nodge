import SwiftUI

struct ShelfView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        ZStack {
            if shelf.items.isEmpty {
                EmptyHint(icon: "tray.and.arrow.down",
                          title: "Dateien, Bilder oder Text hierher ziehen",
                          subtitle: "oder Datei im Finder markieren und \(QuickDrop.shortcutLabel) drücken")
                    .opacity(vm.isDropTargeted ? 0 : 1)
            } else {
                CardRow {
                        ForEach(shelf.items) { item in
                            ShelfItemCard(item: item, vm: vm, shelf: shelf)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                }
                .opacity(vm.isDropTargeted ? 0.25 : 1)
                .blur(radius: vm.isDropTargeted ? 3 : 0)
            }

            if vm.isDropTargeted { DropOverlay() }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: vm.isDropTargeted)
    }
}

struct ShelfItemCard: View {
    let item: ShelfItem
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var shelf: ShelfStore
    @State private var hovering = false
    /// Einmal berechnet statt bei jedem Neuzeichnen (Festplattenzugriff, lange Texte)
    @State private var cachedTitle: String?
    @State private var cachedSubtitle: String?

    var body: some View {
        VStack(spacing: 5) {
            preview.frame(width: 52, height: 52)
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Theme.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 27, alignment: .top)
            Text(subtitle)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Theme.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.top, 11)
        .padding(.bottom, 8)
        .frame(width: 98, height: 122)
        .modifier(CardChrome(hovering: hovering, flashed: vm.flashedID == item.id))
        .overlay(alignment: .topLeading) {
            if item.isPendingMove { CutBadge().offset(x: 7, y: 7) }
        }
        .overlay { if !Snapshot.active { dragSource } }
        .overlay(alignment: .topTrailing) {
            if hovering {
                CardBadgeButton(systemName: "xmark",
                                help: item.isPendingMove ? "Aus der Island entfernen (Datei bleibt, wo sie ist)" : "Entfernen") {
                    shelf.remove(item)
                }
                .offset(x: 4, y: -4)
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { if $0 { hovering = true } }
        .onAppear(perform: cacheMeta)
        .help(helpText)
    }

    /// AppKit-Ebene für Klick, Doppelklick, Ziehen (kopieren oder verschieben) und Rechtsklick
    private var dragSource: some View {
        DragSource(
            writer: { shelf.pasteboardWriter(for: item) },
            dragImage: { dragImage },
            operations: shelf.dragOperations(for: item),
            onHover: { hovering = $0 },
            onClick: { shelf.copy(item); vm.flash(item.id) },
            onDoubleClick: { shelf.open(item) },
            onDragStart: { vm.isInternalDrag = true },
            onDragEnd: { shelf.dragEnded(item, operation: $0) },
            menu: { contextMenu }
        )
    }

    private var dragImage: NSImage? {
        let renderer = ImageRenderer(content:
            VStack(spacing: 4) {
                preview.frame(width: 52, height: 52)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .frame(maxWidth: 140)
            }
            .padding(6)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }

    private var contextMenu: NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: @escaping () -> Void) {
            menu.addItem(ClosureMenuItem(title: title, keyEquivalent: "", action: action))
        }
        switch item.kind {
        case .file:
            add("Öffnen") { shelf.open(item) }
            add("Im Finder zeigen") { shelf.revealInFinder(item) }
            add("Kopieren") { shelf.copy(item); vm.flash(item.id) }
        case .text:
            add("Kopieren") { shelf.copy(item); vm.flash(item.id) }
            add("In TextEdit öffnen") { shelf.open(item) }
        case .link:
            add("Im Browser öffnen") { shelf.open(item) }
            add("Link kopieren") { shelf.copy(item); vm.flash(item.id) }
        }
        menu.addItem(.separator())
        add(item.isPendingMove ? "Aus der Island entfernen" : "Entfernen") { shelf.remove(item) }
        return menu
    }

    // MARK: Inhalt

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case .file:
            if let url = shelf.fileURL(for: item) { FileThumbnail(url: url, size: 52) }
        case .text:
            TextPaper(text: item.text ?? "")
        case .link:
            ZStack {
                Circle().fill(LinearGradient(colors: [Theme.accent, Color(red: 0.2, green: 0.4, blue: 0.95)],
                                             startPoint: .top, endPoint: .bottom))
                Image(systemName: "link").font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
            }
            .frame(width: 44, height: 44)
            .shadow(color: Theme.accent.opacity(0.4), radius: 6, y: 2)
        }
    }

    private var title: String { cachedTitle ?? computeTitle() }
    private var subtitle: String { cachedSubtitle ?? computeSubtitle() }

    private func cacheMeta() {
        cachedTitle = computeTitle()
        cachedSubtitle = computeSubtitle()
    }

    private func computeTitle() -> String {
        switch item.kind {
        case .file: return item.fileName ?? "Datei"
        case .text:
            // Nur den Anfang anschauen – Texte können sehr lang sein
            let head = (item.text ?? "").prefix(400)
            let firstLine = head
                .split(whereSeparator: \.isNewline)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            return firstLine.trimmingCharacters(in: .whitespaces)
        case .link:
            return shelf.linkURL(for: item)?.host?.replacingOccurrences(of: "www.", with: "") ?? "Link"
        }
    }

    private func computeSubtitle() -> String {
        switch item.kind {
        case .file:
            guard let url = shelf.fileURL(for: item) else { return "" }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return item.isPendingMove ? "Ausgeschnitten · Ordner" : "Ordner"
            }
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            return item.isPendingMove ? "Ausgeschnitten · \(size)" : size
        case .text:
            let count = (item.text ?? "").count
            return "\(count.formatted()) Zeichen"
        case .link:
            return "Link"
        }
    }

    private var helpText: String {
        switch item.kind {
        case .file where item.isPendingMove:
            return "\(item.fileName ?? "")\nAusgeschnitten: liegt noch am Originalort.\nAn einen anderen Ort ziehen = verschieben"
        case .file: return "\(item.fileName ?? "")\nKlicken: kopieren · Doppelklick: öffnen · Ziehen: herausnehmen"
        case .text: return String((item.text ?? "").prefix(400)) + "\n\nKlicken: kopieren · Doppelklick: in TextEdit öffnen"
        case .link: return "\(item.text ?? "")\nKlicken: kopieren · Doppelklick: im Browser öffnen"
        }
    }
}

/// Mini-Dokument als Vorschau für Textschnipsel
struct TextPaper: View {
    let text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(white: 0.96))
            Text(String(text.prefix(260)))
                .font(.system(size: 5.2))
                .foregroundColor(.black.opacity(0.72))
                .lineSpacing(0.6)
                .padding(5)
        }
        .frame(width: 42, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
    }
}

/// Kleines Scheren-Abzeichen für ausgeschnittene Dateien
struct CutBadge: View {
    var body: some View {
        Image(systemName: "scissors")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Theme.accent))
            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
            .allowsHitTesting(false)
    }
}
