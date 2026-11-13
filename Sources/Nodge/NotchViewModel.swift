import SwiftUI

final class NotchViewModel: ObservableObject {
    enum Tab { case shelf, history }

    @Published var isOpen = false
    /// Kleines "Jetzt läuft"-Feld (Hover über die rechte Seite)
    @Published var isMediaOpen = false
    /// Es läuft gerade Musik/Video → Logo rechts neben der Notch
    @Published var showsMedia = false
    /// Irgendwo auf dem Bildschirm wird gerade etwas gezogen → Island signalisiert "hier ablegen"
    @Published var isPeeking = false
    @Published var isDropTargeted = false
    @Published var tab: Tab = .shelf
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var flashedID: UUID?

    /// Ein Element wird gerade aus der Island herausgezogen (nicht wieder sich selbst ablegen)
    var isInternalDrag = false

    let openBody = CGSize(width: 640, height: 180)
    private let liveExtension: CGFloat = 34
    private let mediaExtension: CGFloat = 46
    let mediaPanelExtension: CGFloat = 140
    let mediaPanelHeight: CGFloat = 72
    private let peekExtension: CGFloat = 46

    var isExpanded: Bool { isOpen || isMediaOpen }
    var topRadius: CGFloat { isOpen ? 14 : (isMediaOpen ? 12 : 6) }
    var bottomRadius: CGFloat { isOpen ? 30 : (isMediaOpen ? 26 : (isPeeking ? 14 : 10)) }

    /// Grösse des schwarzen Körpers (ohne die nach aussen geschwungenen oberen Ecken)
    func bodySize(itemCount: Int) -> CGSize {
        if isOpen { return openBody }
        if isMediaOpen {
            return CGSize(width: notchSize.width + mediaPanelExtension * 2,
                          height: notchSize.height + mediaPanelHeight)
        }
        if isPeeking {
            return CGSize(width: notchSize.width + peekExtension * 2, height: notchSize.height + 8)
        }
        if showsMedia {
            return CGSize(width: notchSize.width + mediaExtension * 2, height: notchSize.height)
        }
        if itemCount > 0 {
            return CGSize(width: notchSize.width + liveExtension * 2, height: notchSize.height)
        }
        return notchSize
    }

    func islandSize(itemCount: Int) -> CGSize {
        let body = bodySize(itemCount: itemCount)
        return CGSize(width: body.width + topRadius * 2, height: body.height)
    }

    func flash(_ id: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { flashedID = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard self?.flashedID == id else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.flashedID = nil }
        }
    }
}
