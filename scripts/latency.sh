#!/bin/zsh
# Latency gate report (docs/spec.md, "Gates"): p50 and p90 from the stop (`stop` mark: the second chord key-down in
# tap mode, the key-up in hold mode) to Cmd-V sent (`pasteSent` mark), per model, for pasted dictations with 10-20 s
# of audio, cleanup-chord dictations left out. Gate: p50 <= 1000 ms, p90 <= 1500 ms for every model.
# Under each model, the same time split at the provider's network marks (`NetworkTiming`): stop to `uploadSent` (body
# build and upload until the last byte went to the network stack), `uploadSent` to `firstByte` (the part of the body
# still in the kernel's buffer, plus the server), `firstByte` to `pasteSent` (the answer's body and the paste), and
# how many uploads opened a new connection (`connected` mark) instead of reusing the key-down warm-up.
#
# Without RUN=1 the script only prints the database path and the query. With RUN=1 it opens the database read-only
# (`sqlite3 -readonly`) and runs that one SELECT; nothing is written.
# The release app's database by default; DEV=1 reads the development build's (kotoba-dev, App/Install.swift).
# Usage: make latency            # show the query
#        make latency RUN=1      # run it
#        make latency RUN=1 DEV=1
#        KOTOBA_DB=/path/to/kotoba.sqlite make latency RUN=1
set -euo pipefail

folder=kotoba
[[ ${DEV:-} == 1 ]] && folder=kotoba-dev
DB=${KOTOBA_DB:-$HOME/Library/Application Support/$folder/kotoba.sqlite}
P50_GATE_MS=1000
P90_GATE_MS=1500

# One row per model, step and value, sorted by model, step, then value for the percentile step. Step 1: stop to Cmd-V
# sent (the gate); 2-4: the network split; 5: 1 when the upload opened a new connection, else 0. Steps 2-5 exist only
# for dictations with network marks (a route without metrics, or a dictation from before the marks, has none).
QUERY=$(cat <<'SQL'
WITH marks AS MATERIALIZED (
  SELECT coalesce(d.model, 'unknown') AS model,
         max(CASE WHEN m.mark = 'stop'       THEN m.offset_ms END) AS stop_ms,
         max(CASE WHEN m.mark = 'connected'  THEN m.offset_ms END) AS connected_ms,
         max(CASE WHEN m.mark = 'uploadSent' THEN m.offset_ms END) AS sent_ms,
         max(CASE WHEN m.mark = 'firstByte'  THEN m.offset_ms END) AS first_ms,
         max(CASE WHEN m.mark = 'pasteSent'  THEN m.offset_ms END) AS paste_ms
  FROM dictations AS d
  JOIN latency_marks AS m ON m.dictation_id = d.id
  WHERE d.status = 'pasted'
    AND d.audio_duration_ms BETWEEN 10000 AND 20000
    -- Cleanup-chord dictations wait for an LLM on purpose; the gate covers plain dictation only.
    AND NOT EXISTS (SELECT 1 FROM latency_marks AS c WHERE c.dictation_id = d.id AND c.mark = 'cleanStart')
  GROUP BY d.id
  HAVING stop_ms IS NOT NULL AND paste_ms IS NOT NULL
)
SELECT model, 1 AS step, paste_ms - stop_ms AS ms FROM marks
UNION ALL SELECT model, 2, sent_ms - stop_ms FROM marks WHERE sent_ms IS NOT NULL
UNION ALL SELECT model, 3, first_ms - sent_ms FROM marks WHERE sent_ms IS NOT NULL AND first_ms IS NOT NULL
UNION ALL SELECT model, 4, paste_ms - first_ms FROM marks WHERE first_ms IS NOT NULL
UNION ALL SELECT model, 5, connected_ms IS NOT NULL FROM marks WHERE sent_ms IS NOT NULL
ORDER BY model, step, ms;
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
  BEGIN { split("|stop to uploadSent|uploadSent to firstByte|firstByte to pasteSent", name, "|") }
  # Nearest-rank percentile over one step'"'"'s sorted rows.
  function pct(p,  i) { i = int(p * n + 0.999999); if (i < 1) i = 1; return ms[i] }
  function report(  p50, p90) {
    if (!n) return
    p50 = pct(0.5); p90 = pct(0.9)
    if (step == 1) {
      printf "%s: %d dictations, p50 %d ms (gate %d) %s, p90 %d ms (gate %d) %s\n", model, n,
        p50, p50gate, (p50 <= p50gate ? "PASS" : "FAIL"), p90, p90gate, (p90 <= p90gate ? "PASS" : "FAIL")
      if (p50 > p50gate || p90 > p90gate) failed = 1
    } else if (step == 5) {
      printf "  new connection: %d of %d uploads (the others reused the key-down warm-up)\n", sum, n
    } else {
      if (step == 2) printf "  network split, %d dictations with network marks:\n", n
      printf "    %s: p50 %d ms, p90 %d ms\n", name[step], p50, p90
    }
  }
  # A model with no network marks says so, so a missing split is not read as zero.
  function end_model() {
    if (model != "" && !has_split) print "  no network marks yet (a route without metrics, or older dictations)"
  }
  $1 != model || $2 != step {
    report()
    if ($1 != model) { end_model(); model = $1; has_split = 0 }
    step = $2; n = 0; sum = 0
    if (step > 1) has_split = 1
  }
  { ms[++n] = $3; sum += $3; if (step == 1) total++ }
  END {
    if (!total) { print "No pasted 10-20 s dictations yet."; exit 1 }
    report()
    end_model()
    exit failed
  }'
