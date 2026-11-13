import SwiftUI

/// Kleines Feld, das beim Hover über "Jetzt läuft" aufklappt
struct MediaPanel: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var nowPlaying: NowPlaying

    var body: some View {
        let info = nowPlaying.info
        VStack(spacing: 0) {
            // Obere Zeile neben der Kamera-Notch: links App-Name, rechts Logo
            HStack(spacing: 6) {
                AppLogo(bundleID: info?.bundleID, size: 14)
                Text(appName(info?.appPath))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.secondary)
                    .lineLimit(1)
                Spacer(minLength: vm.notchSize.width + 16)
                EqualizerBars(isPlaying: info?.isPlaying ?? false)
            }
            .padding(.horizontal, 16)
            .frame(height: vm.notchSize.height)

            HStack(spacing: 12) {
                Button { nowPlaying.openPlayerApp() } label: {
                    Artwork(image: nowPlaying.artwork, bundleID: info?.bundleID, size: 48, radius: 11)
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .help("App öffnen")

                VStack(alignment: .leading, spacing: 2) {
                    SongTitleButton(title: info?.title ?? "", artist: info?.artist ?? "",
                                    appName: appName(info?.appPath)) {
                        nowPlaying.openPlayerApp()
                    }
                    if let info, info.duration > 0 {
                        ProgressLine(info: info) { nowPlaying.seek(to: $0) }.padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 2) {
                    MediaButton(systemName: "backward.fill", size: 13, help: "Vorheriger") {
                        nowPlaying.send(.previous)
                    }
                    MediaButton(systemName: info?.isPlaying == true ? "pause.fill" : "play.fill",
                                size: 19, help: info?.isPlaying == true ? "Pausieren" : "Abspielen") {
                        nowPlaying.send(.togglePlayPause)
                    }
                    MediaButton(systemName: "forward.fill", size: 13, help: "Nächster") {
                        nowPlaying.send(.next)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func appName(_ path: String?) -> String {
        guard let path else { return "Jetzt läuft" }
        return FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }
}

/// Fortschrittsbalken zum Spulen: ziehen oder an eine Stelle klicken
private struct ProgressLine: View {
    let info: NowPlayingInfo
    let onSeek: (Double) -> Void
    @State private var hovering = false
    /// Während des Ziehens: gewählte Position (0…1)
    @State private var scrub: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let live = info.duration > 0 ? info.position(at: context.date) / info.duration : 0
            let fraction = min(1, max(0, scrub ?? live))
            let position = fraction * info.duration
            let active = hovering || scrub != nil

            HStack(spacing: 6) {
                Text(format(position))
                    .frame(minWidth: 26, alignment: .leading)
                GeometryReader { geo in
                    let width = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                            .frame(height: active ? 6 : 3)
                        Capsule().fill(scrub != nil ? Theme.accent : Color.white.opacity(0.85))
                            .frame(width: max(active ? 6 : 3, width * fraction), height: active ? 6 : 3)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 11, height: 11)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .offset(x: width * fraction - 5.5)
                            .scaleEffect(active ? 1 : 0.2)
                            .opacity(active ? 1 : 0)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                scrub = min(1, max(0, value.location.x / max(width, 1)))
                            }
                            .onEnded { value in
                                let f = min(1, max(0, value.location.x / max(width, 1)))
                                onSeek(f * info.duration)
                                // kurz halten, bis das System die neue Position meldet
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.easeOut(duration: 0.15)) { scrub = nil }
                                }
                            }
                    )
                }
                .frame(height: 14)
                Text("-" + format(max(0, info.duration - position)))
                    .frame(minWidth: 30, alignment: .trailing)
            }
            .font(.system(size: 8.5, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundColor(scrub != nil ? .white : Theme.secondary)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: active)
        }
        .onHover { hovering = $0 }
        .help("Ziehen oder klicken zum Spulen")
    }

    private func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct MediaButton: View {
    let systemName: String
    let size: CGFloat
    let help: String
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button {
            action()
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pressed = false }
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.14 : 0)))
                .scaleEffect(pressed ? 0.82 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Albumcover, sonst App-Logo als Ersatz
struct Artwork: View {
    let image: NSImage?
    let bundleID: String?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    AppLogo(bundleID: bundleID, size: size * 0.6)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct AppLogo: View {
    let bundleID: String?
    let size: CGFloat

    var body: some View {
        if let icon = AppIcons.icon(for: bundleID) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: size * 0.7, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
        }
    }
}

/// Drei tanzende Balken wie beim iPhone; flach, wenn pausiert.
/// Läuft über Core Animation im Render-Server von macOS – kostet Nodge praktisch keine CPU.
/// (Eine SwiftUI-repeatForever-Animation würde die Ansicht ständig neu zeichnen.)
struct EqualizerBars: View {
    let isPlaying: Bool

    var body: some View {
        Group {
            if Snapshot.active {
                StaticBars(isPlaying: isPlaying)
            } else {
                EqualizerLayerView(isPlaying: isPlaying, color: NSColor(Theme.accent))
            }
        }
        .frame(width: 12, height: 12)
    }
}

/// Nur für Snapshots (ImageRenderer kann keine AppKit-Views zeichnen)
private struct StaticBars: View {
    let isPlaying: Bool
    private let heights: [CGFloat] = [0.7, 1, 0.5]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(Theme.accent)
                    .frame(width: 2.5, height: 12 * (isPlaying ? heights[i] : 0.22))
            }
        }
    }
}

private struct EqualizerLayerView: NSViewRepresentable {
    let isPlaying: Bool
    let color: NSColor

    func makeNSView(context: Context) -> EqualizerNSView { EqualizerNSView(color: color) }
    func updateNSView(_ view: EqualizerNSView, context: Context) { view.setPlaying(isPlaying) }
}

final class EqualizerNSView: NSView {
    private let bars: [CALayer]
    private let durations: [CFTimeInterval] = [0.42, 0.33, 0.5]
    private let lows: [CGFloat] = [0.35, 0.55, 0.3]
    private let flat: CGFloat = 0.22
    private var playing: Bool?

    init(color: NSColor) {
        bars = (0..<3).map { _ in
            let bar = CALayer()
            bar.backgroundColor = color.cgColor
            bar.cornerRadius = 1.25
            return bar
        }
        super.init(frame: NSRect(x: 0, y: 0, width: 12, height: 12))
        wantsLayer = true
        bars.forEach { layer?.addSublayer($0) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let width: CGFloat = 2.5, gap: CGFloat = 2
        let startX = (bounds.width - (width * 3 + gap * 2)) / 2
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: 12)
            bar.position = CGPoint(x: startX + CGFloat(i) * (width + gap) + width / 2, y: bounds.midY)
        }
        CATransaction.commit()
    }

    func setPlaying(_ isPlaying: Bool) {
        guard isPlaying != playing else { return }
        playing = isPlaying
        for (i, bar) in bars.enumerated() {
            let current = (bar.presentation()?.value(forKeyPath: "transform.scale.y") as? CGFloat) ?? flat
            bar.removeAllAnimations()
            if isPlaying {
                let dance = CABasicAnimation(keyPath: "transform.scale.y")
                dance.fromValue = lows[i]
                dance.toValue = 1
                dance.duration = durations[i]
                dance.autoreverses = true
                dance.repeatCount = .infinity
                dance.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.transform = CATransform3DMakeScale(1, lows[i], 1)
                bar.add(dance, forKey: "dance")
            } else {
                let settle = CABasicAnimation(keyPath: "transform.scale.y")
                settle.fromValue = current
                settle.toValue = flat
                settle.duration = 0.25
                bar.transform = CATransform3DMakeScale(1, flat, 1)
                bar.add(settle, forKey: "settle")
            }
        }
    }
}

/// Songtitel + Künstler – Klick öffnet die App, die gerade spielt
private struct SongTitleButton: View {
    let title: String
    let artist: String
    let appName: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(hovering ? .white : Theme.primary)
                        .underline(hovering, color: .white.opacity(0.5))
                        .lineLimit(1)
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.secondary)
                        .opacity(hovering ? 1 : 0)
                        .offset(x: hovering ? 0 : -3)
                }
                Text(artist)
                    .font(.system(size: 11))
                    .foregroundColor(hovering ? .white.opacity(0.7) : Theme.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("\(appName) öffnen")
    }
}
