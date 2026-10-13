# Separate checkout and Godot user directory for scene-art screenshots and regressions.
param([ValidateSet('scene-art','building-depth')][string]$ArtifactGroup = 'scene-art')
$ErrorActionPreference = 'Stop'
$source = Split-Path $PSScriptRoot -Parent
$target = Join-Path (Split-Path $source -Parent) 'boomame-scene-art-validation'
New-Item -ItemType Directory -Force -Path $target | Out-Null
foreach ($folder in @('scripts','scenes','assets','tools')) {
    robocopy (Join-Path $source $folder) (Join-Path $target $folder) /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Copy failed: $LASTEXITCODE" }
}
$data = [IO.File]::ReadAllText((Join-Path $source 'project.godot'))
$data = $data.Replace('config/name="Boomame"','config/name="BoomamePresentationValidationMotionSceneArtValidation"')
$data = [regex]::Replace($data,'(?m)^MCPGameBridge=.*\r?\n','')
$data = [regex]::Replace($data,'(?m)^enabled=PackedStringArray\(.*\)','enabled=PackedStringArray()')
[IO.File]::WriteAllText((Join-Path $target 'project.godot'),$data,[Text.UTF8Encoding]::new($false))
# Existing suites keep their isolation guards; redirect only the validation copies.
$artifactRoot = "E:/godotproject/boomame/artifacts/$ArtifactGroup"
foreach ($suite in @('presentation','motion','collapse','ui_refresh','scene_art')) {
    $file = Join-Path $target "tools\${suite}_verify.gd"
    $text = [IO.File]::ReadAllText($file)
    $text = $text.Replace('BoomameCollapseValidation','SceneArtValidation').Replace('BoomameDemoValidation','SceneArtValidation')
    $text = $text.Replace('E:/godotproject/boomame/artifacts/motion/after',"$artifactRoot/regression/motion")
    $text = $text.Replace('E:/godotproject/boomame/artifacts/collapse',"$artifactRoot/regression/collapse")
    $text = $text.Replace('E:/godotproject/boomame/artifacts/ui-refresh',"$artifactRoot/regression/ui")
    $text = $text.Replace('var output := "E:/godotproject/boomame/artifacts"',('var output := "'+$artifactRoot+'/regression/presentation"'))
    if ($suite -eq 'scene_art') { $text = $text.Replace('E:/godotproject/boomame/artifacts/scene-art',$artifactRoot) }
    [IO.File]::WriteAllText($file,$text,[Text.UTF8Encoding]::new($false))
}
Write-Output "Scene-art validation project: $target"
exit 0
