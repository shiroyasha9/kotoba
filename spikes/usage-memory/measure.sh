#!/bin/zsh
# Footprint of UsageBase at 30 s, and of UsageSpike at 30 s (SwiftUI linked, no window), 40 s (Settings open on the
# Usage pane over 10,000 dictations) and 75 s (30 s after close). Usage: ./measure.sh [rounds]
set -euo pipefail
cd "${0:A:h}"
mkdir -p results
fp() { vmmap --summary "$1" 2>/dev/null | awk -F': *' '/^Physical footprint:/ { print $2; exit }'; }
for r in $(seq 1 ${1:-2}); do
  open -g -n build/UsageBase.app; sleep 1; pid=$(pgrep -n -x UsageBase)
  sleep 29; echo "r$r base idle: $(fp $pid)" | tee -a results/footprint.txt; kill -TERM $pid; sleep 2
  open -g -n build/UsageSpike.app; sleep 1; pid=$(pgrep -n -x UsageSpike)
  sleep 29; echo "r$r spike idle (linked, no window): $(fp $pid)" | tee -a results/footprint.txt
  sleep 10; echo "r$r spike window open: $(fp $pid)" | tee -a results/footprint.txt
  sleep 35; echo "r$r spike 30 s after close: $(fp $pid)" | tee -a results/footprint.txt
  kill -TERM $pid; sleep 2
done
