#!/usr/bin/env bash
# ================================================
# build-and-install.sh
# Builds the ipile tarball and writes it directly
# to public/scripts/ipile.tar.gz for Vercel serving.
#
# Run from the repo root:  bash public/scripts/build-and-install.sh
# ================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd -P)"
# public/scripts/ is two levels deep from the repo root
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
OUT_DIR="$SCRIPT_DIR"
TARBALL="$OUT_DIR/ipile.tar.gz"
BASE_URL="https://shogo-portfolio-ebon.vercel.app/scripts"
VERSION="v3.0"

echo "Building ipile $VERSION..."
echo "Output: $TARBALL"
echo ""

# Temp build directory
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT

mkdir -p "$BUILD/bin" "$BUILD/lib"

# === bin/ipile (dispatcher)
cat > "$BUILD/bin/ipile" << 'CLI'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd -P)"
INSTALL_DIR="$(dirname "$SCRIPT_DIR")"
COMMAND="${1:-help}"
case "$COMMAND" in
  dev-setup) bash "$INSTALL_DIR/lib/setup.sh" ;;
  git-multiple-accounts|git-accounts) bash "$INSTALL_DIR/lib/git-multiple-accounts.sh" ;;
  doctor)    bash "$INSTALL_DIR/lib/doctor.sh" ;;
  update)    bash "$INSTALL_DIR/lib/update.sh" ;;
  version|--version) cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "unknown" ;;
  help|*)
    echo "ipile - machine bootstrap"
    echo ""
    echo "Commands:"
    echo "  dev-setup              Full machine bootstrap (Rust, Node, Git, SSH, configs)"
    echo "  git-multiple-accounts  Configure git identities and SSH keys, one account or many"
    echo "  doctor                 Check installed tools"
    echo "  update                 Update ipile itself"
    echo "  version                Show current version"
    exit 0
    ;;
esac
LATEST="$(curl -fsSL BASE_URL_PLACEHOLDER/version.txt 2>/dev/null || echo "")"
CURRENT="$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "unknown")"
if [[ -n "$LATEST" && "$LATEST" != "$CURRENT" ]]; then
  echo ""
  echo "Update available: $LATEST  (run: ipile update)"
fi
CLI
sed -i "s|BASE_URL_PLACEHOLDER|$BASE_URL|g" "$BUILD/bin/ipile"

# === lib/setup.sh (copied from dev-setup.sh in the same directory)
cp "$SCRIPT_DIR/dev-setup.sh" "$BUILD/lib/setup.sh"
cp "$SCRIPT_DIR/git-multiple-accounts.sh" "$BUILD/lib/git-multiple-accounts.sh"

# === lib/doctor.sh
cat > "$BUILD/lib/doctor.sh" << 'DOC'
#!/usr/bin/env bash
set -euo pipefail
echo "Running diagnostics..."
echo ""
pass() { echo "  [ok] $1"; }
fail() { echo "  [!!] $1 - not found"; }
command -v git     >/dev/null && pass "git $(git --version | awk '{print $3}')"     || fail "git"
command -v node    >/dev/null && pass "node $(node -v)"   || fail "node"
command -v pnpm    >/dev/null && pass "pnpm $(pnpm -v)"   || fail "pnpm"
command -v rustc   >/dev/null && pass "rust $(rustc -V | awk '{print $2}')" || fail "rust"
command -v ssh     >/dev/null && pass "ssh" || fail "ssh"
echo ""
echo "Run 'ipile dev-setup' to install anything missing."
DOC

# === lib/update.sh
cat > "$BUILD/lib/update.sh" << UPDEOF
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="\$HOME/.ipile"
CURRENT="\$(cat "\$INSTALL_DIR/VERSION" 2>/dev/null || echo "unknown")"
LATEST="\$(curl -fsSL $BASE_URL/version.txt 2>/dev/null || echo "unknown")"
echo "Current: \$CURRENT"
echo "Latest:  \$LATEST"
if [[ "\$CURRENT" == "\$LATEST" ]]; then
  echo "Already up to date."
  exit 0
fi
echo "Updating ipile..."
curl -fsSL $BASE_URL/ipile.tar.gz -o /tmp/ipile.tar.gz
tar -xzf /tmp/ipile.tar.gz -C "\$INSTALL_DIR" --overwrite
echo "\$LATEST" > "\$INSTALL_DIR/VERSION"
echo "Updated to \$LATEST. Restart your terminal."
UPDEOF

# === VERSION
echo "$VERSION" > "$BUILD/VERSION"

# Make scripts executable
chmod +x "$BUILD/bin/ipile" "$BUILD/lib/"*.sh

# Pack
tar -czf "$TARBALL" -C "$BUILD" .

echo "Done. Tarball written to: $TARBALL"
echo ""
echo "Files served at:"
echo "  $BASE_URL/installer.sh"
echo "  $BASE_URL/dev-setup.sh"
echo "  $BASE_URL/ipile.tar.gz"
echo "  $BASE_URL/version.txt"
echo ""
echo "Deploy via: git push  (Vercel picks up public/scripts/ automatically)"
