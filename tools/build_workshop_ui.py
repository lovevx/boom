"""Editable original nine-slice workshop UI plates. No external artwork input."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/presentation/workshop"

def plate(name, w, h, primary=False, hover=False, pressed=False, disabled=False, panel=False):
    ink = "#07121c"
    rim = "#40586b" if not disabled else "#293b49"
    edge = "#e7a93b" if primary else ("#78d5e5" if hover else "#638297")
    top = "#ffde7b" if primary else ("#35576a" if hover else "#253e50")
    bottom = "#c78b31" if primary else "#112330"
    if pressed:
        top,bottom = bottom,top
    if disabled:
        top,bottom,edge = "#202d37","#17232d","#364c5b"
    cut = 10 if panel else 7
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">',
           f'<defs><linearGradient id="metal" x2="0" y2="1"><stop stop-color="{top}"/><stop offset=".48" stop-color="{bottom}"/><stop offset="1" stop-color="{top}"/></linearGradient></defs>']
    def poly(points, fill, opacity=1):
        svg.append(f'<polygon points="{points}" fill="{fill}" opacity="{opacity}"/>')
    def rect(x,y,r,b,fill,opacity=1):
        svg.append(f'<rect x="{x}" y="{y}" width="{r-x}" height="{b-y}" fill="{fill}" opacity="{opacity}"/>')
    poly(f'0,{cut} {cut},0 {w-cut},0 {w},{cut} {w},{h-cut} {w-cut},{h} {cut},{h} 0,{h-cut}',ink)
    poly(f'3,{cut} {cut},3 {w-cut},3 {w-3},{cut} {w-3},{h-cut} {w-cut},{h-3} {cut},{h-3} 3,{h-cut}',rim)
    poly(f'5,{cut+1} {cut+1},5 {w-cut-1},5 {w-5},{cut+1} {w-5},{h-cut-1} {w-cut-1},{h-5} {cut+1},{h-5} 5,{h-cut-1}','url(#metal)')
    rect(cut+2,5,w-cut-2,7,edge)
    rect(cut+2,h-9,w-cut-2,h-5,ink,.65)
    rect(7,cut+4,9,h-cut-4,edge,.35)
    rect(w-9,cut+4,w-7,h-cut-4,ink,.8)
    # An inset gasket, beveled corners, and real screw heads, fixed by nine-slicing.
    for x,y in [(12,12),(w-12,12),(12,h-12),(w-12,h-12)]:
        poly(f'{x-4},{y-2} {x-2},{y-4} {x+2},{y-4} {x+4},{y-2} {x+4},{y+2} {x+2},{y+4} {x-2},{y+4} {x-4},{y+2}',ink)
        rect(x-2,y-2,x+3,y+2,"#859aa5" if not primary else "#806335")
        rect(x-1,y-2,x+2,y-1,"#c6d0cf")
        rect(x-2,y,x+3,y+1,ink)
    if panel:
        rect(23,17,w-23,19,ink,.8)
        rect(23,h-20,w-23,h-18,"#698191",.6)
        # Offset diagonal warning inlays at both lower corners.
        for x in [24,32,40,48]:
            poly(f'{x},{h-14} {x+5},{h-14} {x+10},{h-7} {x+5},{h-7}',"#dba239")
            poly(f'{w-x-10},{h-14} {w-x-5},{h-14} {w-x},{h-7} {w-x-5},{h-7}',"#dba239")
        for y in range(28,h-30,6):
            rect(11,y,15,y+2,ink,.7)
            rect(w-15,y,w-11,y+2,ink,.7)
    elif primary:
        for x in [22,30,38]:
            poly(f'{x},{h-12} {x+4},{h-12} {x+8},{h-7} {x+4},{h-7}',ink,.55)
        rect(22,10,w-22,12,"#fff1bd",.65)
    else:
        rect(24,10,w-24,11,"#b6d5dc",.22)
    svg.append('</svg>')
    (OUT/f'{name}.svg').write_text('\n'.join(svg),encoding='utf-8')

def build():
    OUT.mkdir(parents=True,exist_ok=True)
    for name,args in {
        'steel':{},'steel_hover':{'hover':True},'steel_pressed':{'pressed':True},
        'gold':{'primary':True},'gold_hover':{'primary':True,'hover':True},
        'gold_pressed':{'primary':True,'pressed':True},'disabled':{'disabled':True},
    }.items():
        plate(name,128,64,**args)
    plate('panel',192,192,panel=True)
    print('Workshop plates authored: 8 editable SVG nine-slice textures')

if __name__=='__main__':
    build()
