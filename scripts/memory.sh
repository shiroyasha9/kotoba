#!/bin/zsh
# Idle-memory check (docs/spec.md, "Gates"): physical footprint of the running kotoba, next to the floor that
# docs/research/memory-spike.md measured for the phase 1 shape (status item + glass panel + prepared engine).
# Usage: launch kotoba, leave it idle (no dictation, no window open) for at least 30 s, then `make memory`.
# Set MEMORY_LIMIT_MB to fail above a limit; memory is a soft target, so by default the script only reports.
# Which process: PID=<pid>, else the one running the app at APP (default the release, /Applications/kotoba.app;
# `make memory DEV=1` passes kotoba Dev from `make build`). Never by name: the release, kotoba Dev and snapshot runs
# are all "kotoba".
set -euo pipefail

FLOOR_MB=16.8  # memory-spike.md, variant C, phys_footprint round 2
IDLE_S=30

app=${${APP:-/Applications/kotoba.app}%/}
pid=${PID:-}
if [[ -z $pid ]]; then
  # `comm` is the executable's full path on macOS; an exact match leaves out other copies of kotoba.
  pids=(${(f)"$(ps -axo pid=,comm= | awk -v exe="$app/Contents/MacOS/kotoba" '{ id = $1; sub(/^ *[0-9]+ /, "") } $0 == exe { print id }')"})
  (( ${#pids} > 0 )) || { echo "$app is not running. Launch it, wait ${IDLE_S} s, then run again." >&2; exit 1; }
  (( ${#pids} == 1 )) || { echo "${#pids} processes run $app (pids ${pids[*]}); pass PID=<pid>." >&2; exit 1; }
  pid=${pids[1]}
fi
ps -p "$pid" >/dev/null 2>&1 || { echo "No process $pid." >&2; exit 1; }
uptime_s=$(ps -o etime= -p "$pid" | awk -F'[-:]' '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }')
(( uptime_s >= IDLE_S )) || { echo "kotoba (pid $pid) started ${uptime_s} s ago; idle numbers need ${IDLE_S} s." >&2; exit 1; }

summary=$(vmmap --summary "$pid" 2>/dev/null)
mb() { awk -v v="$1" 'BEGIN { u = substr(v, length(v)); n = v + 0; if (u == "K") n /= 1024; if (u == "G") n *= 1024; printf "%.1f", n }'; }
now=$(mb "$(print -r -- "$summary" | awk -F': *' '/^Physical footprint:/ { print $2 }')")
peak=$(mb "$(print -r -- "$summary" | awk -F': *' '/^Physical footprint \(peak\):/ { print $2 }')")

echo "kotoba pid $pid, up ${uptime_s} s"
footprint -p "$pid" 2>/dev/null | awk '/Footprint:/ { sub(/^.*Footprint: */, ""); print "footprint:          " $0 }'
echo "physical footprint: ${now} MB (peak ${peak} MB)"
echo "floor (spike C):    ${FLOOR_MB} MB, delta $(awk -v a="$now" -v b="$FLOOR_MB" 'BEGIN { printf "%+.1f", a - b }') MB"

if [[ -n ${MEMORY_LIMIT_MB:-} ]] && awk -v a="$now" -v b="$MEMORY_LIMIT_MB" 'BEGIN { exit !(a > b) }'; then
  echo "FAIL: ${now} MB is over MEMORY_LIMIT_MB=${MEMORY_LIMIT_MB}" >&2
  exit 1
fi
