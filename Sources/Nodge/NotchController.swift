import AppKit
import Combine
import SwiftUI

/// Randloses Panel über der Menüleiste. Wird nie zum aktiven Fenster,
/// damit die Tastatur bei der App bleibt, in der du gerade arbeitest.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isFloatingPanel = true
        // Nach isFloatingPanel setzen – das würde die Ebene sonst auf .floating zurücksetzen
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        appearance = NSAppearance(named: .darkAqua)
        acceptsMouseMovedEvents = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// macOS schiebt Fenster sonst unter die Menüleiste – die Island soll ganz oben sitzen
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Hosting-View, die Mausbewegungen ignoriert, solange die Island geschlossen ist,
/// und sie bei offener Island auf 40×/s drosselt. ProMotion liefert 120 Bewegungen/s,
/// und SwiftUI rechnet bei jeder einzelnen das Layout neu (wegen der Hover-Effekte).
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var passive = true {
        didSet { if passive != oldValue { window?.acceptsMouseMovedEvents = !passive } }
    }

    private let minInterval: TimeInterval = 1.0 / 40.0
    private var lastDelivered: TimeInterval = 0
    private var pending: NSEvent?

    override func mouseMoved(with event: NSEvent) {
        guard !passive else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let wait = lastDelivered + minInterval - now
        if wait <= 0 {
            lastDelivered = now
            pending = nil
            super.mouseMoved(with: event)
        } else {
            // Nur die letzte Bewegung zählt – sie wird nachgeliefert, damit Hover korrekt endet
            let scheduled = pending != nil
            pending = event
            guard !scheduled else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                self?.deliverPending()
            }
        }
    }

    private func deliverPending() {
        guard let event = pending, !passive else { return }
        pending = nil
        lastDelivered = ProcessInfo.processInfo.systemUptime
        super.mouseMoved(with: event)
    }
}

/// Positioniert die Island an der Notch und entscheidet anhand der Mausposition,
/// wann sie aufgeht, offen bleibt und wieder zugeht.
final class NotchController {
    let vm = NotchViewModel()
    private let shelf: ShelfStore
    private let nowPlaying: NowPlaying
    private var mediaObserver: AnyCancellable?
    private let panel = NotchPanel()
    private let dragPasteboard = NSPasteboard(name: .drag)
    /// Offen: Platz für Island + Schatten. Geschlossen: nur so gross wie die kleine Island.
    /// Wichtig fürs Energiesparen: macOS schickt dem (durchsichtigen) Fenster jede Mausbewegung
    /// in seinem Bereich – ein grosses Fenster würde bei Arbeit in Tab-/Adressleiste ständig rechnen.
    private let expandedWindowSize = CGSize(width: 820, height: 320)
    private let closedWindowSize = CGSize(width: 400, height: 60)
    private var windowExpanded = false
    private var hostingView: NotchHostingView<NotchView>?
    private var shrinkGeneration = 0

    private var screen: NSScreen
    /// Langsamer Timer (10×/s): schaut nur, ob die Maus in die Nähe der Notch kommt.
    /// Jede einzelne Mausbewegung zu verfolgen würde Nodge >100×/s wecken.
    private var slowTimer: Timer?
    /// Schneller Timer – nur solange die Maus direkt an der Island ist, sie offen ist
    /// oder die Maustaste gedrückt ist. 20×/s geschlossen, 30×/s offen.
    private var fastTimer: Timer?
    private var fastInterval: TimeInterval = 0
    private var eventMonitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var mouseIgnored = true

    private var hoverSince: Date?
    private var outsideSince: Date?
    private var wasPressed = false
    private var pressStartedInside = false
    private var dragCountAtPress = 0
    private var menuDepth = 0
    /// Nach dem Ablegen per Tastenkürzel kurz offen bleiben, auch ohne Maus
    private var holdOpenUntil = Date.distantPast

    init(shelf: ShelfStore, history: ClipboardHistory, nowPlaying: NowPlaying) {
        self.shelf = shelf
        self.nowPlaying = nowPlaying
        self.screen = NSScreen.main ?? NSScreen.screens[0]

        let host = NotchHostingView(rootView: NotchView(vm: vm, shelf: shelf, history: history, nowPlaying: nowPlaying))
        host.sizingOptions = []
        panel.contentView = host
        hostingView = host

        mediaObserver = nowPlaying.$isVisible.removeDuplicates().sink { [weak self] visible in
            guard let self else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                self.vm.showsMedia = visible
                if !visible { self.vm.isMediaOpen = false }
            }
        }

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.layout()
            self?.tick()
        })
        observers.append(nc.addObserver(forName: NSMenu.didBeginTrackingNotification,
                                        object: nil, queue: .main) { [weak self] _ in self?.menuDepth += 1 })
        observers.append(nc.addObserver(forName: NSMenu.didEndTrackingNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.menuDepth = max(0, (self?.menuDepth ?? 1) - 1)
        })
    }

    func show() {
        layout()
        panel.orderFrontRegardless()

        let slow = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.fastTimer == nil else { return }
            self.tick()
        }
        slow.tolerance = 0.04
        RunLoop.main.add(slow, forMode: .common)
        slowTimer = slow

        // Klicks sofort erkennen. Während die Taste gedrückt ist, übernimmt der schnelle Timer
        // (Drag-Ereignisse würden Nodge sonst bei jedem Textmarkieren >100×/s wecken).
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.tick() }) {
            eventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.tick()
            return event
        }) {
            eventMonitors.append(local)
        }
        tick()
    }

    // MARK: - Timer nur bei Bedarf

    private func setFastTimer(_ needed: Bool) {
        let interval = vm.isExpanded ? 1.0 / 30.0 : 1.0 / 20.0
        if needed {
            guard fastTimer == nil || fastInterval != interval else { return }
            fastTimer?.invalidate()
            let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
            t.tolerance = interval * 0.3
            RunLoop.main.add(t, forMode: .common)
            fastTimer = t
            fastInterval = interval
        } else if let t = fastTimer {
            t.invalidate()
            fastTimer = nil
        }
    }

    private func setMouseIgnored(_ ignored: Bool) {
        guard ignored != mouseIgnored else { return }
        mouseIgnored = ignored
        panel.ignoresMouseEvents = ignored
    }

    func toggle() {
        vm.isOpen ? close() : open()
    }

    /// Island kurz zeigen (z.B. nach dem Ablegen per Tastenkürzel)
    func showBriefly() {
        holdOpenUntil = Date().addingTimeInterval(1.6)
        vm.tab = .shelf
        open()
    }

    // MARK: - Layout

    private func layout() {
        let s = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        screen = s

        if s.safeAreaInsets.top > 0, let left = s.auxiliaryTopLeftArea, let right = s.auxiliaryTopRightArea {
            vm.notchSize = CGSize(width: s.frame.width - left.width - right.width, height: s.safeAreaInsets.top)
        } else {
            // Bildschirm ohne Notch: schwarze Pille in Menüleistenhöhe
            let menuBar = max(24, s.frame.maxY - s.visibleFrame.maxY)
            vm.notchSize = CGSize(width: 190, height: menuBar)
        }

        applyWindowSize()
    }

    private func applyWindowSize() {
        let size = windowExpanded ? expandedWindowSize : closedWindowSize
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2,
                              y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height),
                       display: true)
    }

    /// Vor dem Aufgehen sofort vergrössern; nach dem Schliessen (wenn die Animation fertig ist) verkleinern
    private func setWindowExpanded(_ expanded: Bool) {
        shrinkGeneration += 1
        if expanded {
            hostingView?.passive = false
            guard !windowExpanded else { return }
            windowExpanded = true
            applyWindowSize()
        } else {
            let generation = shrinkGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, generation == self.shrinkGeneration, !self.vm.isExpanded, self.windowExpanded else { return }
                self.windowExpanded = false
                self.hostingView?.passive = true
                self.applyWindowSize()
            }
        }
    }

    /// Zielrechteck der Island in Bildschirmkoordinaten
    private func islandRect() -> NSRect {
        let size = vm.islandSize(itemCount: shelf.items.count)
        return NSRect(x: screen.frame.midX - size.width / 2,
                      y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height + 2)
    }

    // MARK: - Maus-Logik

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        let now = Date()
        let rect = islandRect()

        if pressed && !wasPressed {
            dragCountAtPress = dragPasteboard.changeCount
            pressStartedInside = vm.isExpanded && rect.contains(mouse)
        }
        if !pressed && wasPressed {
            vm.isInternalDrag = false
            // Falls ein Element herausgezogen und dabei verschoben wurde
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.shelf.pruneMissing() }
        }
        wasPressed = pressed

        // Wird gerade Inhalt (Datei, Text, …) gezogen? Pasteboard nur bei gedrückter Taste fragen.
        let contentDrag = pressed && !vm.isInternalDrag && dragPasteboard.changeCount != dragCountAtPress
        if vm.isPeeking != (contentDrag && !vm.isExpanded) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { vm.isPeeking = contentDrag && !vm.isExpanded }
        }
        // Während das Musik-Feld offen ist, etwas hineinziehen → volle Ablage
        if vm.isMediaOpen && contentDrag && rect.contains(mouse) { open() }

        if !vm.isExpanded {
            setMouseIgnored(true)
            if rect.insetBy(dx: -6, dy: 0).contains(mouse) {
                if contentDrag {
                    open()
                } else if !pressed {
                    if let since = hoverSince {
                        if now.timeIntervalSince(since) > 0.08 {
                            // Rechts neben der Notch sitzt "Jetzt läuft" → kleines Musik-Feld
                            let rightOfNotch = mouse.x > screen.frame.midX + vm.notchSize.width / 2 - 2
                            if vm.showsMedia && rightOfNotch { openMedia() } else { open() }
                        }
                    } else {
                        hoverSince = now
                    }
                }
            } else {
                hoverSince = nil
            }
        } else {
            setMouseIgnored(!rect.contains(mouse))
            let keepOpen = rect.insetBy(dx: -14, dy: -14).contains(mouse)
                || menuDepth > 0
                || now < holdOpenUntil
                || (pressed && pressStartedInside)
            if keepOpen {
                outsideSince = nil
            } else if let since = outsideSince {
                if now.timeIntervalSince(since) > (contentDrag ? 0.12 : 0.28) { close() }
            } else {
                outsideSince = now
            }
        }

        // Schnell nachschauen nur, wenn gerade etwas passieren kann. Die Zone ist bewusst klein,
        // damit Arbeiten in Tab- und Adressleiste darunter den Timer nicht startet.
        let nearIsland = rect.insetBy(dx: -30, dy: -30).contains(mouse)
        setFastTimer(vm.isExpanded || pressed || nearIsland || vm.isPeeking || hoverSince != nil)
    }

    private func openMedia() {
        guard !vm.isExpanded else { return }
        setWindowExpanded(true)
        hoverSince = nil
        outsideSince = nil
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.74)) { vm.isMediaOpen = true }
        setFastTimer(true)
    }

    private func open() {
        guard !vm.isOpen else { return }
        setWindowExpanded(true)
        hoverSince = nil
        outsideSince = nil
        shelf.pruneMissing()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.76)) {
            vm.isPeeking = false
            vm.isMediaOpen = false
            vm.isOpen = true
        }
        setFastTimer(true)
    }

    private func close() {
        guard vm.isExpanded else { return }
        outsideSince = nil
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            vm.isOpen = false
            vm.isMediaOpen = false
            vm.isDropTargeted = false
        }
        setWindowExpanded(false)
    }
}
