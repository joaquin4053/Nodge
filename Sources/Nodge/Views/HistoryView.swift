import SwiftUI

struct HistoryView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var history: ClipboardHistory
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        if !settings.recordClipboard && history.entries.isEmpty {
            VStack(spacing: 8) {
                EmptyHint(icon: "pause.circle",
                          title: "Verlauf ist pausiert",
                          subtitle: "Kopiertes wird gerade nicht gespeichert")
                    .overlay(alignment: .bottom) {
                        Button("Aufzeichnen") { settings.recordClipboard = true }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .padding(.bottom, 10)
                    }
            }
        } else if history.entries.isEmpty {
            EmptyHint(icon: "doc.on.doc",
                      title: "Noch nichts kopiert",
                      subtitle: "Alles, was du mit ⌘C kopierst, erscheint automatisch hier")
        } else {
            CardRow {
                    ForEach(history.entries) { entry in
                        HistoryCard(entry: entry, vm: vm, shelf: shelf, history: history)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
            }
        }
    }
}

struct HistoryCard: View {
    let entry: ClipEntry
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var history: ClipboardHistory
    @State private var hovering = false

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "de_CH")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: 5) {
                if let icon = AppIcons.icon(for: entry.appBundleID) {
                    Image(nsImage: icon).resizable().frame(width: 13, height: 13)
                }
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Self.relative.localizedString(for: entry.date, relativeTo: context.date))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if entry.kind == .text {
                    Text("\((entry.text ?? "").count.formatted())")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
        }
        .padding(10)
        .frame(width: 148, height: 122)
        .modifier(CardChrome(hovering: hovering, flashed: vm.flashedID == entry.id))
        .overlay(alignment: .topTrailing) {
            if hovering {
                HStack(spacing: 4) {
                    CardBadgeButton(systemName: "tray.and.arrow.down.fill", help: "In Ablage legen", tint: Theme.accent) {
                        history.moveToShelf(entry, shelf: shelf)
                        vm.flash(entry.id)
                    }
                    CardBadgeButton(systemName: "xmark", help: "Entfernen") { history.remove(entry) }
                }
                .offset(x: 4, y: -4)
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .onDrag {
            vm.isInternalDrag = true
            return history.dragProvider(for: entry)
        }
        .onTapGesture {
            history.copy(entry)
            vm.flash(entry.id)
        }
        .contextMenu {
            Button("Kopieren") { history.copy(entry); vm.flash(entry.id) }
            Button("In Ablage legen") { history.moveToShelf(entry, shelf: shelf) }
            Divider()
            Button("Entfernen", role: .destructive) { history.remove(entry) }
        }
        .help(entry.kind == .text ? String((entry.text ?? "").prefix(400)) : "Bild – klicken zum Kopieren")
    }

    @ViewBuilder private var content: some View {
        switch entry.kind {
        case .text:
            Text((entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 10.5))
                .foregroundColor(.white.opacity(0.85))
                .lineSpacing(1.5)
                .lineLimit(5)
        case .image:
            if let url = history.imageURL(for: entry) {
                FileThumbnail(url: url, size: 80)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
