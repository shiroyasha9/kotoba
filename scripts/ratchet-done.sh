#!/bin/zsh
# Fails while a page is not on the 0.5.0 page system (CODING_STANDARDS.md, "Pages"): a file-level ratchet line that
# disables the page rules (`// swiftlint:disable ui_layout_literal …`), or a page that still has a toolbar
# (`pagesWithToolbar` in App/Settings/SettingsSnapshots.swift, which the title-bar switch check skips). Run by
# `make release`, not by `make check`: the rollout removes them page by page. Usage: scripts/ratchet-done.sh
set -uo pipefail
cd ${0:A:h:h}

rules='ui_layout_literal|appkit_layout_literal|ui_layout_constant|ui_divider|ui_fixed_color|row_is_page_row|page_form'
# ERE for git grep: no \w or \b. A `disable:next` with its reason does not match.
left=$(git grep -n -E "^// swiftlint:disable( [a-z_]+)* ($rules)( |\$)" -- App)
toolbars=$(git grep -n -E 'pagesWithToolbar: \[PaneID\] = \[\.' -- App)
[[ -z $left && -z $toolbars ]] && exit 0
if [[ -n $left ]]; then
  print -r -- "ratchet-done: these files are not on the 0.5.0 page system yet ($(print -r -- "$left" | wc -l | tr -d ' ')):"
  print -r -- "$left" | sed 's/^/  /'
fi
if [[ -n $toolbars ]]; then
  print -r -- "ratchet-done: these pages still have a toolbar, so the title bar changes height:"
  print -r -- "$toolbars" | sed 's/^/  /'
fi
exit 1
