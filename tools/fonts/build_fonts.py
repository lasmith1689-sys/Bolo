"""Builds the fonts the app bundles from the upstream google/fonts files (SIL OFL 1.1).

Eczar ships only as a variable font; iOS is most reliable with static faces, so this cuts static
Regular/Medium/SemiBold instances, plus a slanted Medium for romanization (Eczar has no italic, and
iOS does not synthesize one for custom fonts). Hind Vadodara is copied as is. Neither family declares
a Reserved Font Name, so modified versions may keep the name.

  python3 tools/fonts/build_fonts.py <dir with Eczar[wght].ttf and HindVadodara-*.ttf> App/Resources/Fonts
"""
import math
import os
import shutil
import sys

from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)


def set_names(font, family, style, ps):
    name = font["name"]
    for rec in list(name.names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17, 25):
            name.removeNames(nameID=rec.nameID)
    for nid, value in ((1, family), (2, style), (3, f"{ps};bolo"), (4, f"{family} {style}"), (6, ps)):
        name.setName(value, nid, 3, 1, 0x409)
        name.setName(value, nid, 1, 0, 0)


def instance(weight, style):
    vf = TTFont(os.path.join(src, "eczar-Eczar[wght].ttf"))
    font = instantiateVariableFont(vf, {"wght": weight})
    font["OS/2"].usWeightClass = weight
    set_names(font, "Eczar", style, f"Eczar-{style}")
    return font


def slant(font, degrees=11):
    skew = math.tan(math.radians(degrees))
    glyf, gs = font["glyf"], font.getGlyphSet()
    order = font.getGlyphOrder()
    new = {}
    for gname in order:
        pen = TTGlyphPen(gs)
        gs[gname].draw(TransformPen(pen, (1, 0, skew, 1, 0, 0)))
        new[gname] = pen.glyph()
    for gname in order:
        glyf[gname] = new[gname]
    hmtx = font["hmtx"]
    for gname in order:
        adv, _ = hmtx[gname]
        g = glyf[gname]
        g.recalcBounds(glyf)
        hmtx[gname] = (adv, getattr(g, "xMin", 0))
    font["post"].italicAngle = -degrees
    font["OS/2"].fsSelection = (font["OS/2"].fsSelection | 0x01) & ~0x40
    font["head"].macStyle |= 0x02
    font["hhea"].caretSlopeRise, font["hhea"].caretSlopeRun = 1000, int(1000 * skew)
    for tag in ("fpgm", "prep", "cvt ", "hdmx", "LTSH", "VDMX", "gasp"):
        if tag in font:
            del font[tag]
    return font


for weight, style in ((400, "Regular"), (500, "Medium"), (600, "SemiBold")):
    instance(weight, style).save(os.path.join(out, f"Eczar-{style}.ttf"))
italic = slant(instance(500, "MediumItalic"))
set_names(italic, "Eczar", "Medium Italic", "Eczar-MediumItalic")
italic.save(os.path.join(out, "Eczar-MediumItalic.ttf"))

for style in ("Regular", "Medium", "SemiBold", "Bold"):
    shutil.copy(os.path.join(src, f"hindvadodara-HindVadodara-{style}.ttf"), os.path.join(out, f"HindVadodara-{style}.ttf"))
shutil.copy(os.path.join(src, "eczar-OFL.txt"), os.path.join(out, "Eczar-OFL.txt"))
shutil.copy(os.path.join(src, "hindvadodara-OFL.txt"), os.path.join(out, "HindVadodara-OFL.txt"))

for f in sorted(os.listdir(out)):
    if f.endswith(".ttf"):
        t = TTFont(os.path.join(out, f))
        print(f, "|", t["name"].getDebugName(1), "|", t["name"].getDebugName(2), "|", t["name"].getDebugName(6),
              "| wght", t["OS/2"].usWeightClass, "| italicAngle", t["post"].italicAngle, "|", os.path.getsize(os.path.join(out, f)))
