"""Rollen-Symbole für Notizen: Tank, Heiler, Schaden.

Im Stil des Logos: runde Plakette mit dünnem Goldring und dunklem Saum,
innen die Farbe der Rolle (blau, grün, rot), darauf ein großes weißes
Zeichen - Schild, Kreuz, Schwert. Im Text stehen die Symbole in
Zeilenhöhe (rund 14 px), deshalb füllt das Zeichen fast die ganze
Plakette und Ring wie Glanz bleiben schmal. Gezeichnet auf 512 px,
verkleinert auf 64 px (Zweierpotenz, 32 Bit, unkomprimiertes TGA).

Aufruf: python roles.py   (schreibt nach ..\\Textures)
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

TEX = Path(__file__).parent.parent / "Textures"
TEX.mkdir(exist_ok=True)

S = 512
C = S // 2
GOLD_HI, GOLD_MID, GOLD_LO = (255, 232, 150), (214, 160, 60), (110, 66, 20)
SILVER_HI, SILVER_LO = (255, 255, 255), (190, 198, 212)
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
    d.polygon([(110, 104), (256, 72), (402, 104), (402, 250), (372, 336),
               (256, 448), (140, 336), (110, 250)], fill=255)


def cross(d):
    d.rounded_rectangle((196, 76, 316, 436), radius=20, fill=255)
    d.rounded_rectangle((76, 196, 436, 316), radius=20, fill=255)


def sword(d):
    d.polygon([(256, 40), (316, 110), (308, 316), (204, 316), (196, 110)], fill=255)
    d.rounded_rectangle((140, 306, 372, 356), radius=14, fill=255)
    d.rectangle((230, 356, 282, 430), fill=255)
    d.ellipse((222, 418, 290, 486), fill=255)


EMBLEMS = {"Tank": (shield, 0), "Healer": (cross, 0), "Damager": (sword, -45)}


def badge(role):
    hi, lo = ROLES[role]
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Saum, schmaler Goldring, Rollenfarbe.
    img.paste(solid(EDGE), (0, 0), disc(254))
    img.paste(gradient([(0, GOLD_HI), (0.45, GOLD_MID), (1, GOLD_LO)]), (0, 0), disc(244))
    img.paste(solid(EDGE), (0, 0), disc(226))
    img.paste(gradient([(0, hi), (1, lo)]), (0, 0), disc(220))

    # Zeichen: dunkler Saum, darüber Weiß, unten leicht silbern.
    draw, angle = EMBLEMS[role]
    m = Image.new("L", (S, S), 0)
    draw(ImageDraw.Draw(m))
    if angle:
        m = m.rotate(angle, resample=Image.BICUBIC, center=(C, C))
    img.paste(solid(EDGE), (0, 0), m.filter(ImageFilter.MaxFilter(21)))
    img.paste(gradient([(0, SILVER_HI), (0.6, SILVER_HI), (1, SILVER_LO)]), (0, 0), m)

    return img.resize((64, 64), Image.LANCZOS)


for role in ROLES:
    badge(role).save(TEX / f"Role-{role}.tga", rle=False)
