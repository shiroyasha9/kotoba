#!/bin/zsh
# Latency gate report (docs/spec.md, "Gates"): p50 and p90 from the stop (`stop` mark: the second chord key-down in
# tap mode, the key-up in hold mode) to Cmd-V sent (`pasteSent` mark), per model, for pasted dictations with 10-20 s
# of audio, cleanup-chord dictations left out. Gate: p50 <= 1000 ms, p90 <= 1500 ms for every model.
#
# Without RUN=1 the script only prints the database path and the query. With RUN=1 it opens the database read-only
# (`sqlite3 -readonly`) and runs that one SELECT; nothing is written.
# Usage: make latency            # show the query
#        make latency RUN=1      # run it
#        KOTOBA_DB=/path/to/kotoba.sqlite make latency RUN=1
set -euo pipefail

DB=${KOTOBA_DB:-$HOME/Library/Application Support/kotoba/kotoba.sqlite}
P50_GATE_MS=1000
P90_GATE_MS=1500

# One row per dictation: model and stop to Cmd-V sent in ms, sorted by model then time for the percentile step.
QUERY=$(cat <<'SQL'
SELECT coalesce(d.model, 'unknown') AS model,
       paste.offset_ms - stop.offset_ms AS stop_to_paste_ms
FROM dictations AS d
JOIN latency_marks AS stop  ON stop.dictation_id  = d.id AND stop.mark  = 'stop'
JOIN latency_marks AS paste ON paste.dictation_id = d.id AND paste.mark = 'pasteSent'
WHERE d.status = 'pasted'
  AND d.audio_duration_ms BETWEEN 10000 AND 20000
  -- Cleanup-chord dictations wait for an LLM on purpose; the gate covers plain dictation only.
  AND NOT EXISTS (SELECT 1 FROM latency_marks AS c WHERE c.dictation_id = d.id AND c.mark = 'cleanStart')
ORDER BY model, stop_to_paste_ms;
SQL
)

echo "database: $DB"
echo "query:"
print -r -- "$QUERY" | sed 's/^/  /'

if [[ ${RUN:-} != 1 ]]; then
  echo "Not run. Run with RUN=1 to read the database (read-only)."
  exit 0
fi
[[ -f $DB ]] || { echo "No database at $DB" >&2; exit 1; }

sqlite3 -readonly -batch -noheader -separator '|' "$DB" "$QUERY" |
  awk -F'|' -v p50gate="$P50_GATE_MS" -v p90gate="$P90_GATE_MS" '
  # Nearest-rank percentile over one model'"'"'s sorted rows.
  function pct(p,  i) { i = int(p * n + 0.999999); if (i < 1) i = 1; return ms[i] }
  function report(  p50, p90) {
    p50 = pct(0.5); p90 = pct(0.9)
    printf "%s: %d dictations, p50 %d ms (gate %d) %s, p90 %d ms (gate %d) %s\n", model, n,
      p50, p50gate, (p50 <= p50gate ? "PASS" : "FAIL"), p90, p90gate, (p90 <= p90gate ? "PASS" : "FAIL")
    if (p50 > p50gate || p90 > p90gate) failed = 1
  }
  $1 != model { if (n) report(); model = $1; n = 0 }
  { ms[++n] = $2; total++ }
  END {
    if (!total) { print "No pasted 10-20 s dictations yet."; exit 1 }
    report()
    exit failed
  }'
