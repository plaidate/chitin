#!/bin/bash
# Fightin' Chitin smoke runner: build instrumented, run headless in the Playdate
# Simulator, poll the datastore, report.
#
#   tools/smoke.sh [seconds] [until-grep]

set -u
SECS="${1:-120}"
UNTIL="${2:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="com.sdwfrost.chitin"
DATA="$HOME/Developer/PlaydateSDK/Disk/Data/$BUNDLE"
# SDK 3.0.6: must launch the .app bundle via `open --args`, NOT the inner
# binary (the direct-binary form silently runs nothing on 3.0.6).
APP="$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app"
SHOT="$ROOT/build/chitin-shot.png"

cd "$ROOT"
make smoke >/dev/null || { echo "BUILD FAILED"; exit 1; }

pkill -9 -f "Playdate Simulator" 2>/dev/null
rm -rf "$DATA" "$SHOT"
open "$APP" --args "$ROOT/out/ChitinSmoke.pdx" >/dev/null 2>&1

ITER=$((SECS / 5))
for i in $(seq 1 "$ITER"); do
    [ -s "$DATA/err.json" ] && break
    if [ -n "$UNTIL" ] && grep -qE "$UNTIL" "$DATA/smoke.json" 2>/dev/null; then
        break
    fi
    sleep 5
done

echo "--- err:"
cat "$DATA/err.json" 2>/dev/null || echo "no error"
echo "--- smoke:"
cat "$DATA/smoke.json" 2>/dev/null || echo "NO HEARTBEAT"
echo
[ -f "$SHOT" ] && echo "screenshot: $SHOT"

pkill -9 -f "Playdate Simulator" 2>/dev/null
mkdir -p "$ROOT/results"
cp "$DATA/smoke.json" "$ROOT/results/smoke.json" 2>/dev/null
