<div align="center">

<img src="docs/screenshot-closed.png" width="420" alt="Nodge an der Notch">

# Nodge

**Eine Dynamic Island für die MacBook-Notch.**
Ablage für Dateien, Bilder, Texte und Links · Zwischenablage-Verlauf · Jetzt läuft

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift 5.8](https://img.shields.io/badge/Swift-5.8-F05138?logo=swift&logoColor=white)
![Universal](https://img.shields.io/badge/Apple%20Chip%20%2B%20Intel-Universal-6E56CF)
![Ohne Xcode](https://img.shields.io/badge/Build-ohne%20Xcode-2ea44f)

<img src="docs/demo.gif" width="760" alt="Demo: Dateien ablegen, Verlauf, Jetzt läuft">

<sub>Demo mit fiktiven Dateien und Songs · <a href="docs/demo.mp4">Video in voller Auflösung (MP4)</a></sub>

</div>

---

## Was ist Nodge?

Nodge macht aus der Kamera-Notch einen kleinen Zwischenspeicher, der immer da ist, aber nie im Weg.
Zieh etwas auf die Notch, und es liegt dort, bis du es wieder brauchst: über Programme, Spaces und Neustarts hinweg.
Fährst du mit der Maus nach oben, klappt die Island auf. Fährst du weg, schliesst sie sich wieder.

Nodge ist eine native SwiftUI/AppKit-App: kein Electron, kein Hintergrund-Polling, im geschlossenen Zustand praktisch 0 % CPU.

## Funktionen

<table>
<tr>
<td width="50%" valign="top">

### 🗂️ Ablage
Dateien, Ordner, Bilder, Texte und Links auf die Notch ziehen.
Die Island merkt schon beim Ziehen, dass etwas kommt, und zeigt „Loslassen zum Ablegen“.
Alles bleibt gespeichert, bis du es herausnimmst.

</td>
<td width="50%" valign="top">

<img src="docs/screenshot-drop.png" alt="Ablegen">

</td>
</tr>
<tr>
<td valign="top">

<img src="docs/screenshot-shelf.png" alt="Ablage mit Karten">

</td>
<td valign="top">

### 🃏 Karten
- **Klick**: in die Zwischenablage kopieren
- **Doppelklick**: öffnen (Text in TextEdit, Link im Browser)
- **Herausziehen**: in Finder, Mail, Browser … ablegen
- **Rechtsklick**: weitere Aktionen
- **Einfügen-Knopf**: aktuellen Inhalt der Zwischenablage ablegen

</td>
</tr>
<tr>
<td valign="top">

### 🕘 Verlauf
Alles, was du mit <kbd>⌘</kbd><kbd>C</kbd> kopierst, landet automatisch im Tab „Verlauf“, samt App und Zeitpunkt.
Inhalte aus Passwort-Managern werden nie gespeichert.

</td>
<td valign="top">

<img src="docs/screenshot-history.png" alt="Zwischenablage-Verlauf">

</td>
</tr>
<tr>
<td valign="top">

<img src="docs/screenshot-media.png" alt="Jetzt läuft">

</td>
<td valign="top">

### 🎵 Jetzt läuft
Spielt Musik oder ein Video (Musik, Spotify, Browser …), zeigt die Notch einen Equalizer und das App-Logo.
Maus rechts neben die Notch: Cover, Titel, Pause, Weiter, Zurück und Spulen.

</td>
</tr>
</table>

### ⌨️ Tastenkürzel

| Kürzel | Was passiert |
|---|---|
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>Leertaste</kbd> | **Auswahl ablegen**: im Finder die markierten Dateien, sonst den markierten Text |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>↑</kbd> | **Ausschneiden** (im Finder): Die Datei bleibt liegen, bis du sie aus der Island an einen anderen Ort ziehst, dann wird sie verschoben ✂️ |

### ⚙️ Einstellungen

Im •••-Menü der Island oder über das Symbol in der Menüleiste:
Zwischenablage aufzeichnen · Jetzt läuft anzeigen · Beim Login starten · Ablage-Ordner im Finder zeigen · Ablage bzw. Verlauf leeren
(Papierkorb oben rechts: zweimal klicken).

## Auf einen Blick

| Aktion | Was passiert |
|---|---|
| Maus auf die Notch | Island geht auf, schliesst sich beim Wegfahren |
| Datei/Text/Bild auf die Notch ziehen | Notch zeigt „hier ablegen“, geht auf, loslassen = abgelegt |
| Klick / Doppelklick auf Karte | Kopieren / Öffnen |
| Karte herausziehen | In Finder, Mail, Browser … ablegen |
| Tab „Verlauf“ | Alles, was mit ⌘C kopiert wurde |
| Maus rechts neben die Notch | Jetzt läuft mit Steuerung |

Funktioniert auch auf Macs **ohne** Notch: Die Island sitzt dann oben in der Mitte des Bildschirms.

## Installation

Voraussetzung: **macOS 13 (Ventura) oder neuer** und die Xcode Command Line Tools (`xcode-select --install`). Xcode selbst ist nicht nötig.

```bash
git clone <repo-url> Nodge
cd Nodge
./build.sh --install
```

Danach erscheint oben in der Menüleiste ein Ablage-Symbol, und Nodge läuft.

```bash
./build.sh            # baut build/Nodge.app (Universal: Apple-Chip + Intel)
./build.sh --run      # bauen und starten
./build.sh --install  # nach /Applications kopieren und starten (nötig für „Beim Login starten“)
./build.sh --share    # ~/Desktop/Nodge.zip zum Weitergeben (App + Anleitung.txt)
```

### Erster Start

Die App ist nur ad-hoc signiert und nicht notarisiert. Beim ersten Öffnen deshalb einmal unter
**Systemeinstellungen → Datenschutz & Sicherheit → „Trotzdem öffnen“** freigeben.

Für die Tastenkürzel fragt macOS beim ersten Benutzen evtl. nach:
- „Nodge möchte Finder steuern“ → OK
- **Bedienungshilfen** → Nodge in den Systemeinstellungen einschalten, danach das Kürzel nochmals drücken

## Daten & Privatsphäre

- Alles bleibt lokal in `~/Library/Application Support/Nodge/`, nichts verlässt den Mac.
- Abgelegte Dateien werden als APFS-Clone kopiert: sofort und ohne zusätzlichen Speicherplatz.
- Der Verlauf speichert maximal 60 Einträge und ignoriert als vertraulich markierte Inhalte (z. B. aus 1Password).
- Aufzeichnung des Verlaufs und „Jetzt läuft“ lassen sich jederzeit ausschalten.

## Projektaufbau

```
Sources/Nodge/
├── main.swift               App-Start, Menüleisten-Symbol
├── NotchController.swift    Fenster über der Notch, Hover, Öffnen/Schliessen
├── NotchViewModel.swift     Zustand und Grössen der Island
├── ShelfStore.swift         Ablage (Dateien, Texte, Links), Speichern, Drag & Drop
├── ClipboardHistory.swift   Zwischenablage-Verlauf
├── NowPlaying.swift         Jetzt läuft (über Helper/NowPlayingHelper.m)
├── QuickDrop.swift          Tastenkürzel ⌘⇧Leertaste und ⌘⇧↑
├── Snapshot.swift           Offscreen-Rendering für Tests und Demo
└── Views/                   SwiftUI-Oberfläche (Island, Karten, Verlauf, Medien)
Helper/                      Jetzt-läuft-Helfer (läuft im systemeigenen perl)
Resources/                   Info.plist, App-Symbol, Anleitung.txt
tools/make_demo.py           erzeugt Demo-Video und Screenshots dieser README
```

## Entwicklung

Gebaut wird direkt mit `swiftc` (SwiftPM braucht mit den reinen Command Line Tools teils Xcode).

**Zustände prüfen ohne Bildschirmaufnahme-Rechte:**

```bash
NODGE_SNAPSHOT=/pfad build/Nodge.app/Contents/MacOS/Nodge
```

rendert alle Island-Zustände als PNG und beendet sich.

**Demo-Video und Screenshots neu erzeugen** (braucht Python 3 mit Pillow und ffmpeg):

```bash
./build.sh
python3 tools/make_demo.py   # → docs/demo.mp4, docs/demo.gif, docs/screenshot-*.png
```

Das Skript erzeugt fiktive Beispieldateien, lässt Nodge jeden Zustand offscreen rendern
(`NODGE_DEMO`) und setzt daraus Schreibtisch, Mauszeiger, Untertitel und Übergänge zusammen.
Alle Dateien, Texte und Songs im Demo sind erfunden.
