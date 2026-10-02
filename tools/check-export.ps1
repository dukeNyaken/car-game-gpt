param([string]$Godot = 'C:\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
$buildPath = Join-Path $projectPath 'builds'
$gamePath = Join-Path $buildPath 'OnlyWhatYouNeed.exe'
if (-not (Test-Path -LiteralPath $gamePath)) { throw 'Build first with the Windows Desktop export preset.' }

function Invoke-CheckedWindow([string]$Executable, [string[]]$Arguments, [string]$Name, [string]$Expected) {
    $outLog = Join-Path $buildPath ($Name + '.log')
    $errorLog = Join-Path $buildPath ($Name + '-error.log')
    $process = Start-Process -FilePath $Executable -ArgumentList $Arguments -WorkingDirectory $buildPath -WindowStyle Hidden -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errorLog
    $null = $process.Handle # Keep the exit code available under Windows PowerShell 5.
    if (-not $process.WaitForExit(20000)) {
        Stop-Process -Id $process.Id
        throw "$Name timed out; only this test process was stopped."
    }
    $output = Get-Content -LiteralPath $outLog -Raw
    $errors = Get-Content -LiteralPath $errorLog -Raw
    if ($process.ExitCode -ne 0 -or $errors -match '(?m)^\s*(?:SCRIPT ERROR|ERROR|WARNING|FAIL:)' -or ($Expected -and $output -notmatch [regex]::Escape($Expected))) {
        Write-Output $output
        Write-Output $errors
        throw "$Name failed."
    }
    Write-Output $output
}

# Stock release templates do not support --script. Check binary boot separately.
Invoke-CheckedWindow $gamePath @('--audio-driver','Dummy','--quit-after','90') 'binary-boot' 'Godot Engine'
# The editor binary supplies the test runner; all game resources come from the embedded PCK.
# The build working directory prevents fallback to source files. Tests assert this too.
$inputScript = (Join-Path $projectPath 'tests/input_test.gd').Replace('\','/')
$quotedInput = '"' + $inputScript + '"'
$quotedPack = '"' + $gamePath + '"'
Invoke-CheckedWindow $Godot @('--main-pack',$quotedPack,'--audio-driver','Dummy','--fixed-fps','60','--script',$quotedInput,'--','--export-check') 'packed-input' 'INPUT: 26 checks, 0 failures'

foreach ($strategy in @('shield','cannon','engine')) {
    $flags = @('--novice','--export-check')
    if ($strategy -eq 'cannon') { $flags += '--cannon' }
    if ($strategy -eq 'engine') { $flags += '--keep-engine' }
    $routeScript = (Join-Path $projectPath 'tests/route_test.gd').Replace('\','/')
    $quotedRoute = '"' + $routeScript + '"'
    $routeArguments = @('--headless','--main-pack',$quotedPack,'--fixed-fps','60','--script',$quotedRoute,'--') + $flags
    Invoke-CheckedWindow $Godot $routeArguments ("packed-route-$strategy") 'FULL ROUTE: 0 failures'
}
'EXPORT ACCEPTANCE: binary boot, input and three packed routes passed.'
