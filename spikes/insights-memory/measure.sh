#!/bin/zsh
# Footprint of InsightsNoChart and InsightsSpike at 30 s (window never opened), 40 s (Settings open on the Insights
# pane over 10,000 dictations) and 75 s (30 s after close), and the pane's first read time. Usage: ./measure.sh [rounds]
set -euo pipefail
cd "${0:A:h}"
mkdir -p results
fp() { footprint -p "$1" 2>/dev/null | awk '/Footprint:/ { print $(NF-5), $(NF-4); exit }'; }
for r in $(seq 1 ${1:-2}); do
  for name in InsightsNoChart InsightsSpike; do
    log=results/$name-r$r.log
    build/$name.app/Contents/MacOS/$name > $log 2>&1 &
    pid=$!
    sleep 30; echo "r$r $name idle (no window): $(fp $pid)" | tee -a results/footprint.txt
    sleep 10; echo "r$r $name window open: $(fp $pid)" | tee -a results/footprint.txt
    sleep 35; echo "r$r $name 30 s after close: $(fp $pid)" | tee -a results/footprint.txt
    kill -TERM $pid; wait $pid 2>/dev/null || true
    grep "read" $log | tee -a results/footprint.txt || true
  done
done
