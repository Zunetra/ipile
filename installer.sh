#!/bin/sh
# ipile installer. POSIX sh on purpose: this runs before ipile has
# checked anything about the machine it landed on.
set -eu

BASE_URL="${IPILE_BASE_URL:-https://github.com/Zunetra/ipile/releases/latest/download}"
INSTALL_DIR="$HOME/.ipile"
BIN_DIR="$HOME/.local/bin"
# === Already installed
#
# Same contract as rustup: a second run of the one liner points at the
# updater instead of unpacking over a working install. IPILE_FORCE_INSTALL
# is the escape hatch for repairing an install that cannot update itself.

if [ -f "${INSTALL_DIR}/VERSION" ] && [ -z "${IPILE_FORCE_INSTALL:-}" ]; then
  current="$(tr -d '[:space:]' <"${INSTALL_DIR}/VERSION")"
  latest="$(curl -fsSL "${BASE_URL}/version.txt" 2>/dev/null | tr -d '[:space:]' || true)"

  if [ -z "$latest" ]; then
    echo "ipile ${current} is already installed."
    echo "Run: ipile update  to check for a newer version"
  elif [ "$latest" = "$current" ]; then
    echo "ipile ${current} is already installed and up to date."
  else
    echo "ipile ${current} is already installed."
    echo "${latest} is available. Run: ipile update"
  fi
  echo ""
  echo "To reinstall anyway:"
  echo "  curl -fsSL ${BASE_URL}/installer.sh | IPILE_FORCE_INSTALL=1 sh"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Installing ipile from ${BASE_URL}"

mkdir -p "$INSTALL_DIR" "$BIN_DIR"

curl -fsSL "${BASE_URL}/ipile.tar.gz" -o "${TMP}/ipile.tar.gz"

# === Verify before unpacking
#
# Unpacking an unverified archive into the home directory is the whole
# supply chain in one line. A missing SHA256SUMS is a prompt, not a
# silent pass.

if curl -fsSL "${BASE_URL}/SHA256SUMS" -o "${TMP}/SHA256SUMS" 2>/dev/null; then
  expected="$(grep 'ipile.tar.gz' "${TMP}/SHA256SUMS" | awk '{print $1}' | head -1)"

  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "${TMP}/ipile.tar.gz" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "${TMP}/ipile.tar.gz" | awk '{print $1}')"
  else
    actual=""
    echo "WARNING: no sha256sum or shasum available, cannot verify."
  fi

  if [ -n "$actual" ]; then
    if [ "$expected" != "$actual" ]; then
      echo "CHECKSUM MISMATCH. Refusing to install."
      echo "  expected ${expected}"
      echo "  actual   ${actual}"
      exit 1
    fi
    echo "Checksum verified."
  fi
else
  echo "WARNING: no SHA256SUMS published. The download is unverified."
fi

tar -xzf "${TMP}/ipile.tar.gz" -C "$INSTALL_DIR"
ln -sf "${INSTALL_DIR}/bin/ipile" "${BIN_DIR}/ipile"
chmod +x "${INSTALL_DIR}/bin/ipile"

# === PATH
#
# Guarded per file rather than by inspecting the current PATH, so
# installing twice from two fresh shells cannot append the line twice.

PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$rc" ] || continue
  if ! grep -qF "$PATH_LINE" "$rc" 2>/dev/null; then
    printf '\n%s\n' "$PATH_LINE" >>"$rc"
    echo "Added ~/.local/bin to PATH in $(basename "$rc")"
  fi
done

echo ""
echo "ipile $(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo '') installed."
echo ""
echo "Restart your terminal, then run:"
echo "  ipile              pick what you want to set up"
echo "  ipile status       see what is already done"
echo "  ipile --help       everything else"
