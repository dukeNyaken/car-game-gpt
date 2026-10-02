param([string]$Godot = 'C:\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
foreach ($test in @('smoke_test.gd','polish_test.gd','response_test.gd')) {
    & $Godot --headless --path $projectPath --fixed-fps 60 --script "res://tests/$test"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
& $Godot --headless --path $projectPath --fixed-fps 60 --script res://tests/route_test.gd -- --novice
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Godot --headless --path $projectPath --fixed-fps 60 --script res://tests/route_test.gd -- --novice --cannon
exit $LASTEXITCODE
