# Runs the headless tests. Usage: tools\run_tests.ps1 [name_filter]
# Set $env:GODOT to your Godot console executable if it isn't on PATH.
$root = Split-Path -Parent $PSScriptRoot
$godot = $env:GODOT
if (-not $godot) { $cmd = Get-Command godot -ErrorAction SilentlyContinue; if ($cmd) { $godot = $cmd.Source } }
if (-not $godot) { $godot = "C:\Godot\Godot_v4.5.1-stable_win64_console.exe" }

# Import first so class_name scripts are registered on a fresh checkout.
& $godot --headless --path $root --import *> $null
& $godot --headless --path $root -s res://tests/run_tests.gd -- $args
exit $LASTEXITCODE
