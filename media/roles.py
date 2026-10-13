"""Rollen-Symbole für Notizen: Tank, Heiler, Schaden.

Im Stil des Logos: runde Plakette mit Goldring und dunklem Saum, innen
die Farbe der Rolle (blau, grün, rot), darauf ein silbernes Zeichen -
Schild, Kreuz, Schwert. Gezeichnet auf 512 px, verkleinert auf 64 px
(Zweierpotenz, 32 Bit, unkomprimiertes TGA).

Aufruf: python roles.py   (schreibt nach ..\\Textures)
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

TEX = Path(__file__).parent.parent / "Textures"
TEX.mkdir(exist_ok=True)

S = 512
C = S // 2
GOLD_HI, GOLD_MID, GOLD_LO = (255, 232, 150), (214, 160, 60), (110, 66, 20)
SILVER_HI, SILVER_LO = (255, 255, 255), (150, 158, 175)
EDGE = (28, 16, 4)

ROLES = {
    "Tank":    ((90, 150, 235), (18, 40, 105)),
    "Healer":  ((110, 200, 90), (18, 80, 22)),
    "Damager": ((230, 90, 70), (95, 18, 12)),
}


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def gradient(stops):
    """Senkrechter Verlauf über das ganze Bild, stops: [(t, farbe), ...]."""
    img = Image.new("RGBA", (S, S))
    for y in range(S):
        t = y / (S - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                c = mix(c0, c1, (t - t0) / (t1 - t0))
                break
        img.paste(c + (255,), (0, y, S, y + 1))
    return img


def solid(c):
    return Image.new("RGBA", (S, S), c + (255,))


def disc(r):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).ellipse((C - r, C - r, C + r, C + r), fill=255)
    return m


def shield(d):
    d.polygon([(150, 128), (256, 104), (362, 128), (362, 250), (340, 320),
               (256, 404), (172, 320), (150, 250)], fill=255)


def cross(d):
    d.rounded_rectangle((212, 112, 300, 400), radius=16, fill=255)
    d.rounded_rectangle((112, 212, 400, 300), radius=16, fill=255)


def sword(d):
    d.polygon([(256, 84), (282, 124), (278, 318), (234, 318), (230, 124)], fill=255)
    d.rounded_rectangle((180, 312, 332, 342), radius=10, fill=255)
    d.rectangle((242, 342, 270, 404), fill=255)
    d.ellipse((232, 398, 280, 446), fill=255)


EMBLEMS = {"Tank": (shield, 0), "Healer": (cross, 0), "Damager": (sword, -45)}


def badge(role):
    hi, lo = ROLES[role]
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Saum, Goldring, Rollenfarbe.
    img.paste(solid(EDGE), (0, 0), disc(252))
    img.paste(gradient([(0, GOLD_HI), (0.45, GOLD_MID), (1, GOLD_LO)]), (0, 0), disc(240))
    img.paste(solid(EDGE), (0, 0), disc(206))
    img.paste(gradient([(0, hi), (1, lo)]), (0, 0), disc(198))
    # Glanz oben in der Rollenfarbe.
    shine = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shine).ellipse((C - 150, C - 186, C + 150, C - 30), fill=90)
    shine = Image.composite(shine.filter(ImageFilter.GaussianBlur(20)), Image.new("L", (S, S), 0), disc(198))
    img.paste(solid((255, 255, 255)), (0, 0), shine)

    # Zeichen: dunkler Saum, darüber Silber von hell nach dunkel.
    draw, angle = EMBLEMS[role]
    m = Image.new("L", (S, S), 0)
    draw(ImageDraw.Draw(m))
    if angle:
        m = m.rotate(angle, resample=Image.BICUBIC, center=(C, C))
    img.paste(solid(EDGE), (0, 0), m.filter(ImageFilter.MaxFilter(25)))
    img.paste(gradient([(0, SILVER_HI), (0.55, (215, 220, 230)), (1, SILVER_LO)]), (0, 0), m)

    return img.resize((64, 64), Image.LANCZOS)


for role in ROLES:
    badge(role).save(TEX / f"Role-{role}.tga", rle=False)
