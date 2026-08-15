#!/usr/bin/env bash
# Builds ipile.tar.gz plus its SHA256SUMS.
#
# Unlike the previous version this does not generate any shipped code
# from heredocs. bin/ipile, lib/ and every asset are real files in the
# repository, so what you read is what ships. The build only packs.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd -P)"
OUT_DIR="$SCRIPT_DIR"
TARBALL="${OUT_DIR}/ipile.tar.gz"
SUMS="${OUT_DIR}/SHA256SUMS"

BASE_URL="${IPILE_BASE_URL:-https://shogo-portfolio-ebon.vercel.app/scripts}"
VERSION="$(tr -d '[:space:]' < "${SCRIPT_DIR}/version.txt")"

echo "Building ipile ${VERSION}"
echo "  base url: ${BASE_URL}"
echo "  output:   ${TARBALL}"
echo ""

# === Sanity checks
#
# A tarball that ships a syntax error is worse than a failed build,
# because it installs cleanly and then breaks on someone else's machine.

fail=0
for f in "${SCRIPT_DIR}/bin/ipile" "${SCRIPT_DIR}"/lib/*.sh \
         "${SCRIPT_DIR}"/lib/core/*.sh "${SCRIPT_DIR}"/lib/modules/*.sh; do
  [ -f "$f" ] || continue
  if ! bash -n "$f" 2>/dev/null; then
    echo "SYNTAX ERROR: ${f}"
    bash -n "$f" || true
    fail=1
  fi
done
[ "$fail" -eq 0 ] || { echo ""; echo "Build aborted."; exit 1; }
echo "All scripts parse."

if command -v shellcheck >/dev/null 2>&1; then
  # The exclusions are vetted, not blanket. SC1090/SC1091 are the dynamic
  # sources the module registry is built on. SC2034 fires on MODULE_* and
  # the colour constants, which are read across files it analyses one at a
  # time. SC2088 fires on tildes inside user facing message strings, which
  # are text and never expanded. SC2086 is the deliberate word splitting in
  # the module id lists.
  shellcheck -S warning -e SC1090,SC1091,SC2034,SC2086,SC2088,SC2016,SC2148 \
    "${SCRIPT_DIR}/bin/ipile" \
    "${SCRIPT_DIR}"/lib/*.sh \
    "${SCRIPT_DIR}"/lib/core/*.sh \
    "${SCRIPT_DIR}"/lib/modules/*.sh || echo "shellcheck reported issues (not fatal)"
else
  echo "shellcheck not installed, skipping lint."
fi

# === Assemble

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

mkdir -p "${BUILD}/bin" "${BUILD}/lib"

cp "${SCRIPT_DIR}/bin/ipile" "${BUILD}/bin/ipile"
cp -R "${SCRIPT_DIR}/lib/." "${BUILD}/lib/"
printf '%s\n' "$VERSION" > "${BUILD}/VERSION"

# The hosting URL is the one thing that cannot live in the source, since
# it differs per deployment. It is substituted, never generated.
for f in "${BUILD}/bin/ipile" "${BUILD}/lib/update.sh"; do
  sed -i.bak "s|BASE_URL_PLACEHOLDER|${BASE_URL}|g" "$f"
  rm -f "${f}.bak"
done

if grep -rq 'BASE_URL_PLACEHOLDER' "$BUILD" 2>/dev/null; then
  echo "A BASE_URL_PLACEHOLDER survived substitution:"
  grep -rl 'BASE_URL_PLACEHOLDER' "$BUILD"
  exit 1
fi

chmod +x "${BUILD}/bin/ipile"
find "${BUILD}/lib" -name '*.sh' -exec chmod +x {} \;
[ -d "${BUILD}/lib/assets/hooks" ] && chmod +x "${BUILD}/lib/assets/hooks/"* 2>/dev/null || true

# === Pack

tar -czf "$TARBALL" -C "$BUILD" .

# === Checksums
#
# update.sh refuses to install an unverified download, so publishing this
# file alongside the tarball is not optional.

cd "$OUT_DIR"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum ipile.tar.gz installer.sh version.txt > "$SUMS"
else
  shasum -a 256 ipile.tar.gz installer.sh version.txt > "$SUMS"
fi

echo ""
echo "Built:"
echo "  ${TARBALL}  ($(wc -c < "$TARBALL" | tr -d ' ') bytes)"
echo "  ${SUMS}"
echo ""
echo "Publish these four at ${BASE_URL}/ :"
echo "  installer.sh"
echo "  ipile.tar.gz"
echo "  version.txt"
echo "  SHA256SUMS"
echo ""
echo "version.txt and the packed VERSION both read ${VERSION}, so they cannot drift."
