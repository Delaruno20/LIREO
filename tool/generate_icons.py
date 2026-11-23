"""Génère les icônes de LIREO à partir du logo « livre ouvert » (LireoMark).

Reprend la géométrie de _MarkPainter (lib/features/splash/splash_screen.dart) :
- Android : icône adaptative vectorielle (fond, premier plan, monochrome) + PNG
  pour les lanceurs antérieurs à Android 8 ;
- iOS : toutes les tailles de AppIcon.appiconset ;
- assets/icon/lireo_icon.png : image maître 1024 px.

Usage : python3 tool/generate_icons.py (depuis la racine du projet).
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent

# Couleurs de la palette « Bibliothèque chaleureuse ».
BG_TOP = "#B57A45"
BG_BOTTOM = "#8A5530"
PAGE = "#FFF9F0"
INK = "#A0683A"
RIBBON = "#E2B55C"

# Le logo occupe 54 unités sur le canevas adaptatif de 108 (zone sûre : cercle de 66).
CANVAS = 108.0
MARK_W = 54.0
MARK_H = MARK_W * 0.78
MARK_X = (CANVAS - MARK_W) / 2
MARK_Y = CANVAS / 2 - MARK_H * 0.53


def pt(x, y):
    """Coordonnées relatives au logo -> unités du canevas 108."""
    return (MARK_X + x * MARK_W, MARK_Y + y * MARK_H)


# Chaque page : point de départ, puis segments ('Q', contrôle, fin) ou ('L', fin).
LEFT_PAGE = [(0.5, 0.2), ("Q", (0.3, 0.04), (0.04, 0.1)), ("L", (0.04, 0.86)), ("Q", (0.3, 0.8), (0.5, 0.96))]
RIGHT_PAGE = [(0.5, 0.2), ("Q", (0.7, 0.04), (0.96, 0.1)), ("L", (0.96, 0.86)), ("Q", (0.7, 0.8), (0.5, 0.96))]
TEXT_LINES = [((0.14, 0.34 + i * 0.16), (0.38, 0.36 + i * 0.16)) for i in range(3)]
LINE_WIDTH = MARK_W * 0.035
RIBBON_SHAPE = [(0.7, 0.12), (0.8, 0.1), (0.8, 0.46), (0.75, 0.4), (0.7, 0.46)]


def path_data(shape):
    start, *segments = shape
    parts = ["M%.2f,%.2f" % pt(*start)]
    for seg in segments:
        if seg[0] == "Q":
            parts.append("Q%.2f,%.2f %.2f,%.2f" % (*pt(*seg[1]), *pt(*seg[2])))
        else:
            parts.append("L%.2f,%.2f" % pt(*seg[1]))
    return " ".join(parts) + " Z"


def polygon_data(points):
    return "M" + " L".join("%.2f,%.2f" % pt(*p) for p in points) + " Z"


def line_data(a, b):
    return "M%.2f,%.2f L%.2f,%.2f" % (*pt(*a), *pt(*b))


def sample(shape, steps=48):
    """Approxime un chemin en polygone (unités du canevas) pour Pillow."""
    start, *segments = shape
    pts = [pt(*start)]
    cur = start
    for seg in segments:
        if seg[0] == "Q":
            (cx, cy), (ex, ey) = seg[1], seg[2]
            for i in range(1, steps + 1):
                t = i / steps
                x = (1 - t) ** 2 * cur[0] + 2 * (1 - t) * t * cx + t * t * ex
                y = (1 - t) ** 2 * cur[1] + 2 * (1 - t) * t * cy + t * t * ey
                pts.append(pt(x, y))
            cur = (ex, ey)
        else:
            cur = seg[1]
            pts.append(pt(*cur))
    return pts


# ---------------------------------------------------------------- Android XML

VECTOR_HEAD = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<vector xmlns:android="http://schemas.android.com/apk/res/android"{extra}\n'
    '    android:width="108dp"\n    android:height="108dp"\n'
    '    android:viewportWidth="108"\n    android:viewportHeight="108">\n'
)


def foreground_xml():
    body = [
        f'    <path android:fillColor="{PAGE}" android:fillAlpha="0.78" android:pathData="{path_data(LEFT_PAGE)}" />',
        f'    <path android:fillColor="{PAGE}" android:pathData="{path_data(RIGHT_PAGE)}" />',
    ]
    for a, b in TEXT_LINES:
        body.append(
            f'    <path android:strokeColor="{INK}" android:strokeWidth="{LINE_WIDTH:.2f}" '
            f'android:strokeLineCap="round" android:pathData="{line_data(a, b)}" />'
        )
    body.append(f'    <path android:fillColor="{RIBBON}" android:pathData="{polygon_data(RIBBON_SHAPE)}" />')
    return VECTOR_HEAD.format(extra="") + "\n".join(body) + "\n</vector>\n"


def monochrome_xml():
    # Icônes à thème (Android 13+) : le système teinte la forme, seule l'opacité compte.
    body = [
        f'    <path android:fillColor="#FFFFFF" android:fillAlpha="0.6" android:pathData="{path_data(LEFT_PAGE)}" />',
        f'    <path android:fillColor="#FFFFFF" android:pathData="{path_data(RIGHT_PAGE)}" />',
    ]
    return VECTOR_HEAD.format(extra="") + "\n".join(body) + "\n</vector>\n"


def background_xml():
    return (
        VECTOR_HEAD.format(extra='\n    xmlns:aapt="http://schemas.android.com/aapt"')
        + '    <path android:pathData="M0,0 H108 V108 H0 Z">\n'
        + '        <aapt:attr name="android:fillColor">\n'
        + '            <gradient android:type="linear" android:startX="54" android:startY="0"'
        + ' android:endX="54" android:endY="108">\n'
        + f'                <item android:offset="0" android:color="{BG_TOP}" />\n'
        + f'                <item android:offset="1" android:color="{BG_BOTTOM}" />\n'
        + "            </gradient>\n        </aapt:attr>\n    </path>\n</vector>\n"
    )


ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
"""


# ---------------------------------------------------------------------- PNG


def hex_rgb(h):
    return tuple(int(h[i : i + 2], 16) for i in (1, 3, 5))


def render(size, *, inset=0.0, radius=0.0, alpha=True):
    """Rend l'icône en `size` px. `inset` : part du canevas 108 rognée de chaque
    côté (le fond adaptatif déborde) ; `radius` : arrondi relatif des coins."""
    ss = 4
    big = size * ss
    view = CANVAS - 2 * inset
    scale = big / view

    def tr(p):
        return ((p[0] - inset) * scale, (p[1] - inset) * scale)

    top, bottom = hex_rgb(BG_TOP), hex_rgb(BG_BOTTOM)
    grad = Image.new("RGB", (1, big))
    for y in range(big):
        t = (y / scale + inset) / CANVAS
        grad.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    img = grad.resize((big, big)).convert("RGBA")

    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.polygon([tr(p) for p in sample(LEFT_PAGE)], fill=hex_rgb(PAGE) + (199,))
    img.alpha_composite(layer)
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.polygon([tr(p) for p in sample(RIGHT_PAGE)], fill=hex_rgb(PAGE) + (255,))
    w = LINE_WIDTH * scale
    for a, b in TEXT_LINES:
        pa, pb = tr(pt(*a)), tr(pt(*b))
        d.line([pa, pb], fill=hex_rgb(INK) + (255,), width=round(w))
        for c in (pa, pb):
            d.ellipse([c[0] - w / 2, c[1] - w / 2, c[0] + w / 2, c[1] + w / 2], fill=hex_rgb(INK) + (255,))
    d.polygon([tr(pt(*p)) for p in RIBBON_SHAPE], fill=hex_rgb(RIBBON) + (255,))
    img.alpha_composite(layer)

    if radius:
        mask = Image.new("L", (big, big), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1], radius=radius * big, fill=255)
        img.putalpha(mask)
    img = img.resize((size, size), Image.LANCZOS)
    return img if alpha else img.convert("RGB")


def main():
    res = ROOT / "android/app/src/main/res"
    (res / "drawable/ic_launcher_foreground.xml").write_text(foreground_xml())
    (res / "drawable/ic_launcher_background.xml").write_text(background_xml())
    (res / "drawable/ic_launcher_monochrome.xml").write_text(monochrome_xml())
    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(ADAPTIVE_XML)

    # Lanceurs < Android 8 : carré arrondi, logo un peu agrandi (rognage de 12 unités).
    for name, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        render(px, inset=12, radius=0.2).save(res / f"mipmap-{name}/ic_launcher.png")

    # iOS : carré plein sans transparence, iOS applique lui-même le masque.
    ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for entry in json.loads((ios / "Contents.json").read_text())["images"]:
        base = float(entry["size"].split("x")[0])
        px = round(base * int(entry["scale"].rstrip("x")))
        render(px, inset=12, alpha=False).save(ios / entry["filename"])

    out = ROOT / "assets/icon"
    out.mkdir(parents=True, exist_ok=True)
    render(1024, inset=12, alpha=False).save(out / "lireo_icon.png")


if __name__ == "__main__":
    main()
