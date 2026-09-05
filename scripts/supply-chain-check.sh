#!/usr/bin/env bash
# Blocks a commit that stages the build-config backdoor.
#
# Wired in through .lintstagedrc, so husky invokes it and it survives a
# husky reinstall. lint-staged hands it the staged files as arguments and
# stashes unstaged changes first, so the working tree it sees is the
# content that would actually be committed.
#
# Self-contained on purpose. dev-guard does the deeper sweep, but a repo
# check cannot assume every teammate has it installed.
#
# Background: a backdoor was appended to build config files across our
# repos in 2026. Nobody committed it knowingly. The malware wrote the file,
# `git add .` staged it, and the payload sits behind ~700 spaces on the last
# line, off the right edge of the screen. Review cannot catch that; this can.

set -uo pipefail

[ "$#" -eq 0 ] && exit 0

# Matches the minified form (global.o='7-c1287') and the Prettier
# reformatted one, which has spaces around the '='.
IOC_RE="global\.o *= *'7-"

# The padding trick, independent of any signature. This is what catches the
# next variant, which will not use global.o. Prefiltered with a fixed string
# because a bounded repeat like {200,} defeats grep's literal fast path and
# costs seconds; 100 spaces is half the threshold, so it cannot miss a hit.
PAD_LIT="$(printf '%*s' 100 '')"
PAD_RE='[[:space:]]{200,}[^[:space:]]'

hits=""
for f in "$@"; do
  [ -f "$f" ] || continue
  case "$f" in
    *.js | *.cjs | *.mjs | *.ts) ;;
    *) continue ;;
  esac

  if grep -qE "$IOC_RE" "$f" 2>/dev/null; then
    hits="${hits}  ${f}  (known payload signature)
"
    continue
  fi

  if grep -qF "$PAD_LIT" "$f" 2>/dev/null && grep -qE "$PAD_RE" "$f" 2>/dev/null; then
    hits="${hits}  ${f}  (code hidden behind 200+ spaces)
"
  fi
done

[ -z "$hits" ] && exit 0

printf '\n  \033[1;31m✗  Commit blocked: possible backdoor in staged files\033[0m\n\n'
printf '%s' "$hits"
printf '\n  Open each file and press End on the last line. The payload is\n'
printf '  pushed far right behind hundreds of spaces so it is invisible.\n\n'
printf '  Inspect and clean:  \033[1mdev-guard --scan --heuristics\033[0m\n'
printf '                      \033[1mdev-guard --clean --yes\033[0m\n\n'
printf '  Genuine minified vendor code committed on purpose is the only\n'
printf '  expected false positive. Override once with:\n'
printf '                      \033[1mgit commit --no-verify\033[0m\n\n'
exit 1
