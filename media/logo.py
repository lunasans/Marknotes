"""Marknotes-Logo im Stil der WoW-Fähigkeitssymbole.

Goldrahmen mit Eck-Edelsteinen, arkanblauer Grund, schräges Pergament mit
angesengten Rändern, Tinten-# und Checkliste, Schreibfeder, Wachssiegel.
Nur Formen, keine Schriften. Gezeichnet auf 2048 px, verkleinert.

Aufruf: python logo.py [Zielordner]   (Standard: Ordner dieser Datei)
"""
import math
import random
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent
OUT.mkdir(parents=True, exist_ok=True)

S = 2048
k = S / 1024
rnd = random.Random(7)          # fester Zufall: jedes Mal dasselbe Bild


def P(*v):
    return [round(x * k) for x in v]


def layer():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def blur(img, r):
    return img.filter(ImageFilter.GaussianBlur(r * k))


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


ACCENT = (122, 162, 247)
INK = (58, 34, 16)
GOLD_HI, GOLD_MID, GOLD_LO = (255, 232, 150), (214, 160, 60), (110, 66, 20)

# ------------------------------------------------------------ Hintergrund

img = Image.new("RGBA", (S, S), (6, 8, 20, 255))
bg = ImageDraw.Draw(img)
center = (512, 470)
for r in range(760, 0, -3):
    t = r / 760
    c = mix((52, 78, 150), (6, 8, 20), t ** 0.8)
    bg.ellipse(P(center[0] - r, center[1] - r, center[0] + r, center[1] + r), fill=c)

# Arkanes Leuchten hinter dem Blatt
glow = layer()
ImageDraw.Draw(glow).ellipse(P(220, 170, 820, 830), fill=ACCENT + (150,))
img.alpha_composite(blur(glow, 70))

# ------------------------------------------------------------ Pergament

def ragged_rect(l, t, r, b, step=14, jitter=7):
    pts = []
    for x in range(l, r, step):
        pts.append((x, t + rnd.uniform(-jitter, jitter)))
    for y in range(t, b, step):
        pts.append((r + rnd.uniform(-jitter, jitter), y))
    for x in range(r, l, -step):
        pts.append((x, b + rnd.uniform(-jitter, jitter)))
    for y in range(b, t, -step):
        pts.append((l + rnd.uniform(-jitter, jitter), y))
    return [(px * k, py * k) for px, py in pts]


PL, PT, PR, PB = 250, 190, 770, 830
paper_mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(paper_mask).polygon(ragged_rect(PL, PT, PR, PB), fill=255)

paper = Image.new("RGBA", (S, S))
pdraw = ImageDraw.Draw(paper)
for y in range(S):
    t = y / S
    pdraw.line([(0, y), (S, y)], fill=mix((246, 230, 186), (214, 186, 128), t) + (255,))

# Papierstruktur
noise = Image.effect_noise((S, S), 60).filter(ImageFilter.GaussianBlur(1.2))
noise = noise.point(lambda v: 205 + v * 50 // 255)
paper = ImageChops.multiply(paper, Image.merge("RGBA", (noise, noise, noise, Image.new("L", (S, S), 255))))

# Angesengte Ränder: innen hell, zum Rand hin braun
edge = blur(paper_mask, 28)
burn_alpha = ImageChops.subtract(paper_mask, edge).point(lambda v: min(255, v * 3))
burn = Image.new("RGBA", (S, S), (120, 70, 25, 255))
burn.putalpha(burn_alpha)
paper.alpha_composite(burn)

# Tinte
ink = ImageDraw.Draw(paper)
W = round(26 * k)
for x in (345, 418):                                       # "#"
    ink.line(P(x + 20, 262, x - 6, 450), fill=INK, width=W)
for y in (322, 392):
    ink.line(P(298, y, 492, y), fill=INK, width=W)
ink.line(P(522, 357, 690, 352), fill=INK + (200,), width=round(20 * k))   # Überschrift

# Eng genug, dass das Siegel unten links keine Zeile verdeckt.
rows = [(500, True), (592, True), (684, False)]
for y, done in rows:
    ink.rounded_rectangle(P(304, y - 34, 372, y + 34), radius=round(8 * k),
                          outline=INK, width=round(9 * k))
    if done:
        ink.line(P(316, y - 2, 336, y + 22, 388, y - 46), fill=(150, 30, 20),
                 width=round(16 * k), joint="curve")
    ink.line(P(408, y + 2, 408 + (290 if y != rows[1][0] else 230), y), fill=INK + (190,),
             width=round(14 * k))

paper.putalpha(paper_mask)
paper = paper.rotate(-5, resample=Image.BICUBIC, center=P(512, 512))

shadow = layer()
shadow.paste((0, 0, 0, 170), (0, 0), paper.getchannel("A"))
img.alpha_composite(blur(shadow, 14), (round(14 * k), round(18 * k)))
img.alpha_composite(paper)

# ------------------------------------------------------------ Wachssiegel

seal = layer()
sd = ImageDraw.Draw(seal)
cx, cy, R = 292, 826, 78       # auf der unteren linken Blattecke
pts = []
for i in range(48):
    a = i / 48 * math.tau
    rr = R + rnd.uniform(-6, 7)
    pts.append(((cx + math.cos(a) * rr) * k, (cy + math.sin(a) * rr) * k))
sd.polygon(pts, fill=(128, 16, 22, 255))
for r in range(int(R * 0.86), 0, -2):                      # Wölbung
    t = r / (R * 0.86)
    sd.ellipse(P(cx - r - 10 * (1 - t), cy - r - 12 * (1 - t), cx + r - 10 * (1 - t), cy + r - 12 * (1 - t)),
               fill=mix((214, 60, 58), (150, 22, 28), t))
sd.ellipse(P(cx - 56, cy - 56, cx + 56, cy + 56), outline=(96, 8, 14), width=round(6 * k))
for x in (cx - 12, cx + 14):                               # eingeprägtes "#"
    sd.line(P(x + 6, cy - 30, x - 4, cy + 30), fill=(96, 8, 14), width=round(10 * k))
for y in (cy - 11, cy + 13):
    sd.line(P(cx - 32, y, cx + 32, y), fill=(96, 8, 14), width=round(10 * k))

ss = layer()
ss.paste((0, 0, 0, 160), (0, 0), seal.getchannel("A"))
img.alpha_composite(blur(ss, 8), (round(8 * k), round(10 * k)))
img.alpha_composite(seal)

# ------------------------------------------------------------ Schreibfeder

quill = layer()
qd = ImageDraw.Draw(quill)
ax, ay = 600, 700            # Ansatz der Spitze
bx, by = 900, 150            # Federende
dx, dy = bx - ax, by - ay
ln = math.hypot(dx, dy)
ux, uy = dx / ln, dy / ln
nx, ny = -uy, ux


def along(t, off):
    return ((ax + dx * t + nx * off) * k, (ay + dy * t + ny * off) * k)


left, right = [], []
for i in range(61):
    t = 0.18 + 0.82 * i / 60
    s = max(0.0, math.sin(math.pi * (t - 0.18) / 0.82)) ** 0.75
    left.append(along(t, 78 * s))
    right.append(along(t, -48 * s))
qd.polygon(left + right[::-1], fill=(236, 240, 248, 255))

# Fahne schattieren und Äste ziehen
for i in range(8, 58, 2):
    t = 0.18 + 0.82 * i / 60
    s = max(0.0, math.sin(math.pi * (t - 0.18) / 0.82)) ** 0.75
    qd.line([along(t, 0), along(t + 0.05, 74 * s)], fill=(176, 188, 214, 255), width=round(3 * k))
    qd.line([along(t, 0), along(t + 0.05, -45 * s)], fill=(150, 162, 192, 255), width=round(3 * k))
# Kerben in der Fahne
for t, side in ((0.55, 1), (0.72, -1), (0.4, -1)):
    s = max(0.0, math.sin(math.pi * (t - 0.18) / 0.82)) ** 0.75
    w = (78 if side > 0 else 48) * s
    qd.polygon([along(t, side * w * 1.05), along(t + 0.03, side * w * 0.55),
                along(t + 0.05, side * w * 1.05)], fill=(0, 0, 0, 0))

qd.line([along(0.05, 0), along(1.0, 0)], fill=(120, 110, 100, 255), width=round(7 * k))   # Kiel
# Goldene Spitze
tip = ((ax - ux * 70) * k, (ay - uy * 70) * k)
qd.polygon([tip, along(0.0, 15), along(0.12, 13), along(0.12, -13), along(0.0, -15)],
           fill=GOLD_MID + (255,))
qd.line([tip, along(0.06, 0)], fill=GOLD_LO + (255,), width=round(3 * k))
qd.polygon([along(0.0, 15), along(0.12, 13), along(0.12, 4), along(0.0, 5)], fill=GOLD_HI + (255,))

qs = layer()
qs.paste((0, 0, 0, 150), (0, 0), quill.getchannel("A"))
img.alpha_composite(blur(qs, 10), (round(-12 * k), round(16 * k)))
img.alpha_composite(quill)

# Vignette
vig = Image.new("L", (S, S), 0)
ImageDraw.Draw(vig).rectangle(P(0, 0, 1023, 1023), fill=150)
ImageDraw.Draw(vig).ellipse(P(60, 40, 964, 984), fill=0)
dark = Image.new("RGBA", (S, S), (0, 0, 0, 255))
dark.putalpha(blur(vig, 90))
img.alpha_composite(dark)

# Spielsymbol: nur der Inhalt, ohne Goldrahmen. WoW legt um Symbole
# eigene Rahmen (Minimap-Ring, Addon-Liste), und bei 18 px wäre der
# Goldrahmen nur noch ein Saum. Ausgeschnitten wird knapp innerhalb der
# Stelle, an der gleich der Rahmen sitzt.
game_icon = img.crop(P(70, 70, 954, 954))

# ------------------------------------------------------------ Goldrahmen

fd = ImageDraw.Draw(img)
B = 58                                                     # Rahmenbreite
for i in range(B):
    t = i / (B - 1)
    if t < 0.12:
        c = mix((24, 14, 4), GOLD_LO, t / 0.12)
    elif t < 0.45:
        c = mix(GOLD_LO, GOLD_HI, (t - 0.12) / 0.33)
    elif t < 0.8:
        c = mix(GOLD_HI, GOLD_MID, (t - 0.45) / 0.35)
    else:
        c = mix(GOLD_MID, (36, 20, 6), (t - 0.8) / 0.2)
    fd.rectangle(P(i, i, 1023 - i, 1023 - i), outline=c, width=round(k) + 1)

# Lichtkante oben links, Schatten unten rechts
hl = layer()
hd = ImageDraw.Draw(hl)
hd.polygon(P(0, 0, 1024, 0, 1024 - B, B, B, B, B, 1024 - B, 0, 1024), fill=(255, 245, 200, 50))
img.alpha_composite(hl)
sh = layer()
ImageDraw.Draw(sh).polygon(P(1024, 1024, 0, 1024, B, 1024 - B, 1024 - B, 1024 - B, 1024 - B, B, 1024, 0),
                           fill=(0, 0, 0, 60))
img.alpha_composite(sh)

# Innere dunkle Kante
fd.rectangle(P(B, B, 1023 - B, 1023 - B), outline=(20, 10, 2), width=round(5 * k))

# Edelsteine in den Ecken
for gx, gy in ((B / 2, B / 2), (1023 - B / 2, B / 2), (B / 2, 1023 - B / 2), (1023 - B / 2, 1023 - B / 2)):
    r = 30
    fd.polygon(P(gx, gy - r, gx + r, gy, gx, gy + r, gx - r, gy), fill=GOLD_LO)
    r = 22
    fd.polygon(P(gx, gy - r, gx + r, gy, gx, gy + r, gx - r, gy), fill=(40, 70, 150))
    fd.polygon(P(gx, gy - r, gx + r, gy, gx, gy, gx - r, gy), fill=ACCENT)
    fd.ellipse(P(gx - 7, gy - 13, gx + 1, gy - 5), fill=(235, 245, 255))

for size in (1024, 512, 400, 256, 64):
    img.convert("RGB").resize((size, size), Image.LANCZOS).save(OUT / f"logo-{size}.png", optimize=True)

# Ins Addon: 128x128 (Zweierpotenz), 32 Bit, unkomprimiertes TGA - das
# Format liest WoW in jeder Version. Liegt neben den Lua-Dateien, damit
# es ins Paket kommt (media/ ist in .pkgmeta ausgenommen).
tex = Path(__file__).resolve().parent.parent / "Textures"
tex.mkdir(exist_ok=True)
game_icon.resize((128, 128), Image.LANCZOS).save(tex / "Icon.tga", rle=False)
print("ok")
