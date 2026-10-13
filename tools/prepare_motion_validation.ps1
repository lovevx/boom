# Build a separate project and user directory for the rendered motion checks.
$ErrorActionPreference = 'Stop'
$source = Split-Path $PSScriptRoot -Parent
$target = Join-Path (Split-Path $source -Parent) 'boomame-motion-validation'
New-Item -ItemType Directory -Force -Path $target | Out-Null
foreach ($folder in @('scripts','scenes','assets','tools')) {
    robocopy (Join-Path $source $folder) (Join-Path $target $folder) /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Copy failed: $LASTEXITCODE" }
}
$project = Join-Path $target 'project.godot'
$data = [IO.File]::ReadAllText((Join-Path $source 'project.godot'))
$data = $data.Replace('config/name="Boomame"','config/name="BoomamePresentationValidationMotion"')
$data = [regex]::Replace($data,'(?m)^MCPGameBridge=.*\r?\n','')
$data = [regex]::Replace($data,'(?m)^enabled=PackedStringArray\(.*\)','enabled=PackedStringArray()')
[IO.File]::WriteAllText($project,$data,[Text.UTF8Encoding]::new($false))
Write-Output "Motion validation project: $target"
exit 0
