#!/bin/zsh
# The pipeline's own time on the stop path (KotobaCore/Tests/KotobaCoreTests/StopProbeTests.swift): RUNS dictations
# through DictationPipeline with every port a fake, timed from the stop tap's chord-down handed to `handle` to the Cmd-V
# sent (`Paster.sendPaste`), its chord-up sent at once after. No network, mic, pasteboard or posted event is in it, so
# it shows what a change to the stop path costs, not the latency gate (`make latency-log` reads that).
# With BASE=<ref>, the ref is exported with `git archive` (the probe file from this checkout copied in, so a ref from
# before it works while its fakes take the same calls) and the two run in turn, ROUNDS times each.
# Usage: make stop-probe                  # this checkout, 2,000 stop taps, release build
#        make stop-probe RUNS=10000
#        make stop-probe BASE=main        # main, then this checkout, 3 rounds each
#        make stop-probe CONFIG=debug     # the build `make test` runs
set -euo pipefail

RUNS=${RUNS:-2000}
CONFIG=${CONFIG:-release}
LIMIT=${TEST_LIMIT:-120}
ROUNDS=${ROUNDS:-$([[ -n ${BASE:-} ]] && echo 3 || echo 1)}
root=${0:A:h:h}
probe=KotobaCore/Tests/KotobaCoreTests/StopProbeTests.swift
# Release needs -enable-testing for `@testable import`; debug has it, and the same flags keep `make test`'s build.
flags=(-c $CONFIG)
[[ $CONFIG == release ]] && flags+=(-Xswiftc -enable-testing)

# The package in folder $1, with AGENT's own build folder (`make check AGENT=<name>`).
package() {
  reply=(--package-path $1/KotobaCore)
  if [[ -n ${AGENT:-} ]]; then reply+=(--scratch-path $1/KotobaCore/.build-$AGENT); fi
}

build() {
  echo "building $CONFIG in $1" >&2
  package $1
  swift build --quiet --build-tests $flags $reply >&2
}

# $1: the folder that holds KotobaCore; $2: its label in the output.
run() {
  local out line
  package $1
  if ! out=$(KOTOBA_STOP_PROBE_RUNS=$RUNS "$root/scripts/timeout.pl" $LIMIT \
    swift test --skip-build $flags $reply --filter StopProbeTests 2>&1); then
    print -r -- $out >&2
    echo "stop-probe failed or ran over $LIMIT s in $2" >&2
    exit 1
  fi
  if ! line=$(print -r -- $out | grep '^stop-probe: '); then
    print -r -- $out >&2
    echo "stop-probe printed no result in $2 (was the test skipped?)" >&2
    exit 1
  fi
  echo "$2: ${line#stop-probe: }"
}

base=
if [[ -n ${BASE:-} ]]; then
  sha=$(git -C $root rev-parse --verify "$BASE^{commit}")
  base=$root/build/stop-probe${AGENT:+-$AGENT}/$sha
  if [[ ! -d $base/KotobaCore ]]; then
    mkdir -p $base
    git -C $root archive $sha KotobaCore | tar -x -C $base
  fi
  cp $root/$probe $base/$probe
  build $base
fi
build $root

echo "stop tap chord-down to Cmd-V sent, the pipeline with fakes ($CONFIG build, $RUNS runs per line, after 100 warm-up runs)"
for _ in {1..$ROUNDS}; do
  [[ -n $base ]] && run $base "base ${sha:0:7} ($BASE)"
  run $root "this checkout"
done
