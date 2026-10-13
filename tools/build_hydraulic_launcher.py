"""Original, editable pixel artwork. No borrowed sprite is read by this builder.

SVG groups and JSON primitives are the layered source; PNGs are runtime exports.
The separately saved generated concept was made from text only.
"""
from pathlib import Path
import json
import math
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/presentation"
INK, DARK, STEEL, LIGHT = "#0b1828", "#26394e", "#52677b", "#a9bccb"
YELLOW, SHADE, GOLD, CYAN = "#ffc857", "#b97522", "#ffe49b", "#76d6ed"
layers = {"tracks": [], "chassis": [], "hydraulics": [], "barrel": []}

def poly(layer, points, color):
    layers[layer].append({"type": "polygon", "points": points, "fill": color})

def rect(layer, box, color):
    layers[layer].append({"type": "rect", "box": box, "fill": color})

def author():
    poly("tracks", [(7,49),(56,49),(62,54),(62,59),(57,63),(7,63),(2,59),(2,54)], INK)
    poly("tracks", [(8,51),(55,51),(60,55),(60,58),(56,61),(8,61),(4,58),(4,55)], STEEL)
    rect("tracks", (10,53,54,59), DARK)
    for x in [10,21,32,43,54]:
        poly("tracks", [(x-3,54),(x-1,52),(x+2,52),(x+4,54),(x+4,57),(x+2,59),(x-1,59),(x-3,57)], INK)
        rect("tracks", (x-1,54,x+2,57), STEEL)
        rect("tracks", (x,54,x+1,55), LIGHT)
    for x in range(9,57,6):
        rect("tracks", (x,50,x+3,51), LIGHT)
        rect("tracks", (x,61,x+3,62), STEEL)
    poly("chassis", [(11,45),(20,42),(35,42),(39,35),(55,35),(59,39),(59,49),(11,49)], INK)
    poly("chassis", [(13,46),(22,44),(37,44),(40,37),(54,37),(57,40),(57,47),(13,47)], YELLOW)
    rect("chassis", (14,48,57,49), SHADE)
    rect("chassis", (40,38,53,39), GOLD)
    rect("chassis", (44,41,53,45), DARK)
    for y in [41,43,45]:
        rect("chassis", (45,y,52,y), INK)
    rect("chassis", (36,42,41,46), INK)
    rect("chassis", (37,43,38,45), CYAN)
    rect("chassis", (40,43,40,45), CYAN)
    rect("chassis", (52,32,56,35), INK)
    rect("chassis", (53,31,55,34), "#ff9638")
    rect("chassis", (53,31,54,32), GOLD)
    for x,y in [(15,46),(40,40),(55,46)]:
        rect("chassis", (x,y,x+1,y+1), INK)
    poly("hydraulics", [(20,32),(23,31),(37,43),(34,47)], INK)
    poly("hydraulics", [(22,33),(23,33),(31,40),(29,42)], LIGHT)
    poly("hydraulics", [(28,39),(31,37),(37,43),(34,46)], DARK)
    poly("hydraulics", [(29,40),(31,39),(35,43),(34,44)], CYAN)
    poly("barrel", [(5,19),(10,12),(15,13),(41,30),(43,37),(37,43),(30,40),(8,25)], INK)
    poly("barrel", [(8,19),(11,15),(15,16),(37,31),(34,38),(10,24)], STEEL)
    poly("barrel", [(13,16),(16,17),(37,31),(36,33)], LIGHT)
    poly("barrel", [(11,23),(34,37),(32,39),(10,25)], DARK)
    poly("barrel", [(8,19),(11,15),(13,16),(10,22),(9,23),(7,22)], INK)
    poly("barrel", [(16,18),(18,19),(14,27),(12,26)], YELLOW)
    poly("barrel", [(26,24),(29,26),(24,33),(21,31)], YELLOW)
    poly("barrel", [(34,28),(40,31),(41,36),(37,40),(32,38),(30,35)], SHADE)
    poly("barrel", [(35,30),(39,32),(39,35),(36,38),(33,36)], YELLOW)
    rect("barrel", (35,33,37,35), INK)
    rect("barrel", (36,33,37,34), STEEL)
    rect("barrel", (21,24,22,25), DARK)

def draw_layer(shapes, offset=(0,0)):
    im = Image.new("RGBA", (64,64))
    d = ImageDraw.Draw(im)
    ox,oy = offset
    for s in shapes:
        if s["type"] == "rect":
            x,y,r,b = s["box"]
            d.rectangle((x+ox,y+oy,r+ox,b+oy), fill=s["fill"])
        else:
            d.polygon([(x+ox,y+oy) for x,y in s["points"]], fill=s["fill"])
    return im

def build():
    if not layers["tracks"]:
        author()
    source = OUT / "sources/hydraulic"
    source.mkdir(parents=True, exist_ok=True)
    (source/"layers.json").write_text(json.dumps(layers, indent=2), encoding="utf-8")
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="640" height="640" viewBox="0 0 64 64" shape-rendering="crispEdges">']
    for name, shapes in layers.items():
        svg.append(f'<g id="{name}">')
        draw_layer(shapes).save(source/f"{name}.png")
        for s in shapes:
            if s["type"] == "rect":
                x,y,r,b = s["box"]
                svg.append(f'<rect x="{x}" y="{y}" width="{r-x+1}" height="{b-y+1}" fill="{s["fill"]}"/>')
            else:
                pts = " ".join(f"{x},{y}" for x,y in s["points"])
                svg.append(f'<polygon points="{pts}" fill="{s["fill"]}"/>')
        svg.append('</g>')
    svg.append('</svg>')
    (source/"hydraulic_launcher.svg").write_text("\n".join(svg), encoding="utf-8")
    attack = Image.new("RGBA", (64*33,64))
    for index in range(33):
        recoil = 2 if 20 <= index < 24 else (1 if 24 <= index < 28 else (-1 if 14 <= index < 20 else 0))
        im = Image.new("RGBA", (64,64))
        for name, shapes in layers.items():
            offset = (recoil, max(0,recoil//2)) if name in ["hydraulics","barrel"] else (0,0)
            im.alpha_composite(draw_layer(shapes,offset))
        if index == 0:
            im.save(OUT/"launcher.png")
            im.resize((512,512),Image.Resampling.NEAREST).save(source/"preview.png")
        attack.alpha_composite(im,(index*64,0))
    attack.save(OUT/"launcher_attack.png")
    (source/"provenance.json").write_text(json.dumps({
        "authoring":"Original pixel primitives and editable SVG groups; text-only generated concept",
        "borrowed_art_inputs":[], "canvas":[64,64], "frames":33, "fps":16,
        "fire_frame":20, "fire_muzzle":[10,21], "ground_pixel":63,
        "layers":list(layers), "runtime":["launcher.png","launcher_attack.png","launcher_frames.tres"]
    },indent=2),encoding="utf-8")
    print("Original hydraulic cannon: 64x64, 33 attack frames, editable SVG and four PNG layers")

if __name__ == "__main__":
    build()
