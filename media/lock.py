"""Schloss-Symbole für angeheftete Notizen: zu und offen.

Im Stil des Logos: Körper aus Gold mit dunklem Saum und Glanzkante,
Bügel aus Stahl, Schlüsselloch eingelassen. Gezeichnet auf 512 px,
verkleinert auf 64 px (Zweierpotenz, 32 Bit, unkomprimiertes TGA).

Aufruf: python lock.py   (schreibt nach ..\\Textures)
"""
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter

TEX = Path(__file__).parent.parent / "Textures"
TEX.mkdir(exist_ok=True)

S = 512
GOLD_HI, GOLD_MID, GOLD_LO = (255, 232, 150), (214, 160, 60), (110, 66, 20)
STEEL_HI, STEEL_LO = (235, 238, 245), (90, 96, 110)
EDGE = (28, 16, 4)


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def mask(draw):
    m = Image.new("L", (S, S), 0)
    draw(ImageDraw.Draw(m))
    return m


def gradient(stops):
    """Senkrechter Verlauf über das ganze Bild, stops: [(t, farbe), ...]."""
    img = Image.new("RGBA", (S, S))
    px = img.load()
    for y in range(S):
        t = y / (S - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                c = mix(c0, c1, (t - t0) / (t1 - t0))
                break
        for x in range(S):
            px[x, y] = c + (255,)
    return img


def fill(base, m, src):
    base.paste(src, (0, 0), m)


def lock(open_):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Bügel: Halbkreis mit zwei Beinen. Offen ist er angehoben, und das
    # rechte Bein steckt nicht mehr im Körper.
    lift = 60 if open_ else 0
    left, right, top, w = 146, 366, 70 - lift, 54
    mid = top + (right - left) // 2

    def shackle(d, grow=0):
        g = grow
        d.arc((left - g, top - g, right + g, top + (right - left) + g), 180, 360,
              fill=255, width=w + 2 * g)
        d.rectangle((left - g, mid, left + w + g, 280), fill=255)
        d.rectangle((right - w - g, mid, right + g, 280 - (120 if open_ else 0)), fill=255)

    fill(img, mask(lambda d: shackle(d, 14)), Image.new("RGBA", (S, S), EDGE + (255,)))
    fill(img, mask(shackle), gradient([(0, STEEL_HI), (0.3, (170, 176, 190)), (0.55, STEEL_LO), (1, STEEL_LO)]))
    # Glanz auf dem Bügel: schmaler heller Streifen innen am Bogen.
    shine = mask(lambda d: d.arc((left + 10, top + 10, right - 10, top + (right - left) - 10),
                                 200, 300, fill=255, width=12))
    fill(img, shine.filter(ImageFilter.GaussianBlur(3)), Image.new("RGBA", (S, S), (255, 255, 255, 255)))

    # Körper: dunkler Saum, Gold von hell nach dunkel, Glanzkante oben.
    body = (88, 228, 424, 486)
    fill(img, mask(lambda d: d.rounded_rectangle((body[0] - 14, body[1] - 14, body[2] + 14, body[3] + 14),
                                                 radius=60, fill=255)),
         Image.new("RGBA", (S, S), EDGE + (255,)))
    fill(img, mask(lambda d: d.rounded_rectangle(body, radius=46, fill=255)),
         gradient([(0, GOLD_HI), (0.5, GOLD_HI), (0.62, GOLD_MID), (0.9, GOLD_LO), (1, GOLD_LO)]))
    inner = mask(lambda d: d.rounded_rectangle((body[0] + 22, body[1] + 22, body[2] - 22, body[3] - 22),
                                               radius=30, fill=255))
    rim = ImageChops.subtract(mask(lambda d: d.rounded_rectangle(body, radius=46, fill=255)), inner)
    fill(img, rim.point(lambda v: v * 0.45), Image.new("RGBA", (S, S), GOLD_LO + (255,)))
    top_shine = mask(lambda d: d.rounded_rectangle((body[0] + 30, body[1] + 14, body[2] - 30, body[1] + 34),
                                                   radius=10, fill=255))
    fill(img, top_shine.filter(ImageFilter.GaussianBlur(4)), Image.new("RGBA", (S, S), (255, 248, 210, 255)))

    # Schlüsselloch: dunkel eingelassen, unten ein Lichtsaum.
    def hole(d, dy=0):
        d.ellipse((222, 300 + dy, 290, 368 + dy), fill=255)
        d.polygon([(238, 346 + dy), (274, 346 + dy), (286, 434 + dy), (226, 434 + dy)], fill=255)

    fill(img, mask(lambda d: hole(d, 6)), Image.new("RGBA", (S, S), GOLD_HI + (255,)))
    fill(img, mask(hole), Image.new("RGBA", (S, S), EDGE + (255,)))

    return img.resize((64, 64), Image.LANCZOS)


lock(False).save(TEX / "Lock.tga", rle=False)
lock(True).save(TEX / "Unlock.tga", rle=False)
