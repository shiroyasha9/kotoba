Footprint probe for the per-chunk autorelease pool in `BodyWriter.write(contentsOf:)` (`docs/research/perf-pass-codex.md`).
Compile: `mkdir -p build && for v in before after; do swiftc -O -swift-version 6 -module-cache-path build/mc -o build/body-$v body-$v.swift; done`
Run: `build/body-before 32; build/body-after 32` (argument = input MiB; footprint rise = `after` - `before` in bytes).
