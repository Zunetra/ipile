#!/usr/bin/env bash
# Update ipile itself.
#
# The download is checksum verified. An unverified curl into tar is a
# supply chain hole, and it is multiplied by everyone who installs this.
set -uo pipefail

BASE_URL="https://github.com/Zunetra/ipile/releases/latest/download"
INSTALL_DIR="$HOME/.ipile"
CURRENT="$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || printf 'unknown')"

LATEST="$(curl -fsSL "${BASE_URL}/version.txt" 2>/dev/null || printf '')"

if [ -z "$LATEST" ]; then
  echo "Could not reach ${BASE_URL} to check for updates."
  echo "Current version: ${CURRENT}"
  exit 1
fi

echo "Current: ${CURRENT}"
echo "Latest:  ${LATEST}"

if [ "$CURRENT" = "$LATEST" ]; then
  echo "Already up to date."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading ${LATEST}..."
if ! curl -fsSL "${BASE_URL}/ipile.tar.gz" -o "${TMP}/ipile.tar.gz"; then
  echo "Download failed. Nothing was changed."
  exit 1
fi

# === Checksum

verify_checksum() {
  local sums="${TMP}/SHA256SUMS"
  if ! curl -fsSL "${BASE_URL}/SHA256SUMS" -o "$sums" 2>/dev/null; then
    echo "WARNING: no SHA256SUMS published at ${BASE_URL}."
    echo "The download cannot be verified."
    printf 'Install it anyway? (y/N) '
    read -r answer
    case "$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')" in
      y | yes) return 0 ;;
      *)
        echo "Aborted. Nothing was changed."
        exit 1
        ;;
    esac
  fi

  local expected actual
  expected="$(grep 'ipile.tar.gz' "$sums" 2>/dev/null | awk '{print $1}' | head -1)"
  if [ -z "$expected" ]; then
    echo "SHA256SUMS has no entry for ipile.tar.gz. Aborted."
    exit 1
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "${TMP}/ipile.tar.gz" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "${TMP}/ipile.tar.gz" | awk '{print $1}')"
  else
    echo "Neither sha256sum nor shasum is available. Cannot verify. Aborted."
    exit 1
  fi

  if [ "$expected" != "$actual" ]; then
    echo "CHECKSUM MISMATCH. The download does not match what was published."
    echo "  expected ${expected}"
    echo "  actual   ${actual}"
    echo "Aborted. Nothing was changed."
    exit 1
  fi
  echo "Checksum verified."
}

verify_checksum

# === Install
#
# var/ holds state, logs and backups. It is not in the tarball, so it
# survives the unpack. Do not delete the install directory wholesale.

echo "Installing..."
mkdir -p "$INSTALL_DIR"
tar -xzf "${TMP}/ipile.tar.gz" -C "$INSTALL_DIR" --overwrite
printf '%s\n' "$LATEST" >"${INSTALL_DIR}/VERSION"

echo "Updated to ${LATEST}. Restart your terminal."
