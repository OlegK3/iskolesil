#!/usr/bin/env python3
"""Готовит графику из присланного композита (фото города сверху + иконка №3 снизу).
Запуск: python3 tool/make_icon_assets.py <composite.png>
Создаёт assets/images/iskolesil_home.jpg, iskolesil_icon.png и ресурсы Android в android_overlay/res.
Рисунок иконки не меняется: только вырезка, прозрачность и масштаб под безопасную зону adaptive icon."""
import sys, pathlib
import numpy as np
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
src = Image.open(sys.argv[1]).convert("RGB")
PHOTO_BOTTOM = 1338                      # граница фото (найдена по строкам изображения)
ICON_BOX = (347, 1383, 594, 1629)        # белый скруглённый квадрат иконки

# 1. Фото города (без иконки и серой полосы)
photo = src.crop((0, 0, src.width, PHOTO_BOTTOM))
out_img = ROOT / "assets/images"; out_img.mkdir(parents=True, exist_ok=True)
photo.save(out_img / "iskolesil_home.jpg", quality=92, optimize=True)

# 2. Иконка (квадрат со скруглением, без внешней тени)
icon = src.crop(ICON_BOX)
S = 1024
icon_big = icon.resize((S, S), Image.LANCZOS)
radius = int(S * 0.225)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=radius, fill=255)
rgba = icon_big.convert("RGBA"); rgba.putalpha(mask)
rgba.resize((512, 512), Image.LANCZOS).save(out_img / "iskolesil_icon.png")

# 3. Рисунок (велосипед + метка + линия) отдельно: прозрачный фон
inset = int(S * 0.04)
g = np.asarray(icon_big).astype(float)[inset:-inset, inset:-inset]
alpha = 1.0 - g.min(axis=2) / 255.0
alpha = np.clip((alpha - 0.02) / 0.98, 0, 1)
# отсекаем тень и скругления вне белого квадрата (маска со сдвигом внутрь)
m = Image.new("L", (S, S), 0)
ImageDraw.Draw(m).rounded_rectangle((inset, inset, S - 1 - inset, S - 1 - inset),
                                    radius=max(1, radius - inset), fill=255)
alpha = alpha * (np.asarray(m).astype(float)[inset:-inset, inset:-inset] / 255.0)
a3 = np.maximum(alpha, 1e-6)[..., None]
color = np.clip((g - (1 - a3) * 255) / a3, 0, 255)
ys, xs = np.where(alpha > 0.08)
y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
glyph_rgb = color[y0:y1, x0:x1]
glyph_a = alpha[y0:y1, x0:x1]
gh, gw = glyph_a.shape
print("glyph bbox px (1024 scale):", gw, gh)

# радиус самого дальнего значимого пикселя от центра bbox: по нему подбираем масштаб
yy, xx = np.where(glyph_a > 0.2)
r_max = float(np.max(np.hypot(xx - gw / 2.0, yy - gh / 2.0)))

def layer(canvas, mono=False):
    # безопасная зона adaptive icon: круг диаметром 66/108 холста (радиус 0.305)
    k = (0.30 * canvas) / r_max
    w, h = max(1, round(gw * k)), max(1, round(gh * k))
    rgb = Image.fromarray(glyph_rgb.astype("uint8") if not mono else np.zeros_like(glyph_rgb, dtype="uint8"), "RGB")
    al = Image.fromarray((glyph_a * 255).astype("uint8"), "L")
    rgb = rgb.resize((w, h), Image.LANCZOS); al = al.resize((w, h), Image.LANCZOS)
    im = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    tile = rgb.convert("RGBA"); tile.putalpha(al)
    im.paste(tile, ((canvas - w) // 2, (canvas - h) // 2), tile)
    return im

res = ROOT / "android_overlay/res"
fg = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
leg = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
for d, px in fg.items():
    p = res / f"mipmap-{d}"; p.mkdir(parents=True, exist_ok=True)
    layer(px).save(p / "ic_launcher_foreground.png")
    layer(px, mono=True).save(p / "ic_launcher_monochrome.png")
    rgba.resize((leg[d], leg[d]), Image.LANCZOS).save(p / "ic_launcher.png")
v26 = res / "mipmap-anydpi-v26"; v26.mkdir(parents=True, exist_ok=True)
(v26 / "ic_launcher.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/ic_launcher_background"/>\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
    '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
    '</adaptive-icon>\n', encoding="utf-8")
vals = res / "values"; vals.mkdir(parents=True, exist_ok=True)
(vals / "ic_launcher_background.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
    '    <color name="ic_launcher_background">#FFFFFF</color>\n</resources>\n', encoding="utf-8")
print("ok")
