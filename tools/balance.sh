#!/bin/bash
# Fightin' Chitin balance runner: build the balance variant (SMOKE + BALANCE),
# run headless AI-vs-AI through every unique matchup N times, poll the datastore
# for the completed win matrix, and print a readable win-rate grid.
#
#   tools/balance.sh [max-seconds]

set -u
SECS="${1:-300}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="com.sdwfrost.chitin"
DATA="$HOME/Developer/PlaydateSDK/Disk/Data/$BUNDLE"
APP="$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app"

cd "$ROOT"
make balance >/dev/null || { echo "BUILD FAILED"; exit 1; }

pkill -9 -f "Playdate Simulator" 2>/dev/null
rm -rf "$DATA"
open "$APP" --args "$ROOT/out/ChitinBalance.pdx" >/dev/null 2>&1

ITER=$((SECS / 5))
DONE=0
for i in $(seq 1 "$ITER"); do
    [ -s "$DATA/err.json" ] && break
    if grep -q '"done":true' "$DATA/balance.json" 2>/dev/null; then
        DONE=1
        break
    fi
    sleep 5
done

echo "--- err:"
cat "$DATA/err.json" 2>/dev/null || echo "no error"
echo

pkill -9 -f "Playdate Simulator" 2>/dev/null
mkdir -p "$ROOT/results"
cp "$DATA/balance.json" "$ROOT/results/balance.json" 2>/dev/null
cp "$DATA/smoke.json"   "$ROOT/results/smoke.json"   2>/dev/null

if [ "$DONE" != "1" ]; then
    echo "balance run did not finish within ${SECS}s (partial matrix below)"
fi

python3 - "$DATA/balance.json" "$DATA/smoke.json" <<'PY'
import json, sys
names = ["rhino","leaf","mantis","tiger","dragonfly","assassin"]
short = ["RHIN","LEAF","MANT","TIGR","DRGN","ASSN"]

def load(path):
    try:
        with open(path) as f: return json.load(f)
    except Exception:
        return None

d = load(sys.argv[1]) or load(sys.argv[2]) or {}
m = d.get("matrix")
if not m:
    print("no matrix found"); sys.exit(0)

# matrix may be a list or a dict keyed "1".."6"
def get(mat, i, j):
    row = mat[i] if isinstance(mat, list) else mat.get(str(i+1)) or mat.get(str(i))
    if row is None: return 0
    if isinstance(row, list):
        return row[j] if j < len(row) else 0
    return row.get(str(j+1)) or row.get(str(j)) or 0

print("Win-rate matrix (row fighter's win %% vs column fighter):")
print("        " + "".join("%6s" % s for s in short))
overall = [0]*6
totals  = [0]*6
for i in range(6):
    cells = []
    for j in range(6):
        if i == j:
            cells.append("   -  "); continue
        w = get(m, i, j); l = get(m, j, i); tot = w + l
        overall[i] += w; totals[i] += tot
        pct = (100.0*w/tot) if tot else 0
        cells.append("%5d%%" % round(pct))
    print("%7s " % short[i] + "".join(cells))

print()
print("Overall win rate:")
for i in range(6):
    pct = (100.0*overall[i]/totals[i]) if totals[i] else 0
    print("  %-10s %5.1f%%  (%d/%d)" % (names[i], pct, overall[i], totals[i]))
PY
