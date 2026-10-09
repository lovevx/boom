"""Get the official matching Godot template and install only Windows x86_64."""
from pathlib import Path
import urllib.request
import zipfile
import os

cache=Path(r"E:\godotproject\boomame-validation\Godot_v4.7.2-stable_export_templates.tpz")
url="https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
if not cache.exists():
    partial=cache.with_suffix(".partial")
    request=urllib.request.Request(url,headers={"User-Agent":"Boomame-build"})
    with urllib.request.urlopen(request,timeout=90) as response,partial.open("wb") as output:
        count=0
        while chunk:=response.read(1024*1024):
            output.write(chunk)
            count+=len(chunk)
            if count % (32*1024*1024) == 0:
                print("TEMPLATE_DOWNLOAD_MB",count//1024//1024,flush=True)
    partial.rename(cache)
destination=Path(os.environ["APPDATA"])/"Godot"/"export_templates"/"4.7.2.stable"
destination.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(cache) as archive:
    for name in ["version.txt","windows_release_x86_64.exe","windows_debug_x86_64.exe"]:
        match=next(item for item in archive.namelist() if item.endswith("/"+name))
        (destination/name).write_bytes(archive.read(match))
print("WINDOWS_EXPORT_TEMPLATES_READY",flush=True)
