#!/bin/zsh
# Fails when a `ui_text_*` rule in .swiftlint.yml leaves the shared shape `T(?<=<builders>…T)`: its target T first, then
# a lookbehind with the list of UI builders whose strings are UI text (Text(, Button(, .toolTip = …) that ends with the
# same T. SwiftLint has no shared regex, so each rule holds a copy; a view added to one copy and not the others would
# skip their checks. Usage: scripts/ui-text-builders.sh (run by `make lint`).
set -uo pipefail
cd ${0:A:h:h}

typeset -A lookbehinds
failed=0
# Each ui_text_* rule's name and regex, as written in the YAML (escapes doubled).
awk '/^  ui_text_/ { name = $1; next } /^  [a-z_]+:$/ { name = "" } name && /^    regex:/ { print name, substr($0, 12) }' \
  .swiftlint.yml | while read -r name regex; do
  name=${name%:} regex=${regex#\"} regex=${regex%\"}
  target=${regex%%\(\?\<=*} rest=${regex#*\(\?\<=}
  lookbehind=${rest%%\{0,200\}*}
  if [[ $target == $regex || $rest != *"{0,200}$target)" ]]; then
    print -r -- "ui-text-builders: $name is not T(?<=<builders>…{0,200}T) with the same T at both ends"
    failed=1
  fi
  lookbehinds[$name]=$lookbehind
done

if (( ${#lookbehinds} == 0 )); then
  print -r -- "ui-text-builders: no ui_text_* rule found in .swiftlint.yml"
  exit 1
fi
if (( ${#${(u)lookbehinds[@]}} > 1 )); then
  print -r -- "ui-text-builders: the ui_text_* rules list different UI builders:"
  for name in ${(ok)lookbehinds}; do print -r -- "  $name: ${lookbehinds[$name]}"; done
  failed=1
fi
exit $failed
