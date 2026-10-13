"""Package explicitly requested native-size sprites and author original audio.

Generated artwork stays untouched in sources/. Runtime extraction is deterministic;
no generative service, credentials, or paid API is used by this script.
"""
from pathlib import Path
import json
import shutil
import wave
import urllib.request
from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "presentation"
GEN = Path(r"C:\Users\31992\.codex\generated_images\01a11c84-d31b-74c2-a206-fbc95f80fef0")
SOURCES = {
    "yard": "exec-deefa435-275c-4733-83ae-ce078b04241b.png",
    "materials": "exec-3c7d853b-e080-4169-a7c5-6109451234a3.png",
    "icons": "exec-14b8091a-e43d-4b63-abbe-bccbdf6ace39.png",
    "effects": "exec-3cdf2748-2843-4d3c-83ef-060943533829.png",
    "logo": "exec-5b737cfe-2171-40b3-ba1a-06d862e1b328.png",
}

def save(im, name):
    target = OUT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    im.save(target)

def cell(im, x, y, cols, rows):
    return im.crop((round(x*im.width/cols), round(y*im.height/rows),
                    round((x+1)*im.width/cols), round((y+1)*im.height/rows)))

def fit(im, size, padding=2):
    bounds = im.getchannel("A").point(lambda p: 255 if p > 64 else 0).getbbox()
    if bounds:
        im = im.crop(bounds)
    ratio = (size - 2*padding) / max(im.size)
    im = im.resize((max(1, round(im.width*ratio)), max(1, round(im.height*ratio))),
                   Image.Resampling.NEAREST)
    result = Image.new("RGBA", (size, size))
    result.alpha_composite(im, ((size-im.width)//2, size-padding-im.height))
    return result

def pack_art():
    for key, name in SOURCES.items():
        (OUT / "sources").mkdir(parents=True, exist_ok=True)
        source=OUT / "sources" / (key + ".png")
        if not source.exists():
            shutil.copy2(GEN / name, source)
    yard = Image.open(OUT / "sources/yard.png").convert("RGBA").resize((960,540), Image.Resampling.NEAREST)
    save(yard, "yard.png")
    # Same canvas and anchors across opaque backdrop and transparent near-ground layer.
    near = Image.new("RGBA", yard.size)
    near.alpha_composite(yard.crop((0, 500, 960, 540)), (0,500))
    far = yard.copy()
    far.paste(yard.crop((0,499,960,500)).resize((960,41)), (0,499))
    save(far, "backdrop.png")
    save(near, "foreground.png")
    from build_hydraulic_launcher import build
    build()
    logo = Image.open(OUT/"sources/logo.png").convert("RGBA")
    bounds = logo.getchannel("A").point(lambda p: 255 if p > 64 else 0).getbbox()
    logo = logo.crop(bounds)
    save(logo.resize((420,round(420*logo.height/logo.width)),Image.Resampling.NEAREST),"logo.png")
    icons = Image.open(OUT / "sources/icons.png").convert("RGBA")
    for i, name in enumerate(["hammer", "coin", "bomb", "gear", "building", "upgrade", "lock", "rebirth"]):
        save(fit(cell(icons,i%4,i//4,4,2),24,2), "icons/" + name + ".png")
    tiles = Image.open(OUT / "sources/materials.png").convert("RGBA")
    names = ["plaster", "glass", "limestone", "marble", "float_glass", "concrete",
             "brick", "tempered_glass", "ceramic", "granite", "steel", "cracked"]
    for i, name in enumerate(names):
        tile = cell(tiles,i%4,i//4,4,3).resize((20,20),Image.Resampling.NEAREST)
        save(tile, "materials/" + name + ".png")
        # Pre-baked 6x6 shards: no image readback or random pixel masking during play.
        shards = Image.new("RGBA",(24,6))
        for j in range(4):
            chunk = tile.crop((j*4, j*3, j*4+6, j*3+6))
            mask = Image.new("L",(6,6),0)
            from PIL import ImageDraw
            ImageDraw.Draw(mask).polygon([(1,0),(5,1),(4,5),(0,4)],fill=255)
            chunk.putalpha(mask)
            shards.alpha_composite(chunk,(j*6,0))
        save(shards,"shards/"+name+".png")
    fx = Image.open(OUT / "sources/effects.png").convert("RGBA")
    # Generator output contains unequal cell widths and a large row gap. Use
    # inspected separators, discard low-alpha noise, and preserve frame scale.
    cuts = [0,220,445,710,1015,1300,1550,1810,fx.width]
    for row,name in enumerate(["blast","dust"]):
        sheet = Image.new("RGBA",(512,64))
        frames = []
        for i in range(8):
            y0,y1 = (110,435) if row == 0 else (495,670)
            frame = fx.crop((cuts[i],y0,cuts[i+1],y1))
            frame.putalpha(frame.getchannel("A").point(lambda p: 255 if p > 160 else 0))
            bounds=frame.getbbox()
            frames.append(frame.crop(bounds) if bounds else Image.new("RGBA",(1,1)))
        common_scale = 60/max(max(frame.size) for frame in frames)
        for i,source in enumerate(frames):
            source=source.resize((max(1,round(source.width*common_scale)),max(1,round(source.height*common_scale))),Image.Resampling.NEAREST)
            frame=Image.new("RGBA",(64,64))
            frame.alpha_composite(source,((64-source.width)//2,(64-source.height)//2 if row==0 else 62-source.height))
            sheet.alpha_composite(frame,(i*64,0))
        save(sheet,"fx/"+name+".png")

RATE = 44100
RNG = np.random.default_rng(719)

def tone(freq, length, volume=1.0, kind="pluck"):
    t = np.arange(round(length*RATE))/RATE
    if kind == "bass":
        y = np.sin(2*np.pi*freq*t) + .22*np.sin(4*np.pi*freq*t)
        env = np.minimum(t/.012,1)*np.exp(-t*5)
    elif kind == "bell":
        y = np.sin(2*np.pi*freq*t) + .25*np.sin(2*np.pi*freq*2.01*t)
        env = np.minimum(t/.005,1)*np.exp(-t*7)
    else:
        y = np.sin(2*np.pi*freq*t) + .3*np.sin(4*np.pi*freq*t)+.12*np.sin(6*np.pi*freq*t)
        env = np.minimum(t/.008,1)*np.exp(-t*4)
    return y * env * volume * np.minimum((length-t)/.025,1).clip(0,1)

def write_wav(path, data, peak=.62):
    data = np.nan_to_num(data)
    data *= peak/max(float(np.max(np.abs(data))),.001)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path),"wb") as w:
        w.setnchannels(1 if data.ndim == 1 else 2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((data.clip(-1,1)*32767).astype("<i2").tobytes())

def music(name, energetic=False):
    beat = .6  # 100 BPM, sixteen 4/4 bars, seamless 38.4 second loop.
    duration = beat*64
    out = np.zeros((round(duration*RATE),2),dtype=np.float64)
    chords = [[60,64,67],[57,60,64],[53,57,60],[55,59,62]]
    melody = [0,2,1,2,0,1,2,1,2,1,0,1,2,1,0,2]
    def add(signal, at, pan=0):
        start = round(at*RATE)
        count = min(len(signal),len(out)-start)
        if count>0:
            out[start:start+count,0] += signal[:count]*(.65-.25*pan)
            out[start:start+count,1] += signal[:count]*(.65+.25*pan)
    for bar in range(16):
        chord = chords[(bar//2)%4]
        for step in range(8):
            note = chord[melody[(bar*3+step)%len(melody)]] + 12
            if energetic or step%2==0:
                add(tone(440*2**((note-69)/12),.48,.12,"bell"),(bar*4+step*.5)*beat,(-1)**step*.6)
        for step in range(4):
            note = chord[0]-24 + (7 if step==2 else 0)
            add(tone(440*2**((note-69)/12),.5,.16,"bass"),(bar*4+step)*beat)
        for note in chord:
            add(tone(440*2**((note-69)/12),2.1,.055),(bar*4)*beat)
        if energetic:
            for step in range(8):
                noise = RNG.normal(0,.025,round(RATE*.06))
                noise *= np.exp(-np.arange(len(noise))/RATE*70)
                add(noise,(bar*4+step*.5)*beat,.25)
            for step in [0,2]:
                t=np.arange(round(RATE*.18))/RATE
                kick=np.sin(2*np.pi*(58*t+5*(1-np.exp(-t*30))))*np.exp(-t*28)*.19
                add(kick,(bar*4+step)*beat)
    # Circular short echo preserves loop continuity.
    out += np.roll(out,round(beat*.75*RATE),axis=0)*.14
    write_wav(OUT/"audio"/(name+".wav"),out,.48)

def sfx():
    for name in ["hammer_swing","hammer_hit","shatter_glass","shatter_stone","shatter_metal",
                 "collapse","coin","explosion","launcher_shoot","launcher_deploy","damage_tick",
                 "ui_click","ui_hover","upgrade","error","onboarding_pop","scene_transition"]:
        length = {"explosion":.65,"collapse":.75,"launcher_deploy":.5,"scene_transition":.35,
                  "upgrade":.45,"shatter_glass":.42,"shatter_stone":.3,"shatter_metal":.4}.get(name,.16)
        t=np.arange(round(length*RATE))/RATE
        noise=RNG.normal(0,1,len(t))
        low=np.convolve(noise,np.ones(21)/21,"same")
        if name in ["coin","upgrade","onboarding_pop"]:
            data=np.zeros(len(t))
            for j,f in enumerate([880,1108,1320] if name=="upgrade" else [1174,1568]):
                note=tone(f,length-j*.07,.22,"bell")
                start=round(j*.07*RATE)
                data[start:start+len(note)] += note[:len(data)-start]
        elif name in ["explosion","collapse"]:
            data=(low*.9+noise*.06+np.sin(2*np.pi*(70*t+6*(1-np.exp(-t*20))))*.28)*np.exp(-t*7)
        elif name=="shatter_glass":
            data=noise*.08*np.exp(-t*15)
            for f in [2100,2850,3700]:
                data+=tone(f,length,.15,"bell")
        elif name=="shatter_metal":
            data=tone(430,length,.3,"bell")+tone(830,length,.2,"bell")+low*.14*np.exp(-t*15)
        elif name in ["hammer_swing","scene_transition"]:
            data=low*np.sin(np.pi*t/length)**2
        elif name in ["hammer_hit","shatter_stone","launcher_shoot","launcher_deploy"]:
            data=(low*.8+tone(160,length,.3,"bass"))*np.exp(-t*9)
        else:
            data=tone(340 if name=="error" else 740,length,.3,"bell")+low*.05*np.exp(-t*20)
        data *= np.minimum(t/.002,1)*np.minimum((length-t)/.012,1).clip(0,1)
        write_wav(OUT/"audio/sfx"/(name+".wav"),data,.48 if name in ["coin","ui_hover","damage_tick"] else .68)

def fonts():
    entries = {
        "NotoSansCJKsc-Regular.otf": "https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf",
        "Noto-OFL.txt": "https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/LICENSE",
        "JetBrainsMono-Regular.ttf": "https://raw.githubusercontent.com/JetBrains/JetBrainsMono/master/fonts/ttf/JetBrainsMono-Regular.ttf",
        "JetBrains-OFL.txt": "https://raw.githubusercontent.com/JetBrains/JetBrainsMono/master/OFL.txt",
    }
    for filename,url in entries.items():
        target=OUT/"fonts"/filename
        target.parent.mkdir(parents=True,exist_ok=True)
        if not target.exists():
            urllib.request.urlretrieve(url,target)

if __name__=="__main__":
    pack_art()
    sfx()
    fonts()
    manifest = {"generator":"Built-in imagegen; procedural sound effects; original user BGM",
                "seed":719,"runtime_sizes":{"materials":[20,20],"launcher":[64,64],"icons":[24,24],"background":[960,540]},
                "source_art":dict(SOURCES, launcher="sources/hydraulic/hydraulic_launcher.svg"),"audio_rate":RATE,
                "bgm_files":["assets/audio/bgm/BGM1.mp3","assets/audio/bgm/bgm2.mp3"],
                "launcher_authoring":"Original editable pixel primitives; text-only generated concept; no borrowed sprite input",
                "original_assets":"Preserved in assets/ui, assets/launcher, assets/audio, assets/fx"}
    (OUT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    print("ASSET_PACKAGE_COMPLETE")
