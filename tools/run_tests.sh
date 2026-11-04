#!/bin/sh
# Runs the headless tests. Usage: tools/run_tests.sh [name_filter]
# Set $GODOT to your Godot binary if it isn't on PATH.
root="$(cd "$(dirname "$0")/.." && pwd)"
godot="${GODOT:-$(command -v godot)}"
if [ -z "$godot" ]; then
	godot="/Users/al/Downloads/Godot.app/Contents/MacOS/Godot"
fi

# Import first so class_name scripts are registered on a fresh checkout.
"$godot" --headless --path "$root" --import > /dev/null 2>&1
"$godot" --headless --path "$root" -s res://tests/run_tests.gd -- "$@"
exit $?
