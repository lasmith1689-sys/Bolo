"""Renders the block-print motifs (tools/art/motifs/*.svg, drawn on a 0 0 100 100 viewBox) to vector
PDFs in the app's asset catalog as "Motif/<name>", with the vector data preserved so they stay
crisp at any size. The octagonal frame is drawn by the app, not baked in.

  pip install cairosvg && python3 tools/art/render_motifs.py
"""
import glob
import json
import os

import cairosvg

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "tools/art/motifs")
DST = os.path.join(ROOT, "App/Resources/Assets.xcassets/Motif")
INFO = {"author": "xcode", "version": 1}

os.makedirs(DST, exist_ok=True)
json.dump({"info": INFO, "properties": {"provides-namespace": True}}, open(os.path.join(DST, "Contents.json"), "w"), indent=2)
names = []
for svg in sorted(glob.glob(os.path.join(SRC, "*.svg"))):
    name = os.path.splitext(os.path.basename(svg))[0]
    folder = os.path.join(DST, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    cairosvg.svg2pdf(url=svg, write_to=os.path.join(folder, f"{name}.pdf"), output_width=100, output_height=100)
    json.dump({
        "images": [{"filename": f"{name}.pdf", "idiom": "universal"}],
        "info": INFO,
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "original"},
    }, open(os.path.join(folder, "Contents.json"), "w"), indent=2)
    names.append(name)
print(len(names), "motifs:", " ".join(names))
