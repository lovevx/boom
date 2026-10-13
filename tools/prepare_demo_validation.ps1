# Prepare an isolated project with a different Godot user directory; player saves stay separate.
$ErrorActionPreference = 'Stop'
$source = Split-Path $PSScriptRoot -Parent
$target = Join-Path (Split-Path $source -Parent) 'boomame-demo-validation'
robocopy $source $target /E /XD .git .godot artifacts build /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -ge 8) { throw "Copy failed: $LASTEXITCODE" }
$project = Join-Path $target 'project.godot'
$data = [IO.File]::ReadAllText($project).Replace('config/name="Boomame"','config/name="BoomameDemoValidation"')
$data = [regex]::Replace($data,'(?m)^MCPGameBridge=.*\r?\n','')
$data = [regex]::Replace($data,'(?m)^enabled=PackedStringArray\(.*\)','enabled=PackedStringArray()')
[IO.File]::WriteAllText($project,$data,[Text.UTF8Encoding]::new($false))
foreach ($suite in @('balance','collapse')) {
    $file = Join-Path $target "tools\${suite}_verify.gd"
    $text = [IO.File]::ReadAllText($file)
    $text = $text.Replace('BoomameBalanceValidation','BoomameDemoValidation').Replace('BoomameCollapseValidation','BoomameDemoValidation')
    $text = $text.Replace("artifacts/$suite", "artifacts/demo-growth/$suite-regression")
    [IO.File]::WriteAllText($file,$text,[Text.UTF8Encoding]::new($false))
}
Write-Output "Validation project: $target"
Write-Output 'Import with: godot --headless --editor --path <validation project> --quit'
Write-Output 'Run with: godot --headless --path <validation project> --script res://tools/demo_growth_verify.gd'
Write-Output 'Capture with: godot --path <validation project> --script res://tools/demo_growth_capture.gd'
exit 0
