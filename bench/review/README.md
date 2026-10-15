# Reference review

A local page to hand-correct reference transcripts for kotoba-bench.

## Run

```sh
cd bench
bun run review                     # data folder from KOTOBA_BENCH_DATA, like `bun run bench`
```

Then open http://127.0.0.1:4788/. `--data DIR` overrides `KOTOBA_BENCH_DATA` and `--port N` the port. The server listens on 127.0.0.1 only and makes no network calls.

## What it does

- Review set: 50 clips, chosen once with a fixed seed and written to `DATA/review-set.json`, so later STT runs do not change the set mid-review. Delete that file to choose again.
- Choice (`select.ts`): clips that have a `mai+phraseList` transcript and no owner edit in Wispr. An equal share per duration bucket (`DURATION_BUCKETS` in `data.ts`), seeded with `BENCH_SEED`. Inside a bucket, weighted sampling favours clips where `mai+phraseList`, `grok+keyterms` and Wispr `asrText` disagree (mean pairwise word errors with `score.ts` normalization, over the longer text).
- Output: `DATA/references.jsonl` (`paths().references` in `data.ts`), one row per save: `{clipId, text, source, savedAt}`. The last row per clip wins. At start, the 18 clips with a Wispr edit are appended once with `source: "edited"`.
- Resume: the page opens at the first clip without an owner row. Skipped clips are not recorded, so they come back on the next start.

## Checks

`bun test` and `bun run typecheck` in `bench/` cover `select.ts`.
