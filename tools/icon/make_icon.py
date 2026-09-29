"""Draws the 1024x1024 app icon: the prototype's apple-touch-icon motif (a square and a rotated
square in madder on indigo) with બો in cream, set in the bundled Hind Vadodara. RGB, no alpha,
as App Store Connect requires.

  python3 tools/icon/make_icon.py
"""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
FONT = os.path.join(ROOT, "App/Resources/Fonts/HindVadodara-SemiBold.ttf")

S = 1024
K = 4  # supersample, then downscale for clean edges
NIGHT, MADDER, CREAM = (0x13, 0x1E, 0x33), (0xB0, 0x4A, 0x34), (0xEF, 0xE4, 0xCC)
scale = S * K / 180  # the prototype drew the icon on a 180 x 180 canvas

img = Image.new("RGB", (S * K, S * K), NIGHT)
d = ImageDraw.Draw(img)
w = round(4 * scale)
lo, hi, c = 46 * scale, 134 * scale, 90 * scale
d.rectangle([lo, lo, hi, hi], outline=MADDER, width=w)
r = (hi - lo) / 2 * 2 ** 0.5
d.polygon([(c, c - r), (c + r, c), (c, c + r), (c - r, c)], outline=MADDER, width=w)
font = ImageFont.truetype(FONT, round(62 * scale), layout_engine=ImageFont.Layout.RAQM)
text = "બો"
box = d.textbbox((0, 0), text, font=font, anchor="ls")
x = c - (box[0] + box[2]) / 2
d.text((x, 112 * scale), text, font=font, fill=CREAM, anchor="ls")
img = img.resize((S, S), Image.LANCZOS)
img.save(OUT, optimize=True)
check = Image.open(OUT)
print(OUT, check.size, check.mode)
