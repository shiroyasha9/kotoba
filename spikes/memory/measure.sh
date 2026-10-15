#!/bin/zsh
# Launches each variant, idles 30 s, records footprint and vmmap --summary, quits it.
# Usage: ./measure.sh [rounds] [variants...]   Output: results/<variant>-r<round>-{footprint,vmmap}.txt
set -euo pipefail
cd "${0:A:h}"
rounds=${1:-2}; shift || true
(( $# )) || set -- A B C E
mkdir -p results
for r in $(seq 1 $rounds); do
  for v in "$@"; do
    open -g -n "build/MemSpike$v.app"
    pid=""
    for i in {1..50}; do pid=$(pgrep -n -x "MemSpike$v" || true); [[ -n $pid ]] && break; sleep 0.1; done
    sleep 30
    footprint -p "$pid" > "results/$v-r$r-footprint.txt" 2>&1
    vmmap --summary "$pid" > "results/$v-r$r-vmmap.txt" 2>&1
    kill -TERM "$pid"
    echo "$v round $r pid $pid: $(grep -m1 -i 'Footprint:' results/$v-r$r-footprint.txt)"
    sleep 2
  done
done
