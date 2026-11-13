import AppKit
import QuickLookThumbnailing
import SwiftUI

struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(hovering ? 1 : 0.7))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.16 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Kleiner runder Knopf, der beim Hover über einer Karte erscheint
struct CardBadgeButton: View {
    let systemName: String
    let help: String
    var tint: Color = .white
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(tint)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color(white: hovering ? 0.38 : 0.26)))
                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }
}

/// Grüne Bestätigung, wenn etwas in die Zwischenablage kopiert wurde
struct CopiedOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.62))
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.green)
                Text("Kopiert")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .transition(.scale(scale: 0.85).combined(with: .opacity))
        .allowsHitTesting(false)
    }
}

/// Hintergrund und Hover-Verhalten aller Karten
struct CardChrome: ViewModifier {
    let hovering: Bool
    let flashed: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(hovering ? Theme.cardHover : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(hovering ? 0.1 : 0.04), lineWidth: 1)
            )
            .overlay { if flashed { CopiedOverlay() } }
            .scaleEffect(hovering ? 1.035 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Leerer Zustand mit gestrichelter Fläche
struct EmptyHint: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
            Text(title)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundColor(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .foregroundColor(.white.opacity(0.14))
        )
    }
}

/// Erscheint, während etwas über die Island gezogen wird
struct DropOverlay: View {
    @State private var phase: CGFloat = 0
    @State private var bounce = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.accent.opacity(0.14))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.6, dash: [7, 5], dashPhase: phase))
                .foregroundColor(Theme.accent.opacity(0.9))
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .offset(y: bounce ? 2 : -2)
                Text("Loslassen zum Ablegen")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = -24 }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { bounce = true }
        }
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

// MARK: - Vorschaubilder

/// Vorschaubilder über QuickLook. Jede Anfrage ist teuer (u.a. Sicherheitsfreigabe beim System),
/// deshalb wird auch "hat kein Vorschaubild" gemerkt, und gleichzeitige Anfragen werden gebündelt.
final class Thumbnails {
    static let shared = Thumbnails()
    private let cache = NSCache<NSString, NSImage>()
    private var noThumbnail = Set<String>()
    private var waiting: [String: [(NSImage) -> Void]] = [:]

    /// Bereits geladenes Vorschaubild (sofort, ohne Flackern beim Neuaufbau)
    func cached(_ url: URL, size: CGFloat) -> NSImage? {
        cache.object(forKey: "\(url.path)#\(Int(size))" as NSString)
    }

    func load(_ url: URL, size: CGFloat, completion: @escaping (NSImage) -> Void) {
        let key = "\(url.path)#\(Int(size))"
        if let cached = cache.object(forKey: key as NSString) { return completion(cached) }
        if noThumbnail.contains(key) { return }
        if waiting[key] != nil {
            waiting[key]?.append(completion)
            return
        }
        waiting[key] = [completion]

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            let image = rep?.nsImage
            DispatchQueue.main.async {
                guard let self else { return }
                let callbacks = self.waiting.removeValue(forKey: key) ?? []
                guard let image else {
                    self.noThumbnail.insert(key)
                    return
                }
                self.cache.setObject(image, forKey: key as NSString)
                callbacks.forEach { $0(image) }
            }
        }
    }
}

struct FileThumbnail: View {
    let url: URL
    let size: CGFloat
    @State private var thumbnail: NSImage?

    init(url: URL, size: CGFloat) {
        self.url = url
        self.size = size
        _thumbnail = State(initialValue: Thumbnails.shared.cached(url, size: size))
    }

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .onAppear { Thumbnails.shared.load(url, size: size) { thumbnail = $0 } }
    }
}

enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}

/// Horizontale Kartenreihe. Im Snapshot-Modus ohne ScrollView (ImageRenderer kann keine AppKit-Views).
struct CardRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if Snapshot.active {
            HStack(spacing: 8) { content() }
                .padding(.vertical, 4).padding(.horizontal, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { content() }
                    .padding(.vertical, 4).padding(.horizontal, 2)
            }
        }
    }
}

/// Papierkorb mit Sicherheitsabfrage: erster Klick → "Alle löschen?", zweiter Klick löscht.
/// Ohne zweiten Klick setzt er sich nach 3 Sekunden zurück.
struct ClearAllButton: View {
    let help: String
    let action: () -> Void
    @State private var confirming = false
    @State private var hovering = false

    var body: some View {
        Button {
            if confirming {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { confirming = false }
                action()
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { confirming = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { confirming = false }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: confirming ? "trash.fill" : "trash")
                    .font(.system(size: 10.5, weight: .semibold))
                if confirming {
                    Text("Alle löschen?")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .foregroundColor(confirming ? .white : .white.opacity(hovering ? 1 : 0.7))
            .padding(.horizontal, confirming ? 10 : 0)
            .frame(minWidth: 24, minHeight: 24)
            .background(
                Capsule().fill(confirming ? Color.red.opacity(0.85)
                                          : Color.white.opacity(hovering ? 0.16 : 0.08))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
