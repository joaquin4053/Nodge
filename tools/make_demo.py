#!/usr/bin/env python3
"""Erzeugt Demo-Video und Screenshots für die README – komplett mit fiktiven Daten.

Ablauf:
  1. Beispieldateien erzeugen (.tmp/demo/samples)
  2. Nodge im Demo-Modus starten → transparente Einzelbilder aller Zustände (.tmp/demo/frames)
  3. Bilder auf einen erfundenen Schreibtisch setzen, Mauszeiger + Untertitel animieren
  4. ffmpeg → docs/demo.mp4, docs/demo.gif, docs/screenshot-*.png

Braucht: ./build.sh (gebaute App), Python 3 mit Pillow, ffmpeg.
Aufruf:  python3 tools/make_demo.py
"""
import math
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
TMP = ROOT / ".tmp" / "demo"
SAMPLES = TMP / "samples"
FRAMES = TMP / "frames"
VIDEO_FRAMES = TMP / "video"
DOCS = ROOT / "docs"
APP_BIN = ROOT / "build" / "Nodge.app" / "Contents" / "MacOS" / "Nodge"

S = 2                     # Pixel pro Punkt
W, H = 900, 420           # Leinwand in Punkten
FPS = 30
NOTCH_X = W / 2

FONT = "/System/Library/Fonts/SFNS.ttf"
FONT_R = "/System/Library/Fonts/SFNSRounded.ttf"


def font(size, rounded=False, weight=600):
    f = ImageFont.truetype(FONT_R if rounded else FONT, int(size * S))
    try:  # variable Systemschrift: Gewicht und optische Grösse setzen
        values = []
        for axis in f.get_variation_axes():
            name = axis["name"].decode() if isinstance(axis["name"], bytes) else axis["name"]
            wanted = {"Weight": weight, "Optical Size": size}.get(name, axis["default"])
            values.append(max(axis["minimum"], min(axis["maximum"], wanted)))
        f.set_variation_by_axes(values)
    except Exception:
        pass
    return f


# ---------------------------------------------------------------- 1. Beispieldateien

def make_samples():
    if SAMPLES.exists():
        shutil.rmtree(SAMPLES)
    SAMPLES.mkdir(parents=True)

    # PDF: erfundene Offerte
    page = Image.new("RGB", (1240, 1754), "white")
    d = ImageDraw.Draw(page)
    d.rectangle([0, 0, 1240, 220], fill=(46, 125, 90))
    d.text((90, 70), "Holzbau Sonnenhang", font=ImageFont.truetype(FONT, 64), fill="white")
    d.text((90, 300), "Offerte Gartenhaus", font=ImageFont.truetype(FONT, 56), fill=(30, 30, 30))
    small = ImageFont.truetype(FONT, 30)
    rows = [("Fundament & Bodenplatte", "2'400.–"), ("Holzkonstruktion Lärche", "6'850.–"),
            ("Dach mit Begrünung", "3'120.–"), ("Fenster & Türe", "1'980.–"), ("Montage", "1'450.–")]
    y = 450
    for label, price in rows:
        d.text((90, y), label, font=small, fill=(60, 60, 60))
        d.text((960, y), price, font=small, fill=(60, 60, 60))
        d.line([90, y + 55, 1150, y + 55], fill=(225, 225, 225), width=2)
        y += 90
    d.text((90, y + 30), "Total CHF", font=ImageFont.truetype(FONT, 38), fill=(20, 20, 20))
    d.text((930, y + 30), "15'800.–", font=ImageFont.truetype(FONT, 38), fill=(20, 20, 20))
    for i in range(14):
        d.rectangle([90, 1150 + i * 38, 90 + (1060 if i % 4 else 700), 1166 + i * 38], fill=(235, 235, 235))
    page.save(SAMPLES / "Offerte Gartenhaus.pdf", "PDF", resolution=150)

    # JPG: Moodboard aus Farbflächen
    mood = Image.new("RGB", (1600, 1200), (240, 236, 228))
    md = ImageDraw.Draw(mood)
    tiles = [((40, 40, 780, 620), [(255, 170, 90), (220, 90, 110)]),
             ((820, 40, 1560, 360), [(80, 160, 200), (40, 80, 150)]),
             ((820, 400, 1180, 620), [(120, 180, 120), (60, 120, 80)]),
             ((1220, 400, 1560, 620), [(250, 220, 120), (230, 160, 60)]),
             ((40, 660, 560, 1160), [(90, 120, 200), (160, 110, 210)]),
             ((600, 660, 1560, 1160), [(230, 120, 80), (250, 200, 120)])]
    for (x0, y0, x1, y1), (a, b) in tiles:
        for yy in range(y0, y1):
            t = (yy - y0) / max(1, y1 - y0)
            col = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
            md.line([x0, yy, x1, yy], fill=col)
    md.ellipse([500, 140, 700, 340], fill=(255, 235, 160))
    mood.save(SAMPLES / "Moodboard Tessin.jpg", quality=90)

    # Ordner (für "Ausschneiden")
    folder = SAMPLES / "Projekt Atlas"
    folder.mkdir()
    (folder / "Notizen.txt").write_text("Fiktives Beispielprojekt.\n")


# ---------------------------------------------------------------- 2. Einzelbilder aus der App

def render_frames():
    if not APP_BIN.exists():
        sys.exit("Zuerst ./build.sh ausführen.")
    if FRAMES.exists():
        shutil.rmtree(FRAMES)
    FRAMES.mkdir(parents=True)
    env = dict(os.environ, NODGE_DEMO=str(FRAMES), NODGE_DEMO_FILES=str(SAMPLES))
    subprocess.run([str(APP_BIN)], env=env, check=True, timeout=120)


_cache = {}


def island(name):
    if name not in _cache:
        _cache[name] = Image.open(FRAMES / f"{name}.png").convert("RGBA")
    return _cache[name]


def body_size(img):
    """Grösse der schwarzen Island (ohne Schatten)"""
    a = img.getchannel("A").point(lambda v: 255 if v > 230 else 0)
    box = a.getbbox()
    return (box[2] - box[0], box[3]) if box else (1, 1)


# ---------------------------------------------------------------- 3. Schreibtisch

def make_wallpaper(menu_text=True):
    w, h = W * S, H * S
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(0, w):
            u, v = x / w, y / h
            r = int(40 + 70 * u + 40 * v)
            g = int(60 + 30 * (1 - u) + 50 * v)
            b = int(120 + 80 * (1 - v) + 30 * u)
            px[x, y] = (r, g, b)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([w * 0.55, h * 0.35, w * 1.1, h * 1.3], fill=(255, 150, 120, 120))
    gd.ellipse([-w * 0.2, h * 0.5, w * 0.4, h * 1.4], fill=(120, 200, 255, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    img = Image.alpha_composite(img.convert("RGBA"), glow)

    # Menüleiste (links und rechts der Notch)
    bar = Image.new("RGBA", (w, 32 * S), (10, 12, 25, 90))
    img.alpha_composite(bar, (0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    if not menu_text:
        return img
    x = 18 * S
    for i, label in enumerate(["", "Finder", "Ablage", "Bearbeiten", "Darstellung", "Fenster"]):
        if i == 0:
            d.text((x, 8 * S), "●", font=font(12), fill=(255, 255, 255, 230))
            x += 26 * S
            continue
        f = font(12.5, weight=700 if i == 1 else 500)
        d.text((x, 8.5 * S), label, font=f, fill=(255, 255, 255, 235))
        x += d.textlength(label, font=f) + 16 * S
    right = "Fr. 13. Nov.  09:41"
    f = font(12.5, weight=500)
    d.text((W * S - 18 * S - d.textlength(right, font=f), 8.5 * S), right, font=f, fill=(255, 255, 255, 235))
    # Menüleisten-Symbol von Nodge
    tx = W * S - 18 * S - d.textlength(right, font=f) - 34 * S
    d.rounded_rectangle([tx, 11 * S, tx + 14 * S, 21 * S], radius=2 * S, outline=(255, 255, 255, 230), width=int(1.6 * S))
    d.line([tx + 3 * S, 16 * S, tx + 11 * S, 16 * S], fill=(255, 255, 255, 230), width=int(1.6 * S))
    return img


ICONS = {
    "pdf": ("Offerte Gartenhaus.pdf", "Offerte\nGartenhaus.pdf"),
    "jpg": ("Moodboard Tessin.jpg", "Moodboard\nTessin.jpg"),
    "folder": ("Projekt Atlas", "Projekt Atlas"),
}
ICON_POS = {"pdf": (70, 250), "jpg": (170, 250), "folder": (270, 250), "pdf2": (170, 345)}
NOTE_BOX = (560, 225, 860, 395)


def icon_image(key, size=56):
    name = ICONS[key][0]
    img = Image.open(FRAMES / f"icon-{name}.png").convert("RGBA")
    return img.resize((size * S, size * S), Image.LANCZOS)


def draw_desktop_icon(canvas, key, pos, selected=False, label_key=None):
    x, y = pos
    ic = icon_image(label_key or key)
    d = ImageDraw.Draw(canvas, "RGBA")
    if selected:
        d.rounded_rectangle([(x - 34) * S, (y - 32) * S, (x + 34) * S, (y + 32) * S], radius=8 * S, fill=(255, 255, 255, 60))
    canvas.alpha_composite(ic, (int((x - 28) * S), int((y - 28) * S)))
    label = ICONS[label_key or key][1]
    f = font(10.5, weight=600)
    for i, line in enumerate(label.split("\n")):
        tw = d.textlength(line, font=f)
        ty = (y + 32 + i * 13) * S
        if selected:
            d.rounded_rectangle([x * S - tw / 2 - 4 * S, ty - 1 * S, x * S + tw / 2 + 4 * S, ty + 13 * S],
                                radius=4 * S, fill=(40, 110, 230, 255))
        d.text((x * S - tw / 2 + 1, ty + 1), line, font=f, fill=(0, 0, 0, 120))
        d.text((x * S - tw / 2, ty), line, font=f, fill=(255, 255, 255, 255))


def draw_note_window(canvas, selected):
    x0, y0, x1, y1 = NOTE_BOX
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x0 * S, (y0 + 6) * S, x1 * S, (y1 + 6) * S], radius=12 * S, fill=(0, 0, 0, 110))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14 * S)))
    d = ImageDraw.Draw(canvas, "RGBA")
    d.rounded_rectangle([x0 * S, y0 * S, x1 * S, y1 * S], radius=12 * S, fill=(36, 36, 40, 250),
                        outline=(255, 255, 255, 40), width=S)
    for i, c in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
        cx = (x0 + 16 + i * 18) * S
        d.ellipse([cx - 5 * S, (y0 + 16) * S - 5 * S, cx + 5 * S, (y0 + 16) * S + 5 * S], fill=c)
    d.text(((x0 + 74) * S, (y0 + 9) * S), "Notizen", font=font(12, weight=700), fill=(255, 255, 255, 200))
    lines = ["Workshop-Notizen", "Kickoff Projekt Atlas: Termin am", "4. Dezember, Raum Bergsicht.",
             "Offene Punkte: Moodboard finalisieren,", "Offerte prüfen, Einladungen verschicken."]
    for i, line in enumerate(lines):
        f = font(13 if i == 0 else 11.5, weight=700 if i == 0 else 450)
        ty = (y0 + 40 + i * 22 - (0 if i == 0 else 2)) * S
        if selected:
            tw = d.textlength(line, font=f)
            d.rectangle([(x0 + 16) * S - 2, ty - 2 * S, (x0 + 16) * S + tw + 2, ty + 16 * S], fill=(48, 100, 200, 255))
        d.text(((x0 + 16) * S, ty), line, font=f, fill=(255, 255, 255, 235))


def draw_cursor(canvas, pos, pressed=False):
    x, y = pos[0] * S, pos[1] * S
    k = S * (0.92 if pressed else 1.0)
    pts = [(0, 0), (0, 17), (4.2, 13.2), (6.9, 19.3), (9.6, 18.1), (7, 12.2), (12.2, 12.2)]
    poly = [(x + px * k, y + py * k) for px, py in pts]
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(px + 1.5 * S, py + 2 * S) for px, py in poly], fill=(0, 0, 0, 90))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(2 * S)))
    d = ImageDraw.Draw(canvas, "RGBA")
    d.polygon(poly, fill=(0, 0, 0, 255))
    inner = [(x + px * k * 0.78 + 1.2 * k, y + py * k * 0.78 + 2.4 * k) for px, py in pts]
    d.polygon(inner, fill=(255, 255, 255, 255))


def draw_click_ring(canvas, pos, t):
    """Kleiner Klick-Impuls (t: 0…1)"""
    if not 0 <= t <= 1:
        return
    r = (6 + 16 * t) * S
    a = int(170 * (1 - t))
    d = ImageDraw.Draw(canvas, "RGBA")
    d.ellipse([pos[0] * S - r, pos[1] * S - r, pos[0] * S + r, pos[1] * S + r], outline=(255, 255, 255, a), width=int(2 * S))


def draw_caption(canvas, text, alpha):
    if not text or alpha <= 0:
        return
    f = font(14, rounded=True, weight=650)
    d = ImageDraw.Draw(canvas, "RGBA")
    tw = d.textlength(text, font=f)
    pad = 16 * S
    w, h = tw + pad * 2, 34 * S
    x0 = (W * S - w) / 2
    y0 = (H - 50) * S
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.rounded_rectangle([x0, y0, x0 + w, y0 + h], radius=h / 2, fill=(12, 12, 16, int(205 * alpha)),
                         outline=(255, 255, 255, int(35 * alpha)), width=S)
    ld.text((x0 + pad, y0 + 7.5 * S), text, font=f, fill=(255, 255, 255, int(255 * alpha)))
    canvas.alpha_composite(layer)


def draw_menu(canvas, highlight):
    """Das ⋯-Menü der Island (nachgezeichnet, NSMenu lässt sich nicht offscreen rendern)"""
    items = [("Ablage leeren", None), ("Ablage-Ordner im Finder zeigen", None), None,
             ("Zwischenablage aufzeichnen", True), ("Jetzt läuft anzeigen", True), ("Beim Login starten", True),
             None, ("Nodge beenden", None)]
    x0, y0, w = 590, 46, 230
    h = sum(9 if it is None else 22 for it in items) + 10
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x0 * S, (y0 + 6) * S, (x0 + w) * S, (y0 + h + 6) * S],
                                             radius=10 * S, fill=(0, 0, 0, 120))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(10 * S)))
    ld = ImageDraw.Draw(canvas, "RGBA")
    ld.rounded_rectangle([x0 * S, y0 * S, (x0 + w) * S, (y0 + h) * S], radius=10 * S, fill=(44, 44, 48, 250),
                         outline=(255, 255, 255, 45), width=S)
    y = y0 + 5
    f = font(12.5, weight=500)
    for it in items:
        if it is None:
            ld.line([(x0 + 12) * S, (y + 4) * S, (x0 + w - 12) * S, (y + 4) * S], fill=(255, 255, 255, 40), width=S)
            y += 9
            continue
        label, check = it
        if label == highlight:
            ld.rounded_rectangle([(x0 + 5) * S, y * S, (x0 + w - 5) * S, (y + 22) * S], radius=5 * S, fill=(40, 110, 230, 255))
        if check:
            ld.text(((x0 + 12) * S, (y + 3.5) * S), "✓", font=f, fill=(255, 255, 255, 240))
        ld.text(((x0 + 30) * S, (y + 3.5) * S), label, font=f, fill=(255, 255, 255, 240))
        y += 22


# ---------------------------------------------------------------- Island-Übergänge

def spring(t):
    """Gefedertes Einrasten wie Theme.openSpring"""
    if t >= 1:
        return 1.0
    return 1 - math.exp(-7 * t) * math.cos(9 * t)


def island_frame(a, b, t):
    """Übergang von Zustand a nach b (t: 0…1 seit Beginn, Dauer 0.45 s)"""
    if a == b or t >= 1:
        return island(b)
    A, B = island(a), island(b)
    (aw, ah), (bw, bh) = body_size(A), body_size(B)
    e = spring(t)
    cw, ch = aw + (bw - aw) * e, ah + (bh - ah) * e
    fade = min(1, t * 2.2)
    out = Image.new("RGBA", A.size, (0, 0, 0, 0))
    for img, (iw, ih), alpha in ((A, (aw, ah), 1 - fade), (B, (bw, bh), fade)):
        if alpha <= 0.01:
            continue
        sx, sy = max(0.05, cw / iw), max(0.05, ch / ih)
        nw, nh = int(img.width * sx), int(img.height * sy)
        scaled = img.resize((max(1, nw), max(1, nh)), Image.BILINEAR)
        if alpha < 1:
            scaled.putalpha(scaled.getchannel("A").point(lambda v: int(v * alpha)))
        layer = Image.new("RGBA", A.size, (0, 0, 0, 0))
        layer.paste(scaled, (int((A.width - nw) / 2), 0))
        out = Image.alpha_composite(out, layer)
    return out


# ---------------------------------------------------------------- 4. Drehbuch

def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


class Timeline:
    def __init__(self):
        self.steps = []

    def add(self, dur, state=None, to=None, caption=None, drag=None, press=False, click=False,
            note_sel=None, folder_sel=None, menu=None, extra_icon=None):
        self.steps.append(dict(dur=dur, state=state, to=to, caption=caption, drag=drag, press=press,
                               click=click, note_sel=note_sel, folder_sel=folder_sel, menu=menu,
                               extra_icon=extra_icon))


def card_center(i):
    return (150 + 49 + 106 * i, 104)


def build_script():
    tl = Timeline()
    a = tl.add
    pdf, jpg, folder = ICON_POS["pdf"], ICON_POS["jpg"], ICON_POS["folder"]
    notch = (NOTCH_X, 14)

    a(1.2, state="closed-0", to=(330, 330), caption="Nodge – deine Notch wird zur Ablage")
    # 1. Datei hineinziehen
    a(0.8, to=pdf, caption="Datei auf die Notch ziehen")
    a(0.25, press=True, drag="pdf")
    a(0.7, to=(430, 150), state="peek-0", drag="pdf", press=True)
    a(0.55, to=(notch[0], 22), state="drop-0", drag="pdf", press=True, caption="Loslassen zum Ablegen")
    a(1.1, state="open-1")
    # 2. Bild
    a(0.7, to=jpg, state="closed-1", caption="Bilder, Ordner, Texte, Links – alles geht")
    a(0.2, press=True, drag="jpg")
    a(0.8, to=(notch[0] + 10, 22), state="peek-1", drag="jpg", press=True)
    a(0.35, state="drop-1", drag="jpg", press=True)
    a(1.0, state="open-2")
    # 3. Schnellablage für Text
    a(0.8, to=(700, 330), state="closed-2", caption="Text markieren …")
    a(0.6, note_sel=True)
    a(0.5, note_sel=True, caption="… und ⌘⇧Leertaste drücken")
    a(1.6, state="open-3", note_sel=True, caption="… und ⌘⇧Leertaste drücken")
    # 4. Einfügen-Knopf
    a(0.8, to=(712, 16), state="open-3", caption="Kopierten Link per Knopf einfügen")
    a(0.3, click=True)
    a(1.2, state="open-4")
    # 5. Ausschneiden im Finder
    a(0.8, to=(folder[0] + 6, folder[1] + 6), state="closed-4", caption="Ordner im Finder markieren …")
    a(0.4, folder_sel=True, click=True)
    a(0.5, folder_sel=True, caption="… ⌘⇧↑ = ausschneiden (wird beim Herausziehen verschoben)")
    a(1.8, state="open-5", folder_sel=True, caption="… ⌘⇧↑ = ausschneiden (wird beim Herausziehen verschoben)")
    # 6. Klick = kopieren
    a(0.7, to=card_center(2), caption="Klick auf eine Karte = kopieren")
    a(0.25, click=True)
    a(1.1, state="open-5-copied")
    a(0.4, state="open-5", caption="Doppelklick = öffnen · Rechtsklick = mehr")
    a(0.8)
    # 7. Verlauf
    a(0.6, to=(250, 16), caption="Verlauf: alles, was du mit ⌘C kopiert hast")
    a(0.2, click=True)
    a(2.0, state="history-5")
    a(0.5, to=(178, 16))
    a(0.2, click=True)
    a(0.6, state="open-5")
    # 8. Herausziehen
    a(0.6, to=card_center(0), caption="Karte herausziehen = Datei ablegen")
    a(0.25, press=True, drag="pdf")
    a(0.9, to=ICON_POS["pdf2"], drag="pdf", press=True, state="open-5")
    a(0.2, state="open-4b", extra_icon=True)
    a(0.7, state="closed-4b", extra_icon=True)
    # 9. Musik
    a(1.3, state="media-closed", to=(420, 300), extra_icon=True,
      caption="Läuft Musik, zeigt die Notch Equalizer und App")
    a(0.7, to=(620, 16), extra_icon=True, caption="Maus rechts neben die Notch: Jetzt läuft")
    a(1.4, state="media-open", extra_icon=True)
    a(0.5, to=(613, 60), extra_icon=True, caption="Pause, Weiter, Zurück, Spulen")
    a(0.2, click=True, extra_icon=True)
    a(1.0, state="media-open-paused", extra_icon=True)
    a(0.4, to=(648, 60), extra_icon=True)
    a(0.2, click=True, extra_icon=True)
    a(1.4, state="media-open-next", extra_icon=True)
    a(0.6, to=(470, 300), state="media-closed-next", extra_icon=True)
    # 10. Einstellungen
    a(0.6, to=notch, state="open-4b", extra_icon=True, caption="Menü •••  Verlauf, Jetzt läuft, Beim Login starten")
    a(0.4, to=(740, 16), extra_icon=True)
    a(0.2, click=True, extra_icon=True, menu="")
    a(0.6, to=(680, 160), extra_icon=True, menu="")
    a(1.2, extra_icon=True, menu="Beim Login starten")
    a(0.3, click=True, extra_icon=True)
    # 11. Leeren
    a(0.6, to=(680, 16), extra_icon=True, caption="Papierkorb zweimal klicken = Ablage leeren")
    a(0.2, click=True, extra_icon=True)
    a(0.35, extra_icon=True)
    a(0.2, click=True, extra_icon=True)
    a(1.2, state="open-0", extra_icon=True)
    a(0.7, to=(450, 300), state="media-closed-empty", extra_icon=True, caption="Nodge – schlank, schnell, nativ")
    a(1.6, extra_icon=True)
    return tl


def render_video():
    if VIDEO_FRAMES.exists():
        shutil.rmtree(VIDEO_FRAMES)
    VIDEO_FRAMES.mkdir(parents=True)
    wallpaper = make_wallpaper()
    tl = build_script()

    state, prev_state, state_t0 = "closed-0", "closed-0", -10.0
    cursor = (330.0, 330.0)
    caption, prev_caption, cap_t0 = None, None, -10.0
    t = 0.0
    n = 0
    click_t = -10.0
    click_pos = cursor
    for step in tl.steps:
        start_cursor = cursor
        target = step["to"] or cursor
        if step["state"] and step["state"] != state:
            prev_state, state, state_t0 = state, step["state"], t
        if step["caption"] and step["caption"] != caption:
            prev_caption, caption, cap_t0 = caption, step["caption"], t
        if step["click"]:
            click_t, click_pos = t, target
        frames = max(1, round(step["dur"] * FPS))
        for i in range(frames):
            lt = (i + 1) / frames
            cursor = (start_cursor[0] + (target[0] - start_cursor[0]) * ease(lt),
                      start_cursor[1] + (target[1] - start_cursor[1]) * ease(lt)) if step["to"] else cursor
            canvas = wallpaper.copy()
            draw_note_window(canvas, bool(step["note_sel"]))
            for key in ("pdf", "jpg"):
                draw_desktop_icon(canvas, key, ICON_POS[key])
            draw_desktop_icon(canvas, "folder", ICON_POS["folder"], selected=bool(step["folder_sel"]))
            if step["extra_icon"]:
                draw_desktop_icon(canvas, "pdf", ICON_POS["pdf2"])
            ip = (t - state_t0) / 0.45
            isl = island_frame(prev_state, state, ip)
            canvas.alpha_composite(isl, (0, 0))
            if step["menu"] is not None:
                draw_menu(canvas, step["menu"])
            # Untertitel überblenden
            ct = (t - cap_t0) / 0.3   # alter Text aus, dann neuer ein
            if ct < 0.5 and prev_caption:
                draw_caption(canvas, prev_caption, 1 - ct * 2)
            elif ct >= 0.5 or not prev_caption:
                draw_caption(canvas, caption, min(1, (ct - 0.5) * 2) if prev_caption else min(1, ct))
            if step["drag"]:
                ghost = icon_image(step["drag"], 48)
                ghost.putalpha(ghost.getchannel("A").point(lambda v: int(v * 0.8)))
                canvas.alpha_composite(ghost, (int((cursor[0] - 24) * S), int((cursor[1] - 20) * S)))
            draw_click_ring(canvas, click_pos, (t - click_t) / 0.35)
            draw_cursor(canvas, cursor, pressed=step["press"] or (0 <= t - click_t < 0.12))
            canvas.convert("RGB").save(VIDEO_FRAMES / f"{n:05d}.png")
            n += 1
            t += 1 / FPS
    print(f"{n} Bilder, {t:.1f} s")


def encode():
    DOCS.mkdir(exist_ok=True)
    src = str(VIDEO_FRAMES / "%05d.png")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", src,
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", "-preset", "slow",
                    "-movflags", "+faststart", str(DOCS / "demo.mp4")], check=True)
    palette = TMP / "palette.png"
    # GIF für die README (GitHub spielt Videos aus dem Repo nicht inline ab)
    vf = "fps=12,scale=760:-1:flags=lanczos"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(DOCS / "demo.mp4"),
                    "-vf", f"{vf},palettegen=max_colors=128:stats_mode=full", str(palette)], check=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(DOCS / "demo.mp4"), "-i", str(palette),
                    "-lavfi", f"{vf}[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle",
                    str(DOCS / "demo.gif")], check=True)


def screenshots():
    """Standbilder für die README: Island auf dem Schreibtisch, enger Ausschnitt"""
    DOCS.mkdir(exist_ok=True)
    wallpaper = make_wallpaper(menu_text=False)
    shots = {"shelf": "open-5", "history": "history-5", "media": "media-open",
             "drop": "drop-1", "closed": "media-closed"}
    for name, state in shots.items():
        canvas = wallpaper.copy()
        canvas.alpha_composite(island(state), (0, 0))
        if state.startswith(("open", "history", "drop")):
            box = (80, 0, W - 80, 240)
        elif state.startswith("media-open"):
            box = (120, 0, W - 120, 150)
        else:  # kleine Zustände an der Notch
            box = (250, 0, W - 250, 70)
        crop = canvas.crop(tuple(v * S for v in box))
        crop.convert("RGB").save(DOCS / f"screenshot-{name}.png", optimize=True)


if __name__ == "__main__":
    make_samples()
    render_frames()
    screenshots()
    render_video()
    encode()
    print("✓ docs/demo.mp4, docs/demo.gif, docs/screenshot-*.png")
