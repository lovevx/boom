param(
    [switch]$Quick,
    [string]$Python = 'C:\Users\31992\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference = 'Stop'
$source = Split-Path $PSScriptRoot -Parent
$target = Join-Path (Split-Path $source -Parent) 'boomame-demo-validation'
$reports = Join-Path $source 'artifacts\demo-pacing'
New-Item $reports -ItemType Directory -Force | Out-Null
& (Join-Path $PSScriptRoot 'prepare_demo_validation.ps1')
& godot --headless --editor --path $target --quit *> (Join-Path $reports 'import.log')
if ($LASTEXITCODE -ne 0) { throw 'Validation import failed' }
foreach ($suite in @('demo_pacing','balance','demo_growth','collapse')) {
    & godot --headless --path $target --script "res://tools/${suite}_verify.gd" *> (Join-Path $reports "${suite}-regression.log")
    if ($LASTEXITCODE -ne 0) { throw "$suite verification failed" }
    Write-Output "$suite passed"
}
& $Python (Join-Path $PSScriptRoot 'demo_pacing_simulate.py') *> (Join-Path $reports 'model.log')
if ($LASTEXITCODE -ne 0) { throw 'Economy model failed' }
if (-not $Quick) {
    foreach ($route in @('bomb','hammer','economy')) {
        foreach ($trial in @(7,19,42)) {
            & godot --headless --path $target --fixed-fps 60 --disable-render-loop --script res://tools/demo_pacing_run.gd -- "--route=$route" "--seed=$trial" *> (Join-Path $reports "engine-$route-$trial.log")
            if ($LASTEXITCODE -ne 0) { throw "Engine run failed: $route $trial" }
            Write-Output "$route $trial completed"
        }
    }
    & $Python (Join-Path $PSScriptRoot 'demo_pacing_report.py')
    if ($LASTEXITCODE -ne 0) { throw 'Report generation failed' }
}
