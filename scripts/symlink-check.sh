#!/usr/bin/env bash
# Runs the dispatcher through a symlink, the way the installer links it
# into ~/.local/bin. Running ./bin/ipile directly cannot catch a path that
# only breaks behind the link, which is how v1.0.0 shipped with every lib/
# source resolving to ~/.local/lib.
#
# Usage: scripts/symlink-check.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# Two hops, relative then absolute, so both readlink branches are walked.
mkdir -p "${SANDBOX}/home/.local/bin" "${SANDBOX}/links"
ln -s "${ROOT}/bin/ipile" "${SANDBOX}/links/ipile"
ln -s "../../../links/ipile" "${SANDBOX}/home/.local/bin/ipile"

status=0
errors="$(HOME="${SANDBOX}/home" "${SANDBOX}/home/.local/bin/ipile" version 2>&1 >/dev/null)" || status=$?

if [ "$status" -ne 0 ] || [ -n "$errors" ]; then
  echo "ipile failed when run through a symlink:"
  printf '%s\n' "$errors"
  exit 1
fi

echo "symlink: dispatcher resolves its install through the link"
