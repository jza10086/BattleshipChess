#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
RUN="$(mktemp -d "${TMPDIR:-/tmp}/battleship-tests.XXXXXX")"
mkdir -p "$RUN"/{cache,data,config}
export XDG_CACHE_HOME="$RUN/cache" XDG_DATA_HOME="$RUN/data" XDG_CONFIG_HOME="$RUN/config" LP_NUM_THREADS=2
"$GODOT_BIN" --headless --audio-driver Dummy --path "$ROOT" --editor --import --quit >"$RUN/import.log" 2>&1
cat "$RUN/import.log"
if grep -Eq 'SCRIPT ERROR|^ERROR:' "$RUN/import.log"; then exit 1; fi
"$GODOT_BIN" --headless --audio-driver Dummy --path "$ROOT" --script res://tests/test_rules.gd >"$RUN/rules.log" 2>&1
cat "$RUN/rules.log"
if grep -Eq 'SCRIPT ERROR|^ERROR:|FAIL:' "$RUN/rules.log"; then exit 1; fi
python3 "$ROOT/tests/run_network_tests.py" --godot "$GODOT_BIN" --output "$RUN/network"
printf 'All rule and network tests passed. Logs: %s\n' "$RUN"
