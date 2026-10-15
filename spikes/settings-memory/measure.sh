#!/bin/zsh
# Footprint of SettingsBase at 30 s, and of SettingsSpike at 30 s (SwiftUI linked, no window), 40 s (Dictionary pane
# open) and 75 s (30 s after close). Usage: ./measure.sh [rounds]
set -euo pipefail
cd "${0:A:h}"
mkdir -p results
fp() { vmmap --summary "$1" 2>/dev/null | awk -F': *' '/^Physical footprint:/ { print $2; exit }'; }
for r in $(seq 1 ${1:-2}); do
  open -g -n build/SettingsBase.app; sleep 1; pid=$(pgrep -n -x SettingsBase)
  sleep 29; echo "r$r base idle: $(fp $pid)" | tee -a results/footprint.txt; kill -TERM $pid; sleep 2
  open -g -n build/SettingsSpike.app; sleep 1; pid=$(pgrep -n -x SettingsSpike)
  sleep 29; echo "r$r spike idle (linked, no window): $(fp $pid)" | tee -a results/footprint.txt
  sleep 10; echo "r$r spike window open: $(fp $pid)" | tee -a results/footprint.txt
  sleep 35; echo "r$r spike 30 s after close: $(fp $pid)" | tee -a results/footprint.txt
  kill -TERM $pid; sleep 2
done
