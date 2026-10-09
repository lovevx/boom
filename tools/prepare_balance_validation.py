"""Copy the current project into an isolated validation folder; never use player saves."""
from pathlib import Path
import shutil
import re

source = Path(__file__).resolve().parents[1]
target = source.parent / 'boomame-balance-validation'
shutil.copytree(source, target, ignore=shutil.ignore_patterns('.git', '.godot', 'artifacts', 'build'), dirs_exist_ok=True)
project = target / 'project.godot'
data = project.read_text(encoding='utf-8').replace('config/name="Boomame"', 'config/name="BoomameBalanceValidation"')
data = re.sub(r'^MCPGameBridge=.*\n', '', data, flags=re.M)
data = re.sub(r'^enabled=PackedStringArray\(.*\)\n', 'enabled=PackedStringArray()\n', data, flags=re.M)
project.write_text(data, encoding='utf-8')
print(target)
