import SwiftUI

enum Theme {
    static let accent = Color(red: 0.38, green: 0.68, blue: 1.0)
    static let card = Color.white.opacity(0.055)
    static let cardHover = Color.white.opacity(0.11)
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.45)
    static let openSpring = Animation.spring(response: 0.4, dampingFraction: 0.76)
}

struct NotchView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var history: ClipboardHistory
    @ObservedObject var nowPlaying: NowPlaying

    var body: some View {
        let size = vm.islandSize(itemCount: shelf.items.count)
        let shape = NotchShape(topRadius: vm.topRadius, bottomRadius: vm.bottomRadius)

        ZStack(alignment: .top) {
            if vm.isOpen {
                ExpandedView(vm: vm, shelf: shelf, history: history)
                    .frame(width: vm.openBody.width, height: vm.openBody.height)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.86, anchor: .top))
                            .animation(Theme.openSpring.delay(0.04)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            } else if vm.isMediaOpen {
                MediaPanel(vm: vm, nowPlaying: nowPlaying)
                    .frame(width: vm.bodySize(itemCount: shelf.items.count).width,
                           height: vm.bodySize(itemCount: shelf.items.count).height)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .top))
                            .animation(Theme.openSpring.delay(0.04)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            } else {
                ClosedView(vm: vm, shelf: shelf, nowPlaying: nowPlaying)
                    .frame(width: vm.bodySize(itemCount: shelf.items.count).width,
                           height: vm.bodySize(itemCount: shelf.items.count).height)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .overlay(
            shape.stroke(Theme.accent.opacity(vm.isDropTargeted ? 0.55 : 0), lineWidth: 1.5)
        )
        .compositingGroup()
        .shadow(color: .black.opacity(vm.isExpanded ? 0.55 : 0), radius: 22, y: 10)
        .scaleEffect(vm.isDropTargeted ? 1.015 : 1, anchor: .top)
        .modifier(IslandDropTarget(vm: vm, shelf: shelf))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Geschlossen

/// Kleine "Live-Aktivität" links und rechts der Notch
private struct ClosedView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var nowPlaying: NowPlaying

    var body: some View {
        HStack(spacing: 0) {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, vm.isPeeking ? 14 : 11)
        .padding(.bottom, vm.isPeeking ? 4 : 0)
    }

    @ViewBuilder private var leading: some View {
        if vm.isPeeking {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.accent)
                .transition(.scale.combined(with: .opacity))
        } else if shelf.importing > 0 {
            ProgressView().controlSize(.mini).tint(.white)
        } else if vm.showsMedia {
            // Links: Ablage-Zähler, sonst Albumcover
            if !shelf.items.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "tray.full.fill").font(.system(size: 10, weight: .semibold))
                    Text("\(shelf.items.count)")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                }
                .foregroundColor(.white.opacity(0.85))
                .transition(.scale.combined(with: .opacity))
            } else {
                Artwork(image: nowPlaying.artwork, bundleID: nowPlaying.info?.bundleID, size: 20, radius: 5)
                    .transition(.scale.combined(with: .opacity))
            }
        } else if !shelf.items.isEmpty {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder private var trailing: some View {
        if vm.isPeeking {
            PulsingDot().transition(.scale.combined(with: .opacity))
        } else if vm.showsMedia {
            // Rechts: Logo der App, die gerade spielt
            HStack(spacing: 5) {
                EqualizerBars(isPlaying: nowPlaying.info?.isPlaying ?? false)
                AppLogo(bundleID: nowPlaying.info?.bundleID, size: 18)
                    .opacity(nowPlaying.info?.isPlaying == true ? 1 : 0.55)
            }
            .transition(.scale.combined(with: .opacity))
        } else if !shelf.items.isEmpty {
            Text("\(shelf.items.count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText())
                .transition(.scale.combined(with: .opacity))
        }
    }
}

private struct PulsingDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 7, height: 7)
            .scaleEffect(on ? 1.25 : 0.75)
            .opacity(on ? 1 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

// MARK: - Geöffnet

private struct ExpandedView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var history: ClipboardHistory
    @ObservedObject private var settings = AppSettings.shared
    @Namespace private var tabNamespace

    private let hPadding: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: vm.notchSize.height)
                .padding(.bottom, 8)

            ZStack {
                switch vm.tab {
                case .shelf:
                    ShelfView(vm: vm, shelf: shelf)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                case .history:
                    HistoryView(vm: vm, shelf: shelf, history: history)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .padding(.horizontal, hPadding)
        .padding(.bottom, 14)
    }

    /// Kopfzeile: links Tabs, Mitte frei (dort sitzt die Kamera-Notch), rechts Aktionen
    private var header: some View {
        let side = (vm.openBody.width - hPadding * 2 - vm.notchSize.width - 16) / 2
        return HStack(spacing: 0) {
            HStack(spacing: 2) {
                tabButton(.shelf, icon: "tray.full.fill", title: "Ablage", badge: shelf.items.count)
                tabButton(.history, icon: "clock.fill", title: "Verlauf", badge: nil)
            }
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .frame(width: side, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if vm.tab == .shelf {
                    if !shelf.items.isEmpty {
                        ClearAllButton(help: "Alles aus der Ablage löschen") { shelf.removeAll() }
                            .transition(.scale.combined(with: .opacity))
                    }
                    IconButton(systemName: "doc.on.clipboard", help: "Aus Zwischenablage einfügen") {
                        shelf.addFromPasteboard()
                    }
                } else if !history.entries.isEmpty {
                    ClearAllButton(help: "Ganzen Verlauf löschen") { history.removeAll() }
                        .transition(.scale.combined(with: .opacity))
                }
                moreMenu
            }
            .frame(width: side, alignment: .trailing)
        }
    }

    private func tabButton(_ tab: NotchViewModel.Tab, icon: String, title: String, badge: Int?) -> some View {
        let selected = vm.tab == tab
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { vm.tab = tab }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11.5, weight: .semibold, design: .rounded))
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(selected ? 0.2 : 0.1)))
                        .contentTransition(.numericText())
                }
            }
            .foregroundColor(selected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background {
                if selected {
                    Capsule().fill(Color.white.opacity(0.14))
                        .matchedGeometryEffect(id: "tab", in: tabNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var moreMenu: some View {
        // Snapshot: NSMenu kann ImageRenderer nicht zeichnen → nur das Symbol
        if Snapshot.active { moreMenuLabel } else { realMoreMenu }
    }

    private var moreMenuLabel: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white.opacity(0.7))
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.white.opacity(0.08)))
            .contentShape(Circle())
    }

    private var realMoreMenu: some View {
        Menu {
            if vm.tab == .shelf {
                Button("Ablage leeren") { shelf.removeAll() }.disabled(shelf.items.isEmpty)
                Button("Ablage-Ordner im Finder zeigen") { NSWorkspace.shared.open(AppPaths.files) }
            } else {
                Button("Verlauf leeren") { history.removeAll() }.disabled(history.entries.isEmpty)
            }
            Divider()
            Toggle("Zwischenablage aufzeichnen", isOn: $settings.recordClipboard)
            Toggle("Jetzt läuft anzeigen", isOn: $settings.showNowPlaying)
            Toggle("Beim Login starten", isOn: Binding(get: { settings.launchAtLogin },
                                                      set: { settings.launchAtLogin = $0 }))
            Divider()
            Button("Nodge beenden") { NSApp.terminate(nil) }
        } label: {
            moreMenuLabel
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Drop

/// onDrop erscheint im Snapshot (ImageRenderer) als gelber AppKit-Platzhalter → dort weglassen
private struct IslandDropTarget: ViewModifier {
    let vm: NotchViewModel
    let shelf: ShelfStore

    func body(content: Content) -> some View {
        if Snapshot.active {
            content
        } else {
            content.onDrop(of: ShelfStore.acceptedTypes, delegate: IslandDropDelegate(vm: vm, shelf: shelf))
        }
    }
}

struct IslandDropDelegate: DropDelegate {
    let vm: NotchViewModel
    let shelf: ShelfStore

    func validateDrop(info: DropInfo) -> Bool {
        !vm.isInternalDrag && info.hasItemsConforming(to: ShelfStore.acceptedTypes)
    }

    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            vm.isDropTargeted = true
            vm.tab = .shelf
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.isDropTargeted = false }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: vm.isInternalDrag ? .forbidden : .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.isDropTargeted = false }
        guard !vm.isInternalDrag else { return false }
        shelf.add(providers: info.itemProviders(for: ShelfStore.acceptedTypes))
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        return true
    }
}
