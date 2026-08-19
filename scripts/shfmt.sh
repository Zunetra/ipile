#!/usr/bin/env bash
# Formats the shell tree, fetching a static binary if the machine has none.
# Same reasoning as scripts/shellcheck.sh: ipile bootstraps machines that
# have nothing installed yet, so its own tooling refuses to depend on a
# package manager having been run. prettier handles the JSON and Markdown;
# it has no idea what a shell script is.
#
# Usage: scripts/shfmt.sh [--check | --install] [files...]
#   --check     report files that need formatting, change nothing
#   --install   fetch the binary and stop
#   files...    format only these, instead of the whole tree

set -euo pipefail

SHFMT_VERSION="v3.13.1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="${ROOT}/.tools"
VENDORED="${TOOLS}/shfmt"

install_shfmt() {
  local url arch os
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64 | arm64) arch="arm64" ;;
    *)
      echo "shfmt: no static build published for $arch" >&2
      return 1
      ;;
  esac

  os="linux"
  [ "$(uname -s)" = "Darwin" ] && os="darwin"

  url="https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_${os}_${arch}"

  echo "Fetching shfmt into .tools/ ..."
  mkdir -p "$TOOLS"
  # A single binary, not a tarball, so it is written straight to its path.
  curl -fsSL "$url" -o "$VENDORED"
  chmod +x "$VENDORED"
  "$VENDORED" --version
}

# A shfmt already on PATH wins, so a system install is never duplicated.
# The vendored copy is only the fallback.
resolve() {
  if command -v shfmt >/dev/null 2>&1; then
    command -v shfmt
  elif [ -x "$VENDORED" ]; then
    printf '%s\n' "$VENDORED"
  else
    return 1
  fi
}

MODE="write"
if [ "${1:-}" = "--install" ]; then
  install_shfmt
  exit 0
elif [ "${1:-}" = "--check" ]; then
  MODE="check"
  shift
fi

if ! SHFMT="$(resolve)"; then
  install_shfmt || {
    echo "shfmt: could not install. Run 'pnpm format:install' by hand." >&2
    exit 1
  }
  SHFMT="$VENDORED"
fi

cd "$ROOT"

# Explicit file list when given one, e.g. by lint-staged. Otherwise the same
# set shellcheck lints, so the two never disagree about what is source.
if [ "$#" -gt 0 ]; then
  TARGETS=("$@")
else
  TARGETS=(
    bin/ipile
    lib/core/*.sh
    lib/modules/*.sh
    lib/manifest.sh
    lib/doctor.sh
    lib/update.sh
    lib/assets/hooks/pre-commit
    lib/assets/hooks/pre-push
    lib/assets/shell/*.sh
    scripts/*.sh
    .husky/pre-commit
    .husky/pre-push
  )
fi

# Indentation and the rest come from .editorconfig, which shfmt reads on its
# own. Keeping them there rather than as flags means an editor and this
# script cannot drift apart.
if [ "$MODE" = "check" ]; then
  echo "Checking shell formatting with $SHFMT"
  "$SHFMT" --diff "${TARGETS[@]}"
  echo "shfmt: all formatted"
else
  echo "Formatting shell with $SHFMT"
  "$SHFMT" --write --list "${TARGETS[@]}"
fi
