#!/bin/zsh
# Fails when a tracked file holds something that must not be public: a home or session temp path, an email address
# (only reserved example domains and GitHub noreply addresses pass), an API key, or a private key block.
# The patterns are generic on purpose: this file is public too. Usage: scripts/privacy.sh (run by `make check`).
set -uo pipefail
cd ${0:A:h:h}

failed=0
# Matches print as file:line:text; this file holds the patterns, so it is skipped.
search() { git grep -n -I -E "$@" -- . ':!scripts/privacy.sh' }
report() {
  local found=$1 what=$2
  [[ -z $found ]] && return
  print -r -- "privacy: $what"
  print -r -- "$found" | sed 's/^/  /'
  failed=1
}

report "$(search -e '/Users/[^/[:space:]]' -e '/private/tmp/claude-' -e '/home/[a-z]')" "home or session temp path"

email='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
allowed='@(example\.(com|org|net)|users\.noreply\.github\.com)$'
report "$(search -o -e "$email" | grep -v -E "$allowed")" "email address (use an example.com address in tests)"

report "$(search -o \
  -e 'sk-or-v1-[0-9a-f]{32,}' -e 'sk-ant-[A-Za-z0-9_-]{20,}' -e 'sk-(proj-)?[A-Za-z0-9]{32,}' \
  -e 'xai-[A-Za-z0-9]{20,}' -e 'AKIA[0-9A-Z]{16}' -e 'AIza[0-9A-Za-z_-]{35}' \
  -e 'gh[pousr]_[A-Za-z0-9]{36}' -e 'github_pat_[A-Za-z0-9_]{20,}' -e 'xox[abprs]-[A-Za-z0-9-]{10,}' |
  sed -E 's/^([^:]*:[^:]*:.{12}).*/\1…/')" "API key (rotate it: it is in the working tree)"

report "$(search -e '-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----')" "private key block"

exit $failed
