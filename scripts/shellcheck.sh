#!/usr/bin/env bash
# Runs shellcheck over the tree, fetching a static binary if the machine
# has none. ipile bootstraps machines that have nothing installed yet, so
# its own lint refuses to depend on a package manager having been run.
#
# Usage: scripts/shellcheck.sh [--install]
#   --install   fetch the binary and stop, without linting

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="${ROOT}/.tools"
VENDORED="${TOOLS}/shellcheck"

# Exclusions are named one by one, with a reason each, because a blanket
# exclusion is how a linter starts crying wolf.
#   SC1090/SC1091  sourced paths built at runtime, which is the whole design
#   SC2034         colour variables consumed by callers after sourcing
#   SC2086         deliberate word splitting on the module list
#   SC2088         a literal ~ inside a message shown to the user
#   SC2016         single quotes in rc fragments, which must not expand here
#   SC2148         rc fragments are sourced, so they correctly have no shebang
EXCLUDE="SC1090,SC1091,SC2034,SC2086,SC2088,SC2016,SC2148"

install_shellcheck() {
  local url arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64)          arch="x86_64" ;;
    aarch64 | arm64) arch="aarch64" ;;
    *)
      echo "shellcheck: no static build published for $arch" >&2
      return 1
      ;;
  esac

  url="https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.${arch}.tar.xz"
  [ "$(uname -s)" = "Darwin" ] &&
    url="https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.darwin.${arch}.tar.xz"

  echo "Fetching shellcheck into .tools/ ..."
  mkdir -p "$TOOLS"
  curl -fsSL "$url" | tar -xJ -C "$TOOLS" --strip-components=1 "shellcheck-stable/shellcheck"
  chmod +x "$VENDORED"
  "$VENDORED" --version | head -2
}

# A shellcheck already on PATH wins, so a system install is never
# duplicated. The vendored copy is only the fallback.
resolve() {
  if command -v shellcheck >/dev/null 2>&1; then
    command -v shellcheck
  elif [ -x "$VENDORED" ]; then
    printf '%s\n' "$VENDORED"
  else
    return 1
  fi
}

if [ "${1:-}" = "--install" ]; then
  install_shellcheck
  exit 0
fi

if ! SHELLCHECK="$(resolve)"; then
  install_shellcheck || {
    echo "shellcheck: could not install. Run 'pnpm lint:install' by hand." >&2
    exit 1
  }
  SHELLCHECK="$VENDORED"
fi

cd "$ROOT"
echo "Linting with $SHELLCHECK"
"$SHELLCHECK" -S warning -e "$EXCLUDE" \
  bin/ipile \
  lib/core/*.sh \
  lib/modules/*.sh \
  lib/doctor.sh \
  lib/update.sh

echo "shellcheck: 0 findings"
