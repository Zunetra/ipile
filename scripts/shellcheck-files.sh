#!/usr/bin/env bash
# Lints exactly the files it is handed, for lint-staged. scripts/shellcheck.sh
# lints the whole tree and is the right thing on push; this one keeps a commit
# proportional to what the commit actually touches.
#
# Skips rather than fails when no shellcheck is resolvable. A commit hook that
# silently starts a multi-megabyte download is worse than one that defers the
# check to pre-push, which runs the full lint and will catch it there.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDORED="${ROOT}/.tools/shellcheck"

# Kept in step with scripts/shellcheck.sh. See the reason for each there.
EXCLUDE="SC1090,SC1091,SC2034,SC2086,SC2088,SC2016,SC2148"

[ "$#" -eq 0 ] && exit 0

if command -v shellcheck >/dev/null 2>&1; then
  SHELLCHECK="$(command -v shellcheck)"
elif [ -x "$VENDORED" ]; then
  SHELLCHECK="$VENDORED"
else
  echo "  shellcheck not installed, skipping. Run 'pnpm lint:install' to enable it."
  exit 0
fi

exec "$SHELLCHECK" -S warning -e "$EXCLUDE" "$@"
