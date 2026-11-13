import AppKit
import SwiftUI

/// AppKit-Drag für Karten. SwiftUI's onDrag erlaubt nur "Kopieren" – hier können wir
/// dem Ziel (z.B. Finder) "Verschieben" anbieten und erfahren, was am Ende passiert ist.
/// Übernimmt auch Klick, Doppelklick, Hover und Rechtsklick-Menü der Karte.
struct DragSource: NSViewRepresentable {
    var writer: () -> NSPasteboardWriting?
    var dragImage: () -> NSImage?
    var operations: NSDragOperation
    var onHover: (Bool) -> Void
    var onClick: () -> Void
    var onDoubleClick: () -> Void
    var onDragStart: () -> Void
    var onDragEnd: (NSDragOperation) -> Void
    var menu: () -> NSMenu

    func makeNSView(context: Context) -> DragSourceNSView { DragSourceNSView() }

    func updateNSView(_ view: DragSourceNSView, context: Context) {
        view.config = self
    }
}

final class DragSourceNSView: NSView, NSDraggingSource {
    var config: DragSource?
    private var mouseDownEvent: NSEvent?
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { config?.onHover(true) }
    override func mouseExited(with event: NSEvent) { config?.onHover(false) }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        dragging = false
        if event.clickCount == 2 { config?.onDoubleClick() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let down = mouseDownEvent, let config else { return }
        let start = down.locationInWindow, now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) > 4, let writer = config.writer() else { return }
        dragging = true

        let item = NSDraggingItem(pasteboardWriter: writer)
        let image = config.dragImage() ?? NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
        let size = image.size
        let p = convert(down.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: p.x - size.width / 2, y: p.y - size.height / 2,
                                     width: size.width, height: size.height),
                              contents: image)
        config.onDragStart()
        let session = beginDraggingSession(with: [item], event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        if !dragging && event.clickCount == 1 { config?.onClick() }
    }

    override func menu(for event: NSEvent) -> NSMenu? { config?.menu() }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? (config?.operations ?? .copy) : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        config?.onDragEnd(operation)
    }
}
