#!/bin/zsh
# Latency report from the unified log, with no database read: the same gate as `make latency` (p50 <= 1000 ms,
# p90 <= 1500 ms from the stop to Cmd-V sent, pasted 10-20 s dictations, cleanup-chord dictations left out), plus the
# stop path split at its marks, from the one notice line per pasted dictation on `Log.latency`
# ("<id> model=... audioMs=... stopToPasteMs=... stop=... uploadStart=...").
# The providers' upload lines ("upload <model>: reused ..., upload N ms, wait N ms") are summed apart: `wait` is the
# last body byte handed to the network stack to the first byte of the answer. Primer lines ("upload primer <model>:")
# are summed on their own; cleanup lines ("upload cleanup ...") are left out.
# Each set is split by the quiet time before it (since the previous dictation or upload): the upstream path of
# OpenRouter answers slower after a quiet minute (docs/research/latency-pass.md).
# Usage: make latency-log               # the release app, last 7 days
#        make latency-log DEV=1 LAST=2d # kotoba Dev (App/Install.swift), last 2 days
#        make latency-log FROM=<file>   # a saved `log show --style compact` copy
set -euo pipefail

subsystem=tech.teensy.kotoba
[[ ${DEV:-} == 1 ]] && subsystem=tech.teensy.kotoba.dev
LAST=${LAST:-7d}
QUIET_S=60
P50_GATE_MS=1000
P90_GATE_MS=1500

# The log store keeps these lines for hours to days (it is size-bound), so FROM=<file> reads a saved copy instead.
lines() {
  if [[ -n ${FROM:-} ]]; then
    echo "log: $FROM" >&2
    cat "$FROM"
  else
    echo "log: $subsystem, category latency, last $LAST" >&2
    # `log` is a zsh builtin; the system tool is /usr/bin/log.
    /usr/bin/log show --last "$LAST" --style compact \
      --predicate "subsystem == \"$subsystem\" AND category == \"latency\"" 2>/dev/null
  fi
}

lines |
  awk -v quiet="$QUIET_S" '
  # Seconds since midnight of the line'"'"'s day, plus the day number, from "2026-10-16 14:10:32.121".
  function seconds(date, time,  d, t) {
    split(date, d, "-"); split(time, t, ":")
    return ((d[1] * 372 + d[2] * 31 + d[3]) * 86400) + t[1] * 3600 + t[2] * 60 + t[3]
  }
  function emit(set, value) { print set "|" value }
  / stopToPasteMs=/ {
    now = seconds($1, $2); split("", m)
    for (i = 1; i <= NF; i++) if (split($i, kv, "=") == 2) m[kv[1]] = kv[2]
    gap = (lastDictation == "" || now - lastDictation >= quiet) ? "after a quiet minute" : "within a minute"
    lastDictation = now
    if ("cleanStart" in m || !("stop" in m) || !("uploadStart" in m) || !("response" in m) || !("pasteSent" in m)) next
    gated = m["audioMs"] >= 10000 && m["audioMs"] <= 20000
    for (pass = 1; pass <= 2; pass++) {
      if (pass == 1 && !gated) continue
      set = (pass == 1 ? "10-20 s" : "all lengths") " " m["model"]
      emit(set " ~ 0 stop to Cmd-V sent", m["pasteSent"] - m["stop"])
      emit(set " ~ 0 stop to Cmd-V sent, " gap, m["pasteSent"] - m["stop"])
      emit(set " ~ 1 stop to uploadStart (capture end, FLAC close)", m["uploadStart"] - m["stop"])
      if ("uploadSent" in m && "firstByte" in m) {
        emit(set " ~ 2 uploadStart to uploadSent (body build, upload)", m["uploadSent"] - m["uploadStart"])
        emit(set " ~ 3 uploadSent to firstByte (server), " gap, m["firstByte"] - m["uploadSent"])
        emit(set " ~ 4 firstByte to response (answer body)", m["response"] - m["firstByte"])
      } else {
        emit(set " ~ 2 uploadStart to response (no network marks)", m["response"] - m["uploadStart"])
      }
      emit(set " ~ 5 response to Cmd-V sent (replacements, save, chord release, paste)", m["pasteSent"] - m["response"])
      if ("connected" in m) emit(set " ~ 6 new connection after the stop (count)", 1)
    }
    next
  }
  # The primer sent at the announcement (TranscriptionProvider.prime): its own wait, apart from the dictations.
  / upload primer [^ :]+: reused / {
    match($0, / upload primer [^ :]+: reused/); model = substr($0, RSTART + 15, RLENGTH - 23)
    wait = $0; sub(/.*wait /, "", wait); sub(/ ms.*/, "", wait)
    if (wait ~ /^[0-9]+$/) emit("primer lines " model " ~ server wait", wait)
    next
  }
  / upload [^ :]+: reused / {
    now = seconds($1, $2)
    gap = (lastUpload == "" || now - lastUpload >= quiet) ? "after a quiet minute" : "within a minute"
    lastUpload = now
    match($0, / upload [^ :]+: reused/); model = substr($0, RSTART + 8, RLENGTH - 16)
    wait = $0; sub(/.*wait /, "", wait); sub(/ ms.*/, "", wait)
    if (wait ~ /^[0-9]+$/) { emit("upload lines " model " ~ server wait", wait); emit("upload lines " model " ~ server wait, " gap, wait) }
  }' |
  sort -t'|' -k1,1 -k2,2n |
  awk -F'|' -v p50gate="$P50_GATE_MS" -v p90gate="$P90_GATE_MS" '
  function pct(p,  i) { i = int(p * n + 0.999999); if (i < 1) i = 1; return ms[i] }
  function report(  head, step, p50, p90, verdict) {
    if (!n) return
    split(set, part, " ~ "); head = part[1]; step = part[2]
    if (head != lastHead) { print head ":"; lastHead = head }
    sub(/^[0-9] /, "", step)
    p50 = pct(0.5); p90 = pct(0.9)
    if (step ~ /\(count\)/) { printf "  %s: %d\n", step, n; return }
    verdict = ""
    if (head ~ /^10-20 s/ && step == "stop to Cmd-V sent") {
      verdict = sprintf(" (gate %s)", (p50 <= p50gate && p90 <= p90gate) ? "PASS" : "FAIL")
      if (verdict ~ /FAIL/) failed = 1
    }
    printf "  %s: n %d, p50 %d ms, p90 %d ms, max %d ms%s\n", step, n, p50, p90, ms[n], verdict
  }
  $1 != set { report(); set = $1; n = 0 }
  { ms[++n] = $2; seen = 1 }
  END {
    report()
    if (!seen) { print "No latency lines in the log for this period."; exit 1 }
    exit failed
  }'
