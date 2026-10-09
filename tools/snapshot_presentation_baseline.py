"""Capture the pre-upgrade tracked version without touching the working tree."""
from pathlib import Path
import shutil
import subprocess
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT.parent/"boomame-presentation-baseline"
OUT.mkdir(exist_ok=True)
files=subprocess.check_output(["git","ls-files","-z"],cwd=ROOT).decode("utf-8").strip("\0").split("\0")
for name in files:
    if name.startswith(("build/","addons/",".godot/")):
        continue
    target=OUT/name
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_bytes(subprocess.check_output(["git","show","HEAD:"+name],cwd=ROOT))
config=OUT/"project.godot"
text=config.read_text(encoding="utf-8").replace('config/name="Boomame"','config/name="BoomamePresentationBaseline"')
config.write_text(text,encoding="utf-8")
(OUT/"tools").mkdir(exist_ok=True)
shutil.copy2(ROOT/"tools/presentation_capture.gd",OUT/"tools/presentation_capture.gd")
print("BASELINE_SOURCE_READY",OUT)
